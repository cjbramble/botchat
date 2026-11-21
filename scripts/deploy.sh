#!/usr/bin/env bash
# Build, push and roll out one service.  Usage: ./scripts/deploy.sh chat|game|bots
# Run from the repo root, on main, with `aws login --profile botchat` done,
# AWS_PROFILE=botchat exported and ./scripts/tunnel.sh running.
set -euo pipefail

overlay=deploy/k8s/overlays/ec2

svc=${1:-}
case "$svc" in
  chat | game | bots) ;;
  *) echo "usage: $0 chat|game|bots" >&2; exit 2 ;;
esac

# Only ever deploy to the instance's k3s, never to the local cluster (or anything else).
context=$(kubectl config current-context)
if [[ "$context" != "botchat-ec2" ]]; then
  echo "kubectl points at '$context', not botchat-ec2: kubectl config use-context botchat-ec2" >&2
  exit 1
fi

# The image tag is the commit, so the code must be committed. The manifest file
# this script edits is the one exception.
if [[ -n "$(git status --porcelain -- . ":!$overlay/kustomization.yaml")" ]]; then
  echo "commit or stash your changes first: the image tag is the commit" >&2
  exit 1
fi
tag=$(git rev-parse --short=12 HEAD)
registry=$(terraform -chdir=infra output -raw ecr_registry)
image="$registry/botchat/$svc:$tag"

aws ecr get-login-password --region us-east-1 |
  docker login --username AWS --password-stdin "$registry" >/dev/null

# Tags are immutable: build and push only if this commit isn't there yet.
if aws ecr describe-images --repository-name "botchat/$svc" --image-ids imageTag="$tag" >/dev/null 2>&1; then
  echo "$image already exists"
else
  docker buildx build --platform linux/arm64 --tag "$image" --push "$svc"
fi

# k3s pulls from ECR with a token that lasts 12 hours: refresh the pull secret every deploy.
kubectl create namespace botchat --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n botchat create secret docker-registry ecr \
  --docker-server="$registry" --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-east-1)" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Record the tag in the manifests, then apply all of them: unchanged objects stay as they are.
sed -i.bak "\|newName: .*/botchat/$svc\$|,/newTag:/ s|newTag: .*|newTag: \"$tag\"|" "$overlay/kustomization.yaml"
rm "$overlay/kustomization.yaml.bak"
kubectl apply -k "$overlay"
kubectl -n botchat rollout status "deployment/$svc" --timeout=5m

echo "deployed $image"
echo "now commit $overlay/kustomization.yaml, so main says what's running"
