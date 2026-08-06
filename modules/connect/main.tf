resource "aws_connect_queue" "claims" {
  name                  = "queue-claims"
  description           = "Claims Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_claims_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_queue" "benefits" {
  name                  = "queue-benefits"
  description           = "Benefits Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_benefits_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_queue" "authorizations" {
  name                  = "queue-authorizations"
  description           = "authorizations Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_authorizations_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_queue" "billing" {
  name                  = "queue-billing"
  description           = "Billing Queue"
  instance_id           = data.aws_connect_instance.main.id
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_billing_max_contacts
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_routing_profile" "basic" {
  instance_id = data.aws_connect_instance.main.id
  name        = "routing-profile-basic"
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
}

resource "aws_connect_contact_flow" "main_inbound" {
  instance_id = data.aws_connect_instance.main.id
  name        = "Main-Inbound"
  description = "Main inbound contact flow"
  type        = "CONTACT_FLOW"
  content     = file("${path.module}/contact_flows/main_inbound.json")
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_connect_lambda_function_association" "eligibility_check" {
  instance_id  = data.aws_connect_instance.main.id
  function_arn = var.lambda_eligibility_check_function_arn
}


