output "function_arn" {
  description = "abandonment-metric Lambda ARN"
  value       = aws_lambda_function.abandonment_metric.arn
}

output "function_name" {
  description = "abandonment-metric Lambda name"
  value       = aws_lambda_function.abandonment_metric.function_name
}

output "alias_arn" {
  description = "abandonment-metric Lambda alias ARN -- reference this from the EventBridge Scheduler target"
  value       = aws_lambda_alias.abandonment_metric_live.arn
}

output "alias_name" {
  description = "abandonment-metric Lambda alias name -- needed by the Scheduler target's qualifier"
  value       = aws_lambda_alias.abandonment_metric_live.name
}

output "dedup_table_name" {
  description = "DynamoDB table name for poll-cycle dedup"
  value       = aws_dynamodb_table.dedup.name
}
