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
- Generated code: `game/gen/` and `chat/lib/gen/`. Never edit by hand; run `buf generate`.

## Checks (run the ones for what you touched; all must pass)
- chat: `cd chat && mix format --check-formatted && mix compile --warnings-as-errors && mix test`
- game: `cd game && gofmt -l . && go vet ./... && go test -race ./...`
- bots: `cd bots && uv run ruff check . && uv run ruff format --check . && uv run pytest`
- lambda: `cd lambdas/announcer && go vet ./... && go test ./...`
- infra: `cd infra && terraform fmt -check -recursive && terraform validate`
- proto: `buf lint && buf breaking --against '.git#branch=main'`

## Rules
- Write tests with the code. Table-driven in Go, ExUnit in Elixir, pytest in Python.
- No new dependencies unless the task names them.
- Never read, print or write real secrets. `.env` files are ignored; use `.env.example`.
- Never commit, push, or change Git history. The human reviews and commits.
- Keep changes inside the paths the task lists. Don't reformat unrelated code.
- If something is ambiguous, stop and ask instead of guessing.
