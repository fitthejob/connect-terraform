
output "function_arn" {
  description = "contact-event-publisher Lambda ARN"
  value       = aws_lambda_function.contact_event_publisher.arn
}

output "function_name" {
  description = "contact-event-publisher Lambda name"
  value       = aws_lambda_function.contact_event_publisher.function_name
}

output "alias_arn" {
  description = "contact-event-publisher Lambda alias ARN — reference this from voice/chat contact flows' InvokeLambdaFunction actions at initiation/transfer/disconnect points"
  value       = aws_lambda_alias.contact_event_publisher_live.arn
}
