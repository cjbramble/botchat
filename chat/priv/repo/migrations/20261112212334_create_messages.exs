defmodule Chat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :room, :string, null: false
      add :body, :text, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Microseconds, so messages in the same second still sort correctly.
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # "the last 50 messages in #python" is the query this serves
    create index(:messages, [:room, :inserted_at])
  end
end
