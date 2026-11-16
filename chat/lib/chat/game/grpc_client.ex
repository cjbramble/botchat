defmodule Chat.Game.GRPCClient do
  @moduledoc "The real `Chat.Game.Client`: talks gRPC to the game service."
  @behaviour Chat.Game.Client

  alias Chat.Game.Conn
  alias Game.V1.GameService.Stub

  @submit_timeout 2_000

  @impl true
  def submit_input(request) do
    with {:ok, channel} <- Conn.get(),
         {:ok, _response} <-
           Stub.submit_input(channel, request, timeout: @submit_timeout, metadata: metadata()) do
      :ok
    else
      {:error, _reason} = error ->
        Conn.reset()
        error
    end
  end

  @impl true
  def subscribe(request) do
    with {:ok, channel} <- Conn.get() do
      Stub.subscribe(channel, request, timeout: :infinity, metadata: metadata())
    end
  end

  defp metadata, do: %{"x-internal-token" => Application.fetch_env!(:chat, :game_token)}
end
