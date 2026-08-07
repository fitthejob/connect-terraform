
variable "environment" {
  description = "Environment name (dev, staging, prod) — suffixed onto IAM role/policy names so all three environments can coexist in the same AWS account"
  type        = string
}

variable "s3_bucket_lambda_artifacts" {
  description = "S3 bucket for Amazon Connect Lambdas"
  type        = string
}

variable "s3_key" {
  description = "S3 key for the contact-event-publisher Lambda artifact zip"
  type        = string
}

variable "function_name" {
  description = "Name of the contact-event-publisher Lambda"
  type        = string
}

variable "layer_arn" {
  description = "ARN of the shared dependencies Lambda layer"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the contact-center-events EventBridge bus"
  type        = string
}

variable "event_bus_arn" {
  description = "ARN of the contact-center-events EventBridge bus, for IAM scoping"
  type        = string
}
