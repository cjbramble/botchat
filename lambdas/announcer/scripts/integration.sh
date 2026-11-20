#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../../infra"
IN=$(aws sqs get-queue-url --queue-name announcements --query QueueUrl --output text)
OUT=$(terraform output -raw chat_notices_queue_url)
ID="qa_$(date +%s)"

aws sqs send-message --queue-url "$IN" \
  --message-body "{\"type\":\"player.leveled_up\",\"version\":1,\"player_id\":\"$ID\",\"old_level\":1,\"new_level\":2}" >/dev/null

for _ in $(seq 1 12); do        # up to ~60 s
  BODY=$(aws sqs receive-message --queue-url "$OUT" --wait-time-seconds 5 \
           --query 'Messages[0].Body' --output text)
  if [[ "$BODY" == *"$ID has reached level 2"* ]]; then
    echo "PASS  notice arrived: $BODY"
    exit 0
  fi
done
echo "FAIL  no notice for $ID within 60 s"; exit 1
