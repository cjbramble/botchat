#!/usr/bin/env bash
# Create or update both CDC connectors, then show their state.
# Usage: ./scripts/connectors.sh [connect-url]   (default http://localhost:8083)
set -euo pipefail

url=${1:-http://localhost:8083}

for db in chat game; do
  # PUT .../config creates the connector or replaces its config: safe to rerun.
  curl -fsS -X PUT -H 'Content-Type: application/json' \
    --data @"analytics/connect/$db.json" "$url/connectors/botchat-$db/config" >/dev/null
done

sleep 5 # give the tasks a moment to start
for db in chat game; do
  curl -fsS "$url/connectors/botchat-$db/status" | python3 -c '
import json, sys
s = json.load(sys.stdin)
tasks = ", ".join(t["state"] for t in s["tasks"]) or "none yet"
print(s["name"] + ": connector " + s["connector"]["state"] + ", tasks " + tasks)'
done
