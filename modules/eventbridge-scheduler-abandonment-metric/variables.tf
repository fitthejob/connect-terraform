
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "target_lambda_alias_arn" {
  description = "ARN of the abandonment-metric Lambda's live alias to invoke on schedule"
  type        = string
}

variable "poll_interval_minutes" {
  description = "How often the schedule fires. Should stay roughly 2-3x smaller than the target Lambda's own lookback_minutes variable (modules/lambda-abandonment-metric), per the design's polling parameters -- not enforced here, keep both in sync manually when tuning either."
  type        = number
  default     = 2
}
