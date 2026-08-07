
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
# eligibility_check function. No DLQ on the function itself -- this Lambda
# is invoked asynchronously by EventBridge rule targets, which already
# have their own retry policy and a per-rule DLQ (see
# modules/eventbridge-pipeline), so a function-level DLQ here would be
# redundant.
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
