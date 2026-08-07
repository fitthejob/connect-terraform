
output "function_arn" {
  description = "This subscriber instance's Lambda ARN"
  value       = aws_lambda_function.subscriber.arn
}

output "alias_arn" {
  description = "This subscriber instance's Lambda alias ARN — target this from the EventBridge rule"
  value       = aws_lambda_alias.subscriber_live.arn
}

output "function_name" {
  description = "This subscriber instance's Lambda function name — needed for aws_lambda_permission's function_name argument"
  value       = aws_lambda_function.subscriber.function_name
}
