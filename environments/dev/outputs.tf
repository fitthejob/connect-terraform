output "validation_sandbox_contact_flow_id" {
  description = "Contact flow ID of the CI validation sandbox flow"
  value       = module.connect.validation_sandbox_contact_flow_id
}

output "connect_instance_id" {
  description = "Amazon Connect instance ID"
  value       = module.connect.connect_instance_id
}

output "queue_claims_id" {
  description = "Claims Queue ID"
  value       = module.connect.queue_claims_id
}

output "queue_benefits_id" {
  description = "Benefits Queue ID"
  value       = module.connect.queue_benefits_id
}

output "queue_authorizations_id" {
  description = "Authorizations Queue ID"
  value       = module.connect.queue_authorizations_id
}

output "queue_billing_id" {
  description = "Billing Queue ID"
  value       = module.connect.queue_billing_id
}

output "queue_general_id" {
  description = "General Queue ID"
  value       = module.connect.queue_general_id
}

output "lex_bot_alias_arn" {
  description = "ARN of the Lex bot alias associated with this instance"
  value       = module.lex.bot_alias_arn
}
