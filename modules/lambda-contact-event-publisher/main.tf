
# IAM role for contact-event-publisher Lambda - Assume role via STS
resource "aws_iam_role" "contact_event_publisher" {
  name = "lambda-contact-event-publisher-role-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "contact_event_publisher_basic" {
  role       = aws_iam_role.contact_event_publisher.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Required for tracing_config { mode = "Active" } on the function below
resource "aws_iam_role_policy_attachment" "contact_event_publisher_xray" {
  role       = aws_iam_role.contact_event_publisher.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_policy" "contact_event_publisher_eventbridge" {
  name = "lambda-contact-event-publisher-eventbridge-policy-${var.environment}"
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

resource "aws_iam_role_policy_attachment" "contact_event_publisher_eventbridge" {
  role       = aws_iam_role.contact_event_publisher.name
  policy_arn = aws_iam_policy.contact_event_publisher_eventbridge.arn
}

# Dead-letter queue, defense-in-depth only -- this Lambda is invoked
# synchronously via InvokeLambdaFunction, same rationale as
# modules/lambda/main.tf's eligibility_check_dlq.
resource "aws_sqs_queue" "contact_event_publisher_dlq" {
  name                    = "lambda-contact-event-publisher-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_iam_role_policy" "contact_event_publisher_dlq" {
  name = "lambda-contact-event-publisher-dlq-policy-${var.environment}"
  role = aws_iam_role.contact_event_publisher.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.contact_event_publisher_dlq.arn
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
resource "aws_lambda_function" "contact_event_publisher" {
  function_name = var.function_name
  role          = aws_iam_role.contact_event_publisher.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  s3_bucket     = var.s3_bucket_lambda_artifacts
  s3_key        = var.s3_key
  publish       = true
  environment {
    variables = {
      EVENT_BUS_NAME = var.event_bus_name
    }
  }
  layers = [var.layer_arn]

  kms_key_arn = data.aws_kms_key.lambda_default.arn

  # No reserved_concurrent_executions -- see modules/lambda/main.tf for why.

  dead_letter_config {
    target_arn = aws_sqs_queue.contact_event_publisher_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }
}

# Lambda alias that will update when new versions are deployed
resource "aws_lambda_alias" "contact_event_publisher_live" {
  name             = "live"
  function_name    = aws_lambda_function.contact_event_publisher.function_name
  function_version = aws_lambda_function.contact_event_publisher.version
}
