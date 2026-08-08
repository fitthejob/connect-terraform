output "validation_sandbox_contact_flow_id" {
  description = "Contact flow ID of the CI validation sandbox flow"
  value       = module.connect.validation_sandbox_contact_flow_id
}

output "validation_sandbox_module_id" {
  description = "Contact flow module ID of the CI validation sandbox module"
  value       = module.connect.validation_sandbox_module_id
}

output "callback_offer_module_id" {
  description = "Contact flow module ID of the CallbackOffer flow module"
  value       = module.connect.callback_offer_module_id
}

output "module_customer_lookup_id" {
  description = "Contact flow module ID of the CustomerLookup flow module"
  value       = module.connect.module_customer_lookup_id
}

output "module_sms_verification_id" {
  description = "Contact flow module ID of the SmsVerification flow module"
  value       = module.connect.module_sms_verification_id
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
