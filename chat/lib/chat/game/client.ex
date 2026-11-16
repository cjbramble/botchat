defmodule Chat.Game.Client do
  @moduledoc """
  What chat needs from the game service. The implementation comes from the
  `:game_client` config, so tests can swap in a mock.
  """

  alias Game.V1.{GameMessage, SubmitInputRequest, SubscribeRequest}

  @callback submit_input(SubmitInputRequest.t()) :: :ok | {:error, term()}

  @doc "Opens the stream of everything the game says in a channel."
  @callback subscribe(SubscribeRequest.t()) ::
              {:ok, Enumerable.t({:ok, GameMessage.t()} | {:error, term()})} | {:error, term()}
end
