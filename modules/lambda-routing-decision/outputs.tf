
output "function_arn" {
  description = "routing-decision Lambda ARN"
  value       = aws_lambda_function.routing_decision.arn
}

output "function_name" {
  description = "routing-decision Lambda name"
  value       = aws_lambda_function.routing_decision.function_name
}

output "alias_arn" {
  description = "routing-decision Lambda alias ARN — reference this from the voice/chat contact flow's InvokeLambdaFunction action"
  value       = aws_lambda_alias.routing_decision_live.arn
}
