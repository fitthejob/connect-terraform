#!/usr/bin/env bash
# Idempotent Lex V2 bot association, invoked by Terraform's `data "external"`.
# aws_connect_bot_association only supports Lex V1 bots (checked hashicorp/aws
# v5.100.0 and v6.58.0 schemas directly — no lex_v2_bot block exists), even
# though the AWS API itself supports it via AssociateBot's LexV2Bot field.
# Reads a JSON object with instance_id, alias_arn on stdin; writes a JSON
# object with associated=true on stdout.
set -euo pipefail

eval "$(jq -r '@sh "INSTANCE_ID=\(.instance_id) ALIAS_ARN=\(.alias_arn)"')"

ALREADY_ASSOCIATED=$(aws connect list-bots \
  --instance-id "$INSTANCE_ID" \
  --lex-version V2 \
  --query "LexBots[?LexV2Bot.AliasArn=='${ALIAS_ARN}'] | length(@)" \
  --output text)

if [ "$ALREADY_ASSOCIATED" = "0" ]; then
  aws connect associate-bot \
    --instance-id "$INSTANCE_ID" \
    --lex-v2-bot AliasArn="$ALIAS_ARN" \
    >/dev/null
fi

jq -n '{associated: "true"}'
