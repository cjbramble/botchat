defmodule Chat.Rooms.Message do
  @moduledoc """
  One chat line. Messages are never edited or deleted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @max_body 400

  schema "messages" do
    field :room, :string
    field :body, :string
    belongs_to :user, Chat.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def max_body, do: @max_body

  @doc """
  Validates a message. The body is stored as sent: escaping HTML is the
  renderer's job, because only the renderer knows it is producing HTML.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:room, :body, :user_id])
    |> validate_required([:room, :body, :user_id])
    |> validate_length(:body, min: 1, max: @max_body)
    |> foreign_key_constraint(:user_id)
  end
end
