
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
  # per-rule resources (DLQ, alarm, rule itself). All four rules target the
  # same shared subscriber Lambda (var.subscriber_alias_arn) -- one
  # concern (event -> CloudWatch metric), not four separate functions.
  rules = {
    contact_initiated = {
      detail_type = "contact.initiated"
    }
    contact_transferred = {
      detail_type = "contact.transferred"
    }
    contact_disconnected = {
      detail_type = "contact.disconnected"
    }
    verification_completed = {
      detail_type = "verification.completed"
    }
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
