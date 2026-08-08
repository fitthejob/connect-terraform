#!/usr/bin/env bash
# Manual testing helper for module-sms-verification's live DTMF/spoken-code
# path. Run this BEFORE dialing the test number -- it polls for the new
# contact, then polls DynamoDB for the code sms-verification writes on
# "send", and prints just the raw code once it's ready. Not part of the
# build/deploy pipeline; not applied via Terraform; purely a manual
# debugging aid so the code can be keyed in during the live 45s collection
# window without hand-assembling AWS CLI commands under time pressure.
#
# Usage: bash scripts/dev-tools/wait_for_sms_code.sh
# (edit INSTANCE_ID / TABLE_NAME below if they ever change)
set -uo pipefail

INSTANCE_ID="b1e76e5b-4f72-4e23-b6d1-281f53b3daeb"
TABLE_NAME="sms-verification-codes-dev"

# START is padded 15s into the past -- Connect's own timestamp and this
# machine's clock are never perfectly in sync, and a call that started a
# second "before" START (per Connect's clock) would otherwise never match.
START=$(date -u -d "15 seconds ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-15S +%Y-%m-%dT%H:%M:%SZ)
echo "Waiting for your call (polling every 2s, showing each attempt)..."

CID=""
ATTEMPT=0
while [ -z "$CID" ] || [ "$CID" == "None" ]; do
  ATTEMPT=$((ATTEMPT + 1))
  RESULT=$(aws connect search-contacts \
    --instance-id "$INSTANCE_ID" \
    --time-range StartTime=$START,EndTime=$(date -u +%Y-%m-%dT%H:%M:%SZ),Type=INITIATION_TIMESTAMP \
    --query "Contacts[0].Id" --output text 2>&1)
  STATUS=$?
  if [ "$STATUS" -ne 0 ]; then
    echo "  [poll $ATTEMPT] ERROR: $RESULT"
  else
    CID="$RESULT"
    echo "  [poll $ATTEMPT] result: '$CID'"
  fi
  sleep 2
done

echo "Contact found: $CID"
echo "Waiting for verification code (polling every 2s)..."

CODE=""
ATTEMPT=0
while [ -z "$CODE" ] || [ "$CODE" == "None" ]; do
  ATTEMPT=$((ATTEMPT + 1))
  RESULT=$(aws dynamodb get-item \
    --table-name "$TABLE_NAME" \
    --key "{\"contactId\":{\"S\":\"$CID\"}}" \
    --query "Item.code.S" --output text 2>&1)
  STATUS=$?
  if [ "$STATUS" -ne 0 ]; then
    echo "  [poll $ATTEMPT] ERROR: $RESULT"
  else
    CODE="$RESULT"
    echo "  [poll $ATTEMPT] result: '$CODE'"
  fi
  sleep 2
done

echo ""
echo "########################"
echo "###   CODE: $CODE   ###"
echo "########################"
