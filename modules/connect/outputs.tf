output "connect_instance_id" {
  description = "Amazon Connect instance ID"
  value       = data.aws_connect_instance.main.id
}

output "queue_claims_id" {
  description = "Claims Queue ID"
  value       = aws_connect_queue.claims.queue_id
}

output "queue_claims_arn" {
  description = "Claims Queue ARN"
  value       = aws_connect_queue.claims.arn
}

output "queue_benefits_id" {
  description = "Benefits Queue ID"
  value       = aws_connect_queue.benefits.queue_id
}

output "queue_benefits_arn" {
  description = "Benefits Queue ARN"
  value       = aws_connect_queue.benefits.arn
}

output "queue_authorizations_id" {
  description = "Claims Queue ID"
  value       = aws_connect_queue.authorizations.queue_id
}

output "queue_authorizations_arn" {
  description = "authorizations Queue ARN"
  value       = aws_connect_queue.authorizations.arn
}

output "routing_profile_basic_id" {
  description = "Basic Routing Profile ID"
  value       = aws_connect_routing_profile.basic.routing_profile_id
}
