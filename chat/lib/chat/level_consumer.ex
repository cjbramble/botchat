defmodule Chat.LevelConsumer do
  @moduledoc """
  Reads player.leveled_up events from the level-updates SQS queue and
  updates level badges. Started only when `:level_producer` is configured.
  """
  use Broadway
  require Logger

  alias Broadway.Message

  def start_link(_opts) do
    {module, opts} = Application.fetch_env!(:chat, :level_producer)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: {module, opts}, concurrency: 1],
      processors: [default: [concurrency: 2]]
    )
  end

  @impl true
  def handle_message(_processor, %Message{data: data} = message, _context) do
    Chat.Tracing.with_message_span("level_consumer.handle", message, fn ->
      case apply_event(data) do
        :ok -> message
        {:error, reason} -> Message.failed(message, reason)
      end
    end)
  end

  @doc """
  Applies one raw event. Unknown event types are accepted and ignored, so a
  new event on the topic can't jam this queue. Malformed events return
  `{:error, reason}` so SQS retries and then dead-letters them.
  """
  def apply_event(data) do
    case Jason.decode(data) do
      {:ok,
       %{
         "type" => "player.leveled_up",
         "version" => 1,
         "player_id" => nick,
         "new_level" => level
       }}
      when is_binary(nick) and is_integer(level) ->
        Chat.Accounts.bump_level_cache(nick, level)
        :ok

      {:ok, %{"type" => "player.leveled_up", "version" => 1}} ->
        {:error, :malformed}

      {:ok, %{"type" => type, "version" => version}} ->
        Logger.warning("ignoring event #{inspect(type)} v#{inspect(version)}")
        :ok

      {:ok, _other} ->
        {:error, :malformed}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
