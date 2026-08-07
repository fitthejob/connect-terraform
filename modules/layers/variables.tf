variable "environment" {
  description = "Environment name (dev, staging, prod) — suffixed onto the layer name so all three environments can coexist in the same AWS account"
  type        = string
}

variable "s3_bucket_lambda_artifacts" {
  description = "Layer zips bucket"
  type        = string
}

variable "shared_deps_layer_s3_key" {
  description = "S3 key for the shared dependencies layer zip"
  type        = string
}

variable "compatible_runtimes" {
  description = "Compatible runtimes for the shared dependencies layer"
  type        = list(string)
  default     = ["nodejs24.x"]
}
