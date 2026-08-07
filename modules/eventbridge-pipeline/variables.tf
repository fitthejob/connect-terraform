
variable "environment" {
  description = "Environment name (dev, staging, prod) — suffixed onto all resource names so all three environments can coexist in the same AWS account"
  type        = string
}

variable "contact_initiated_subscriber_alias_arn" {
  description = "Alias ARN of the contact.initiated metric subscriber Lambda"
  type        = string
}

variable "contact_initiated_subscriber_function_name" {
  description = "Function name of the contact.initiated metric subscriber Lambda"
  type        = string
}

variable "contact_transferred_subscriber_alias_arn" {
  description = "Alias ARN of the contact.transferred metric subscriber Lambda"
  type        = string
}

variable "contact_transferred_subscriber_function_name" {
  description = "Function name of the contact.transferred metric subscriber Lambda"
  type        = string
}

variable "contact_disconnected_subscriber_alias_arn" {
  description = "Alias ARN of the contact.disconnected metric subscriber Lambda"
  type        = string
}

variable "contact_disconnected_subscriber_function_name" {
  description = "Function name of the contact.disconnected metric subscriber Lambda"
  type        = string
}

variable "verification_completed_subscriber_alias_arn" {
  description = "Alias ARN of the verification.completed metric subscriber Lambda"
  type        = string
}

variable "verification_completed_subscriber_function_name" {
  description = "Function name of the verification.completed metric subscriber Lambda"
  type        = string
}
