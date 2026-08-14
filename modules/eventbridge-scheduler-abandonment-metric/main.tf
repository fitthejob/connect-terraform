
resource "aws_iam_role" "scheduler_invoke" {
  name = "eventbridge-scheduler-abandonment-metric-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "eventbridge-scheduler-abandonment-metric-invoke-policy-${var.environment}"
  role = aws_iam_role.scheduler_invoke.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = var.target_lambda_alias_arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "abandonment_metric_poll" {
  name       = "abandonment-metric-poll-${var.environment}"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(${var.poll_interval_minutes} minutes)"

  target {
    arn      = var.target_lambda_alias_arn
    role_arn = aws_iam_role.scheduler_invoke.arn
  }
}
