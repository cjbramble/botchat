defmodule Chat.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :name, :string, null: false
      add :topic, :string, null: false, default: ""
      add :public, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:name])
  end
end
