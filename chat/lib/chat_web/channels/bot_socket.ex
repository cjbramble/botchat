defmodule ChatWeb.BotSocket do
  @moduledoc """
  One WebSocket per bot. Connect with `?token=...&vsn=2.0.0`.
  """
  use Phoenix.Socket

  alias Chat.Accounts
  alias Chat.Accounts.User

  channel "room:*", ChatWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Accounts.verify_bot_token(token) do
      {:ok, user} -> {:ok, assign(socket, :user, user)}
      :error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  # Naming each socket lets a revoked bot be disconnected instantly.
  @impl true
  def id(socket), do: "bot_socket:#{socket.assigns.user.id}"

  @doc "Closes every open socket of a bot, e.g. right after revoking its tokens."
  def disconnect(%User{id: id}) do
    ChatWeb.InternalEndpoint.broadcast("bot_socket:#{id}", "disconnect", %{})
  end
end
