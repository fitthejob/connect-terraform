#!/usr/bin/env bash
# Idempotent Lex V2 bot alias creation, invoked by Terraform's `data "external"`.
# Reads a JSON object with bot_id, bot_version, alias_name, locale_id on stdin;
# writes a JSON object with alias_arn on stdout.
#
# Only CreateBotAlias returns botAliasArn in its response — DescribeBotAlias
# and UpdateBotAlias do not (confirmed against a live bot: describe-bot-alias
# has no arn field of any kind in its output). So the ARN is constructed from
# its documented, fixed format instead of read back from the API:
#   arn:aws:lex:REGION:ACCOUNT:bot-alias/BOTID/ALIASID
set -euo pipefail

eval "$(jq -r '@sh "BOT_ID=\(.bot_id) BOT_VERSION=\(.bot_version) ALIAS_NAME=\(.alias_name) LOCALE_ID=\(.locale_id)"')"

echo "create_bot_alias: AWS_REGION='${AWS_REGION:-<unset>}' AWS_DEFAULT_REGION='${AWS_DEFAULT_REGION:-<unset>}' configured_region='$(aws configure get region 2>&1 || echo <error>)'" >&2

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region)}}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$REGION" ]; then
  echo "create_bot_alias: ERROR - could not resolve AWS region (checked \$AWS_REGION, \$AWS_DEFAULT_REGION, aws configure get region)" >&2
  exit 1
fi

EXISTING_ALIAS_ID=$(aws lexv2-models list-bot-aliases \
  --bot-id "$BOT_ID" \
  --query "botAliasSummaries[?botAliasName=='${ALIAS_NAME}'].botAliasId" \
  --output text)

if [ -n "$EXISTING_ALIAS_ID" ] && [ "$EXISTING_ALIAS_ID" != "None" ]; then
  ALIAS_ID="$EXISTING_ALIAS_ID"

  aws lexv2-models update-bot-alias \
    --bot-id "$BOT_ID" \
    --bot-alias-id "$ALIAS_ID" \
    --bot-alias-name "$ALIAS_NAME" \
    --bot-version "$BOT_VERSION" \
    --bot-alias-locale-settings "{\"${LOCALE_ID}\": {\"enabled\": true}}" \
    >/dev/null
else
  CREATE_OUTPUT=$(aws lexv2-models create-bot-alias \
    --bot-id "$BOT_ID" \
    --bot-alias-name "$ALIAS_NAME" \
    --bot-version "$BOT_VERSION" \
    --bot-alias-locale-settings "{\"${LOCALE_ID}\": {\"enabled\": true}}")

  ALIAS_ID=$(echo "$CREATE_OUTPUT" | jq -r '.botAliasId')
fi

if [ -z "$ALIAS_ID" ] || [ "$ALIAS_ID" = "None" ] || [ "$ALIAS_ID" = "null" ]; then
  echo "create_bot_alias: ERROR - could not resolve alias id (got: '$ALIAS_ID')" >&2
  exit 1
fi

ALIAS_ARN="arn:aws:lex:${REGION}:${ACCOUNT_ID}:bot-alias/${BOT_ID}/${ALIAS_ID}"

jq -n --arg alias_arn "$ALIAS_ARN" '{alias_arn: $alias_arn}'
