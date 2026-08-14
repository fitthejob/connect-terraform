# DynamoDB table for poll-cycle dedup. TTL enabled on expiresAt (epoch
# seconds). contactId is the partition key. Unlike
# sms-verification-codes-{env}'s TTL (which reflects the SMS code's own
# 5-minute business validity), this table's TTL is tied purely to how long
# a ContactId could still appear in an overlapping poll lookback window --
# see docs/superpowers/specs/2026-08-14-self-service-abandonment-metric-design.md.
resource "aws_dynamodb_table" "dedup" {
  name         = "abandonment-metric-dedup-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "contactId"

  attribute {
    name = "contactId"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }
}

resource "aws_iam_role" "abandonment_metric" {
  name = "lambda-abandonment-metric-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "abandonment_metric_basic" {
  role       = aws_iam_role.abandonment_metric.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Required for tracing_config { mode = "Active" } on the function below
resource "aws_iam_role_policy_attachment" "abandonment_metric_xray" {
  role       = aws_iam_role.abandonment_metric.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_policy" "abandonment_metric_dynamodb" {
  name = "lambda-abandonment-metric-dynamodb-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
        ]
        Resource = aws_dynamodb_table.dedup.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "abandonment_metric_dynamodb" {
  role       = aws_iam_role.abandonment_metric.name
  policy_arn = aws_iam_policy.abandonment_metric_dynamodb.arn
}

# connect:SearchContacts and connect:DescribeContact are not scopable to a
# specific instance ARN for these actions in AWS's IAM action reference --
# same "resources = *" pattern modules/iam's ConnectManage/ConnectReadOnly
# statements already use for other Connect actions (see
# modules/iam/main.tf's inline comments on this exact tradeoff).
resource "aws_iam_policy" "abandonment_metric_connect" {
  name = "lambda-abandonment-metric-connect-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "connect:SearchContacts",
          "connect:DescribeContact",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "abandonment_metric_connect" {
  role       = aws_iam_role.abandonment_metric.name
  policy_arn = aws_iam_policy.abandonment_metric_connect.arn
}

resource "aws_iam_policy" "abandonment_metric_logs" {
  name = "lambda-abandonment-metric-logs-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:FilterLogEvents"
        Resource = "arn:aws:logs:*:*:log-group:${var.flow_log_group_name}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "abandonment_metric_logs" {
  role       = aws_iam_role.abandonment_metric.name
  policy_arn = aws_iam_policy.abandonment_metric_logs.arn
}

resource "aws_iam_policy" "abandonment_metric_cloudwatch" {
  name = "lambda-abandonment-metric-cloudwatch-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "cloudwatch:PutMetricData"
        # PutMetricData has no resource-level permissions -- AWS does not
        # support scoping it to a specific namespace.
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "abandonment_metric_cloudwatch" {
  role       = aws_iam_role.abandonment_metric.name
  policy_arn = aws_iam_policy.abandonment_metric_cloudwatch.arn
}

# Dead-letter queue, defense-in-depth. Unlike the other 5 Lambdas in this
# repo (invoked synchronously from a Connect flow/module), this Lambda is
# invoked by EventBridge Scheduler -- asynchronously -- so per CLAUDE.md's
# known-gotchas entry on async Lambda invocation, it needs its own
# event_invoke_config with a dedicated on_failure destination, not just this
# DLQ alone (see Step 3 below), mirroring modules/lambda-event-metric-subscriber's
# pattern rather than modules/lambda-sms-verification's (which is
# synchronous and only needs the DLQ as defense-in-depth).
resource "aws_sqs_queue" "abandonment_metric_dlq" {
  name                    = "lambda-abandonment-metric-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_iam_role_policy" "abandonment_metric_dlq" {
  name = "lambda-abandonment-metric-dlq-policy-${var.environment}"
  role = aws_iam_role.abandonment_metric.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.abandonment_metric_dlq.arn
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "abandonment_metric_dlq" {
  queue_url = aws_sqs_queue.abandonment_metric_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.abandonment_metric_dlq.arn
      }
    ]
  })
}

data "aws_kms_key" "lambda_default" {
  key_id = "alias/aws/lambda"
}

# Not placed in a VPC: prototype build, same rationale as
# modules/lambda/main.tf's eligibility_check function.
resource "aws_lambda_function" "abandonment_metric" {
  function_name = var.function_name
  role          = aws_iam_role.abandonment_metric.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  s3_bucket     = var.s3_bucket_lambda_artifacts
  s3_key        = var.s3_key
  publish       = true
  timeout       = 60
  environment {
    variables = {
      INSTANCE_ID      = var.connect_instance_id
      LOG_GROUP_NAME   = var.flow_log_group_name
      DEDUP_TABLE_NAME = aws_dynamodb_table.dedup.name
      METRIC_NAMESPACE = var.metric_namespace
      STAGE            = var.environment
      LOOKBACK_MINUTES = tostring(var.lookback_minutes)
    }
  }
  layers = [var.layer_arn]

  kms_key_arn = data.aws_kms_key.lambda_default.arn

  # No reserved_concurrent_executions -- see modules/lambda/main.tf for why.

  dead_letter_config {
    target_arn = aws_sqs_queue.abandonment_metric_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_alias" "abandonment_metric_live" {
  name             = "live"
  function_name    = aws_lambda_function.abandonment_metric.function_name
  function_version = aws_lambda_function.abandonment_metric.version
}

# Async-invoke destination config -- required because EventBridge Scheduler
# invokes this Lambda asynchronously (202 Accepted on handoff), so an
# in-function throw is otherwise invisible and silently discarded after
# Lambda's default 2 retries. Same pattern as
# modules/lambda-event-metric-subscriber/main.tf.
resource "aws_lambda_function_event_invoke_config" "abandonment_metric" {
  function_name          = aws_lambda_function.abandonment_metric.function_name
  qualifier              = aws_lambda_alias.abandonment_metric_live.name
  maximum_retry_attempts = 2

  destination_config {
    on_failure {
      destination = aws_sqs_queue.abandonment_metric_dlq.arn
    }
  }
}
