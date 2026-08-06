#!/usr/bin/env bash
# Idempotent Lex V2 bot alias creation, invoked by Terraform's `data "external"`.
# Reads a JSON object with bot_id, bot_version, alias_name, locale_id on stdin;
# writes a JSON object with alias_arn on stdout.
set -euo pipefail

eval "$(jq -r '@sh "BOT_ID=\(.bot_id) BOT_VERSION=\(.bot_version) ALIAS_NAME=\(.alias_name) LOCALE_ID=\(.locale_id)"')"

EXISTING_ALIAS_ID=$(aws lexv2-models list-bot-aliases \
  --bot-id "$BOT_ID" \
  --query "botAliasSummaries[?botAliasName=='${ALIAS_NAME}'].botAliasId" \
  --output text)

if [ -n "$EXISTING_ALIAS_ID" ] && [ "$EXISTING_ALIAS_ID" != "None" ]; then
  aws lexv2-models update-bot-alias \
    --bot-id "$BOT_ID" \
    --bot-alias-id "$EXISTING_ALIAS_ID" \
    --bot-alias-name "$ALIAS_NAME" \
    --bot-version "$BOT_VERSION" \
    --bot-alias-locale-settings "{\"${LOCALE_ID}\": {\"enabled\": true}}" \
    >/dev/null

  ALIAS_ARN=$(aws lexv2-models describe-bot-alias \
    --bot-id "$BOT_ID" \
    --bot-alias-id "$EXISTING_ALIAS_ID" \
    --query "botAliasArn" \
    --output text)
else
  CREATE_OUTPUT=$(aws lexv2-models create-bot-alias \
    --bot-id "$BOT_ID" \
    --bot-alias-name "$ALIAS_NAME" \
    --bot-version "$BOT_VERSION" \
    --bot-alias-locale-settings "{\"${LOCALE_ID}\": {\"enabled\": true}}")

  ALIAS_ARN=$(echo "$CREATE_OUTPUT" | jq -r '.botAliasArn')
fi

jq -n --arg alias_arn "$ALIAS_ARN" '{alias_arn: $alias_arn}'
