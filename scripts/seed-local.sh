#!/usr/bin/env bash
# Seed channels and bots in the local cluster and store the bots' tokens in a Secret.
# Tilt runs this once chat is up (Step 12b); you can also run it by hand.
set -euo pipefail

if [[ "$(kubectl config current-context)" != "kind-botchat" ]]; then
  echo "refusing to seed: kubectl isn't pointing at kind-botchat" >&2
  exit 1
fi
if [[ ! -f bots/.env ]]; then
  echo "bots/.env is missing: copy bots/.env.example and add your OpenRouter key" >&2
  exit 1
fi

k() { kubectl -n botchat "$@"; }

k exec deploy/chat -- /app/bin/chat eval 'Chat.Release.seed()'

pod=$(k get pod -l app=chat -o jsonpath='{.items[0].metadata.name}')
k cp bots/bots/personas.toml "$pod:/tmp/personas.toml"

# kubectl keeps quotes around a value as part of it (Compose strips them), so strip them here.
unquote() {
  sed -E -e 's/^([A-Za-z_][A-Za-z0-9_]*)="(.*)"$/\1=\2/' -e "s/^([A-Za-z_][A-Za-z0-9_]*)='(.*)'\$/\1=\2/"
}

# New tokens every run (seed_bots revokes the old ones), straight into the Secret.
k create secret generic bots --dry-run=client -o yaml \
  --from-env-file=<(grep -Ev '^(BOT_TOKEN_|CHAT_URL=)' bots/.env | unquote) \
  --from-env-file=<(k exec deploy/chat -- /app/bin/chat eval 'Chat.Release.seed_bots("/tmp/personas.toml")' | grep '^BOT_TOKEN_') |
  k apply -f -

# Running bots still hold the old tokens; restart them if they exist yet.
k rollout restart deployment/bots 2>/dev/null || true
echo "seeded; bots will connect with fresh tokens"
