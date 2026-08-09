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

output "agent_whisper_flow_id" {
  description = "Contact flow ID of the shared Agent Whisper flow"
  value       = module.connect.agent_whisper_flow_id
}

output "agent_whisper_flow_arn" {
  description = "Contact flow ARN of the shared Agent Whisper flow (required by UpdateContactEventHooks)"
  value       = module.connect.agent_whisper_flow_arn
}

output "customer_lookup_lambda_arn" {
  description = "Alias ARN of the customer-lookup Lambda"
  value       = module.lambda_customer_lookup.alias_arn
}

output "routing_decision_lambda_arn" {
  description = "Alias ARN of the routing-decision Lambda"
  value       = module.lambda_routing_decision.alias_arn
}

output "sms_verification_lambda_arn" {
  description = "Alias ARN of the sms-verification Lambda"
  value       = module.lambda_sms_verification.alias_arn
}

output "contact_event_publisher_lambda_arn" {
  description = "Alias ARN of the contact-event-publisher Lambda"
  value       = module.lambda_contact_event_publisher.alias_arn
}

output "queue_claims_arn" {
  description = "Claims Queue ARN"
  value       = module.connect.queue_claims_arn
}

output "queue_benefits_arn" {
  description = "Benefits Queue ARN"
  value       = module.connect.queue_benefits_arn
}

output "queue_authorizations_arn" {
  description = "Authorizations Queue ARN"
  value       = module.connect.queue_authorizations_arn
}

output "queue_billing_arn" {
  description = "Billing Queue ARN"
  value       = module.connect.queue_billing_arn
}

output "queue_general_arn" {
  description = "General Queue ARN"
  value       = module.connect.queue_general_arn
}
