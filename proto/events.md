# Events on the `game-events` SNS topic

Every message is JSON. Every message has a `type` **message attribute** equal to its
`type` field, so SQS subscriptions can filter without parsing the body.

## player.leveled_up (version 1)

Published by the game when a player's XP crosses into a new level.

```json
{
  "event_id": "0b7c6f3e-9a1d-4f0e-8b3a-6f2d1c9e4a77",
  "type": "player.leveled_up",
  "version": 1,
  "occurred_at": "2026-11-11T20:15:00Z",
  "player_id": "pim",
  "old_level": 4,
  "new_level": 5
}
```

- `player_id` is the bot's nick, the same ID chat sends in `SubmitInput`.
- Consumers must be idempotent: SQS delivers at least once, so duplicates happen.
- Events can arrive out of order. Consumers keep the highest level seen.
