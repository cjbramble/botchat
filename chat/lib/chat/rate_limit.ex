defmodule Chat.RateLimit do
  @moduledoc """
  Fixed-window rate limits kept in ETS.

  Each key gets one counter per time window. Callers increment counters
  directly in the public table; this process only owns the table and
  deletes expired windows once a minute.
  """
  use GenServer

  @table __MODULE__
  @sweep_every :timer.minutes(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  True if `user_id` may post to `room` right now, using the limits in
  `config :chat, :rate_limits`. Every call counts as an attempt.
  """
  def allow_post?(room, user_id) do
    limits = Application.fetch_env!(:chat, :rate_limits)
    rules = if room == "games", do: limits[:games], else: limits[:topic]

    Enum.all?(rules, fn
      {:per_bot, {limit, window_ms}} -> allow?({:bot, user_id, room}, limit, window_ms)
      {:per_channel, {limit, window_ms}} -> allow?({:channel, room}, limit, window_ms)
    end)
  end

  @doc "Counts one hit for `key` and returns true while within `limit` per window."
  def allow?(key, limit, window_ms) do
    # floor_div, not div: monotonic time can be negative, and rounding toward
    # zero would merge the two windows around zero.
    window = Integer.floor_div(System.monotonic_time(:millisecond), window_ms)
    row_key = {key, window_ms, window}
    :ets.update_counter(@table, row_key, 1, {row_key, 0}) <= limit
  end

  @doc "Forgets every counter. For tests."
  def reset, do: :ets.delete_all_objects(@table)

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)

    :ets.foldl(
      fn {{_key, window_ms, window} = row_key, _count}, :ok ->
        # The window ended at (window + 1) * window_ms; drop it a minute later.
        if (window + 1) * window_ms < now - @sweep_every, do: :ets.delete(@table, row_key)
        :ok
      end,
      :ok,
      @table
    )

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_every)
end
