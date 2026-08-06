
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

# Define execution policy for getting and searching Amazon Connect customer profiles
resource "aws_iam_policy" "lambda_customer_profiles_permissions" {
  name = "lambda-eligibility-check-customer-profiles-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "profile:SearchProfiles",
          "profile:GetProfile"
        ]
      }
    ]
  })
}

# Attach execution policy for Connect customer profiles to lambda-eligibility-check-role
resource "aws_iam_role_policy_attachment" "lambda_connect_customer_profiles" {
  role       = aws_iam_role.eligibility_check.name
  policy_arn = aws_iam_policy.lambda_customer_profiles_permissions.arn
}

# Lambda eligibility check function
resource "aws_lambda_function" "eligibility_check" {
  function_name = "lambda-eligibility-check"
  role          = aws_iam_role.eligibility_check.arn
  runtime       = "nodejs18.x"
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
