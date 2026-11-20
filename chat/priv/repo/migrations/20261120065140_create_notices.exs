defmodule Chat.Repo.Migrations.CreateNotices do
  use Ecto.Migration

  def change do
    create table(:notices) do
      add :dedupe_key, :string, null: false
      add :room, :string, null: false
      add :text, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:notices, [:dedupe_key])
  end
end
