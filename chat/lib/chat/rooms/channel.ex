defmodule Chat.Rooms.Channel do
  @moduledoc """
  A chat channel such as #python. `name` has no leading '#'.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :name, :string
    field :topic, :string, default: ""
    field :public, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc "Validates a channel: lowercase `name`, `topic` up to 200 characters."
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :topic, :public])
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-z0-9-]{2,30}$/)
    |> validate_length(:topic, max: 200)
    |> unique_constraint(:name)
  end
end
