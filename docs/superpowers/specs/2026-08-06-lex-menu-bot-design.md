# Lex V2 Menu Bot for Main Inbound Flow

## Context

`modules/connect`'s main inbound contact flow (`contact_flows/main_inbound.json`) is currently a stub that immediately disconnects the caller. This project adds the first real routing step: a voice+DTMF menu backed by a Lex V2 bot that lets callers reach one of the four existing queues (claims, benefits, authorizations, billing) by speaking or pressing a digit, with a new `general` queue as a fallback for calls that can't be routed.

This is scoped to menu routing only. The existing `eligibility-check` Lambda and its Connect association are untouched and out of scope.

## Call Flow

1. Caller enters the main inbound flow.
2. A "Get customer input" block plays a prompt listing the four options and invokes the Lex bot, which accepts either DTMF digits or spoken words for the same choice (e.g. pressing `1` or saying "claims" both satisfy `ClaimsIntent`).
3. On a recognized intent, the flow branches to the corresponding queue (claims/benefits/authorizations/billing), reusing the existing `aws_connect_queue` resources and routing profile.
4. On no input or no match, the flow plays "We're sorry, we did not hear your choice" and loops back to step 2.
5. After 2 retries (3 total attempts), the flow routes to a new `general` queue instead of looping again or disconnecting.

## Intents

Four intents, strict-utterance matching only (no open-ended NLU) — each accepts the option's digit word, its name, and a small set of close variants:

| Intent | Example utterances |
|---|---|
| `ClaimsIntent` | "claims", "claim", "one", "file a claim" |
| `BenefitsIntent` | "benefits", "two", "my benefits" |
| `AuthorizationsIntent` | "authorizations", "authorization", "three" |
| `BillingIntent` | "billing", "four", "my bill" |

No slots are required — these are pure routing intents with no data capture.

## Terraform Structure

### New `modules/lex/`

Mirrors the existing per-service module pattern (`modules/connect`, `modules/lambda`, `modules/layers`):

- `aws_lexv2models_bot` — the bot itself
- Bot locale (en_US) with voice/NLU confidence settings
- Four `aws_lexv2models_intent` resources (`ClaimsIntent`, `BenefitsIntent`, `AuthorizationsIntent`, `BillingIntent`), each with its utterance set
- Bot version and bot alias (Connect associates to an alias, not directly to the bot/draft)
- Dedicated IAM role + policy for the Lex bot runtime, scoped to what Lex needs (following `modules/lambda`'s role-per-module convention, not a shared/reused role)
- `aws_connect_bot_association` linking the bot alias to the Connect instance (`data.aws_connect_instance.main`, looked up the same way `modules/connect` does it)

`modules/lex/variables.tf` and `outputs.tf` follow the existing style: typed variables with descriptions, outputs for anything `modules/connect` or the contact flow needs to reference (bot alias ARN/ID at minimum).

### Changes to `modules/connect/`

- New `aws_connect_queue.general` resource, same shape as `claims`/`benefits`/`authorizations`/`billing` (`lifecycle { prevent_destroy = true }`, `hours_of_operation_id` from the existing data source)
- `aws_connect_routing_profile.basic` gains a `queue_configs` block for the new general queue (next priority after billing)
- `contact_flows/main_inbound.json` rewritten to implement the menu loop described above (Get customer input → branch on intent → queue transfer, with the retry-then-fallback path to `general`)
- New output(s) for `queue_general_id` / `queue_general_arn`, matching the existing per-queue output pattern

### Environment wiring

All three environments (`dev`, `staging`, `prod`) get:
- A new `module "lex"` block in `main.tf`, following the same `source = "../../modules/lex"` convention as `connect`/`lambda`/`layers`
- Any new variables required by the `lex` module added to each environment's `variables.tf` and `terraform.tfvars`, per CLAUDE.md's "update all three environments together" convention
- `modules/connect`'s module call updated if the general queue introduces any new required variables (unlikely — it reuses `hours_of_operation_name` and existing max-contacts pattern, so a `queue_general_max_contacts` variable with a default is the most likely addition)

## Out of Scope

- Eligibility-check Lambda / Customer Profiles integration with this flow
- Open-ended natural language understanding (this bot only recognizes the four fixed menu choices)
- Any Lex bot testing/versioning workflow beyond a single version + alias sufficient for Connect association

## Working Style

This is a learning exercise for the Lex/Terraform resources involved. Implementation should proceed as a guided walkthrough: explain each resource block before it's written, and let the user author the actual Terraform rather than generating the files wholesale.
