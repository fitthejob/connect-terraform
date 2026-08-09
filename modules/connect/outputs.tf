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
  description = "Authorizations Queue ID"
  value       = aws_connect_queue.authorizations.queue_id
}

output "queue_authorizations_arn" {
  description = "Authorizations Queue ARN"
  value       = aws_connect_queue.authorizations.arn
}

output "queue_billing_id" {
  description = "Billing Queue ID"
  value       = aws_connect_queue.billing.queue_id
}

output "queue_billing_arn" {
  description = "Billing Queue ARN"
  value       = aws_connect_queue.billing.arn
}

output "queue_general_id" {
  description = "General Queue ID"
  value       = aws_connect_queue.general.queue_id
}

output "queue_general_arn" {
  description = "General Queue ARN"
  value       = aws_connect_queue.general.arn
}

output "routing_profile_basic_id" {
  description = "Basic Routing Profile ID"
  value       = aws_connect_routing_profile.basic.routing_profile_id
}

output "validation_sandbox_contact_flow_id" {
  description = "Contact flow ID of the CI validation sandbox flow"
  value       = aws_connect_contact_flow.validation_sandbox.contact_flow_id
}

output "agent_whisper_flow_id" {
  description = "Contact flow ID of the shared Agent Whisper flow"
  value       = aws_connect_contact_flow.agent_whisper.contact_flow_id
}

output "validation_sandbox_module_id" {
  description = "Contact flow module ID of the CI validation sandbox module"
  value       = aws_connect_contact_flow_module.validation_sandbox_module.contact_flow_module_id
}

output "callback_offer_module_id" {
  description = "Contact flow module ID of the CallbackOffer flow module"
  value       = aws_connect_contact_flow_module.callback_offer.contact_flow_module_id
}

output "module_customer_lookup_id" {
  description = "Contact flow module ID of the CustomerLookup flow module"
  value       = aws_connect_contact_flow_module.module_customer_lookup.contact_flow_module_id
}

output "module_sms_verification_id" {
  description = "Contact flow module ID of the SmsVerification flow module"
  value       = aws_connect_contact_flow_module.module_sms_verification.contact_flow_module_id
}
