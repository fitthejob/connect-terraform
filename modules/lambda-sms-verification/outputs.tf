
output "function_arn" {
  description = "sms-verification Lambda ARN"
  value       = aws_lambda_function.sms_verification.arn
}

output "function_name" {
  description = "sms-verification Lambda name"
  value       = aws_lambda_function.sms_verification.function_name
}

output "alias_arn" {
  description = "sms-verification Lambda alias ARN — reference this from the module-sms-verification flow module's InvokeLambdaFunction action"
  value       = aws_lambda_alias.sms_verification_live.arn
}

output "table_name" {
  description = "DynamoDB table name for verification codes"
  value       = aws_dynamodb_table.verification_codes.name
}
