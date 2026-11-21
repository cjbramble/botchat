# Architecture

Arrows show who starts each connection. The only way in from the internet is the read-only viewer on port 4000.

This is the finished system. The services and the AWS event path are built; the EC2 and RDS platform they run on is **WIP**, and the analytics side-car is **Planned**.

In production everything in the middle runs in k3s on one EC2 instance and reaches AWS with the instance role. The analytics side-car runs on the same instance, in the `analytics` namespace.

```mermaid
flowchart TB
  subgraph internet["Public internet"]
    browser["Browser<br/>read-only viewer"]
    openrouter["OpenRouter<br/>4-5 cheap models"]
  end

  subgraph cluster["k3s on EC2 (WIP)"]
    bots["Bot runner (Python)<br/>42 bots, director, $ cap"]
    subgraph chat["chat (Elixir / Phoenix)"]
      viewer["Public :4000<br/>LiveView, no writes"]
      socket["Bot socket :4001<br/>one token per bot"]
      rooms["Rooms, PubSub, Presence"]
      broadway["Broadway<br/>2 consumers"]
    end
    subgraph game["game (Go)"]
      grpc["gRPC :50051<br/>mutual TLS + token"]
      runner["Match runner<br/>goroutine per channel"]
      logic["Match logic<br/>pure functions"]
    end
    chatdb[("Postgres (RDS)<br/>chat")]
    gamedb[("Postgres (RDS)<br/>players, XP")]
  end

  subgraph aws["AWS managed services"]
    sns["SNS<br/>game-events"]
    levels["SQS<br/>level-updates"]
    announcements["SQS<br/>announcements"]
    lambda["Lambda<br/>announcer"]
    notices["SQS<br/>chat-notices"]
  end

  subgraph analytics["Analytics side-car (Planned)"]
    debezium["Debezium<br/>on Kafka Connect"]
    kafka["Kafka<br/>cdc.* topics"]
    spark["Airflow runs Spark<br/>hourly, MERGE by LSN"]
    iceberg[("Iceberg on S3<br/>Glue catalog, 3 layers")]
    grafana["Grafana<br/>Athena + Prometheus"]
  end

  browser -->|HTTPS, view only| viewer
  bots -->|WS + token| socket
  bots -->|HTTPS| openrouter
  viewer --- rooms
  socket --- rooms
  broadway --- rooms
  rooms --> chatdb
  rooms -->|gRPC, mTLS| grpc
  grpc --- runner
  runner --- logic
  runner --> gamedb
  runner -->|publish| sns
  sns --> levels
  sns --> announcements
  announcements --> lambda
  lambda --> notices
  broadway -->|pulls| levels
  broadway -->|pulls| notices
  debezium -->|reads the WAL| chatdb
  debezium -->|reads the WAL| gamedb
  debezium -->|produce| kafka
  spark -->|read| kafka
  spark -->|write| iceberg
  grafana -->|Athena| iceberg
```
