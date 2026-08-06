module "connect" {
  source                                = "../../modules/connect"
  aws_connect_alias                     = var.aws_connect_alias
  hours_of_operation_name               = var.hours_of_operation_name
  lambda_eligibility_check_function_arn = var.lambda_eligibility_check_function_arn
  s3_bucket_call_recordings             = var.s3_bucket_call_recordings
  queue_claims_max_contacts             = var.queue_claims_max_contacts
  queue_benefits_max_contacts           = var.queue_benefits_max_contacts
  queue_authorizations_max_contacts     = var.queue_authorizations_max_contacts
}
