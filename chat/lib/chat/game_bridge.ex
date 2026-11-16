defmodule Chat.GameBridge do
  @moduledoc """
  Posts everything the game says in a room as GameServ. One process per room
  keeps a Subscribe stream open and reconnects when it ends.
  """
  use GenServer

  require Logger

  alias Chat.{Accounts, Rooms}
  alias Game.V1.{GameMessage, SubscribeRequest}

  @service_nick "GameServ"
  @min_backoff_ms 500
  @max_backoff_ms 30_000

  def start_link(room) when is_binary(room) do
    GenServer.start_link(__MODULE__, room, name: via(room))
  end

  defp via(room), do: {:via, Registry, {Chat.Registry, {:bridge, room}}}

  @impl true
  def init(room) do
    state = %{room: room, task: nil, backoff: @min_backoff_ms, last_seq: nil}
    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state), do: {:noreply, start_stream(state)}

  @impl true
  def handle_info({:game_message, %GameMessage{} = message}, state) do
    warn_on_gap(state, message)
    post(state.room, message.text)
    {:noreply, %{state | backoff: @min_backoff_ms, last_seq: message.seq}}
  end

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, reconnect_later(state, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    {:noreply, reconnect_later(state, reason)}
  end

  def handle_info(:reconnect, state), do: {:noreply, start_stream(state)}

  # Blocking on the stream in a task keeps this process free to post and to
  # notice when the stream dies.
  defp start_stream(state) do
    bridge = self()
    room = state.room
    task = Task.Supervisor.async_nolink(Chat.TaskSup, fn -> read_stream(room, bridge) end)
    %{state | task: task}
  end

  defp read_stream(room, bridge) do
    with {:ok, stream} <- Chat.Game.client().subscribe(%SubscribeRequest{channel: room}) do
      Enum.reduce_while(stream, :closed, fn
        {:ok, %GameMessage{} = message}, acc ->
          send(bridge, {:game_message, message})
          {:cont, acc}

        {:error, reason}, _acc ->
          {:halt, {:error, reason}}
      end)
    end
  end

  defp reconnect_later(state, reason) do
    Logger.warning(
      "game stream for ##{state.room} ended (#{inspect(reason)}), " <>
        "reconnecting in #{state.backoff} ms"
    )

    Process.send_after(self(), :reconnect, state.backoff)
    %{state | task: nil, backoff: min(state.backoff * 2, @max_backoff_ms)}
  end

  # Any break in the numbering counts: a jump is a dropped stream or a slow
  # subscriber, and a step back is a restarted game counting from 1 again.
  defp warn_on_gap(%{last_seq: last_seq, room: room}, %GameMessage{seq: seq})
       when is_integer(last_seq) and seq != last_seq + 1 do
    Logger.warning("game stream for ##{room} missed messages (seq #{last_seq} -> #{seq})")
  end

  defp warn_on_gap(_state, _message), do: :ok

  defp post(room, text) do
    with {:error, changeset} <-
           Rooms.post_message(room, Accounts.ensure_service!(@service_nick), text) do
      Logger.warning("game line for ##{room} not posted: #{inspect(changeset.errors)}")
    end
  end
end
