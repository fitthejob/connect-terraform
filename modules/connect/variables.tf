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

variable "s3_bucket_call_recordings" {
  description = "S3 bucket for call recordings"
  type        = string
}
