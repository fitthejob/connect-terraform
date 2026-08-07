module "deploy_role" {
  source = "../../modules/iam"

  role_name            = "github-connect-deploy-dev"
  role_description     = "GitHub Actions deploy-dev - apply-capable, main branch only"
  github_repo          = var.github_repo
  github_repo_numeric  = var.github_repo_numeric
  allowed_branches     = ["main"]
  allowed_environments = ["staging", "prod"]
  allow_pull_requests  = false

  permissions_profile     = "deploy"
  environments            = ["dev", "staging", "prod"]
  lambda_artifacts_bucket = var.lambda_artifacts_bucket
  tfstate_bucket          = var.tfstate_bucket
}

module "pr_checks_role" {
  source = "../../modules/iam"

  role_name           = "github-connect-pr-checks"
  role_description    = "GitHub Actions PR checks - plan only, no apply"
  policy_name         = "github-connect-pr-checks-readonly"
  github_repo         = var.github_repo
  github_repo_numeric = var.github_repo_numeric
  allow_pull_requests = true

  permissions_profile     = "pr_checks"
  environments            = ["dev", "staging", "prod"]
  lambda_artifacts_bucket = var.lambda_artifacts_bucket
  tfstate_bucket          = var.tfstate_bucket
}
