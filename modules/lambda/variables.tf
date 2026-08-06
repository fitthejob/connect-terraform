
variable "s3_bucket_lambda_artifacts" {
  description = "S3 bucket for Amazon Connect Lambdas"
  type        = string
}

variable "lambda_eligibility_check_s3_key" {
  description = "S3 key for the eligibility check Lambda artifact zip"
  type        = string
}

variable "lambda_eligibility_check_function_name" {
  description = "Name of the eligibility check Lambda"
  type        = string
}

variable "layer_arn" {
  description = "ARN of the shared dependencies Lambda layer"
  type        = string
}

variable "connect_instance_id" {
  description = "Amazon Connect instance ID"
  type        = string
}

variable "customer_profiles_domain_name" {
  description = "Amazon Connect Customer Profiles Domain name"
  type        = string
}
