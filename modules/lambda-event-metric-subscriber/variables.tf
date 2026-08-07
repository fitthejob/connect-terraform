
variable "environment" {
  description = "Environment name (dev, staging, prod) — suffixed onto IAM role/policy names so all three environments can coexist in the same AWS account"
  type        = string
}

variable "s3_bucket_lambda_artifacts" {
  description = "S3 bucket for Amazon Connect Lambdas"
  type        = string
}

variable "s3_key" {
  description = "S3 key for the event-metric-subscriber Lambda artifact zip"
  type        = string
}

variable "function_name" {
  description = "Name of the event-metric-subscriber Lambda"
  type        = string
}

variable "layer_arn" {
  description = "ARN of the shared dependencies Lambda layer"
  type        = string
}
