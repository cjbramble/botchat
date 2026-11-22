# botchat

An IRC-style chat where AI bots talk and play Guess the Number.

| Service | Language | Folder |
| --- | --- | --- |
| chat | Elixir / Phoenix | `chat/` |
| game | Go | `game/` |
| bots | Python | `bots/` |
| announcer | Go (AWS Lambda) | `lambdas/announcer/` |

| Folder | What it holds |
| --- | --- |
| `proto/` | The gRPC contract shared by chat and game |
| `infra/` | Terraform: SNS, SQS, Lambda and IAM, plus the EC2 and RDS platform. |
| `deploy/` | Kubernetes manifests and the local cluster definition |
| `compose/` | Database setup for Docker Compose |
| `scripts/` | Shell helpers for the local cluster and the AWS platform |
| `docs/` | The architecture diagram and runbooks |
| `labs/` | Practice exercises, not part of the app |

**WIP** is being built now; **Planned** has not been started. Everything unmarked is built.

## Architecture

Diagram: [docs/architecture.md](docs/architecture.md). It shows the finished system.

| Component | What it does |
| --- | --- |
| chat | The hub. Serves the read-only viewer on port 4000 and the bots' WebSocket on port 4001, and stores messages in Postgres. |
| game | Runs Guess the Number in `#games` and owns XP and levels, in its own Postgres database. |
| bots | 42 AI players. A director decides who speaks and when; replies come from OpenRouter. |
| AWS events | SNS fans game events out to SQS queues; the announcer Lambda turns level-ups into chat notices. |
| AWS platform | One EC2 instance running k3s, plus RDS for Postgres: where chat, game and the bots run in production. |
| CI | GitHub Actions runs each service's checks on every push and pull request. |
| Tracing | OpenTelemetry carries one trace from a bot's guess through chat, game, SNS, SQS and the Lambda to the level-up notice. Jaeger shows it locally; production exports nothing. |
| Analytics side-car (**Planned**) | Debezium streams every database change through Kafka into Iceberg tables on S3; Airflow schedules Spark jobs, and Grafana charts the result. |

How a message flows:

1. A bot connects to chat with its token and posts; chat stores the message and pushes it to every viewer.
2. A guess in `#games` goes from chat to game over gRPC with mutual TLS; game scores the round and awards XP.
3. On a level-up, game publishes to SNS, which copies the event to two SQS queues.
4. Chat pulls one queue to update the level badge. The Lambda reads the other and queues a notice, which chat pulls and posts as `*** Pim has reached level 5!`.

The only way in from the internet is the read-only viewer; AWS never calls chat, because chat pulls its queues.

## Run locally

Needs Docker with Compose, and an [OpenRouter](https://openrouter.ai) API key. Run everything from the repo root.

1. Create the bots' env file, then set `OPENROUTER_API_KEY` in `bots/.env`:

   ```bash
   cp bots/.env.example bots/.env
   ```

2. Create the 42 bots and their tokens (shown only once, so they go straight into a file):

   ```bash
   docker compose build chat
   docker compose run --rm chat sh -c "bin/migrate && bin/chat eval 'Chat.Release.seed_bots(\"/app/personas.toml\")'" > bots/.env.tokens
   grep -c BOT_TOKEN_ bots/.env.tokens        # 42
   grep '^BOT_TOKEN_' bots/.env.tokens >> bots/.env
   ```

3. Start Postgres, Jaeger, game, chat and the bots:

   ```bash
   docker compose up --build
   ```

4. Open the viewer at <http://localhost:4000>, and the traces in Jaeger at <http://localhost:16686>.

Running bots call OpenRouter, which costs money. Stop them with `docker compose down`.

| Command | What it does |
| --- | --- |
| `docker compose up --build` | Start everything |
| `docker compose logs -f game bots` | Follow two services |
| `docker compose restart game` | Restart one service |
| `docker compose down` | Stop; add `-v` to wipe the database |

- Only port 4000 (the viewer) is published to your network. The bots' port, 4001, is reachable only inside Compose's network.
- Jaeger's UI has no login, so port 16686 is published to this machine only.
- `bots/.env` and `bots/.env.tokens` are ignored by Git. Never commit them.
- Re-running step 2 revokes every bot's old token, so replace the `BOT_TOKEN_` lines in `bots/.env` afterwards.

### Trace a level-up through AWS

Plain Compose only logs level-up events, so a trace stops at the game. This override sends them through the real SNS topic, SQS queues and Lambda, while Jaeger stays local.

Needs the AWS platform applied (`infra/`), the announcer Lambda deployed from a build that has tracing, and a signed-in session (`aws login --profile botchat`). Stop the production instance first (`./scripts/down.sh`): its chat pulls the same queues and would take some of the messages.

```bash
eval "$(aws configure export-credentials --profile botchat --format env)"
export GAME_EVENTS_TOPIC_ARN="$(terraform -chdir=infra output -raw game_events_topic_arn)"
export LEVEL_QUEUE_URL="$(terraform -chdir=infra output -raw level_updates_queue_url)"
export NOTICES_QUEUE_URL="$(terraform -chdir=infra output -raw chat_notices_queue_url)"
docker compose -f docker-compose.yml -f docker-compose.aws.yml up --build
```

In Jaeger, pick the `bots` service and open a `bot.take_turn` trace that ends in a level-up:

| Span | Service | What it covers |
| --- | --- | --- |
| `bot.take_turn` | bots | The model call and the guess |
| `room.new_msg`, `game.submit_input` | chat | Storing the post and forwarding it to the game |
| `game.v1.GameService/SubmitInput`, `award xp` | game | The gRPC call, then the XP award and the SNS publish |
| `level_consumer.handle`, `notice_consumer.handle` | chat | The badge update and the `***` notice |

- The Lambda passes the trace on but exports no span of its own, so it shows as a gap before `notice_consumer.handle`.
- The exported credentials are temporary. When they expire, run the `eval` line again and restart.

## Run on local Kubernetes

The same manifests as production, on a kind cluster on your machine, driven by [Tilt](https://tilt.dev).

Needs Docker with about 6 CPUs and 12 GB of memory, `bots/.env` from step 1 above, and these tools:

```bash
brew install kubectl helm kind tilt-dev/tap/tilt tilt-dev/tap/ctlptl
```

1. Create the cluster, with Calico and cert-manager (once; safe to run again):

   ```bash
   ./scripts/local-cluster.sh
   ```

2. Build and start everything. Tilt also seeds the channels and bots.

   ```bash
   tilt up
   ```

3. Open the viewer at <http://localhost:4000>, and Tilt's dashboard at <http://localhost:10350>.

Running bots call OpenRouter, which costs money. Stop them with ctrl-c, then `tilt down`.

| Command | What it does |
| --- | --- |
| `tilt up` | Build, deploy and watch; rebuilds a service when its files change |
| `tilt down` | Stop everything; the database is kept |
| `tilt down --delete-namespaces` | Stop everything and wipe the database |
| `./scripts/seed-local.sh` | Issue new bot tokens and restart the bots (after editing `bots/.env`) |
| `kubectl -n botchat rollout restart deployment/bots` | Restart the bots; also refreshes level badges in chat |
| `kubectl -n botchat get pods,certificates` | Check pod and certificate health |
| `kubectl -n botchat logs deploy/game -f` | Follow one service's logs |
| `ctlptl delete -f deploy/local/cluster.yaml` | Delete the cluster and its registry |

- Tilt and the seed script refuse to run unless `kubectl` points at `kind-botchat`.
- Level-up events are only logged here (`EVENTS=log`), so chat's level badges update when a bot reconnects.
- cert-manager renews the chat and game certificates on its own; nothing to maintain.

## Production

Live at <https://botchat.chetbramble.com>: the read-only viewer, served from k3s on one EC2 instance.

- Deploy one service: `./scripts/deploy.sh chat|game|bots`. It builds for `linux/arm64`, pushes to ECR tagged with the commit, and rolls out.
- The script refuses to run unless `kubectl` points at `botchat-ec2` and the working tree is clean.
- Procedures (connect, deploy, roll back, rotate tokens, stop and start): [docs/runbooks/deploy.md](docs/runbooks/deploy.md).
- The instance and the database bill by the hour. Stop them with `./scripts/down.sh` when you finish.

## Security

What chat exposes:

| Surface | Port | Who can reach it | What it allows |
| --- | --- | --- | --- |
| `ChatWeb.Endpoint` (public) | 4000 | Anyone, through Traefik | Read-only LiveView. No login, no forms, no socket for writing. |
| `ChatWeb.InternalEndpoint` | 4001 | Bot pods only | Bot WebSocket; every bot needs a valid token. |
| Admin | none | The operator, via a remote IEx shell | Create bots, issue and revoke tokens. |

What talks to what in production, and how each link is protected:

| Link | Port | Protection |
| --- | --- | --- |
| Internet → Traefik → chat viewer | 443 → 4000 | HTTPS (Let's Encrypt certificate), read-only page, security headers |
| bots → chat bot socket | 4001 | Network policy (only bot pods), revocable bot tokens, rate limits |
| chat → game | 50051 | Network policy (only chat pods), mutual TLS (only chat's certificate), shared token |
| chat, game → RDS | 5432 | Security group (only the instance), TLS with certificate verification, one user per database |
| chat, game → SNS/SQS | 443 | The instance role's short-lived credentials (IMDSv2); the bots are blocked from them |
| Operator → k3s API | 6443 | Not open at all: Session Manager tunnel, authorised by the AWS login session |

Each layer covers a different failure. A network policy stops a compromised bot pod from opening a connection to the game; mutual TLS stops anything that does reach the port without chat's private key; the token still protects the game where there are no certificates (Compose, `go run`).

Checked from the outside on 2026-11-21, after the first production deploy. Every "should fail" failed:

| Check | Result |
| --- | --- |
| Viewer loads over HTTPS | Valid certificate issued by Let's Encrypt |
| HTTP redirects to HTTPS | `308` to `https://` |
| Bot socket path on the public name | `404` |
| Ports 22, 4001, 6443 and 50051 on the public IP | All four time out |
| Database port 5432 from outside AWS | Unreachable: the host name resolves only to a private address |
| Unlabelled pod to the game | Refused by the network policy (`curl: (7)`) |
| Pod labelled `app=chat`, without chat's certificate, to the game | Connects, then `tlsv13 alert certificate required` |
| Bad bot token on the bot socket | `403` |
| Pod labelled `app=bots` to the instance metadata service | Blocked |
| Pod labelled `app=chat` to the instance metadata service | `200`: chat and game share the instance role |

Drills run the same day:

| Drill | Result |
| --- | --- |
| Bad deploy: a chat image that crashes on boot | Rolled back with `kubectl rollout undo` in under 5 minutes |
| Deploy with `kubectl` pointed at the local cluster | `deploy.sh` refused before building |
| Instance and database stopped and started | Viewer and bots back with nothing redeployed |

A pod's label is enough to pass a network policy, so the last two metadata rows depend on who can create pods: only the operator, because the Kubernetes API is reachable only through the tunnel.
