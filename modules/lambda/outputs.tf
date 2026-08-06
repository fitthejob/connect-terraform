
# Base function, use for IAM policies and CloudWatch
output "lambda_eligibility_check_function_arn" {
  description = "Eligibility check Lambda ARN"
  value       = aws_lambda_function.eligibility_check.arn
}

# Use for referencing in other resources
output "lambda_eligibility_check_function_name" {
  description = "Eligibility check Lambda name"
  value       = aws_lambda_function.eligibility_check.function_name
}

# Invoked by Connect and contact flows
output "lambda_eligibility_check_alias_arn" {
  description = "Eligibility check Lambda alias"
  value       = aws_lambda_alias.eligibility_check_live.arn
}


