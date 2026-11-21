# Instructions for coding agents

This repo is **botchat**: an IRC-style chat where AI bots talk and play Guess the
Number. It follows a step-by-step build guide; match its file paths and names exactly.

## Layout
- `chat/`: Elixir/Phoenix. Business logic in `lib/chat/` (contexts), web code in
  `lib/chat_web/`. `Chat.Rooms.post_message/3` is the only way messages are written.
- `game/`: Go. `internal/match` is pure rules (no I/O, no clock, no global rand);
  `internal/runner` owns each match in one goroutine; `cmd/server` is the gRPC shell.
- `bots/`: Python with uv, flat layout (package in `bots/bots/`).
- `lambdas/announcer/`: Go AWS Lambda. `infra/`: Terraform. `proto/`: shared contract.
- `deploy/k8s/`: Kubernetes manifests. `base/` is shared; `overlays/local` (kind + Tilt,
  see `Tiltfile`) and `overlays/ec2` (k3s on EC2) add what differs. `scripts/`: shell helpers.
- Generated code: `game/gen/` and `chat/lib/gen/`. Never edit by hand; run `buf generate`.

## Checks (run the ones for what you touched; all must pass)
- chat: `cd chat && mix format --check-formatted && mix compile --warnings-as-errors && mix test`
- game: `cd game && gofmt -l . && go vet ./... && go test -race ./...`
- bots: `cd bots && uv run ruff check . && uv run ruff format --check . && uv run pytest`
- lambda: `cd lambdas/announcer && go vet ./... && go test ./...`
- infra: `cd infra && terraform fmt -check -recursive && terraform validate`
- proto: `buf lint && buf breaking --against '.git#branch=main'`
- deploy: `kubectl kustomize deploy/k8s/overlays/local > /dev/null && kubectl kustomize deploy/k8s/overlays/ec2 > /dev/null`
- scripts: `for s in scripts/*.sh; do bash -n "$s"; done`

## Rules
- Write tests with the code. Table-driven in Go, ExUnit in Elixir, pytest in Python.
- No new dependencies unless the task names them.
- Never read, print or write real secrets. `.env` files are ignored; use `.env.example`.
- Never commit, push, or change Git history. The human reviews and commits.
- Keep changes inside the paths the task lists. Don't reformat unrelated code.
- If something is ambiguous, stop and ask instead of guessing.
- Some actions are the human's alone: creating accounts or keys, `aws sso login`,
  `terraform apply`, `helm install`, deploying, anything in a cloud console or a browser,
  and anything that spends money (real bot runs). Don't run them; say exactly what the
  human should run and why, and wait.
- Never point `kubectl`, `tilt` or `terraform` at production on your own. Local work uses
  the `kind-botchat` context only.
- Before a pull request, update the status labels in `README.md` and
  `docs/architecture.md` to match the branch: remove **WIP** from what is now done, and
  change **Planned** to **WIP** for what has been started.
- End every task with a "Your turn" list of what the human needs to do next.
