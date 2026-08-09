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
