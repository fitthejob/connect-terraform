
output "function_arn" {
  description = "event-metric-subscriber Lambda ARN"
  value       = aws_lambda_function.subscriber.arn
}

output "alias_arn" {
  description = "event-metric-subscriber Lambda alias ARN — target this from all four EventBridge rules"
  value       = aws_lambda_alias.subscriber_live.arn
}

output "function_name" {
  description = "event-metric-subscriber Lambda function name — needed for aws_lambda_permission's function_name argument"
  value       = aws_lambda_function.subscriber.function_name
}
