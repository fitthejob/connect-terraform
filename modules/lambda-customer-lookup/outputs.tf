
output "function_arn" {
  description = "customer-lookup Lambda ARN"
  value       = aws_lambda_function.customer_lookup.arn
}

output "function_name" {
  description = "customer-lookup Lambda name"
  value       = aws_lambda_function.customer_lookup.function_name
}

output "alias_arn" {
  description = "customer-lookup Lambda alias ARN — reference this from the customer-lookup flow module's InvokeLambdaFunction action"
  value       = aws_lambda_alias.customer_lookup_live.arn
}
