module "connect" {
  source                            = "../../modules/connect"
  environment                       = "dev"
  aws_connect_alias                 = var.aws_connect_alias
  hours_of_operation_name           = var.hours_of_operation_name
  s3_bucket_call_recordings         = var.s3_bucket_call_recordings
  queue_claims_max_contacts         = var.queue_claims_max_contacts
  queue_benefits_max_contacts       = var.queue_benefits_max_contacts
  queue_authorizations_max_contacts = var.queue_authorizations_max_contacts
  queue_billing_max_contacts        = var.queue_billing_max_contacts
  queue_general_max_contacts        = var.queue_general_max_contacts
  aws_lex_bot_alias_arn             = module.lex.bot_alias_arn
  enable_load_test_sandbox          = true
  connect_phone_number              = var.connect_phone_number
}

module "lex" {
  source   = "../../modules/lex"
  bot_name = var.lex_bot_name
}

module "lambda" {
  source                                 = "../../modules/lambda"
  environment                            = "dev"
  s3_bucket_lambda_artifacts             = var.s3_bucket_lambda_artifacts
  lambda_eligibility_check_function_name = var.lambda_eligibility_check_function_name
  lambda_eligibility_check_s3_key        = "eligibility-check/dev/eligibility-check-${var.artifact_sha}.zip"
  connect_instance_id                    = module.connect.connect_instance_id
  customer_profiles_domain_name          = var.customer_profiles_domain_name
  layer_arn                              = module.layers.shared_deps_layer_arn
}

module "layers" {
  source                     = "../../modules/layers"
  environment                = "dev"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  shared_deps_layer_s3_key   = "shared-deps/dev/shared-deps-${var.artifact_sha}.zip"
}

# --- Contact center prototype spec, Phase 2: EventBridge pipeline ---
# Single shared metric-subscriber Lambda for all four rules
# (contact-center-prototype-spec.md Layer 4's "Lambda subscriber for
# real-time action") -- one concern (event -> CloudWatch metric), branching
# internally on detail-type rather than four separately deployed instances.

module "lambda_event_metric_subscriber" {
  source                     = "../../modules/lambda-event-metric-subscriber"
  environment                = "dev"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "event-metric-subscriber-dev"
  s3_key                     = "event-metric-subscriber/dev/event-metric-subscriber-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
}

module "eventbridge_pipeline" {
  source      = "../../modules/eventbridge-pipeline"
  environment = "dev"

  subscriber_alias_arn     = module.lambda_event_metric_subscriber.alias_arn
  subscriber_function_name = module.lambda_event_metric_subscriber.function_name
}

# --- Contact center prototype spec, Phase 1 Lambdas, now wired for real
# with the Phase 2 EventBridge bus above (were validate-and-revert only
# until this point). ---

module "lambda_customer_lookup" {
  source                        = "../../modules/lambda-customer-lookup"
  environment                   = "dev"
  s3_bucket_lambda_artifacts    = var.s3_bucket_lambda_artifacts
  function_name                 = "customer-lookup-dev"
  s3_key                        = "customer-lookup/dev/customer-lookup-${var.artifact_sha}.zip"
  customer_profiles_domain_name = var.customer_profiles_domain_name
  layer_arn                     = module.layers.shared_deps_layer_arn
  event_bus_name                = module.eventbridge_pipeline.bus_name
  event_bus_arn                 = module.eventbridge_pipeline.bus_arn
}

module "lambda_routing_decision" {
  source                     = "../../modules/lambda-routing-decision"
  environment                = "dev"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "routing-decision-dev"
  s3_key                     = "routing-decision/dev/routing-decision-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
  queue_claims_arn           = module.connect.queue_claims_arn
  queue_benefits_arn         = module.connect.queue_benefits_arn
  queue_authorizations_arn   = module.connect.queue_authorizations_arn
  queue_billing_arn          = module.connect.queue_billing_arn
  queue_general_arn          = module.connect.queue_general_arn
}

module "lambda_sms_verification" {
  source                     = "../../modules/lambda-sms-verification"
  environment                = "dev"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "sms-verification-dev"
  s3_key                     = "sms-verification/dev/sms-verification-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
  event_bus_name             = module.eventbridge_pipeline.bus_name
  event_bus_arn              = module.eventbridge_pipeline.bus_arn
}

module "lambda_contact_event_publisher" {
  source                     = "../../modules/lambda-contact-event-publisher"
  environment                = "dev"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "contact-event-publisher-dev"
  s3_key                     = "contact-event-publisher/dev/contact-event-publisher-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
  event_bus_name             = module.eventbridge_pipeline.bus_name
  event_bus_arn              = module.eventbridge_pipeline.bus_arn
}

# The abandonment-metric Lambda's lookback_minutes must stay roughly 2-3x
# the EventBridge Scheduler's poll_interval_minutes (see the design's
# Polling parameters section) so that overlapping poll windows reliably
# catch a contact whose CTR/flow-log wasn't ready on the prior pass. Both
# module blocks below derive their values from this single local instead of
# relying on either module's own default, so the two can't silently drift
# out of that relationship.
locals {
  abandonment_metric_poll_interval_minutes = 2
}

module "lambda_abandonment_metric" {
  source                     = "../../modules/lambda-abandonment-metric"
  environment                = "dev"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "abandonment-metric-dev"
  s3_key                     = "abandonment-metric/dev/abandonment-metric-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
  connect_instance_id        = module.connect.connect_instance_id
  flow_log_group_name        = module.connect.flow_log_group_name
  lookback_minutes           = local.abandonment_metric_poll_interval_minutes * 3
}

module "eventbridge_scheduler_abandonment_metric" {
  source                  = "../../modules/eventbridge-scheduler-abandonment-metric"
  environment             = "dev"
  target_lambda_alias_arn = module.lambda_abandonment_metric.alias_arn
  poll_interval_minutes   = local.abandonment_metric_poll_interval_minutes
}

resource "aws_connect_lambda_function_association" "eligibility_check" {
  instance_id  = module.connect.connect_instance_id
  function_arn = module.lambda.lambda_eligibility_check_alias_arn
}

# The other 5 Lambdas (Phase 1/2) were never associated with the Connect
# instance -- InvokeLambdaFunction/InvokeFlowModule actions calling them
# fail immediately with no CloudWatch invocation recorded at all, since
# Connect never had permission to invoke them in the first place. Confirmed
# live: module-customer-lookup's InvokeCustomerLookup action fell through to
# its NoMatchingError transition on every real call, despite the Lambda
# working correctly via direct aws lambda invoke.
resource "aws_connect_lambda_function_association" "customer_lookup" {
  instance_id  = module.connect.connect_instance_id
  function_arn = module.lambda_customer_lookup.alias_arn
}

resource "aws_connect_lambda_function_association" "routing_decision" {
  instance_id  = module.connect.connect_instance_id
  function_arn = module.lambda_routing_decision.alias_arn
}

resource "aws_connect_lambda_function_association" "sms_verification" {
  instance_id  = module.connect.connect_instance_id
  function_arn = module.lambda_sms_verification.alias_arn
}

resource "aws_connect_lambda_function_association" "contact_event_publisher" {
  instance_id  = module.connect.connect_instance_id
  function_arn = module.lambda_contact_event_publisher.alias_arn
}
