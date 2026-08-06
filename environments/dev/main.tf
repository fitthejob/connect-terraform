module "connect" {
  source                            = "../../modules/connect"
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
  s3_bucket_lambda_artifacts             = var.s3_bucket_lambda_artifacts
  lambda_eligibility_check_function_name = var.lambda_eligibility_check_function_name
  lambda_eligibility_check_s3_key        = "eligibility-check/dev/eligibility-check-${var.artifact_sha}.zip"
  connect_instance_id                    = module.connect.connect_instance_id
  customer_profiles_domain_name          = var.customer_profiles_domain_name
  layer_arn                              = module.layers.shared_deps_layer_arn
}

module "layers" {
  source                     = "../../modules/layers"
  s3_bucket_lambda_artifacts = var.s3_bucket_lambda_artifacts
  shared_deps_layer_s3_key   = "shared-deps/dev/shared-deps-${var.artifact_sha}.zip"
}



resource "aws_connect_lambda_function_association" "eligibility_check" {
  instance_id  = module.connect.connect_instance_id
  function_arn = module.lambda.lambda_eligibility_check_alias_arn
}
