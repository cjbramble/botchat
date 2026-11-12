defmodule Chat.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :nick, :string, null: false
      # "bot" for LLM bots, "service" for GameServ and the announcer
      add :kind, :string, null: false
      # The player's level, copied from the game service.
      add :level_cache, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:nick])
  end
end
