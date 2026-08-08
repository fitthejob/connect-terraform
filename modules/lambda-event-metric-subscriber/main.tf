
# IAM role for the event-metric-subscriber Lambda - Assume role via STS
resource "aws_iam_role" "subscriber" {
  name = "lambda-event-metric-subscriber-role-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "subscriber_basic" {
  role       = aws_iam_role.subscriber.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "subscriber_cloudwatch" {
  name = "lambda-event-metric-subscriber-cloudwatch-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # cloudwatch:PutMetricData has no resource-level permissions --
        # metrics are not ARN-addressable resources.
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "subscriber_cloudwatch" {
  role       = aws_iam_role.subscriber.name
  policy_arn = aws_iam_policy.subscriber_cloudwatch.arn
}

# AWS-managed key for encrypting the Lambda's environment variables at rest.
data "aws_kms_key" "lambda_default" {
  key_id = "alias/aws/lambda"
}

# Single shared subscriber for all four EventBridge rules -- one concern
# (turn an event into a CloudWatch metric under the ContactCenter/Events
# namespace), branching internally on detail-type rather than four
# separately deployed, env-var-parameterized instances. Not placed in a
# VPC: prototype build, same rationale as modules/lambda/main.tf's
# eligibility_check function.
resource "aws_lambda_function" "subscriber" {
  function_name = var.function_name
  role          = aws_iam_role.subscriber.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  s3_bucket     = var.s3_bucket_lambda_artifacts
  s3_key        = var.s3_key
  publish       = true
  layers        = [var.layer_arn]

  kms_key_arn = data.aws_kms_key.lambda_default.arn

  # No reserved_concurrent_executions -- see modules/lambda/main.tf for why.

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_alias" "subscriber_live" {
  name             = "live"
  function_name    = aws_lambda_function.subscriber.function_name
  function_version = aws_lambda_function.subscriber.version
}

# EventBridge invokes this Lambda asynchronously, which puts Lambda's own
# async-invoke retry/failure handling in the loop -- entirely separate from
# EventBridge's own retry_policy/dead_letter_config on the rule target
# (modules/eventbridge-pipeline). EventBridge only retries/DLQs a *failed
# handoff* (throttling, missing permissions, deleted function); once Lambda
# accepts the invocation, an in-function throw is invisible to EventBridge
# and is governed solely by this config. Confirmed live: a forced in-function
# error (CloudWatch rejecting an out-of-window metric timestamp) retried per
# Lambda's own default async config (2 retries) and was silently discarded --
# no EventBridge DLQ entry, no AWS/Events CloudWatch metric at all -- until
# this destination_config was added.
resource "aws_sqs_queue" "subscriber_failure_dlq" {
  # lambda-*-${env} naming, matching every other Lambda's DLQ in this repo --
  # required for modules/iam's sqs_scoped_resources wildcard to grant the
  # deploy role sqs:CreateQueue on it.
  name                    = "lambda-event-metric-subscriber-failure-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue_policy" "subscriber_failure_dlq" {
  queue_url = aws_sqs_queue.subscriber_failure_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.subscriber_failure_dlq.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_lambda_function.subscriber.arn }
        }
      }
    ]
  })
}

resource "aws_lambda_function_event_invoke_config" "subscriber" {
  function_name = aws_lambda_function.subscriber.function_name
  qualifier     = aws_lambda_alias.subscriber_live.name

  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 300

  destination_config {
    on_failure {
      destination = aws_sqs_queue.subscriber_failure_dlq.arn
    }
  }
}
