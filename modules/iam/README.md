# modules/iam

Defines the two IAM roles GitHub Actions assumes via OIDC: `github-connect-deploy-dev`
(broad, used by deploy-dev/staging/prod workflows) and `github-connect-pr-checks`
(read-only, used by pr-checks).

## Why this isn't wired into environments/dev, staging, or prod

This module is applied from `environments/bootstrap` only, and `environments/bootstrap`
is never run by CI — only by a human, locally, with their own AWS credentials. This is
deliberate: the deploy role's own permissions policy is what this module manages, so if
that policy is ever broken by a bad change, the deploy role itself may no longer be able
to fix it. Keeping the fix path outside the thing that might be broken means there's
always a way back in.

Before this module existed, both roles were hand-maintained as JSON files applied via
ad-hoc `aws iam` CLI commands — no version history, no diffs, no review, and the AWS
account ID hardcoded throughout every ARN. This module replaces that with the same
`plan`/`apply` discipline the rest of this repo already gets: permissions changes are
now visible diffs, and the account ID is resolved at apply time via
`data.aws_caller_identity` instead of being a literal anywhere.

This pass deliberately keeps both roles on one shared deploy role/policy rather than
splitting into per-environment roles (`-dev`/`-staging`/`-prod`), matching what already
existed live in AWS — tighter blast-radius isolation is a real improvement worth doing,
but it's a separate security-boundary decision with its own risk (new secrets, new trust
policies), not bundled into this relocation. The module already parametrizes permissions
by an `environments` list, so that split is a call-site change away whenever it's taken up.

## Applying changes

```bash
cd environments/bootstrap
terraform init
terraform plan
terraform apply
```

Run these yourself, from your own machine. Never add a CI workflow step that runs
`environments/bootstrap`.
