defmodule ChatWeb.Presence do
  @moduledoc """
  Who is in each room. Bots are tracked by their channel process, so they
  disappear automatically when they disconnect.
  """
  use Phoenix.Presence,
    otp_app: :chat,
    pubsub_server: Chat.PubSub

  def topic(room), do: "presence:" <> room

  def track_bot(pid, room, user) do
    track(pid, topic(room), user.nick, %{level: user.level_cache})
  end

  @doc "Subscribes to presence_diff broadcasts for a room."
  def subscribe(room), do: Phoenix.PubSub.subscribe(Chat.PubSub, topic(room))

  def unsubscribe(room), do: Phoenix.PubSub.unsubscribe(Chat.PubSub, topic(room))

  def nicks(room), do: room |> topic() |> list() |> Map.keys() |> Enum.sort()
end
