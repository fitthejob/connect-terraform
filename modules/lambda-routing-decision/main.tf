
# IAM role for routing-decision Lambda - Assume role via STS
resource "aws_iam_role" "routing_decision" {
  name = "lambda-routing-decision-role-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "routing_decision_basic" {
  role       = aws_iam_role.routing_decision.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Required for tracing_config { mode = "Active" } on the function below
resource "aws_iam_role_policy_attachment" "routing_decision_xray" {
  role       = aws_iam_role.routing_decision.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Dead-letter queue, defense-in-depth only -- this Lambda is invoked
# synchronously (via InvokeLambdaFunction from the contact flow), same
# rationale as modules/lambda/main.tf's eligibility_check_dlq.
resource "aws_sqs_queue" "routing_decision_dlq" {
  name                    = "lambda-routing-decision-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_iam_role_policy" "routing_decision_dlq" {
  name = "lambda-routing-decision-dlq-policy-${var.environment}"
  role = aws_iam_role.routing_decision.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.routing_decision_dlq.arn
      }
    ]
  })
}

# AWS-managed key for encrypting the Lambda's environment variables at rest.
data "aws_kms_key" "lambda_default" {
  key_id = "alias/aws/lambda"
}

# Not placed in a VPC: prototype build, same rationale as
# modules/lambda/main.tf's eligibility_check function. This Lambda has no
# external AWS service dependency (no Customer Profiles, no DynamoDB, no
# EventBridge) -- purely queue-selection logic driven by env-var queue ARNs.
resource "aws_lambda_function" "routing_decision" {
  function_name = var.function_name
  role          = aws_iam_role.routing_decision.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  s3_bucket     = var.s3_bucket_lambda_artifacts
  s3_key        = var.s3_key
  publish       = true
  environment {
    variables = {
      QUEUE_CLAIMS_ARN         = var.queue_claims_arn
      QUEUE_BENEFITS_ARN       = var.queue_benefits_arn
      QUEUE_AUTHORIZATIONS_ARN = var.queue_authorizations_arn
      QUEUE_BILLING_ARN        = var.queue_billing_arn
      QUEUE_GENERAL_ARN        = var.queue_general_arn
    }
  }
  layers = [var.layer_arn]

  kms_key_arn = data.aws_kms_key.lambda_default.arn

  # No reserved_concurrent_executions -- see modules/lambda/main.tf for why.

  dead_letter_config {
    target_arn = aws_sqs_queue.routing_decision_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }
}

# Lambda alias that will update when new versions are deployed
resource "aws_lambda_alias" "routing_decision_live" {
  name             = "live"
  function_name    = aws_lambda_function.routing_decision.function_name
  function_version = aws_lambda_function.routing_decision.version
}
