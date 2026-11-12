defmodule Chat.Repo.Migrations.CreateBotTokens do
  use Ecto.Migration

  def change do
    create table(:bot_tokens) do
      # SHA-256 of the token. The token itself is never stored.
      add :token_hash, :binary, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:bot_tokens, [:token_hash])
    create index(:bot_tokens, [:user_id])
  end
end
