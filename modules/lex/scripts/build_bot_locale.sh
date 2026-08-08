#!/usr/bin/env bash
# Idempotent Lex V2 DRAFT locale build, invoked by Terraform's `data "external"`.
# Reads a JSON object with bot_id, locale_id on stdin; writes a JSON object
# with bot_locale_status on stdout.
#
# BuildBotLocale only accepts bot_version = "DRAFT" -- it's the step that
# compiles a bot's intents/slots into a working NLU model. Skipped by every
# other Lex resource in this repo (aws_lexv2models_intent/slot/bot_version
# only create/update configuration, none of them trigger a build), which
# meant CreateBotVersion was snapshotting an unbuilt DRAFT: the resulting
# version's alias failed at runtime with
# "Couldn't start a conversation with bot alias ... The alias isn't built"
# (confirmed live via Connect flow logs, /aws/connect/mini-connect).
#
# BuildBotLocale is asynchronous (returns immediately, builds in the
# background) -- must poll DescribeBotLocale until botLocaleStatus is
# terminal (Built, or a Failed-family status) before returning, otherwise
# aws_lexv2models_bot_version.v1 could snapshot DRAFT mid-build and
# reproduce the same "isn't built" failure as a race condition instead of
# a hard miss.
set -euo pipefail

eval "$(jq -r '@sh "BOT_ID=\(.bot_id) LOCALE_ID=\(.locale_id)"')"

echo "build_bot_locale: BOT_ID='$BOT_ID' LOCALE_ID='$LOCALE_ID'" >&2

CURRENT_STATUS=$(aws lexv2-models describe-bot-locale \
  --bot-id "$BOT_ID" \
  --bot-version "DRAFT" \
  --locale-id "$LOCALE_ID" \
  --query "botLocaleStatus" \
  --output text)

echo "build_bot_locale: current status before build='$CURRENT_STATUS'" >&2

if [ "$CURRENT_STATUS" != "Built" ]; then
  aws lexv2-models build-bot-locale \
    --bot-id "$BOT_ID" \
    --bot-version "DRAFT" \
    --locale-id "$LOCALE_ID" \
    >/dev/null

  # Poll until the build reaches a terminal status. Real builds have taken
  # well under a minute for this bot's small intent/slot set in practice,
  # but no documented SLA -- generous bound (5 min) with a short interval.
  ATTEMPTS=0
  MAX_ATTEMPTS=60
  SLEEP_SECONDS=5

  while [ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ]; do
    STATUS=$(aws lexv2-models describe-bot-locale \
      --bot-id "$BOT_ID" \
      --bot-version "DRAFT" \
      --locale-id "$LOCALE_ID" \
      --query "botLocaleStatus" \
      --output text)

    echo "build_bot_locale: poll $ATTEMPTS status='$STATUS'" >&2

    case "$STATUS" in
      Built)
        break
        ;;
      Failed|Deleting)
        echo "build_bot_locale: ERROR - build reached terminal failure status '$STATUS'" >&2
        exit 1
        ;;
    esac

    ATTEMPTS=$((ATTEMPTS + 1))
    sleep "$SLEEP_SECONDS"
  done

  if [ "$STATUS" != "Built" ]; then
    echo "build_bot_locale: ERROR - build did not reach 'Built' status within $((MAX_ATTEMPTS * SLEEP_SECONDS))s (last status: '$STATUS')" >&2
    exit 1
  fi
else
  STATUS="Built"
fi

jq -n --arg status "$STATUS" '{bot_locale_status: $status}'
