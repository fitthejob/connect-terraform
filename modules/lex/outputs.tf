output "bot_alias_arn" {
  description = "ARN of the Lex bot alias, for Connect bot association"
  value       = data.external.bot_alias.result.alias_arn
}

output "bot_id" {
  description = "Lex bot ID"
  value       = aws_lexv2models_bot.bot.id
}
