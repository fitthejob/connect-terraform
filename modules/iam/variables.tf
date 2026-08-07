variable "role_name" {
  description = "Name of the IAM role to create"
  type        = string
}

variable "github_repo" {
  description = "owner/repo, e.g. fitthejob/connect-terraform"
  type        = string
}

variable "github_repo_numeric" {
  description = "GitHub's numeric-ID-suffixed repo identifier, e.g. fitthejob@210087960/connect-terraform@1325218330 — GitHub includes this as an alternate sub-claim format alongside the plain one, discovered via CloudTrail when the plain-format-only trust policy rejected real GitHub Actions runs."
  type        = string
}

variable "allowed_branches" {
  description = "Branches allowed to assume this role on a push trigger (produces repo:OWNER/REPO:ref:refs/heads/<branch> sub claims, plus the numeric-ID variant)"
  type        = list(string)
  default     = []
}

variable "allowed_environments" {
  description = "GitHub environment names allowed to assume this role (produces repo:OWNER/REPO:environment:<name> sub claims, plus the numeric-ID variant, for jobs declaring an environment: key)"
  type        = list(string)
  default     = []
}

variable "allow_pull_requests" {
  description = "Allow the pull_request-triggered sub claim (repo:OWNER/REPO:pull_request, plus the numeric-ID variant)"
  type        = bool
  default     = false
}

variable "permissions_profile" {
  description = "Which permissions profile to attach: \"deploy\" (full read/write for CI deploys) or \"pr_checks\" (read-only, for PR validation)"
  type        = string

  validation {
    condition     = contains(["deploy", "pr_checks"], var.permissions_profile)
    error_message = "permissions_profile must be \"deploy\" or \"pr_checks\"."
  }
}

variable "environments" {
  description = "Environment names this role needs scoped IAM resource access for (only used when permissions_profile = \"deploy\"), e.g. [\"dev\", \"staging\", \"prod\"]"
  type        = list(string)
  default     = []
}

variable "lambda_artifacts_bucket" {
  description = "S3 bucket name for Lambda/layer build artifacts"
  type        = string
}

variable "tfstate_bucket" {
  description = "S3 bucket name for Terraform remote state"
  type        = string
}
