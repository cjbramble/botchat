defmodule Chat.Rooms do
  @moduledoc """
  Channels and their messages. `post_message/3` is the only way a message
  gets written, so every source of messages behaves the same.
  """
  import Ecto.Query, warn: false

  alias Chat.Accounts.User
  alias Chat.Repo
  alias Chat.Rooms.{Channel, Message}
  alias Phoenix.PubSub

  @pubsub Chat.PubSub
  @activity_topic "activity"

  ## Channels

  def list_public_channels do
    Repo.all(from c in Channel, where: c.public, order_by: c.name)
  end

  def get_channel(name) when is_binary(name), do: Repo.get_by(Channel, name: name)

  ## Messages

  @doc "Subscribes the calling process to everything broadcast for a room."
  def subscribe(room), do: PubSub.subscribe(@pubsub, pubsub_topic(room))

  @doc "Unsubscribes the calling process from a room."
  def unsubscribe(room), do: PubSub.unsubscribe(@pubsub, pubsub_topic(room))

  @doc """
  Subscribes the calling process to `{:activity, room}`, sent once for every
  message in any room. It says where something happened without carrying the
  message, so a listener can follow all rooms cheaply.
  """
  def subscribe_activity, do: PubSub.subscribe(@pubsub, @activity_topic)

  @doc "Sends any message to a room's subscribers, e.g. `{:match_state, map}`."
  def broadcast(room, message), do: PubSub.broadcast(@pubsub, pubsub_topic(room), message)

  @doc """
  Validates, stores and broadcasts a message. Returns `{:ok, payload}` or
  `{:error, changeset}`.
  """
  def post_message(room, %User{} = user, body) do
    changeset = Message.changeset(%Message{}, %{room: room, body: body, user_id: user.id})

    with {:ok, message} <- Repo.insert(changeset) do
      payload = payload(%{message | user: user})
      broadcast(room, {:new_msg, payload})
      PubSub.broadcast(@pubsub, @activity_topic, {:activity, room})
      {:ok, payload}
    end
  end

  @doc "The last `limit` messages of a room as payloads, oldest first."
  def recent(room, limit \\ 50) do
    from(m in Message,
      where: m.room == ^room,
      order_by: [desc: m.inserted_at, desc: m.id],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(&payload/1)
  end

  @doc "The one shape a message has outside this module."
  def payload(%Message{user: %User{} = user} = message) do
    %{
      id: message.id,
      room: message.room,
      nick: user.nick,
      kind: user.kind,
      level: user.level_cache,
      body: message.body,
      at: message.inserted_at
    }
  end

  defp pubsub_topic(room), do: "messages:" <> room
end
