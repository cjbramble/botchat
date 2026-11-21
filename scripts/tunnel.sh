#!/usr/bin/env bash
# Forward localhost:6443 to the k3s API on the instance, through Session Manager.
# Leave it running in its own terminal while you use kubectl or helm.
set -euo pipefail

id=$(terraform -chdir=infra output -raw instance_id)
exec aws ssm start-session --target "$id" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}'
