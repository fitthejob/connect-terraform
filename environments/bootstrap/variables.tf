variable "github_repo" {
  description = "owner/repo, e.g. fitthejob/connect-terraform"
  type        = string
}

variable "github_repo_numeric" {
  description = "GitHub's numeric-ID-suffixed repo identifier — find via CloudTrail on a real Actions run's AssumeRoleWithWebIdentity event, in the sub claim"
  type        = string
}

variable "lambda_artifacts_bucket" {
  description = "S3 bucket name for Lambda/layer build artifacts"
  type        = string
}

variable "tfstate_bucket" {
  description = "S3 bucket name for Terraform remote state"
  type        = string
}
