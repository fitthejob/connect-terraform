# modules/lex

Provisions one Lex V2 bot per module instance: IAM role, locale, intents, a
published bot version, and an alias. Call it once per bot (e.g. `bot_name =
"menu-dev"`), following the pattern in `environments/*/main.tf`.

## Provider gaps this module works around

`hashicorp/aws` (checked v5.100.0 and v6.58.0 directly against the provider
schema) does not fully support Lex V2 in two places that matter here. Both
gaps are permanent, not version lag — worth knowing before "upgrade the
provider" comes up as a fix.

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

## Practical implications

- Every real AWS call these workarounds make happens through the AWS CLI
  inside the `local-exec`-style scripts, not through Terraform's own
  provider — so `terraform plan` won't show a diff for alias or association
  changes the way it does for normal resources. Drift here is invisible to
  `plan`.
- No destroy-time cleanup: destroying this module's bot doesn't disassociate
  it from Connect first. Not exercised by any CI workflow (deploys are
  apply-only), but worth knowing if you ever run `terraform destroy` by
  hand — see the bot association block's comment in `modules/connect/main.tf`.
- Both scripts require the AWS CLI to be present wherever `terraform apply`
  runs (GitHub Actions' `ubuntu-latest` images ship it by default).

## If HashiCorp ever adds real support

Revisit both workarounds if `terraform providers schema -json` ever shows
`aws_lexv2models_bot_alias` or a `lex_v2_bot` block on
`aws_connect_bot_association`. Until then, this is the correct, idiomatic
Terraform pattern for the gap.
