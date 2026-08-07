
output "bus_name" {
  description = "Name of the contact-center-events EventBridge bus — pass to Lambdas as EVENT_BUS_NAME"
  value       = aws_cloudwatch_event_bus.contact_center.name
}

output "bus_arn" {
  description = "ARN of the contact-center-events EventBridge bus — pass to Lambda IAM policies for events:PutEvents scoping"
  value       = aws_cloudwatch_event_bus.contact_center.arn
}

output "archive_arn" {
  description = "ARN of the 7-day event archive"
  value       = aws_cloudwatch_event_archive.contact_center.arn
}
