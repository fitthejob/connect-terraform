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

locals {
  iam_scoped_resources = flatten([
    for env in var.environments : [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/lambda-eligibility-check-role-${env}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/lambda-eligibility-check-customer-profiles-policy-${env}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/connect-lex-menu-${env}-role",
    ]
  ])
}

data "aws_iam_policy_document" "deploy_permissions" {
  count = var.permissions_profile == "deploy" ? 1 : 0

  statement {
    sid    = "ConnectManage"
    effect = "Allow"
    actions = [
      "connect:Describe*",
      "connect:Get*",
      "connect:List*",
      "connect:Search*",
      "connect:CreateQueue",
      "connect:UpdateQueue*",
      "connect:DeleteQueue",
      "connect:TagResource",
      "connect:UntagResource",
      "connect:CreateRoutingProfile",
      "connect:UpdateRoutingProfile*",
      "connect:DeleteRoutingProfile",
      "connect:CreateContactFlow",
      "connect:UpdateContactFlow*",
      "connect:DeleteContactFlow",
      "connect:AssociateLambdaFunction",
      "connect:DisassociateLambdaFunction",
      "connect:ListLambdaFunctions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LambdaManage"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetAlias",
      "lambda:GetLayerVersion",
      "lambda:GetPolicy",
      "lambda:ListVersionsByFunction",
      "lambda:ListAliases",
      "lambda:ListLayerVersions",
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:PublishVersion",
      "lambda:PublishLayerVersion",
      "lambda:DeleteLayerVersion",
      "lambda:CreateAlias",
      "lambda:UpdateAlias",
      "lambda:DeleteAlias",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IamScopedToThisStack"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
    ]
    resources = local.iam_scoped_resources
  }

  statement {
    sid    = "LexV2Manage"
    effect = "Allow"
    actions = [
      "lex:DescribeBot",
      "lex:CreateBot",
      "lex:UpdateBot",
      "lex:DeleteBot",
      "lex:ListBots",
      "lex:TagResource",
      "lex:UntagResource",
      "lex:ListTagsForResource",
      "lex:DescribeBotLocale",
      "lex:CreateBotLocale",
      "lex:UpdateBotLocale",
      "lex:DeleteBotLocale",
      "lex:ListBotLocales",
      "lex:BuildBotLocale",
      "lex:DescribeIntent",
      "lex:CreateIntent",
      "lex:UpdateIntent",
      "lex:DeleteIntent",
      "lex:ListIntents",
      "lex:DescribeBotVersion",
      "lex:CreateBotVersion",
      "lex:DeleteBotVersion",
      "lex:ListBotVersions",
      "lex:CreateBotAlias",
      "lex:UpdateBotAlias",
      "lex:DeleteBotAlias",
      "lex:DescribeBotAlias",
      "lex:ListBotAliases",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ConnectBotAssociation"
    effect = "Allow"
    actions = [
      "connect:AssociateBot",
      "connect:DisassociateBot",
      "connect:ListBots",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IamAwsManagedPolicyAttach"
    effect = "Allow"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
    ]
    resources = [
      "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
      "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",
    ]
  }

  statement {
    sid    = "LambdaArtifactsBucketRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.lambda_artifacts_bucket}",
      "arn:aws:s3:::${var.lambda_artifacts_bucket}/*",
    ]
  }

  statement {
    sid       = "LambdaArtifactsBucketWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.lambda_artifacts_bucket}/*"]
  }

  statement {
    sid    = "StateBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}",
      "arn:aws:s3:::${var.tfstate_bucket}/*",
    ]
  }

  statement {
    sid       = "CallerIdentityForArnConstruction"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "pr_checks_permissions" {
  count = var.permissions_profile == "pr_checks" ? 1 : 0

  statement {
    sid    = "ConnectReadOnly"
    effect = "Allow"
    actions = [
      "connect:Describe*",
      "connect:Get*",
      "connect:List*",
      "connect:Search*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LambdaReadOnly"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetAlias",
      "lambda:GetLayerVersion",
      "lambda:ListVersionsByFunction",
      "lambda:ListAliases",
      "lambda:ListLayerVersions",
      "lambda:GetPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IamReadOnly"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListPolicyVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "StateBucketAccess"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}",
      "arn:aws:s3:::${var.tfstate_bucket}/*",
    ]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.this.id
  policy = var.permissions_profile == "deploy" ? data.aws_iam_policy_document.deploy_permissions[0].json : data.aws_iam_policy_document.pr_checks_permissions[0].json
}
