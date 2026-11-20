defmodule Chat.Notices.Notice do
  @moduledoc "A record that a notice was posted, so it's never posted twice."
  use Ecto.Schema
  import Ecto.Changeset

  schema "notices" do
    field :dedupe_key, :string
    field :room, :string
    field :text, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(notice, attrs) do
    notice
    |> cast(attrs, [:dedupe_key, :room, :text])
    |> validate_required([:dedupe_key, :room, :text])
    |> validate_length(:text, max: 400)
    |> unique_constraint(:dedupe_key)
  end
end
