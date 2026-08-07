output "deploy_role_arn" {
  value = module.deploy_role.role_arn
}

output "pr_checks_role_arn" {
  value = module.pr_checks_role.role_arn
}
