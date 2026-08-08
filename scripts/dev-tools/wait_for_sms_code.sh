#!/usr/bin/env bash
# Manual testing helper for module-sms-verification's live DTMF/spoken-code
# path. Run this BEFORE dialing the test number -- it polls DynamoDB directly
# for the newest code (by expiresAt, since each code has a 5-minute TTL and
# only one live test call is expected at a time), and prints it once found.
# Not part of the build/deploy pipeline; not applied via Terraform; purely a
# manual debugging aid so the code can be keyed in during the live 45s
# collection window without hand-assembling AWS CLI commands under time
# pressure.
#
# Usage: bash scripts/dev-tools/wait_for_sms_code.sh
# (edit TABLE_NAME below if it ever changes)
set -uo pipefail

TABLE_NAME="sms-verification-codes-dev"

echo "Waiting for verification code (polling every 2s)..."

CODE=""
ATTEMPT=0
while [ -z "$CODE" ] || [ "$CODE" == "None" ]; do
  ATTEMPT=$((ATTEMPT + 1))
  RESULT=$(aws dynamodb scan \
    --table-name "$TABLE_NAME" \
    --query "sort_by(Items, &expiresAt.N)[-1].code.S" \
    --output text 2>&1)
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
