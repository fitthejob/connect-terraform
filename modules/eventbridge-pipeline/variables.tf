
variable "environment" {
  description = "Environment name (dev, staging, prod) — suffixed onto all resource names so all three environments can coexist in the same AWS account"
  type        = string
}

variable "subscriber_alias_arn" {
  description = "Alias ARN of the shared event-metric-subscriber Lambda — all four rules target this same function"
  type        = string
}

variable "subscriber_function_name" {
  description = "Function name of the shared event-metric-subscriber Lambda"
  type        = string
}
