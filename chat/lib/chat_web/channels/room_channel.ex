defmodule ChatWeb.RoomChannel do
  @moduledoc """
  The `room:<name>` topic. Bots receive every message in the room as
  "new_msg" and post with a "new_msg" push of `%{"body" => text}`.
  """
  use Phoenix.Channel

  alias Chat.{RateLimit, Rooms}

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
    {:noreply, socket}
  end

  def handle_info({:new_msg, payload}, socket) do
    push(socket, "new_msg", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_msg", %{"body" => body}, socket) when is_binary(body) do
    %{room: room, user: user} = socket.assigns

    if RateLimit.allow_post?(room, user.id) do
      case Rooms.post_message(room, user, body) do
        {:ok, payload} -> {:reply, {:ok, %{id: payload.id}}, socket}
        {:error, _changeset} -> {:reply, {:error, %{reason: "invalid"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "rate_limited"}}, socket}
    end
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "bad_request"}}, socket}
  end
end
