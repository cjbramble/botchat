#!/usr/bin/env bash
# Post-deploy smoke test for the game service.
# Usage: GAME_ADDR=host:50051 GAME_INTERNAL_TOKEN=... [GAME_TLS_DIR=dir] ./scripts/smoke.sh
# With GAME_TLS_DIR (tls.crt, tls.key, ca.crt), connects with mutual TLS.
set -euo pipefail

ADDR="${GAME_ADDR:-localhost:50051}"
H="x-internal-token: ${GAME_INTERNAL_TOKEN:?set GAME_INTERNAL_TOKEN}"
if [[ -n "${GAME_TLS_DIR:-}" ]]; then
  # -servername checks the certificate against "game" even when dialing localhost.
  CONN=(-cacert "$GAME_TLS_DIR/ca.crt" -cert "$GAME_TLS_DIR/tls.crt" -key "$GAME_TLS_DIR/tls.key" -servername game)
else
  CONN=(-plaintext)
fi

pass() { echo "PASS  $1"; }
fail() {
  echo "FAIL  $1"
  exit 1
}

if grpcurl "${CONN[@]}" -H "$H" "$ADDR" list | grep -q game.v1.GameService; then
  pass "service is listed"
else
  fail "service is listed"
fi

if grpcurl "${CONN[@]}" "$ADDR" list >/dev/null 2>&1; then
  fail "no token is refused"
else
  pass "no token is refused"
fi

if [[ -n "${GAME_TLS_DIR:-}" ]]; then
  if grpcurl -insecure -H "$H" "$ADDR" list >/dev/null 2>&1; then
    fail "no client certificate is refused"
  else
    pass "no client certificate is refused"
  fi
fi

# The "smoke" channel keeps this away from real matches in other channels.
if grpcurl "${CONN[@]}" -H "$H" -d '{"channel":"smoke","player_id":"smoke","text":"hello","msg_id":"smoke-1"}' \
  "$ADDR" game.v1.GameService/SubmitInput >/dev/null; then
  pass "SubmitInput accepts input"
else
  fail "SubmitInput accepts input"
fi

if grpcurl "${CONN[@]}" -H "$H" -d '{"player_id":"smoke"}' "$ADDR" game.v1.GameService/GetPlayer | grep -q level; then
  pass "GetPlayer answers"
else
  fail "GetPlayer answers"
fi
