locals {
  branch_subs = flatten([
    for branch in var.allowed_branches : [
      "repo:${var.github_repo}:ref:refs/heads/${branch}",
      "repo:${var.github_repo_numeric}:ref:refs/heads/${branch}",
    ]
  ])

  environment_subs = flatten([
    for env in var.allowed_environments : [
      "repo:${var.github_repo}:environment:${env}",
      "repo:${var.github_repo_numeric}:environment:${env}",
    ]
  ])

  pull_request_subs = var.allow_pull_requests ? [
    "repo:${var.github_repo}:pull_request",
    "repo:${var.github_repo_numeric}:pull_request",
  ] : []

  allowed_subs = concat(local.branch_subs, local.environment_subs, local.pull_request_subs)
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_subs
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
}
