#!/bin/bash
# EC2 user data: runs once, as root, on the instance's first boot.
# Log: /var/log/cloud-init-output.log on the instance.
set -euo pipefail

mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<'YAML'
write-kubeconfig-mode: "0600" # only root may read the admin kubeconfig
secrets-encryption: true      # Kubernetes Secrets are encrypted in k3s's datastore
node-name: botchat
YAML

# The Elastic IP replaces the temporary public address a few seconds after boot,
# which can cut a download short, so retry.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${k3s_version}' sh -s - server; then
    exit 0
  fi
  echo "k3s install attempt $attempt failed; retrying in 15s" >&2
  sleep 15
done
exit 1
