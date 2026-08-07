
# IAM role for eligibility check Lambda - Assume role via STS
resource "aws_iam_role" "eligibility_check" {
  name = "lambda-eligibility-check-role-${var.environment}"

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

# Assign AWS managed basic execution policy to lambda-eligibility-check-role
resource "aws_iam_role_policy_attachment" "eligibility_check_basic" {
  role       = aws_iam_role.eligibility_check.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Required for tracing_config { mode = "Active" } on the function below
resource "aws_iam_role_policy_attachment" "eligibility_check_xray" {
  role       = aws_iam_role.eligibility_check.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Define execution policy for getting and searching Amazon Connect customer profiles.
# profile:SearchProfiles and profile:GetProfile have no resource-level
# permissions in Connect Customer Profiles; AWS does not support scoping
# these to a domain ARN.
resource "aws_iam_policy" "lambda_customer_profiles_permissions" {
  name = "lambda-eligibility-check-customer-profiles-policy-${var.environment}"
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

# Attach execution policy for Connect customer profiles to lambda-eligibility-check-role
resource "aws_iam_role_policy_attachment" "lambda_connect_customer_profiles" {
  role       = aws_iam_role.eligibility_check.name
  policy_arn = aws_iam_policy.lambda_customer_profiles_permissions.arn
}

# Dead-letter queue for the eligibility check Lambda. Amazon Connect invokes
# this function synchronously (RequestResponse), so a failure surfaces
# directly in the call flow rather than through Lambda's own async retry
# path -- this DLQ is defense-in-depth for any future async invocation
# source (e.g. EventBridge, SNS), not the Connect-triggered call path.
resource "aws_sqs_queue" "eligibility_check_dlq" {
  name                    = "lambda-eligibility-check-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_iam_role_policy" "eligibility_check_dlq" {
  name = "lambda-eligibility-check-dlq-policy-${var.environment}"
  role = aws_iam_role.eligibility_check.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.eligibility_check_dlq.arn
      }
    ]
  })
}

# AWS-managed key for encrypting the Lambda's environment variables at
# rest. Using the account's existing managed key rather than a
# customer-managed one avoids owning a key policy for a single Lambda.
data "aws_kms_key" "lambda_default" {
  key_id = "alias/aws/lambda"
}

# Lambda eligibility check function. Not placed in a VPC: this is a
# prototype build. In a live build, this Lambda would be moved into a VPC
# (with NAT/VPC endpoints for Connect Customer Profiles access) for network
# isolation. Deferred here to avoid introducing VPC/subnet/NAT infra and the
# cold-start latency hit on a function in a live customer call path before
# that tradeoff is decided on. (See .checkov.yml for the CKV_AWS_117 skip --
# Checkov's inline checkov:skip comment doesn't suppress this specific check.)
resource "aws_lambda_function" "eligibility_check" {
  function_name = var.lambda_eligibility_check_function_name
  role          = aws_iam_role.eligibility_check.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  s3_bucket     = var.s3_bucket_lambda_artifacts
  s3_key        = var.lambda_eligibility_check_s3_key
  publish       = true
  environment {
    variables = {
      CUSTOMER_PROFILES_DOMAIN = var.customer_profiles_domain_name
    }
  }
  layers = [var.layer_arn]

  kms_key_arn = data.aws_kms_key.lambda_default.arn

  # Caps concurrent executions so a spike in calls can't consume the
  # account's entire concurrency pool and starve other Lambdas.
  reserved_concurrent_executions = 20

  dead_letter_config {
    target_arn = aws_sqs_queue.eligibility_check_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }
}

# Lambda alias that will update when new versions are deployed
resource "aws_lambda_alias" "eligibility_check_live" {
  name             = "live"
  function_name    = aws_lambda_function.eligibility_check.function_name
  function_version = aws_lambda_function.eligibility_check.version
}

# Associate Lambda function to Connect instance
resource "aws_connect_lambda_function_association" "eligibility_check_assoc" {
  instance_id  = var.connect_instance_id
  function_arn = aws_lambda_alias.eligibility_check_live.arn
}
