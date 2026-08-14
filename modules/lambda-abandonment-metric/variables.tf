variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "s3_bucket_lambda_artifacts" {
  description = "S3 bucket for Amazon Connect Lambdas"
  type        = string
}

variable "s3_key" {
  description = "S3 key for the abandonment-metric Lambda artifact zip"
  type        = string
}

variable "function_name" {
  description = "Name of the abandonment-metric Lambda"
  type        = string
}

variable "layer_arn" {
  description = "ARN of the shared dependencies Lambda layer"
  type        = string
}

variable "connect_instance_id" {
  description = "Connect instance ID to search contacts against"
  type        = string
}

variable "flow_log_group_name" {
  description = "CloudWatch log group name for the Connect instance's flow logs"
  type        = string
}

variable "metric_namespace" {
  description = "CloudWatch namespace to publish the abandonment metric under"
  type        = string
  default     = "ContactCenter/SelfService"
}

variable "lookback_minutes" {
  description = "How far back each poll searches for disconnected contacts -- should be roughly 2-3x the poll interval (see the design's Polling parameters section)"
  type        = number
  default     = 6
}

variable "dedup_ttl_seconds" {
  description = "TTL for the dedup table's records -- sized to the lookback window plus a 3-5x safety multiplier, per the design (~30-60 min range)"
  type        = number
  default     = 1800
}

variable "poll_interval_minutes" {
  description = "Polling interval in minutes, consumed by Task 8's EventBridge Scheduler rule (not by this module directly) -- declared here so environments/dev/main.tf has one place to set it, matching the schedule expression needing to agree with the Lambda's own lookback config"
  type        = number
  default     = 2
}
