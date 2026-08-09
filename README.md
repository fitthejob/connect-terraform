# connect-terraform

Terraform infrastructure-as-code for an Amazon Connect contact center
prototype: queues, a routing profile, contact flows/modules, a Lex V2 bot,
and a handful of Lambdas providing customer lookup, routing decisions, SMS
verification, and event publishing — provisioned against a pre-existing
Connect instance (looked up by alias, not created by this repo).

**This is an explicit prototype**, not a production system. Several things
are deliberately deferred rather than built out — see "Deliberately
deferred" below and `.checkov.yml`.

## Architecture

Four environments — `bootstrap`, `dev`, `staging`, `prod` — under
`environments/`, sharing reusable modules under `modules/`. `bootstrap`
creates the two CI/CD IAM roles and is applied manually, once, before any
GitHub Actions workflow can run; `dev`/`staging`/`prod` wire the actual
contact center resources together.

```
Caller
  │
  ▼
Amazon Connect instance (pre-existing, looked up by alias)
  │
  ├─ main inbound contact flow (modules/connect)
  │   ├─ Lex V2 bot (modules/lex) — queue-selection intents + a
  │   │   verification-code intent, DTMF and speech input both supported
  │   ├─ customer-lookup Lambda — Customer Profiles SearchProfiles by ANI
  │   ├─ routing-decision Lambda — maps intent + customer status → queue
  │   ├─ sms-verification Lambda — SNS send + DynamoDB TTL-backed code
  │   │   storage/verification, gates the sensitive queues (claims,
  │   │   benefits, authorizations, billing)
  │   └─ eligibility-check Lambda — Phase 1's original Lambda, Customer
  │       Profiles-backed eligibility check
  │
  ├─ contact-event-publisher Lambda — EventBridge lifecycle events
  │   (contact.initiated/transferred/disconnected)
  │
  └─ queues: claims, benefits, authorizations, billing, general
      + one routing profile
```

Every Lambda a flow/module invokes needs its own
`aws_connect_lambda_function_association` — without it, Connect never had
`lambda:InvokeFunction` permission and the invoke fails silently (falls
through to the error transition, zero CloudWatch metrics, looks like the
Lambda "ran" when it never did). This bit twice during Phase 1–3 build-out;
see the "Known gotchas" section of `CLAUDE.md` for the live-debugged detail.

## Key architectural decisions

- **Connect instance is looked up, not created.** This repo provisions
  resources *against* an existing instance (`data.tf` in `modules/connect`),
  not the instance itself.
- **`bootstrap` is separate and manual-only.** It creates the IAM roles that
  every other environment's CI workflow assumes. It is never run by CI —
  only by a human with standing AWS credentials — because the deploy role's
  own permissions are what this module manages; if a bad change breaks that
  policy, the deploy role may no longer be able to fix itself. Keeping the
  fix path outside the thing that might be broken means there's always a
  way back in.
- **`staging`/`prod` promote artifacts, they don't rebuild them.** `dev`
  derives its Lambda/layer S3 keys from the pushing commit's SHA (built
  fresh by CI); `staging`/`prod` instead take a pre-set S3 key — the exact
  artifact that already passed dev. This is intentional, not drift.
- **`deploy-prod.yml` is `workflow_dispatch`-only**, not auto-chained from
  staging. A deliberate human gate for the last hop, not an incomplete
  pipeline.
- **Two IAM roles, both hand-scoped, one prototype-wide `resources = ["*"]`
  gap.** `ConnectManage`/`ConnectReadOnly` statements use `["*"]` for
  Connect actions that could in principle be scoped to the specific
  instance ARN — `modules/iam` doesn't currently take an instance ID as an
  input. Deliberately deferred, tracked in `CLAUDE.md`'s TODOs.
- **Flow-authoring goes through a package, not hand-written JSON.**
  `@fitthejob/connect-flow-builder` (a separate npm package,
  `github.com/fitthejob/connect-flow-builder`) generates the actual
  `contact_flows/*.json` files. Validator gaps found while building this
  repo's flows get fixed upstream in that package, not patched locally.

## Deliberately deferred (prototype-vs-production tradeoffs)

Documented in `.checkov.yml` and `CLAUDE.md`'s TODO list — don't "fix"
these without asking, they're tracked tradeoffs:

- Lambda VPC isolation (`CKV_AWS_117`)
- Lambda code-signing (`CKV_AWS_272`)
- Connect instance ARN scoping in IAM policies
- Per-environment (vs. shared) CI/CD IAM roles

## Lessons learned (the expensive ones)

A few bugs surfaced during build-out were costly enough — in debugging time,
or in how silently they failed — that they're worth knowing before touching
related code. Full detail lives in `CLAUDE.md`'s "Known gotchas" section;
summarized here:

- **A Connect-invoked Lambda's real `ContactId` lives under
  `event.Details.ContactData.ContactId`, not `event.Details.ContactId`.**
  Every flow-invoked Lambda in this repo had this wrong from Phase 1 onward.
  It went undetected everywhere `contactId` was only used for logging
  (silently `undefined`, no visible symptom) and only surfaced once
  `sms-verification` needed it as a real DynamoDB partition key. Direct
  `aws lambda invoke` testing never caught this, because hand-built test
  payloads happened to put `ContactId` at the top level — which isn't what
  Connect actually sends.
- **Missing Lambda-Connect associations fail silently.** No association →
  no invoke permission → the action falls through to its error transition
  with zero CloudWatch invocation metrics, no logs, nothing indicating the
  Lambda was even supposed to run. Direct-invoke testing gives false
  confidence here too, since it bypasses Connect's invoke-permission model
  entirely.
- **Lex V2's Terraform support has real, permanent gaps** — no
  `aws_lexv2models_bot_alias` resource, `aws_connect_bot_association` is
  Lex V1-only, bot versions never auto-republish on content changes,
  `BuildBotLocale` is never called by any native resource, and
  `slot_priority` has a genuine unresolved circular dependency between
  `aws_lexv2models_intent` and `aws_lexv2models_slot`. All worked around via
  `data "external"` scripts calling the AWS CLI directly — see
  `modules/lex/README.md` for the full detail on each gap and its fix.
- **Slot type choice affects speech recognition, not just data shape.**
  `AMAZON.AlphaNumeric` seemed like the right choice for a 6-digit
  verification code (exact string match, leading zeros preserved) but its
  ASR grammar is tuned for spelled-out confirmation codes, not digit-by-
  digit spoken input — confirmed live, spoken codes consistently failed to
  match despite DTMF entry of the same code working. `AMAZON.NumberSequence`
  is the correct choice for spoken PIN-style input.
- **A pure-DTMF `GetParticipantInput` action needs an explicit
  `InputTimeLimitExceeded` error transition**, not just
  `NoMatchingCondition` — Connect rejects flow/module content missing it,
  but only at the real API level (`InvalidContactFlowModuleException` via
  CloudTrail), not via any local validator.
- **`CONTACT_FLOW_MODULE` content requires a top-level `Settings` block**
  (`InputParameters`, `OutputParameters`, `Transitions`) — omitting it fails
  `CreateContactFlowModule`/`UpdateContactFlowModuleContent` outright, again
  only visible against the real API.

## Commands

Run from inside an environment directory (`environments/dev`,
`environments/staging`, `environments/prod`, or `environments/bootstrap`):

```
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Flow-authoring tooling and the eligibility-check Lambda source each have
their own `npm install` + build/generate commands — see `CLAUDE.md` for the
full command reference and CI/CD workflow breakdown.

## Where to go next

- **`CLAUDE.md`** — the living working-notes doc: repo structure detail,
  every command, CI/CD wiring, security scanning config, and a dated log of
  every gotcha discovered during build-out. Start there for anything this
  README doesn't answer.
- **`modules/lex/README.md`**, **`modules/iam/README.md`** — per-module
  detail for the two modules with the most non-obvious design decisions.
- **`docs/superpowers/specs/`** — phased build plan and design docs for
  individual features (Lex menu bot, IAM-as-Terraform migration, callback
  queue module).
