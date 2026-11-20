import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :chat, Chat.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5434,
  database: "chat_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :chat, ChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BIjr8eZi5xndOV30K60Re8QgJXByanqToarjY0kO3s1DcW0FO5LnVcQzm21FmtW9",
  server: false

config :chat, ChatWeb.InternalEndpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "test-only-secret-test-only-secret-test-only-secret-test-only!!",
  server: false

# Shorter #games window so tests don't have to sleep for 2 s.
config :chat, :rate_limits,
  topic: [per_bot: {1, 30_000}, per_channel: {1, 5_000}],
  games: [per_bot: {1, 200}]

# The game is mocked, nothing subscribes on boot, and retries don't sleep.
config :chat,
  game_client: Chat.Game.MockClient,
  start_game_bridge: false,
  game_retry_delays_ms: [0, 0, 0]

# Tests start the queue pipelines themselves with start_supervised!/1 and feed
# them with Broadway.test_message/3.
config :chat,
  level_producer: {Broadway.DummyProducer, []},
  notice_producer: {Broadway.DummyProducer, []},
  start_queue_consumers: false

# Socket tests connect bots without asking the (mock) game for levels.
config :chat, refresh_levels: false

# In test we don't send emails
config :chat, Chat.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
