defmodule Chat.Accounts.BotToken do
  @moduledoc """
  The SHA-256 hash of one bot's token. Deleting the row revokes the token.
  """
  use Ecto.Schema

  schema "bot_tokens" do
    # redact: true keeps the hash out of logs and inspect/1 output
    field :token_hash, :binary, redact: true
    belongs_to :user, Chat.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
