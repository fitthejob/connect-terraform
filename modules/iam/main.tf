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
  description        = var.role_description
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_region" "current" {}

locals {
  iam_scoped_resources = flatten([
    for env in var.environments : [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/lambda-eligibility-check-role-${env}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/lambda-eligibility-check-customer-profiles-policy-${env}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/connect-lex-menu-${env}-role",
    ]
  ])

  # eligibility-check-{env} is this repo's fixed Lambda naming convention
  # (see environments/*/terraform.tfvars: lambda_eligibility_check_function_name).
  lambda_scoped_resources = flatten([
    for env in var.environments : [
      "arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:eligibility-check-${env}",
      "arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:eligibility-check-${env}:*",
    ]
  ])

  sqs_scoped_resources = flatten([
    for env in var.environments : [
      "arn:aws:sqs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:lambda-eligibility-check-dlq-${env}",
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
      "connect:CreateContactFlowModule",
      "connect:UpdateContactFlowModule*",
      "connect:DeleteContactFlowModule",
      "connect:AssociateLambdaFunction",
      "connect:DisassociateLambdaFunction",
      "connect:ListLambdaFunctions",
    ]
    # Could be scoped to the specific Connect instance ARN
    # (arn:aws:connect:region:account:instance/instance-id), but modules/iam
    # doesn't currently take the instance ID/alias as an input — a real
    # follow-up, not done here.
    resources = ["*"]
  }

  statement {
    sid    = "LambdaFunctionManage"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetAlias",
      "lambda:GetPolicy",
      "lambda:ListVersionsByFunction",
      "lambda:ListAliases",
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:PublishVersion",
      "lambda:PutFunctionConcurrency",
      "lambda:DeleteFunctionConcurrency",
      "lambda:GetFunctionConcurrency",
      "lambda:CreateAlias",
      "lambda:UpdateAlias",
      "lambda:DeleteAlias",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = local.lambda_scoped_resources
  }

  statement {
    sid    = "SqsDlqManage"
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:CreateQueue",
      "sqs:SetQueueAttributes",
      "sqs:DeleteQueue",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "sqs:ListQueueTags",
    ]
    resources = local.sqs_scoped_resources
  }

  statement {
    sid    = "LambdaKmsKeyRead"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
    ]
    resources = ["arn:aws:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:key/*"]
  }

  statement {
    sid    = "LambdaLayerManage"
    effect = "Allow"
    actions = [
      "lambda:GetLayerVersion",
      "lambda:ListLayerVersions",
      "lambda:PublishLayerVersion",
      "lambda:DeleteLayerVersion",
    ]
    # Layer version numbers are assigned by AWS on publish and aren't known
    # ahead of time; not scopable before the first PublishLayerVersion call.
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
    # lex:CreateBot's target doesn't exist before the call (the bot ID is
    # assigned by AWS on creation), so this can't be scoped ahead of a first
    # apply.
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
    # See ConnectManage above — same instance-ARN scoping opportunity,
    # deferred as a follow-up.
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
    sid     = "CallerIdentityForArnConstruction"
    effect  = "Allow"
    actions = ["sts:GetCallerIdentity"]
    # sts:GetCallerIdentity has no resource-level permissions at all — it is
    # account/caller introspection, not a resource-scoped action.
    resources = ["*"]
  }
}

# Split from deploy_permissions above: a single aws_iam_policy has a hard
# 6144-character size limit, and adding these statements to
# deploy_permissions directly exceeded it (CreatePolicyVersion:
# LimitExceeded). This is a second policy document attached to the same
# deploy role, not a separate permissions profile.
data "aws_iam_policy_document" "deploy_permissions_contact_center" {
  count = var.permissions_profile == "deploy" ? 1 : 0

  # --- Contact center prototype spec (docs/superpowers/specs/contact-center-prototype-spec.md), Phase 0 ---
  # Drafted from AWS IAM action references ahead of Phase 1+ work so the
  # apply -> AccessDenied -> add-permission loop from the eligibility-check
  # build doesn't repeat wholesale. TODO: scope resources down to specific
  # ARNs once Phase 1's actual DynamoDB table name, SNS topic name, and
  # EventBridge bus/rule names are decided -- "*" here is a starting point,
  # not the intended final shape.

  statement {
    sid    = "DynamoDbVerificationTableManage"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:UpdateTable",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:ListTagsOfResource",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SnsVerificationTopicManage"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:ListSubscriptionsByTopic",
      "sns:Publish",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EventBridgePipelineManage"
    effect = "Allow"
    actions = [
      "events:CreateEventBus",
      "events:DeleteEventBus",
      "events:DescribeEventBus",
      "events:TagResource",
      "events:UntagResource",
      "events:ListTagsForResource",
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:ListRules",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:ListTargetsByRule",
      "events:CreateArchive",
      "events:DeleteArchive",
      "events:DescribeArchive",
      "events:UpdateArchive",
      "events:PutEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchAlarmManage"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource",
    ]
    # PutMetricAlarm has no resource-level permissions for alarm creation
    # itself in most action contexts; scoped to alarm-name patterns once
    # Phase 2's alarm naming convention is decided.
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
    # See ConnectManage in deploy_permissions above — same instance-ARN
    # scoping opportunity, deferred as a follow-up.
    resources = ["*"]
  }

  statement {
    sid    = "LambdaFunctionReadOnly"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetAlias",
      "lambda:ListVersionsByFunction",
      "lambda:ListAliases",
      "lambda:GetPolicy",
    ]
    resources = local.lambda_scoped_resources
  }

  statement {
    sid    = "LambdaLayerReadOnly"
    effect = "Allow"
    actions = [
      "lambda:GetLayerVersion",
      "lambda:ListLayerVersions",
    ]
    # See LambdaLayerManage in deploy_permissions above — layer version
    # numbers aren't known ahead of time.
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
    resources = local.iam_scoped_resources
  }

  statement {
    sid    = "StateBucketAccess"
    effect = "Allow"
    # terraform plan still acquires the S3-native state lock (use_lockfile =
    # true in environments/*/backend.tf), which requires PutObject/
    # DeleteObject on the .tflock file even for a read-only plan.
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}",
      "arn:aws:s3:::${var.tfstate_bucket}/*",
    ]
  }
}

resource "aws_iam_policy" "this" {
  name   = coalesce(var.policy_name, var.role_name)
  policy = var.permissions_profile == "deploy" ? data.aws_iam_policy_document.deploy_permissions[0].json : data.aws_iam_policy_document.pr_checks_permissions[0].json
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

# Second policy for the deploy profile only -- see the comment on
# deploy_permissions_contact_center above for why this is split out.
resource "aws_iam_policy" "contact_center" {
  count  = var.permissions_profile == "deploy" ? 1 : 0
  name   = "${coalesce(var.policy_name, var.role_name)}-contact-center"
  policy = data.aws_iam_policy_document.deploy_permissions_contact_center[0].json
}

resource "aws_iam_role_policy_attachment" "contact_center" {
  count      = var.permissions_profile == "deploy" ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.contact_center[0].arn
}
