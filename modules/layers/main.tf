resource "aws_lambda_layer_version" "shared_deps" {
  layer_name          = "connect-shared-dependencies-${var.environment}"
  s3_bucket           = var.s3_bucket_lambda_artifacts
  s3_key              = var.shared_deps_layer_s3_key
  compatible_runtimes = ["nodejs18.x"]
}
