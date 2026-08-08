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
    effect  = "Allow"
    actions = ["polly:SynthesizeSpeech"]
    # polly:SynthesizeSpeech has no resource-level permissions; AWS-managed
    # Polly voices aren't ARN-addressable.
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

# Captures a spoken verification code (module-sms-verification's Lex path,
# alongside a DTMF path in the same module for keyed-in entry). Separate
# from the queue-selection intents above -- deliberately no sample
# utterances that overlap with digit-only phrases like ClaimsIntent's "one",
# to avoid NLU misclassification between a queue choice and a spoken code.
resource "aws_lexv2models_intent" "verification_code" {
  bot_id      = aws_lexv2models_bot.bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "VerificationCodeIntent"

  sample_utterance {
    utterance = "my code is {VerificationCode}"
  }
  sample_utterance {
    utterance = "the code is {VerificationCode}"
  }
  sample_utterance {
    utterance = "{VerificationCode}"
  }
}

# AMAZON.AlphaNumeric (not AMAZON.Number) preserves the exact digit string
# Lex heard, including leading zeros -- AMAZON.Number would parse "007123"
# as the integer 7123, breaking exact-match verification against the code
# stored by sms-verification's DynamoDB record.
resource "aws_lexv2models_slot" "verification_code" {
  bot_id      = aws_lexv2models_bot.bot.id
  bot_version = "DRAFT"
  intent_id   = aws_lexv2models_intent.verification_code.intent_id
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "VerificationCode"

  slot_type_id = "AMAZON.AlphaNumeric"

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      max_retries = 2

      message_group {
        message {
          plain_text_message {
            value = "Please say the 6-digit code we sent you."
          }
        }
      }
    }
  }

  # Confirmed hashicorp/terraform-provider-aws issue (open since April
  # 2024): aws_lexv2models_slot's prompt_specification triggers
  # "Provider produced inconsistent result after apply" because AWS
  # auto-populates several fields we never set (allow_interrupt,
  # message_selection_strategy, and a full 3-entry
  # prompt_attempts_specification set with nested DTMF/audio timing) that
  # the provider's schema doesn't correctly mark as Computed. The slot
  # still gets created correctly server-side; Terraform just can't
  # reconcile its own plan against what AWS returns. Ignoring the whole
  # nested block rather than hardcoding AWS's defaults ourselves, since
  # those defaults aren't something this repo actually controls and
  # hardcoding them would silently drift if AWS ever changes them.
  lifecycle {
    ignore_changes = [value_elicitation_setting]
  }
}

# aws_lexv2models_bot_version snapshots DRAFT once at creation and has no
# built-in mechanism to detect that DRAFT's intents/slots changed later --
# none of its own arguments (bot_id, description, locale_specification)
# change just because an intent/slot resource elsewhere in this file did,
# so Terraform sees no diff and never republishes. Confirmed live: the bot
# alias kept serving a version that predated VerificationCodeIntent/slot
# entirely, so ConnectParticipantWithLexBot could never match it -- every
# attempt silently fell through to the retry loop with zero Lex-side error,
# because from Lex's perspective the utterance simply didn't match any
# intent that existed in the version actually being served. Embedding a
# hash of every intent/slot's meaningful content into `description` forces
# a real diff (and therefore a new published version + republish) whenever
# any of them changes.
locals {
  lex_content_hash = md5(jsonencode({
    fallback = {
      parent_intent_signature = aws_lexv2models_intent.fallback.parent_intent_signature
    }
    claims                   = [for u in aws_lexv2models_intent.claims.sample_utterance : u.utterance]
    benefits                 = [for u in aws_lexv2models_intent.benefits.sample_utterance : u.utterance]
    authorizations           = [for u in aws_lexv2models_intent.authorizations.sample_utterance : u.utterance]
    billing                  = [for u in aws_lexv2models_intent.billing.sample_utterance : u.utterance]
    verification_code_intent = [for u in aws_lexv2models_intent.verification_code.sample_utterance : u.utterance]
    verification_code_slot = {
      slot_type_id = aws_lexv2models_slot.verification_code.slot_type_id
      name         = aws_lexv2models_slot.verification_code.name
    }
  }))
}

resource "aws_lexv2models_bot_version" "v1" {
  bot_id      = aws_lexv2models_bot.bot.id
  description = "Published version -- content hash ${local.lex_content_hash}"

  locale_specification = {
    (aws_lexv2models_bot_locale.en_us.locale_id) = {
      source_bot_version = "DRAFT"
    }
  }

  lifecycle {
    replace_triggered_by = [
      aws_lexv2models_intent.fallback,
      aws_lexv2models_intent.claims,
      aws_lexv2models_intent.benefits,
      aws_lexv2models_intent.authorizations,
      aws_lexv2models_intent.billing,
      aws_lexv2models_intent.verification_code,
      aws_lexv2models_slot.verification_code,
    ]
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
