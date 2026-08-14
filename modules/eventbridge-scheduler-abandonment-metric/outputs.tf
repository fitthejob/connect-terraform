
output "schedule_arn" {
  description = "ARN of the abandonment-metric poll schedule"
  value       = aws_scheduler_schedule.abandonment_metric_poll.arn
}

output "schedule_role_arn" {
  description = "IAM role ARN EventBridge Scheduler assumes to invoke the abandonment-metric Lambda"
  value       = aws_iam_role.scheduler_invoke.arn
}
