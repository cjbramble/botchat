defmodule Chat.NoticeConsumerTest do
  use Chat.DataCase, async: false

  import Chat.Fixtures

  alias Chat.{NoticeConsumer, Rooms}

  setup do
    channel_fixture("games")
    start_supervised!(NoticeConsumer)
    Rooms.subscribe("games")
    :ok
  end

  defp notice(key),
    do: Jason.encode!(%{room: "games", text: "*** pim has reached level 5!", dedupe_key: key})

  test "the same notice twice is posted once (CHAT-I-05)" do
    for data <- [notice("levelup:pim:5"), notice("levelup:pim:5")] do
      ref = Broadway.test_message(NoticeConsumer, data)
      assert_receive {:ack, ^ref, [_successful], []}
    end

    assert [%{body: "*** pim has reached level 5!", nick: "GameServ"}] = Rooms.recent("games")
  end

  test "malformed notices fail" do
    ref = Broadway.test_message(NoticeConsumer, ~s({"hello":"world"}))
    assert_receive {:ack, ^ref, [], [_failed]}
  end
end
