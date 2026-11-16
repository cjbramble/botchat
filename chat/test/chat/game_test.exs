defmodule Chat.GameTest do
  # Not async: the mock is global because forwarding runs in other processes.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Chat.Accounts.User
  alias Chat.Game.MockClient
  alias Game.V1.SubmitInputRequest

  setup :set_mox_global
  setup :verify_on_exit!

  @bot %User{nick: "alice", kind: "bot"}
  @payload %{id: 42, room: "games", body: "!start"}

  defp rpc_error(status), do: GRPC.RPCError.exception(status: status)

  defp expect_submits(times, result) do
    test = self()

    expect(MockClient, :submit_input, times, fn request ->
      send(test, {:submitted, request})
      result
    end)
  end

  # Forwarding is asynchronous, so wait for it before the mock is verified.
  defp await_forwarding do
    for pid <- Task.Supervisor.children(Chat.TaskSup) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  test "a bot's #games message is forwarded once with its msg_id (CHAT-I-01)" do
    expect_submits(1, :ok)

    assert :ok = Chat.Game.forward(@payload, @bot)
    await_forwarding()

    assert_received {:submitted,
                     %SubmitInputRequest{
                       channel: "games",
                       player_id: "alice",
                       text: "!start",
                       msg_id: "42"
                     }}

    refute_received {:submitted, _request}
  end

  test "other rooms and non-bots are not forwarded (CHAT-I-02)" do
    assert :ok = Chat.Game.forward(%{@payload | room: "python"}, @bot)
    assert :ok = Chat.Game.forward(@payload, %User{nick: "GameServ", kind: "service"})
    await_forwarding()
    # verify_on_exit! fails the test if the mock was called.
  end

  test "a failing game doesn't crash the caller and is tried 4 times" do
    expect_submits(4, {:error, :econnrefused})

    log =
      capture_log(fn ->
        assert :ok = Chat.Game.forward(@payload, @bot)
        await_forwarding()
      end)

    assert log =~ "game input 42 dropped"
  end

  test "UNAVAILABLE is retried with the same msg_id (CHAT-I-06)" do
    test = self()

    MockClient
    |> expect(:submit_input, fn request ->
      send(test, {:submitted, request})
      {:error, rpc_error(:unavailable)}
    end)
    |> expect(:submit_input, fn request ->
      send(test, {:submitted, request})
      :ok
    end)

    assert :ok = Chat.Game.forward(@payload, @bot)
    await_forwarding()

    assert_received {:submitted, %SubmitInputRequest{msg_id: "42"}}
    assert_received {:submitted, %SubmitInputRequest{msg_id: "42"}}
  end

  test "DEADLINE_EXCEEDED is retried" do
    MockClient
    |> expect(:submit_input, fn _request -> {:error, rpc_error(:deadline_exceeded)} end)
    |> expect(:submit_input, fn _request -> :ok end)

    assert :ok = Chat.Game.forward(@payload, @bot)
    await_forwarding()
  end

  test "INVALID_ARGUMENT is not retried (CHAT-I-07)" do
    expect_submits(1, {:error, rpc_error(:invalid_argument)})

    log =
      capture_log(fn ->
        assert :ok = Chat.Game.forward(@payload, @bot)
        await_forwarding()
      end)

    assert log =~ "game input 42 dropped"
  end
end
