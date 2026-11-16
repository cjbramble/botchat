defmodule Chat.GameBridgeTest do
  # Not async: the mock is global because the bridge reads in its own task.
  use Chat.DataCase, async: false

  import Chat.Fixtures
  import ExUnit.CaptureLog
  import Mox

  alias Chat.Game.MockClient
  alias Chat.{GameBridge, Rooms}
  alias Game.V1.{GameMessage, SubscribeRequest}

  setup :set_mox_global

  setup do
    channel_fixture("games")
    :ok
  end

  defp line(text, seq), do: {:ok, %GameMessage{channel: "games", text: text, seq: seq}}

  # Each Subscribe call takes the next result; once they run out the game
  # looks down, so a reconnect timer firing late in a test changes nothing.
  defp stub_subscribe(results) do
    test = self()
    {:ok, queue} = Agent.start_link(fn -> results end)

    stub(MockClient, :subscribe, fn %SubscribeRequest{channel: "games"} ->
      send(test, {:subscribed, self()})

      Agent.get_and_update(queue, fn
        [result | rest] -> {result, rest}
        [] -> {{:error, :down}, []}
      end)
    end)
  end

  # Returns once the bridge has seen the end of its current Subscribe stream.
  defp await_stream_end(bridge) do
    assert_receive {:subscribed, task}
    ref = Process.monitor(task)
    assert_receive {:DOWN, ^ref, :process, ^task, _reason}
    # The task's result reached the bridge before this call did.
    :sys.get_state(bridge)
  end

  test "lines are posted as GameServ, in order" do
    stub_subscribe([{:ok, [line("Guess a number", 1), line("alice: too low", 2)]}])
    Rooms.subscribe("games")

    capture_log(fn ->
      bridge = start_supervised!({GameBridge, "games"})
      await_stream_end(bridge)
    end)

    assert_receive {:new_msg, %{nick: "GameServ", kind: "service", body: "Guess a number"}}
    assert_receive {:new_msg, %{nick: "GameServ", kind: "service", body: "alice: too low"}}
    assert ["Guess a number", "alice: too low"] = Enum.map(Rooms.recent("games"), & &1.body)
  end

  test "a gap in seq is logged and the line is still posted" do
    stub_subscribe([{:ok, [line("one", 1), line("four", 4)]}])

    log =
      capture_log(fn ->
        bridge = start_supervised!({GameBridge, "games"})
        await_stream_end(bridge)
      end)

    assert log =~ "missed messages (seq 1 -> 4)"
    assert ["one", "four"] = Enum.map(Rooms.recent("games"), & &1.body)
  end

  test "a restarted game counting from 1 again is logged as missed messages" do
    stub_subscribe([{:ok, [line("before", 5)]}, {:ok, [line("after", 1)]}])

    log =
      capture_log(fn ->
        bridge = start_supervised!({GameBridge, "games"})
        await_stream_end(bridge)

        send(bridge, :reconnect)
        await_stream_end(bridge)
      end)

    assert log =~ "missed messages (seq 5 -> 1)"
    assert ["before", "after"] = Enum.map(Rooms.recent("games"), & &1.body)
  end

  test "an ended stream reconnects, doubling the backoff until a message arrives" do
    stub_subscribe([
      {:ok, []},
      {:ok, [{:error, GRPC.RPCError.exception(status: :unavailable)}]},
      {:ok, [line("back", 7)]}
    ])

    capture_log(fn ->
      bridge = start_supervised!({GameBridge, "games"})

      # Waited 500 ms, the next wait is doubled.
      assert %{backoff: 1_000} = await_stream_end(bridge)

      send(bridge, :reconnect)
      assert %{backoff: 2_000} = await_stream_end(bridge)

      # The message resets the backoff to 500 ms before the stream ends again.
      send(bridge, :reconnect)
      assert %{backoff: 1_000} = await_stream_end(bridge)
    end)

    assert ["back"] = Enum.map(Rooms.recent("games"), & &1.body)
  end

  test "a failed subscribe is retried" do
    stub_subscribe([{:error, :econnrefused}, {:ok, [line("hello", 1)]}])

    log =
      capture_log(fn ->
        bridge = start_supervised!({GameBridge, "games"})
        assert %{backoff: 1_000} = await_stream_end(bridge)

        send(bridge, :reconnect)
        await_stream_end(bridge)
      end)

    assert log =~ "ended ({:error, :econnrefused}), reconnecting in 500 ms"
    assert ["hello"] = Enum.map(Rooms.recent("games"), & &1.body)
  end

  test "the cap on the backoff is 30 s" do
    stub_subscribe([])

    capture_log(fn ->
      bridge = start_supervised!({GameBridge, "games"})
      await_stream_end(bridge)

      for _ <- 1..7 do
        send(bridge, :reconnect)
        await_stream_end(bridge)
      end

      assert %{backoff: 30_000} = :sys.get_state(bridge)
    end)
  end
end
