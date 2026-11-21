# Deploy runbook

How to reach, start, stop and rebuild the botchat platform on AWS: one EC2 instance
running k3s, plus RDS. No secrets or real IDs live here.

## Before you start

- Signed in: `aws login --profile botchat`, with `AWS_PROFILE=botchat` exported (see `aws-account.md`).
- Tools: `brew install kubectl helm` and `brew install --cask session-manager-plugin`.
- Run every script from the repo root; they read `instance_id` from `terraform -chdir=infra output`.

## Pinned versions

| What | Version | Where it is set |
|---|---|---|
| k3s | `v1.36.5+k3s1` | `k3s_version` in `infra/variables.tf` |
| cert-manager chart | `v1.20.1` | the `helm install` below and `scripts/local-cluster.sh` |

Upgrading either is a deliberate change:

- k3s: run the installer with the newer `INSTALL_K3S_VERSION` in a Session Manager shell, then update the variable's default to match. Editing the variable alone changes nothing on a running instance.
- cert-manager: `helm upgrade` with the new `--version`, then update this table and `scripts/local-cluster.sh`.

## Connect

The Kubernetes API (port 6443) is not open to the internet. Reach it through a Session Manager tunnel.

1. Terminal 1, leave it running:

   ```sh
   ./scripts/tunnel.sh
   ```

2. Terminal 2, once per instance (again after a rebuild):

   ```sh
   ./scripts/kubeconfig.sh      # writes ~/.kube/botchat-ec2.yaml, mode 600
   ```

3. Once, in `~/.zshrc`, so `kubectl` sees both the kind cluster and this one:

   ```sh
   export KUBECONFIG="$HOME/.kube/config:$HOME/.kube/botchat-ec2.yaml"
   ```

4. Check:

   ```sh
   kubectl config use-context botchat-ec2
   kubectl get nodes                  # one node, "botchat", STATUS Ready
   kubectl get pods -n kube-system    # coredns, traefik, svclb-traefik, local-path, metrics-server
   ```

- The tunnel closes when the AWS login expires. Sign in again and restart it; the kubeconfig keeps working.
- Shell on the instance: `aws ssm start-session --target "$(terraform -chdir=infra output -raw instance_id)"`, then `sudo -i`. `sudo k3s kubectl` works there without a kubeconfig.
- First-boot log, if k3s is missing: `/var/log/cloud-init-output.log` on the instance.

## cert-manager

Installed once per instance. It issues the private CA for mutual TLS between chat and game.

```sh
helm --kube-context botchat-ec2 install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.20.1 \
  --set crds.enabled=true

kubectl -n cert-manager rollout status deployment/cert-manager-webhook
```

## Stop and start

The instance and the database bill by the hour while they run. Stopping keeps the disk
(k3s and everything in it), the database and the IP address.

```sh
./scripts/down.sh    # when you stop working
./scripts/up.sh      # the database and the instance; then ./scripts/tunnel.sh for kubectl
```

- Restart the tunnel after every stop and start: press Ctrl-C in the old tunnel's terminal first. A stop ends the session on the instance, but the old process keeps local port 6443, so a second tunnel cannot open and `kubectl` hangs.
- `up.sh` right after `down.sh` exits with "the database is still stopping": wait a few minutes and run it again.
- After `up.sh`, pods that started before the database restart until it answers (a minute or two).
- RDS starts itself again after 7 days stopped. Run `down.sh` again if you are still away.

## Rebuild the instance

Replaces the machine and keeps the Elastic IP, the DNS name and the database. Nothing
inside the cluster survives.

1. `terraform -chdir=infra apply -replace=aws_instance.k3s`
2. Press Ctrl-C in the old tunnel, wait a minute or two for k3s to install, then `./scripts/tunnel.sh`.
3. `./scripts/kubeconfig.sh` (the new cluster has new keys, so the old file stops working).
4. Install cert-manager (above). `helm install` works once per cluster; a second run fails with "cannot reuse a name that is still in use" and changes nothing.

Time taken: about 15 minutes, most of it waiting for k3s to install.
