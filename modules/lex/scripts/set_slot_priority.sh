#!/usr/bin/env bash
# Idempotent Lex V2 slot-priority assignment, invoked by Terraform's
# `data "external"`. Reads a JSON object with bot_id, locale_id,
# intent_id, intent_name, slot_id, sample_utterances_json (a JSON array of
# {"utterance": "..."} objects) on stdin; writes a JSON object with
# slot_id/priority on stdout.
#
# aws_lexv2models_intent's slot_priority block requires slot_id, which
# only exists after aws_lexv2models_slot is created -- but
# aws_lexv2models_slot requires intent_id, which only exists after
# aws_lexv2models_intent is created. Each resource needs a real output
# value from the other, which Terraform's dependency graph cannot express
# without an actual cycle (confirmed: matches the exact symptom in
# hashicorp/terraform-provider-aws#39948, an open, unresolved bug -- not
# something to work around with depends_on, since that only orders
# resources that need each other's timing, not resources that need each
# other's *values* in both directions). Lex's own build validator requires
# slot_priority to be set (confirmed live: BuildBotLocale fails with
# "Slot ids [...] don't define a slot priority"), so this can't be
# skipped either -- same category of gap as create_bot_alias.sh and
# build_bot_locale.sh, worked around the same way: an imperative AWS CLI
# call once both real IDs already exist in state.
#
# UpdateIntent is a full-replace API, not a patch -- sample_utterances is
# re-supplied explicitly on every call (from the same utterances defined
# in main.tf) rather than omitted, since Lex V2's update semantics for
# omitted list fields aren't clearly documented and the safer assumption
# is that omitting it could wipe the intent's existing utterances.
set -euo pipefail

# Read stdin once -- a second `jq` reading from stdin directly would get
# nothing, since the first jq invocation already consumed the pipe.
QUERY_JSON=$(cat)
eval "$(echo "$QUERY_JSON" | jq -r '@sh "BOT_ID=\(.bot_id) LOCALE_ID=\(.locale_id) INTENT_ID=\(.intent_id) INTENT_NAME=\(.intent_name) SLOT_ID=\(.slot_id)"')"
SAMPLE_UTTERANCES_JSON=$(echo "$QUERY_JSON" | jq -r '.sample_utterances_json')

echo "set_slot_priority: BOT_ID='$BOT_ID' LOCALE_ID='$LOCALE_ID' INTENT_ID='$INTENT_ID' SLOT_ID='$SLOT_ID'" >&2

aws lexv2-models update-intent \
  --bot-id "$BOT_ID" \
  --bot-version "DRAFT" \
  --locale-id "$LOCALE_ID" \
  --intent-id "$INTENT_ID" \
  --intent-name "$INTENT_NAME" \
  --sample-utterances "$SAMPLE_UTTERANCES_JSON" \
  --slot-priorities "[{\"priority\": 1, \"slotId\": \"$SLOT_ID\"}]" \
  >/dev/null

echo "set_slot_priority: update-intent succeeded" >&2

jq -n --arg slot_id "$SLOT_ID" '{slot_id: $slot_id, priority: "1"}'
