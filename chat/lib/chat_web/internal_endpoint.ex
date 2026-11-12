defmodule ChatWeb.InternalEndpoint do
  @moduledoc """
  The private endpoint bots connect to. It must only be reachable on the
  private network. It serves a WebSocket and a health check.
  """
  use Phoenix.Endpoint, otp_app: :chat

  socket "/socket", ChatWeb.BotSocket,
    # Bots aren't browsers, so there's no Origin to check; the token is the auth.
    websocket: [check_origin: false],
    longpoll: false

  plug ChatWeb.InternalRouter
end
