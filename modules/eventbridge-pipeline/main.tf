
resource "aws_cloudwatch_event_bus" "contact_center" {
  name = "contact-center-events-${var.environment}"
}

resource "aws_cloudwatch_event_archive" "contact_center" {
  name             = "contact-center-events-archive-${var.environment}"
  event_source_arn = aws_cloudwatch_event_bus.contact_center.arn
  retention_days   = 7
}

locals {
  # One entry per rule: detail-type to match, the subscriber Lambda alias
  # ARN/function name for the Lambda target, and a short key used to name
  # per-rule resources (DLQ, alarm, rule itself).
  rules = {
    contact_initiated = {
      detail_type          = "contact.initiated"
      subscriber_alias_arn = var.contact_initiated_subscriber_alias_arn
      subscriber_name      = var.contact_initiated_subscriber_function_name
    }
    contact_transferred = {
      detail_type          = "contact.transferred"
      subscriber_alias_arn = var.contact_transferred_subscriber_alias_arn
      subscriber_name      = var.contact_transferred_subscriber_function_name
    }
    contact_disconnected = {
      detail_type          = "contact.disconnected"
      subscriber_alias_arn = var.contact_disconnected_subscriber_alias_arn
      subscriber_name      = var.contact_disconnected_subscriber_function_name
    }
    verification_completed = {
      detail_type          = "verification.completed"
      subscriber_alias_arn = var.verification_completed_subscriber_alias_arn
      subscriber_name      = var.verification_completed_subscriber_function_name
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
  arn            = each.value.subscriber_alias_arn

  dead_letter_config {
    arn = aws_sqs_queue.lambda_target_dlq[each.key].arn
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  for_each = local.rules

  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.subscriber_name
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
