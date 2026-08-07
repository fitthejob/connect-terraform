variable "aws_connect_alias" {
  description = "AWS Connect instance alias"
  type        = string
}

variable "customer_profiles_domain_name" {
  description = "Amazon Connect Customer Profiles Domain name"
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

variable "s3_bucket_lambda_artifacts" {
  description = "S3 bucket for Amazon Connect Lambdas"
  type        = string
}

# Eligibility check Lambda variables

variable "lambda_eligibility_check_s3_key" {
  description = "S3 key for the eligibility check Lambda artifact zip"
  type        = string
}

variable "lambda_eligibility_check_function_name" {
  description = "Name of the eligibility check Lambda"
  type        = string
}

# layers vars

variable "shared_deps_layer_s3_key" {
  description = "S3 key for the shared dependencies layer zip"
  type        = string
}

# lex vars

variable "lex_bot_name" {
  description = "Name for the main menu Lex bot instance"
  type        = string
}
