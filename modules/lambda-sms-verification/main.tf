
# DynamoDB table for verification codes. TTL enabled on expiresAt (epoch
# seconds); on-demand billing per the spec. contactId is the partition key
# -- one record per contact, overwritten if a new code is requested for the
# same contact.
resource "aws_dynamodb_table" "verification_codes" {
  name         = "sms-verification-codes-${var.environment}"
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

# IAM role for sms-verification Lambda - Assume role via STS
resource "aws_iam_role" "sms_verification" {
  name = "lambda-sms-verification-role-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "sms_verification_basic" {
  role       = aws_iam_role.sms_verification.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Required for tracing_config { mode = "Active" } on the function below
resource "aws_iam_role_policy_attachment" "sms_verification_xray" {
  role       = aws_iam_role.sms_verification.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_policy" "sms_verification_dynamodb" {
  name = "lambda-sms-verification-dynamodb-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.verification_codes.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sms_verification_dynamodb" {
  role       = aws_iam_role.sms_verification.name
  policy_arn = aws_iam_policy.sms_verification_dynamodb.arn
}

# sns:Publish to a phone number (not a topic ARN) has no resource-level
# permissions -- AWS does not support scoping SMS Publish to specific
# destination numbers.
resource "aws_iam_policy" "sms_verification_sns" {
  name = "lambda-sms-verification-sns-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sms_verification_sns" {
  role       = aws_iam_role.sms_verification.name
  policy_arn = aws_iam_policy.sms_verification_sns.arn
}

resource "aws_iam_policy" "sms_verification_eventbridge" {
  name = "lambda-sms-verification-eventbridge-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = var.event_bus_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sms_verification_eventbridge" {
  role       = aws_iam_role.sms_verification.name
  policy_arn = aws_iam_policy.sms_verification_eventbridge.arn
}

# Dead-letter queue, defense-in-depth only -- this Lambda is invoked
# synchronously via InvokeFlowModule, same rationale as
# modules/lambda/main.tf's eligibility_check_dlq.
resource "aws_sqs_queue" "sms_verification_dlq" {
  name                    = "lambda-sms-verification-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_iam_role_policy" "sms_verification_dlq" {
  name = "lambda-sms-verification-dlq-policy-${var.environment}"
  role = aws_iam_role.sms_verification.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.sms_verification_dlq.arn
      }
    ]
  })
}

# AWS-managed key for encrypting the Lambda's environment variables at rest.
data "aws_kms_key" "lambda_default" {
  key_id = "alias/aws/lambda"
}

# Not placed in a VPC: prototype build, same rationale as
# modules/lambda/main.tf's eligibility_check function.
resource "aws_lambda_function" "sms_verification" {
  function_name = var.function_name
  role          = aws_iam_role.sms_verification.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  s3_bucket     = var.s3_bucket_lambda_artifacts
  s3_key        = var.s3_key
  publish       = true
  environment {
    variables = {
      VERIFICATION_TABLE_NAME = aws_dynamodb_table.verification_codes.name
      EVENT_BUS_NAME          = var.event_bus_name
    }
  }
  layers = [var.layer_arn]

  kms_key_arn = data.aws_kms_key.lambda_default.arn

  # No reserved_concurrent_executions -- see modules/lambda/main.tf for why.

  dead_letter_config {
    target_arn = aws_sqs_queue.sms_verification_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }
}

# Lambda alias that will update when new versions are deployed
resource "aws_lambda_alias" "sms_verification_live" {
  name             = "live"
  function_name    = aws_lambda_function.sms_verification.function_name
  function_version = aws_lambda_function.sms_verification.version
}
