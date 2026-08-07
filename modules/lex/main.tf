data "aws_iam_policy_document" "lex_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lexv2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lex_bot" {
  name               = "connect-lex-${var.bot_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lex_assume_role.json
}

data "aws_iam_policy_document" "lex_bot_permissions" {
  statement {
    effect = "Allow"
    # tfsec:ignore:aws-iam-no-policy-wildcards - polly:SynthesizeSpeech has no
    # resource-level permissions; AWS-managed Polly voices aren't ARN-addressable.
    actions   = ["polly:SynthesizeSpeech"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lex/connect-${var.bot_name}*"]
  }
}

resource "aws_iam_role_policy" "lex_bot" {
  name   = "connect-lex-${var.bot_name}-permissions"
  role   = aws_iam_role.lex_bot.id
  policy = data.aws_iam_policy_document.lex_bot_permissions.json
}

resource "aws_lexv2models_bot" "bot" {
  name     = "connect-${var.bot_name}"
  role_arn = aws_iam_role.lex_bot.arn

  data_privacy {
    child_directed = false
  }

  idle_session_ttl_in_seconds = 300

}

resource "aws_lexv2models_bot_locale" "en_us" {
  bot_id      = aws_lexv2models_bot.bot.id
  bot_version = "DRAFT"
  locale_id   = "en_US"

  n_lu_intent_confidence_threshold = 0.40

  voice_settings {
    voice_id = "Joanna"
    engine   = "neural"
  }
}

resource "aws_lexv2models_intent" "fallback" {
  bot_id                  = aws_lexv2models_bot.bot.id
  bot_version             = "DRAFT"
  locale_id               = aws_lexv2models_bot_locale.en_us.locale_id
  name                    = "FallbackIntent"
  parent_intent_signature = "AMAZON.FallbackIntent"
}

# claims intent

resource "aws_lexv2models_intent" "claims" {
  bot_id      = aws_lexv2models_bot.bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "ClaimsIntent"

  sample_utterance {
    utterance = "claims"
  }
  sample_utterance {
    utterance = "claim"
  }
  sample_utterance {
    utterance = "one"
  }
  sample_utterance {
    utterance = "file a claim"
  }
}

resource "aws_lexv2models_intent" "benefits" {
  bot_id      = aws_lexv2models_bot.bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "BenefitsIntent"

  sample_utterance {
    utterance = "benefits"
  }
  sample_utterance {
    utterance = "two"
  }
  sample_utterance {
    utterance = "my benefits"
  }
}

resource "aws_lexv2models_intent" "authorizations" {
  bot_id      = aws_lexv2models_bot.bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "AuthorizationsIntent"

  sample_utterance {
    utterance = "authorizations"
  }
  sample_utterance {
    utterance = "authorization"
  }
  sample_utterance {
    utterance = "three"
  }
}

resource "aws_lexv2models_intent" "billing" {
  bot_id      = aws_lexv2models_bot.bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "BillingIntent"

  sample_utterance {
    utterance = "billing"
  }
  sample_utterance {
    utterance = "four"
  }
  sample_utterance {
    utterance = "my bill"
  }
}

resource "aws_lexv2models_bot_version" "v1" {
  bot_id      = aws_lexv2models_bot.bot.id
  description = "Initial published version"

  locale_specification = {
    (aws_lexv2models_bot_locale.en_us.locale_id) = {
      source_bot_version = "DRAFT"
    }
  }
}

# aws_lexv2models_bot_alias does not exist in hashicorp/aws (checked v5.100.0
# and v6.58.0 schemas directly), and HashiCorp closed the feature request as
# "not planned" (github.com/hashicorp/terraform-provider-aws/issues/35780) —
# this is a permanent gap, not a version-lag issue. Create the alias via the
# AWS CLI, wrapped in `data "external"` so Terraform can capture the
# resulting alias ARN into its graph. The script is idempotent (checks for
# an existing alias before creating), so re-running it on every plan/apply
# is safe.
data "external" "bot_alias" {
  program = ["bash", "${path.module}/scripts/create_bot_alias.sh"]

  query = {
    bot_id      = aws_lexv2models_bot.bot.id
    bot_version = aws_lexv2models_bot_version.v1.bot_version
    alias_name  = "live"
    locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  }
}
