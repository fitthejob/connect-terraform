
variable "environment" {
  description = "Environment name (dev, staging, prod) — suffixed onto IAM role/policy names so all three environments can coexist in the same AWS account"
  type        = string
}

variable "instance_name" {
  description = "Short unique name for this subscriber instance (e.g. \"contact-initiated-metric\") — used in IAM role/policy naming so multiple instances of this module can coexist"
  type        = string
}

variable "s3_bucket_lambda_artifacts" {
  description = "S3 bucket for Amazon Connect Lambdas"
  type        = string
}

variable "s3_key" {
  description = "S3 key for the event-metric-subscriber Lambda artifact zip (shared across all instances — same code, different env vars)"
  type        = string
}

variable "function_name" {
  description = "Name of this subscriber Lambda instance"
  type        = string
}

variable "layer_arn" {
  description = "ARN of the shared dependencies Lambda layer"
  type        = string
}

variable "metric_name" {
  description = "CloudWatch metric name this instance publishes under the ContactCenter/Events namespace"
  type        = string
}

variable "dimension_field" {
  description = "Field on the event detail to use as a CloudWatch metric dimension (e.g. \"queue\", \"verificationStatus\"). Empty string for no dimension."
  type        = string
  default     = ""
}

variable "value_field" {
  description = "Field on the event detail to use as the metric value (e.g. \"durationSeconds\"). Empty string to count invocations (value 1) instead."
  type        = string
  default     = ""
}
