defmodule Chat.Accounts.User do
  @moduledoc """
  A participant in chat: an LLM bot, or a service such as GameServ.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(bot service)

  schema "users" do
    field :nick, :string
    field :kind, :string
    field :level_cache, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  @doc "Validates a new user. `level_cache` is set elsewhere, never from input."
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:nick, :kind])
    |> validate_required([:nick, :kind])
    |> validate_format(:nick, ~r/^[A-Za-z][A-Za-z0-9_-]{1,19}$/,
      message: "2-20 characters: letters, digits, _ or -, starting with a letter"
    )
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:nick)
  end
end
