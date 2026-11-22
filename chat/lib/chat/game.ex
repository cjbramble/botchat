defmodule Chat.Game do
  @moduledoc """
  Chat's side of the game service: forwards what bots say in #games to it and
  seeds level badges from it.
  """
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Chat.Accounts
  alias Chat.Accounts.User
  alias Game.V1.SubmitInputRequest

  @room "games"
  @default_retry_delays_ms [200, 1_000, 3_000]
  @retryable_statuses [GRPC.Status.unavailable(), GRPC.Status.deadline_exceeded()]

  @doc "The `Chat.Game.Client` implementation in use."
  def client, do: Application.get_env(:chat, :game_client, Chat.Game.GRPCClient)

  @doc """
  Sends a posted message to the game if a bot said it in #games. Runs in the
  background and always returns `:ok`: a game outage must not fail the post.
  """
  def forward(%{room: @room} = payload, %User{kind: "bot"} = user) do
    request = %SubmitInputRequest{
      channel: @room,
      player_id: user.nick,
      text: payload.body,
      msg_id: to_string(payload.id)
    }

    delays = Application.get_env(:chat, :game_retry_delays_ms, @default_retry_delays_ms)
    # The task is another process, so the caller's trace has to be handed to it.
    ctx = :otel_ctx.get_current()

    forward = fn ->
      :otel_ctx.attach(ctx)
      Tracer.with_span("game.submit_input", do: submit(request, delays))
    end

    case Task.Supervisor.start_child(Chat.TaskSup, forward) do
      {:ok, _pid} ->
        :ok

      other ->
        Logger.warning("game input #{request.msg_id} not forwarded: #{inspect(other)}")
        :ok
    end
  end

  def forward(_payload, _user), do: :ok

  @doc """
  Asks the game for a bot's level in the background and raises the cached
  badge if needed. Always returns `:ok`: the badge is a cache, so an
  unavailable game is skipped and the next level-up event corrects it.
  """
  def refresh_level(%User{kind: "bot", nick: nick}) do
    if Application.get_env(:chat, :refresh_levels, true) do
      case Task.Supervisor.start_child(Chat.TaskSup, fn -> fetch_level(nick) end) do
        {:ok, _pid} -> :ok
        other -> Logger.warning("level refresh for #{nick} not started: #{inspect(other)}")
      end
    end

    :ok
  end

  defp fetch_level(nick) do
    case client().get_player(nick) do
      {:ok, %{level: level}} -> Accounts.bump_level_cache(nick, level)
      {:error, reason} -> Logger.info("GetPlayer for #{nick} skipped: #{inspect(reason)}")
    end
  end

  defp submit(request, delays) do
    with {:error, reason} <- client().submit_input(request) do
      case {retryable?(reason), delays} do
        {true, [delay | rest]} ->
          Process.sleep(delay)
          submit(request, rest)

        _ ->
          Logger.warning("game input #{request.msg_id} dropped: #{inspect(reason)}")
      end
    end
  end

  # Retrying is safe because the msg_id stays the same. Other RPC errors mean
  # the game answered and refused, so asking again would not help.
  defp retryable?(%GRPC.RPCError{status: status}), do: status in @retryable_statuses
  defp retryable?(_reason), do: true
end
