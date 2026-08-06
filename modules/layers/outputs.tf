output "shared_deps_layer_arn" {
  description = "ARN of the shared dependencies Lambda layer"
  value       = aws_lambda_layer_version.shared_deps.arn
}
