#!/usr/bin/env bash
# Create the local cluster and its add-ons (Step 12b). Safe to run again.
set -euo pipefail

CALICO_VERSION=v3.30.0       # pod networking that enforces NetworkPolicy
CERT_MANAGER_VERSION=v1.20.1 # the same version as in production (Step 13.11)

ctlptl apply -f deploy/local/cluster.yaml
kubectl config use-context kind-botchat

kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml"
kubectl -n kube-system rollout status daemonset/calico-node --timeout=5m

helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager --create-namespace \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true --wait

echo "local cluster ready; now run: tilt up"
