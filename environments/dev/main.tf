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
# The 4 metric-subscriber Lambda instances (contact-center-prototype-spec.md
# Layer 4's "Lambda subscriber for real-time action" per rule). Each shares
# the same event-metric-subscriber source but is a distinct build-matrix
# artifact and Terraform resource, parameterized by metric name/dimension.

module "subscriber_contact_initiated" {
  source                     = "../../modules/lambda-event-metric-subscriber"
  environment                = "dev"
  instance_name              = "contact-initiated-metric"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "contact-initiated-metric-dev"
  s3_key                     = "contact-initiated-metric/dev/contact-initiated-metric-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
  metric_name                = "ContactsInitiated"
}

module "subscriber_contact_transferred" {
  source                     = "../../modules/lambda-event-metric-subscriber"
  environment                = "dev"
  instance_name              = "contact-transferred-metric"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "contact-transferred-metric-dev"
  s3_key                     = "contact-transferred-metric/dev/contact-transferred-metric-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
  metric_name                = "ContactsTransferred"
  dimension_field            = "queue"
}

module "subscriber_contact_disconnected" {
  source                     = "../../modules/lambda-event-metric-subscriber"
  environment                = "dev"
  instance_name              = "contact-disconnected-metric"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "contact-disconnected-metric-dev"
  s3_key                     = "contact-disconnected-metric/dev/contact-disconnected-metric-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
  metric_name                = "ContactDurationSeconds"
  value_field                = "durationSeconds"
}

module "subscriber_verification_completed" {
  source                     = "../../modules/lambda-event-metric-subscriber"
  environment                = "dev"
  instance_name              = "verification-completed-metric"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  function_name              = "verification-completed-metric-dev"
  s3_key                     = "verification-completed-metric/dev/verification-completed-metric-${var.artifact_sha}.zip"
  layer_arn                  = module.layers.shared_deps_layer_arn
  metric_name                = "VerificationOutcome"
  dimension_field            = "verificationStatus"
}

module "eventbridge_pipeline" {
  source      = "../../modules/eventbridge-pipeline"
  environment = "dev"

  contact_initiated_subscriber_alias_arn          = module.subscriber_contact_initiated.alias_arn
  contact_initiated_subscriber_function_name      = module.subscriber_contact_initiated.function_name
  contact_transferred_subscriber_alias_arn        = module.subscriber_contact_transferred.alias_arn
  contact_transferred_subscriber_function_name    = module.subscriber_contact_transferred.function_name
  contact_disconnected_subscriber_alias_arn       = module.subscriber_contact_disconnected.alias_arn
  contact_disconnected_subscriber_function_name   = module.subscriber_contact_disconnected.function_name
  verification_completed_subscriber_alias_arn     = module.subscriber_verification_completed.alias_arn
  verification_completed_subscriber_function_name = module.subscriber_verification_completed.function_name
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

resource "aws_connect_lambda_function_association" "eligibility_check" {
  instance_id  = module.connect.connect_instance_id
  function_arn = module.lambda.lambda_eligibility_check_alias_arn
}
