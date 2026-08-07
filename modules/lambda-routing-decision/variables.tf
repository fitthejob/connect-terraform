
variable "environment" {
  description = "Environment name (dev, staging, prod) — suffixed onto IAM role/policy names so all three environments can coexist in the same AWS account"
  type        = string
}

variable "s3_bucket_lambda_artifacts" {
  description = "S3 bucket for Amazon Connect Lambdas"
  type        = string
}

variable "s3_key" {
  description = "S3 key for the routing-decision Lambda artifact zip"
  type        = string
}

variable "function_name" {
  description = "Name of the routing-decision Lambda"
  type        = string
}

variable "layer_arn" {
  description = "ARN of the shared dependencies Lambda layer"
  type        = string
}

variable "queue_claims_arn" {
  description = "ARN of the claims queue"
  type        = string
}

variable "queue_benefits_arn" {
  description = "ARN of the benefits queue"
  type        = string
}

variable "queue_authorizations_arn" {
  description = "ARN of the authorizations queue"
  type        = string
}

variable "queue_billing_arn" {
  description = "ARN of the billing queue"
  type        = string
}

variable "queue_general_arn" {
  description = "ARN of the general queue"
  type        = string
}
