resource "aws_connect_queue" "claims" {
  name                  = "queue-claims-${var.environment}"
  description           = "Claims Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_claims_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_queue" "benefits" {
  name                  = "queue-benefits-${var.environment}"
  description           = "Benefits Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_benefits_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_queue" "authorizations" {
  name                  = "queue-authorizations-${var.environment}"
  description           = "authorizations Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_authorizations_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_queue" "billing" {
  name                  = "queue-billing-${var.environment}"
  description           = "Billing Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_billing_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_queue" "general" {
  name                  = "queue-general-${var.environment}"
  description           = "General Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_general_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_routing_profile" "basic" {
  instance_id = data.aws_connect_instance.main.id
  name        = "routing-profile-basic-${var.environment}"
  description = "Basic Routing Profile"
  media_concurrencies {
    concurrency = 1
    channel     = "VOICE"
  }
  default_outbound_queue_id = aws_connect_queue.claims.queue_id
  queue_configs {
    queue_id = aws_connect_queue.claims.queue_id
    priority = 1
    delay    = 0
    channel  = "VOICE"
  }
  queue_configs {
    queue_id = aws_connect_queue.benefits.queue_id
    priority = 2
    delay    = 0
    channel  = "VOICE"
  }
  queue_configs {
    queue_id = aws_connect_queue.authorizations.queue_id
    priority = 3
    delay    = 0
    channel  = "VOICE"
  }
  queue_configs {
    queue_id = aws_connect_queue.billing.queue_id
    priority = 4
    delay    = 0
    channel  = "VOICE"
  }
  queue_configs {
    queue_id = aws_connect_queue.general.queue_id
    priority = 5
    delay    = 0
    channel  = "VOICE"
  }
}

resource "aws_connect_contact_flow" "main_inbound" {
  instance_id = data.aws_connect_instance.main.id
  name        = "Main-Inbound-${var.environment}"
  description = "Main inbound contact flow"
  type        = "CONTACT_FLOW"
  content     = file("${path.module}/contact_flows/main_inbound.json")
  lifecycle {
    prevent_destroy = true
  }
}

# Target for CI to push freshly-generated main-inbound flow JSON to via the
# AWS CLI (UpdateContactFlowContent) before it's trusted enough to apply to
# main_inbound itself. Terraform only owns this flow's existence and a
# permanently-safe stub; the actual validation push happens out-of-band in
# CI. See scripts/main-inbound-flow.ts and docs/superpowers/specs/ for the
# generation + validation flow this supports.
resource "aws_connect_contact_flow" "validation_sandbox" {
  instance_id = data.aws_connect_instance.main.id
  name        = "Validation-Sandbox-${var.environment}"
  description = "CI target for validating generated flow JSON against the real Connect API before deploying to Main-Inbound"
  type        = "CONTACT_FLOW"
  content     = file("${path.module}/contact_flows/validation_sandbox.json")
}

# Dedicated entry point for the load-test test case (see
# modules/connect/scripts/sync_test_case.sh and test_cases/smoke-test.json).
# Deliberately NOT Validation-Sandbox-{env} above -- that flow's content is
# routinely overwritten by deploy-dev.yml's propose-main-inbound-flow-update
# job and by manual module testing (see CLAUDE.md's 2026-08-08 TODO on
# Validation-Sandbox contention). This flow's content is swapped out-of-band,
# manually, whenever you want to load-test a specific flow shape -- Terraform
# only owns its existence and a safe stub, same pattern as validation_sandbox.
resource "aws_connect_contact_flow" "load_test_sandbox" {
  count       = var.enable_load_test_sandbox ? 1 : 0
  instance_id = data.aws_connect_instance.main.id
  name        = "Load-Test-Sandbox-${var.environment}"
  description = "Entry point for synthetic load-test contacts injected via the Connect test-simulation API. Content swapped out-of-band -- Terraform only owns existence + a safe stub."
  type        = "CONTACT_FLOW"
  content     = file("${path.module}/contact_flows/load_test_sandbox.json")

  lifecycle {
    precondition {
      condition     = !var.enable_load_test_sandbox || length(var.connect_phone_number) > 0
      error_message = "connect_phone_number must be set when enable_load_test_sandbox is true -- CreateTestCase will otherwise fail at apply time with a misleading AWS error (\"Must specify either FlowId or phone numbers\")."
    }
  }
}

# Syncs the load-test smoke-test test case (modules/connect/test_cases/smoke-test.json,
# generated by scripts/load-test-smoke-test.ts) against the real Connect
# instance on every `terraform apply`. See modules/connect/scripts/sync_test_case.sh.
#
# null_resource + local-exec, not `data "external"`: local-exec only runs on
# `apply`, never on `plan` -- avoids the known problem this repo already has
# with data "external" mutating live state on every plan (see CLAUDE.md's
# 2026-08-08 TODO on modules/lex's bot-alias script). This is a NEW pattern
# for this repo -- it runs AWS-mutating commands in TWO different execution
# contexts, not just one:
#   1. A human's local `terraform apply` -- CLAUDE.md rule #6 applies here as
#      normal (only the human's own AWS credentials run apply; flag AWS
#      mutations explicitly before running).
#   2. deploy-dev.yml's unattended `terraform apply -auto-approve` against
#      environments/dev on every push to main (environments/dev/terraform.tfvars
#      is committed and auto-loaded, so this fires with no human in the loop).
#      There is no "flag before apply" step in CI -- what makes this safe here
#      is sync_test_case.sh's own idempotency (list-then-create-or-update, see
#      its ListTestCases/CreateTestCase/UpdateTestCase branching) and the
#      github-connect-deploy-dev role having exactly the Connect test-case
#      permissions this script needs, nothing broader. See CLAUDE.md's Known
#      gotchas for the 2026-08-17 entry documenting this.
#
# Trigger covers the content hash AND the two other values the script's API
# call actually depends on (entry-point flow ID, destination phone number) --
# see the entry_point_ids trigger below. Content hash alone would miss a
# change to either of those, letting the live test case silently desync from
# Terraform's believed state while `terraform plan` still reports 0 changes.
resource "null_resource" "sync_test_case" {
  count = var.enable_load_test_sandbox ? 1 : 0

  triggers = {
    content_hash    = filesha1("${path.module}/test_cases/smoke-test.json")
    entry_point_ids = "${aws_connect_contact_flow.load_test_sandbox[0].contact_flow_id}|${var.connect_phone_number}"
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/sync_test_case.sh '${data.aws_connect_instance.main.id}' '${aws_connect_contact_flow.load_test_sandbox[0].contact_flow_id}' 'smoke-test' '${path.module}/test_cases/smoke-test.json'"

    environment = {
      # Maps to VoiceCallEntryPointParameters.SourcePhoneNumber inside the
      # script, not DestinationPhoneNumber -- see sync_test_case.sh's own
      # comment for the live-verified reasoning. Named for what the value
      # IS (the real claimed number), not which API field it lands in.
      CLAIMED_PHONE_NUMBER = var.connect_phone_number
    }
  }

  depends_on = [aws_connect_contact_flow.load_test_sandbox]
}

# Phase 4: shared agent whisper flow, branches on contact attributes set
# earlier in Main-Inbound (Queue, CustomerStatus, CustomerTier,
# VerificationStatus) rather than one whisper flow per queue -- see
# scripts/agent-whisper-flow.ts for the branching logic.
resource "aws_connect_contact_flow" "agent_whisper" {
  instance_id = data.aws_connect_instance.main.id
  name        = "Agent-Whisper-${var.environment}"
  description = "Shared agent whisper flow, branches on queue/customer/verification attributes"
  type        = "AGENT_WHISPER"
  content     = file("${path.module}/contact_flows/agent_whisper.json")
}

# Module counterpart to validation_sandbox above -- CI pushes generated
# module JSON (e.g. callback_offer.json) here via UpdateContactFlowModuleContent
# before trusting it enough to apply to the real module resource.
resource "aws_connect_contact_flow_module" "validation_sandbox_module" {
  instance_id = data.aws_connect_instance.main.id
  name        = "Validation-Sandbox-Module-${var.environment}"
  description = "CI target for validating generated flow module JSON against the real Connect API"
  content     = file("${path.module}/contact_flows/validation_sandbox_module.json")
}

resource "aws_connect_contact_flow_module" "callback_offer" {
  instance_id = data.aws_connect_instance.main.id
  name        = "Callback-Offer-${var.environment}"
  description = "Offers a native Connect callback when a queue is at capacity"
  content     = file("${path.module}/contact_flows/callback_offer.json")
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_contact_flow_module" "module_customer_lookup" {
  instance_id = data.aws_connect_instance.main.id
  name        = "Module-CustomerLookup-${var.environment}"
  description = "Invokes customer-lookup and sets CustomerStatus/CustomerId/CustomerTier contact attributes"
  content     = file("${path.module}/contact_flows/module_customer_lookup.json")
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_contact_flow_module" "module_sms_verification" {
  instance_id = data.aws_connect_instance.main.id
  name        = "Module-SmsVerification-${var.environment}"
  description = "Sends and verifies an SMS code, sets VerificationStatus contact attribute"
  content     = file("${path.module}/contact_flows/module_sms_verification.json")
  lifecycle {
    prevent_destroy = true
  }
}

# aws_connect_bot_association only supports Lex V1 bots in this provider
# (no lex_v2_bot block — checked schemas directly, and HashiCorp's tracking
# issue for V2 support, github.com/hashicorp/terraform-provider-aws/issues/30869,
# remains open/unimplemented). Associate via the AWS CLI instead. The script
# is idempotent, so re-running it on every plan/apply is safe.
data "external" "lex_bot_association" {
  program = ["bash", "${path.module}/scripts/associate_lex_bot.sh"]

  query = {
    instance_id = data.aws_connect_instance.main.id
    alias_arn   = var.aws_lex_bot_alias_arn
  }
}
