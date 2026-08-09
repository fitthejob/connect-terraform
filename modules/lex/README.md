# modules/lex

Provisions one Lex V2 bot per module instance: IAM role, locale, intents, a
published bot version, and an alias. Call it once per bot (e.g. `bot_name =
"menu-dev"`), following the pattern in `environments/*/main.tf`.

## Provider gaps this module works around

`hashicorp/aws` (checked v5.100.0 and v6.58.0 directly against the provider
schema) does not fully support Lex V2 in several places that matter here.
These gaps are permanent, not version lag — worth knowing before "upgrade
the provider" comes up as a fix.

### No `aws_lexv2models_bot_alias` resource

The provider has `aws_lexv2models_bot`, `_bot_locale`, `_bot_version`,
`_intent`, `_slot`, and `_slot_type` — no `_bot_alias`. The AWS API supports
Lex V2 aliases fine; HashiCorp closed the tracking issue as "not planned"
([hashicorp/terraform-provider-aws#35780](https://github.com/hashicorp/terraform-provider-aws/issues/35780)).

**Workaround:** `scripts/create_bot_alias.sh`, invoked via `data "external"`
in `main.tf`. The script is idempotent — it looks up an existing alias by
name first, updates it if found, creates it otherwise — because `data
"external"` runs its program on every `plan`/`apply`, not just when its
`query` inputs change. `bot_alias_arn` in `outputs.tf` reads the script's
result.

### `aws_connect_bot_association` is Lex V1 only

Its schema (also checked directly) only has a `lex_bot { name, lex_region }`
block. The AWS API's `AssociateBot` supports a separate `LexV2Bot { AliasArn
}` field, but the Terraform resource never exposes it
([hashicorp/terraform-provider-aws#30869](https://github.com/hashicorp/terraform-provider-aws/issues/30869),
open/unimplemented).

**Workaround:** this one lives in `modules/connect`, not here — see
`modules/connect/scripts/associate_lex_bot.sh` and the `data "external"
"lex_bot_association"` block in `modules/connect/main.tf`. Mentioned here
because it's the same class of gap and easy to go looking for in this
module first.

### `aws_lexv2models_bot_version` never republishes on content changes

None of the resource's own tracked arguments (`bot_id`, `description`,
`locale_specification`) change just because a sibling intent/slot resource
changed elsewhere in this file, so Terraform sees no diff and the published
version silently goes stale relative to `DRAFT`. Confirmed live: the bot
alias kept serving a version that predated `VerificationCodeIntent`
entirely — every utterance attempt fell through to the retry loop with zero
Lex-side error, since from Lex's perspective nothing matched any intent in
the version actually being served.

**Workaround:** `local.lex_content_hash` (a hash of every intent's
utterances, the slot's type/name, and the slot's externally-set priority —
see below) is embedded into the version's `description`, and
`replace_triggered_by` forces a real replace whenever that hash changes.
`create_before_destroy = true` is required alongside it — Lex refuses to
delete a version while any alias still points at it.

### `aws_lexv2models_intent.slot_priority` has a genuine, unresolved cycle with `aws_lexv2models_slot`

`aws_lexv2models_intent`'s `slot_priority` block needs a real `slot_id`,
which only exists after the slot resource is created — but
`aws_lexv2models_slot` needs `intent_id`, which only exists after the intent
resource is created. Each resource needs the other's real output value in
both directions, a genuine cycle Terraform's DAG cannot express
(confirmed to match [hashicorp/terraform-provider-aws#39948](https://github.com/hashicorp/terraform-provider-aws/issues/39948)
exactly, open/unresolved). `depends_on` cannot fix this — it only orders
resources that need each other's *timing*, not resources that need each
other's *values* bidirectionally.

Slot priority isn't optional at the Lex API level either — `BuildBotLocale`
fails outright without it (`"Slot ids [...] don't define a slot priority"`).

**Workaround:** `scripts/set_slot_priority.sh`, invoked via `data "external"
"slot_priority"`, calls `UpdateIntent` directly once both real IDs already
exist in Terraform state. Its result is fed back into
`local.lex_content_hash` — without that, a version published before this
fix landed would never get superseded, since nothing Terraform tracks
natively would differ from what produced the stale version (confirmed live
as the actual cause of a `botVersion` stuck on `"2"` that never advanced).

### `BuildBotLocale` is never called by any native resource

`aws_lexv2models_bot_version`'s `CreateBotVersion` snapshots whatever state
`DRAFT` is in — it does not itself build `DRAFT` first, and no resource in
the provider calls the separate, mandatory `BuildBotLocale` step that
compiles intents/slots into a working NLU model. Every published version
was therefore silently unbuilt; confirmed live via Connect flow logs:
`"Couldn't start a conversation with bot alias ... The alias isn't built."`

**Workaround:** `scripts/build_bot_locale.sh`, invoked via `data "external"
"build_bot_locale"`. `BuildBotLocale` is asynchronous, so the script polls
`DescribeBotLocale` until a terminal status before returning. This resource
`depends_on` every intent/slot and on `data.external.slot_priority`, so a
still-missing priority never reaches a build attempt.

## Practical implications

- Every real AWS call these workarounds make happens through the AWS CLI
  inside the `local-exec`-style scripts, not through Terraform's own
  provider — so `terraform plan` won't show a diff for alias, association,
  slot-priority, or build-status changes the way it does for normal
  resources. Drift here is invisible to `plan`.
- No destroy-time cleanup: destroying this module's bot doesn't disassociate
  it from Connect first. Not exercised by any CI workflow (deploys are
  apply-only), but worth knowing if you ever run `terraform destroy` by
  hand — see the bot association block's comment in `modules/connect/main.tf`.
- All scripts require the AWS CLI to be present wherever `terraform apply`
  runs (GitHub Actions' `ubuntu-latest` images ship it by default).
- `data "external"` scripts run their program on every `plan`, not just
  `apply` — `create_bot_alias.sh` mutates live Lex state (`create/update-bot-alias`)
  even during a plan-only run. Idempotent, so safe, but surprising; see the
  dated TODO in the repo root `CLAUDE.md` for the deferred real fix.

## Choosing a slot type for spoken input

`AMAZON.AlphaNumeric`'s ASR grammar is tuned for spelled-out alphanumeric
confirmation codes (letters + digits dictated individually), not purely-
spoken digit sequences — confirmed live, digit-by-digit spoken input into an
`AMAZON.AlphaNumeric` slot consistently failed to match ("Sorry, we didn't
catch that") despite DTMF entry of the identical code working correctly via
the same `ConnectParticipantWithLexBot` action. `AMAZON.NumberSequence` is
purpose-built for spoken PIN/code sequences and, unlike `AMAZON.Number`,
preserves leading zeros as a string rather than parsing them away as an
integer. See `verification_code` slot in `main.tf`.

## If HashiCorp ever adds real support

Revisit both workarounds if `terraform providers schema -json` ever shows
`aws_lexv2models_bot_alias` or a `lex_v2_bot` block on
`aws_connect_bot_association`. Until then, this is the correct, idiomatic
Terraform pattern for the gap.
