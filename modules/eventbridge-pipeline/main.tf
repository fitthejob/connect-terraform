
resource "aws_cloudwatch_event_bus" "contact_center" {
  name = "contact-center-events-${var.environment}"
}

resource "aws_cloudwatch_event_archive" "contact_center" {
  name             = "contact-center-events-archive-${var.environment}"
  event_source_arn = aws_cloudwatch_event_bus.contact_center.arn
  retention_days   = 7
}

locals {
  # One entry per rule: detail-type to match, and a short key used to name
  # per-rule resources (DLQ, alarm, rule itself). Both rules in this map
  # target the same shared subscriber Lambda (var.subscriber_alias_arn) --
  # one concern (event -> CloudWatch metric), not two separate functions.
  # (The module as a whole defines a third rule, native_contact_events
  # below, which also targets this same Lambda but isn't part of this map
  # since it lives on the account's default bus, not this module's custom
  # bus, and uses a different event_pattern shape.)
  #
  # contact_initiated and contact_disconnected were removed here --
  # Amazon Connect's native EventBridge Contact Events already provide
  # this data (source: aws.connect) with zero custom Lambda code, and the
  # custom versions carried no payload beyond contactId/channel/timestamp
  # that the native event doesn't already have. See the new
  # aws_cloudwatch_event_rule.native_contact_events resource below for
  # the replacement. contact_transferred and verification_completed
  # remain here because they carry resolved contact/flow attributes
  # (Queue/Intent, VerificationStatus) that native events do not include.
  rules = {
    contact_transferred = {
      detail_type = "contact.transferred"
    }
    verification_completed = {
      detail_type = "verification.completed"
    }
  }
}

# Native Amazon Connect Contact Events -- delivered automatically to the
# account's DEFAULT EventBridge bus (no event_bus_name set below), not
# this module's own custom contact-center-events-{env} bus. Replaces the
# old contact.initiated/contact.disconnected custom events. Filtered to
# DISCONNECTED only -- INITIATED was dropped (ContactsInitiated duplicated
# Connect's own native AWS/Connect metrics, e.g. ContactsHandled, with no
# new information). Connect emits several other native event types
# (QUEUED, CONNECTED_TO_AGENT, COMPLETED, CONTACT_DATA_UPDATED, etc.) not
# currently consumed by anything in this repo.
#
# detail-type value: confirmed correct as "Amazon Connect Contact Event" --
# this matches the EventBridge service-event registry (events-ref-connect.html),
# the authoritative source, and is also shown in an AWS Contact Center blog
# post's console walkthrough. A second string, "Connect Customer Contact
# Event", appears in one of AWS's own doc sample JSON blobs -- that's an
# artifact of an in-progress "Amazon Connect" -> "Connect Customer" product
# rebrand in AWS's docs (the sample blobs were partially rewritten to the
# new name, but the service-event registry page was not); it is not a
# second real value the API might send. Still worth a belt-and-braces
# confirmation against a live event (eventbridge console's rule-testing
# tool, or CloudWatch Logs on event-metric-subscriber after a real call)
# once this is actually applied and exercised -- not because the value is
# in doubt, just as normal first-live-run verification.
resource "aws_cloudwatch_event_rule" "native_contact_events" {
  name = "contact-center-native-contact-events-${var.environment}"

  event_pattern = jsonencode({
    source      = ["aws.connect"]
    detail-type = ["Amazon Connect Contact Event"]
    detail = {
      eventType = ["DISCONNECTED"]
    }
  })
}

resource "aws_sqs_queue" "native_contact_events_durable" {
  name                    = "contact-center-native-contact-events-durable-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_cloudwatch_event_target" "native_contact_events_sqs" {
  rule      = aws_cloudwatch_event_rule.native_contact_events.name
  target_id = "durable-sqs"
  arn       = aws_sqs_queue.native_contact_events_durable.arn
}

resource "aws_sqs_queue_policy" "native_contact_events_durable" {
  queue_url = aws_sqs_queue.native_contact_events_durable.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.native_contact_events_durable.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.native_contact_events.arn }
        }
      }
    ]
  })
}

resource "aws_sqs_queue" "native_contact_events_lambda_target_dlq" {
  name                    = "contact-center-native-contact-events-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue_policy" "native_contact_events_lambda_target_dlq" {
  queue_url = aws_sqs_queue.native_contact_events_lambda_target_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.native_contact_events_lambda_target_dlq.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.native_contact_events.arn }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "native_contact_events_lambda" {
  rule      = aws_cloudwatch_event_rule.native_contact_events.name
  target_id = "lambda-subscriber"
  arn       = var.subscriber_alias_arn

  dead_letter_config {
    arn = aws_sqs_queue.native_contact_events_lambda_target_dlq.arn
  }

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 300
  }
}

resource "aws_lambda_permission" "allow_eventbridge_native_contact_events" {
  statement_id  = "AllowEventBridge-native-contact-events"
  action        = "lambda:InvokeFunction"
  function_name = var.subscriber_function_name
  qualifier     = "live"
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.native_contact_events.arn
}

resource "aws_cloudwatch_metric_alarm" "native_contact_events_durable_dlq_depth" {
  alarm_name          = "contact-center-native-contact-events-durable-dlq-depth-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.native_contact_events_durable.name
  }
}

resource "aws_cloudwatch_metric_alarm" "native_contact_events_lambda_dlq_depth" {
  alarm_name          = "contact-center-native-contact-events-lambda-dlq-depth-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.native_contact_events_lambda_target_dlq.name
  }
}

resource "aws_cloudwatch_event_rule" "rule" {
  for_each = local.rules

  name           = "contact-center-${replace(each.value.detail_type, ".", "-")}-${var.environment}"
  event_bus_name = aws_cloudwatch_event_bus.contact_center.name

  event_pattern = jsonencode({
    source      = ["contact-center.ivr"]
    detail-type = [each.value.detail_type]
  })
}

# Durable-processing SQS target per rule, with its own DLQ for messages
# that fail delivery to the queue itself (distinct from the Lambda target's
# DLQ below).
resource "aws_sqs_queue" "durable" {
  for_each = local.rules

  name                    = "contact-center-${replace(each.value.detail_type, ".", "-")}-durable-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_cloudwatch_event_target" "sqs" {
  for_each = local.rules

  rule           = aws_cloudwatch_event_rule.rule[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.contact_center.name
  target_id      = "durable-sqs"
  arn            = aws_sqs_queue.durable[each.key].arn
}

resource "aws_sqs_queue_policy" "durable" {
  for_each  = local.rules
  queue_url = aws_sqs_queue.durable[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.durable[each.key].arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.rule[each.key].arn }
        }
      }
    ]
  })
}

# DLQ for the Lambda target -- receives events EventBridge couldn't
# deliver to the subscriber Lambda after retrying (per the spec's
# "SQS dead letter queue on all rules" requirement).
resource "aws_sqs_queue" "lambda_target_dlq" {
  for_each = local.rules

  name                    = "contact-center-${replace(each.value.detail_type, ".", "-")}-dlq-${var.environment}"
  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue_policy" "lambda_target_dlq" {
  for_each  = local.rules
  queue_url = aws_sqs_queue.lambda_target_dlq[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.lambda_target_dlq[each.key].arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.rule[each.key].arn }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  for_each = local.rules

  rule           = aws_cloudwatch_event_rule.rule[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.contact_center.name
  target_id      = "lambda-subscriber"
  arn            = var.subscriber_alias_arn

  dead_letter_config {
    arn = aws_sqs_queue.lambda_target_dlq[each.key].arn
  }

  # AWS's default (24h / 185 attempts) is too tolerant for this pipeline --
  # these events feed CloudWatch metrics, where a datapoint published hours
  # or a day late is useless; failing fast to the DLQ surfaces real problems
  # via the DLQ-depth alarm instead of silently retrying for a day.
  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 300
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  for_each = local.rules

  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = var.subscriber_function_name
  qualifier     = "live"
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rule[each.key].arn
}

# Alarms on both DLQs per rule -- "SQS dead letter queue on all rules" plus
# "CloudWatch alarm on DLQ depth greater than 0" from the spec.
resource "aws_cloudwatch_metric_alarm" "durable_dlq_depth" {
  for_each = local.rules

  alarm_name          = "contact-center-${replace(each.value.detail_type, ".", "-")}-durable-dlq-depth-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.durable[each.key].name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_target_dlq_depth" {
  for_each = local.rules

  alarm_name          = "contact-center-${replace(each.value.detail_type, ".", "-")}-lambda-dlq-depth-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.lambda_target_dlq[each.key].name
  }
}
