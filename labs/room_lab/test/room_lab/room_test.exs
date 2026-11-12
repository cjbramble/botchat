defmodule RoomLab.RoomTest do
  use ExUnit.Case, async: true

  alias RoomLab.Room

  setup do
    name = "room-#{System.unique_integer([:positive])}"
    {:ok, _pid} = Room.start(name)
    %{room: name}
  end

  test "history returns messages in the order they were said", %{room: room} do
    :ok = Room.join(room, "ada")
    :ok = Room.join(room, "bob")

    :ok = Room.say(room, "ada", "first")
    :ok = Room.say(room, "bob", "second")
    :ok = Room.say(room, "ada", "third")

    assert Room.history(room) == [{"ada", "first"}, {"bob", "second"}, {"ada", "third"}]
  end

  test "say is rejected for users who have not joined", %{room: room} do
    assert Room.say(room, "stranger", "hi") == {:error, :not_joined}
    assert Room.history(room) == []
  end

  test "only the last 100 messages are kept", %{room: room} do
    :ok = Room.join(room, "ada")

    for i <- 1..150, do: :ok = Room.say(room, "ada", "msg #{i}")

    history = Room.history(room)
    assert length(history) == 100
    assert hd(history) == {"ada", "msg 51"}
    assert List.last(history) == {"ada", "msg 150"}
  end

  test "1,000 concurrent says leave 100 messages and a live process", %{room: room} do
    :ok = Room.join(room, "ada")

    results =
      1..1_000
      |> Enum.map(fn i -> Task.async(fn -> Room.say(room, "ada", "msg #{i}") end) end)
      |> Task.await_many()

    assert Enum.all?(results, &(&1 == :ok))
    assert length(Room.history(room)) == 100
    assert room |> Room.via() |> GenServer.whereis() |> Process.alive?()
  end
end
