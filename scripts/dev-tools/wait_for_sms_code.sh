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
set -euo pipefail

INSTANCE_ID="b1e76e5b-4f72-4e23-b6d1-281f53b3daeb"
TABLE_NAME="sms-verification-codes-dev"

START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Waiting for your call..."

CID=""
while [ -z "$CID" ] || [ "$CID" == "None" ]; do
  CID=$(aws connect search-contacts \
    --instance-id "$INSTANCE_ID" \
    --time-range StartTime=$START,EndTime=$(date -u +%Y-%m-%dT%H:%M:%SZ),Type=INITIATION_TIMESTAMP \
    --query "Contacts[0].Id" --output text 2>/dev/null)
  sleep 1
done

echo "Contact found: $CID"
echo "Waiting for verification code..."

CODE=""
while [ -z "$CODE" ] || [ "$CODE" == "None" ]; do
  CODE=$(aws dynamodb get-item \
    --table-name "$TABLE_NAME" \
    --key "{\"contactId\":{\"S\":\"$CID\"}}" \
    --query "Item.code.S" --output text 2>/dev/null)
  sleep 1
done

echo ""
echo "########################"
echo "###   CODE: $CODE   ###"
echo "########################"
