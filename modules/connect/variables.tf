variable "environment" {
  description = "Environment name (dev, staging, prod) — suffixed onto every named Connect resource so all three environments can coexist on the same shared Connect instance"
  type        = string
}

variable "aws_connect_alias" {
  description = "AWS Connect instance alias"
  type        = string
}

variable "hours_of_operation_name" {
  description = "Name of the hours of operation to associate with queues"
  type        = string
}

variable "queue_claims_max_contacts" {
  description = "Max contacts for the claims queue"
  type        = number
  default     = 10
}

variable "queue_benefits_max_contacts" {
  description = "Max contacts for the benfits queue"
  type        = number
  default     = 10
}

variable "queue_authorizations_max_contacts" {
  description = "Max contacts for the authorizations queue"
  type        = number
  default     = 10
}

variable "queue_billing_max_contacts" {
  description = "Max contacts for the billing queue"
  type        = number
  default     = 10
}

variable "queue_general_max_contacts" {
  description = "Max contacts for the general queue"
  type        = number
  default     = 10
}

variable "s3_bucket_call_recordings" {
  description = "S3 bucket for call recordings"
  type        = string
}

variable "aws_lex_bot_alias_arn" {
  description = "ARN of the Lex bot alias to associate with this Connect instance"
  type        = string
}

variable "enable_load_test_sandbox" {
  description = "Whether to provision the Load-Test-Sandbox-{env} contact flow and sync a Connect test case against it. Only environments/dev sets this true today — the load-testing IAM role and EventBridge pipeline this depends on are dev-only."
  type        = bool
  default     = false
}

variable "connect_phone_number" {
  description = "A phone number already claimed on this Connect instance, used as the SourcePhoneNumber (not DestinationPhoneNumber, which is omitted entirely) for the load-test sandbox's synthetic test case entry point. Required (non-empty) only when enable_load_test_sandbox is true — this is a real claimed number, not a placeholder; Connect uses it to resolve which flow a simulated contact enters."
  type        = string
  default     = ""
}
