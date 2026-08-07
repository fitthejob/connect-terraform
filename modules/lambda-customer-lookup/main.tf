
# IAM role for customer-lookup Lambda - Assume role via STS
resource "aws_iam_role" "customer_lookup" {
  name = "lambda-customer-lookup-role-${var.environment}"

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

# Assign AWS managed basic execution policy to lambda-customer-lookup-role
resource "aws_iam_role_policy_attachment" "customer_lookup_basic" {
  role       = aws_iam_role.customer_lookup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Required for tracing_config { mode = "Active" } on the function below
resource "aws_iam_role_policy_attachment" "customer_lookup_xray" {
  role       = aws_iam_role.customer_lookup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Define execution policy for getting and searching Amazon Connect customer profiles.
# profile:SearchProfiles and profile:GetProfile have no resource-level
# permissions in Connect Customer Profiles; AWS does not support scoping
# these to a domain ARN.
resource "aws_iam_policy" "lambda_customer_profiles_permissions" {
  name = "lambda-customer-lookup-customer-profiles-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "profile:SearchProfiles",
          "profile:GetProfile"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_connect_customer_profiles" {
  role       = aws_iam_role.customer_lookup.name
  policy_arn = aws_iam_policy.lambda_customer_profiles_permissions.arn
}

# Publish permission for the contact-center-events EventBridge bus. Scoped
# to the specific bus ARN passed in via var.event_bus_arn.
resource "aws_iam_policy" "customer_lookup_eventbridge" {
  name = "lambda-customer-lookup-eventbridge-policy-${var.environment}"
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

resource "aws_iam_role_policy_attachment" "customer_lookup_eventbridge" {
  role       = aws_iam_role.customer_lookup.name
  policy_arn = aws_iam_policy.customer_lookup_eventbridge.arn
}

# Dead-letter queue, defense-in-depth only -- this Lambda is invoked
# synchronously via InvokeFlowModule, same rationale as
# modules/lambda/main.tf's eligibility_check_dlq.
resource "aws_sqs_queue" "customer_lookup_dlq" {
  name                    = "lambda-customer-lookup-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_iam_role_policy" "customer_lookup_dlq" {
  name = "lambda-customer-lookup-dlq-policy-${var.environment}"
  role = aws_iam_role.customer_lookup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.customer_lookup_dlq.arn
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
resource "aws_lambda_function" "customer_lookup" {
  function_name = var.function_name
  role          = aws_iam_role.customer_lookup.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  s3_bucket     = var.s3_bucket_lambda_artifacts
  s3_key        = var.s3_key
  publish       = true
  environment {
    variables = {
      CUSTOMER_PROFILES_DOMAIN = var.customer_profiles_domain_name
      EVENT_BUS_NAME           = var.event_bus_name
    }
  }
  layers = [var.layer_arn]

  kms_key_arn = data.aws_kms_key.lambda_default.arn

  # No reserved_concurrent_executions -- see modules/lambda/main.tf for why.

  dead_letter_config {
    target_arn = aws_sqs_queue.customer_lookup_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }
}

# Lambda alias that will update when new versions are deployed
resource "aws_lambda_alias" "customer_lookup_live" {
  name             = "live"
  function_name    = aws_lambda_function.customer_lookup.function_name
  function_version = aws_lambda_function.customer_lookup.version
}
