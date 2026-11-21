#!/usr/bin/env bash
# Copy k3s's admin kubeconfig to ~/.kube/botchat-ec2.yaml, with everything named botchat-ec2.
set -euo pipefail

id=$(terraform -chdir=infra output -raw instance_id)
out="$HOME/.kube/botchat-ec2.yaml"

cmd=$(aws ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
  --parameters 'commands=["cat /etc/rancher/k3s/k3s.yaml"]' \
  --query Command.CommandId --output text)
aws ssm wait command-executed --command-id "$cmd" --instance-id "$id"

mkdir -p "$HOME/.kube"
umask 077 # the file holds an admin key: readable by you only
aws ssm get-command-invocation --command-id "$cmd" --instance-id "$id" \
  --query StandardOutputContent --output text |
  sed -E 's/^([ -]*)(name|cluster|user|current-context): default$/\1\2: botchat-ec2/' >"$out"

echo "wrote $out"
echo "add it to KUBECONFIG (see below), then: kubectl config use-context botchat-ec2"
