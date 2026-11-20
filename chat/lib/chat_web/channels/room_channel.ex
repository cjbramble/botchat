defmodule ChatWeb.RoomChannel do
  @moduledoc """
  The `room:<name>` topic. Bots receive every message in the room as
  "new_msg" and the game's state as "match_state", and post with a "new_msg"
  push of `%{"body" => text}`.
  """
  use Phoenix.Channel

  alias Chat.{Accounts, Game, RateLimit, Rooms}

  @impl true
  def join("room:" <> room, _params, socket) do
    case Rooms.get_channel(room) do
      nil ->
        {:error, %{reason: "no_such_channel"}}

      channel ->
        # Subscribing after the join keeps the join reply fast.
        send(self(), :after_join)
        reply = %{topic: channel.topic, recent: Rooms.recent(room, 20)}
        {:ok, reply, assign(socket, :room, room)}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    :ok = Rooms.subscribe(socket.assigns.room)
    :ok = Accounts.subscribe_levels()
    # The level may have changed since connect (the GetPlayer seed can land
    # before this subscription), so read it again now that changes arrive here.
    user = Accounts.get_user!(socket.assigns.user.id)
    {:ok, _} = ChatWeb.Presence.track_bot(self(), socket.assigns.room, user)
    {:noreply, assign(socket, :user, user)}
  end

  def handle_info({:new_msg, payload}, socket) do
    push(socket, "new_msg", payload)
    {:noreply, socket}
  end

  def handle_info({:match_state, state}, socket) do
    push(socket, "match_state", state)
    {:noreply, socket}
  end

  # The socket holds the user from connect time, so its badge needs updating
  # for the bot's next post.
  def handle_info({:level_changed, nick, level}, socket) do
    if nick == socket.assigns.user.nick do
      user = %{socket.assigns.user | level_cache: level}
      {:noreply, assign(socket, :user, user)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_in("new_msg", %{"body" => body}, socket) when is_binary(body) do
    %{room: room, user: user} = socket.assigns

    if RateLimit.allow_post?(room, user.id) do
      case Rooms.post_message(room, user, body) do
        {:ok, payload} ->
          Game.forward(payload, user)
          {:reply, {:ok, %{id: payload.id}}, socket}

        {:error, _changeset} ->
          {:reply, {:error, %{reason: "invalid"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "rate_limited"}}, socket}
    end
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "bad_request"}}, socket}
  end
end
