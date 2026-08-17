#!/usr/bin/env bash
# Idempotent Connect test-case sync, invoked by Terraform's null_resource
# local-exec provisioner (modules/connect/main.tf). Not a `data "external"`
# script -- local-exec only runs on `apply`, not `plan`, unlike this
# module's Lex `data "external"` scripts (see modules/lex/scripts/ for that
# different pattern, which exists for a different provider gap).
#
# Usage: sync_test_case.sh <instance_id> <entry_point_flow_id> <test_case_name> <content_path>
#
# ListTestCases has no server-side Name filter (verified against AWS docs)
# -- existence check pages through NextToken and matches Name client-side.
set -euo pipefail

INSTANCE_ID="$1"
ENTRY_POINT_FLOW_ID="$2"
TEST_CASE_NAME="$3"
CONTENT_PATH="$4"

# Simulated caller ANI -- metadata only, never dialed, safe as a fixed
# marker value in the reserved 555 exchange (never a real assignable
# number). DestinationPhoneNumber, by contrast, MUST be a real number
# already claimed on the instance -- Connect uses it to resolve which
# flow the simulated contact enters. It is passed in as part of
# ENTRY_POINT_FLOW_ID's caller context via the DESTINATION_PHONE_NUMBER
# env var (set by the null_resource's `environment` block), not a
# positional arg, since it's a coordinate value not specific to this
# script's create/update logic.
SOURCE_PHONE_NUMBER="+15550100000"
DESTINATION_PHONE_NUMBER="${DESTINATION_PHONE_NUMBER:?DESTINATION_PHONE_NUMBER env var must be set}"

echo "sync_test_case: INSTANCE_ID='$INSTANCE_ID' ENTRY_POINT_FLOW_ID='$ENTRY_POINT_FLOW_ID' TEST_CASE_NAME='$TEST_CASE_NAME' CONTENT_PATH='$CONTENT_PATH'" >&2

# Passed via file:// rather than an inline JSON string argument, matching
# --content's existing mechanism below. Not required for correctness (the
# real "Must specify either FlowId or phone numbers" root cause, confirmed
# live via --debug wire tracing, was CreateTestCase rejecting a target flow
# whose only action was DisconnectParticipant -- see load_test_sandbox.json's
# stub content, fixed to include a MessageParticipant action first) -- kept
# as a harmless, arguably more robust way to hand AWS CLI a JSON payload
# without depending on shell quoting behavior.
ENTRY_POINT_FILE=$(mktemp)
INITIALIZATION_DATA_FILE=$(mktemp)
trap 'rm -f "$ENTRY_POINT_FILE" "$INITIALIZATION_DATA_FILE"' EXIT

jq -n \
  --arg source "$SOURCE_PHONE_NUMBER" \
  --arg dest "$DESTINATION_PHONE_NUMBER" \
  --arg flow_id "$ENTRY_POINT_FLOW_ID" \
  '{
    Type: "VOICE_CALL",
    VoiceCallEntryPointParameters: {
      SourcePhoneNumber: $source,
      DestinationPhoneNumber: $dest,
      FlowId: $flow_id
    }
  }' > "$ENTRY_POINT_FILE"

jq -n '{Attributes: {isSyntheticTest: "true"}}' > "$INITIALIZATION_DATA_FILE"

EXISTING_TEST_CASE_ID=""
NEXT_TOKEN=""
while :; do
  if [ -n "$NEXT_TOKEN" ]; then
    PAGE=$(aws connect list-test-cases --instance-id "$INSTANCE_ID" --next-token "$NEXT_TOKEN")
  else
    PAGE=$(aws connect list-test-cases --instance-id "$INSTANCE_ID")
  fi

  MATCH_ID=$(echo "$PAGE" | jq -r --arg name "$TEST_CASE_NAME" '.TestCaseSummaryList[] | select(.Name == $name) | .Id' | head -n1)
  if [ -n "$MATCH_ID" ] && [ "$MATCH_ID" != "null" ]; then
    EXISTING_TEST_CASE_ID="$MATCH_ID"
    break
  fi

  NEXT_TOKEN=$(echo "$PAGE" | jq -r '.NextToken // empty')
  if [ -z "$NEXT_TOKEN" ]; then
    break
  fi
done

echo "sync_test_case: EXISTING_TEST_CASE_ID='$EXISTING_TEST_CASE_ID'" >&2

if [ -n "$EXISTING_TEST_CASE_ID" ]; then
  aws connect update-test-case \
    --instance-id "$INSTANCE_ID" \
    --test-case-id "$EXISTING_TEST_CASE_ID" \
    --name "$TEST_CASE_NAME" \
    --content "file://${CONTENT_PATH}" \
    --entry-point "file://${ENTRY_POINT_FILE}" \
    --initialization-data "file://${INITIALIZATION_DATA_FILE}" \
    --status PUBLISHED \
    >/dev/null
  echo "sync_test_case: updated test case $EXISTING_TEST_CASE_ID" >&2
else
  CREATE_OUTPUT=$(aws connect create-test-case \
    --instance-id "$INSTANCE_ID" \
    --name "$TEST_CASE_NAME" \
    --content "file://${CONTENT_PATH}" \
    --entry-point "file://${ENTRY_POINT_FILE}" \
    --initialization-data "file://${INITIALIZATION_DATA_FILE}" \
    --status PUBLISHED)
  NEW_TEST_CASE_ID=$(echo "$CREATE_OUTPUT" | jq -r '.TestCaseId')
  echo "sync_test_case: created test case $NEW_TEST_CASE_ID" >&2
fi
