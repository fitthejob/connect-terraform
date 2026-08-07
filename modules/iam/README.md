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
always a way back in. See `docs/superpowers/specs/2026-08-07-iam-as-terraform-design.md`
for the full design rationale, including why per-environment role splitting was
deliberately deferred rather than bundled into this change.

## Applying changes

```bash
cd environments/bootstrap
terraform init
terraform plan
terraform apply
```

Run these yourself, from your own machine. Never add a CI workflow step that runs
`environments/bootstrap`.
