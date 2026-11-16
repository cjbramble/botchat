defmodule Chat.RoomsTest do
  use Chat.DataCase, async: true

  import Chat.Fixtures

  alias Chat.Rooms
  alias Chat.Rooms.Message

  setup do
    channel_fixture("python")
    %{bot: bot_fixture()}
  end

  test "list_public_channels/0 and get_channel/1 read channels" do
    channel_fixture("elixir")

    hidden =
      %Rooms.Channel{}
      |> Rooms.Channel.changeset(%{name: "hidden", public: false})
      |> Repo.insert!()

    assert Enum.map(Rooms.list_public_channels(), & &1.name) == ["elixir", "python"]
    assert Rooms.get_channel("hidden").id == hidden.id
    assert Rooms.get_channel("nope") == nil
  end

  test "post_message/3 stores and broadcasts one payload", %{bot: bot} do
    Rooms.subscribe("python")

    assert {:ok, payload} = Rooms.post_message("python", bot, "hello")
    assert payload.nick == bot.nick
    assert payload.body == "hello"
    assert %{room: "python", kind: "bot", level: 1, id: _, at: %DateTime{}} = payload
    assert_receive {:new_msg, ^payload}
  end

  test "post_message/3 announces activity in the room, but not for rejected messages", %{bot: bot} do
    Rooms.subscribe_activity()

    assert {:ok, _payload} = Rooms.post_message("python", bot, "hello")
    assert_receive {:activity, "python"}

    assert {:error, _} = Rooms.post_message("python", bot, "")
    refute_receive {:activity, _room}, 50
  end

  test "bodies must be 1 to 400 characters", %{bot: bot} do
    assert {:error, _} = Rooms.post_message("python", bot, "")
    assert {:error, _} = Rooms.post_message("python", bot, "   ")
    assert {:error, _} = Rooms.post_message("python", bot, String.duplicate("a", 401))
    assert {:ok, _} = Rooms.post_message("python", bot, String.duplicate("a", 400))
  end

  test "Message.changeset/2 accepts 1 to 400 characters (CHAT-U-05)" do
    valid? = fn length ->
      attrs = %{room: "python", body: String.duplicate("a", length), user_id: 1}
      Message.changeset(%Message{}, attrs).valid?
    end

    refute valid?.(0)
    assert valid?.(1)
    assert valid?.(400)
    refute valid?.(401)
  end

  test "payload/1 has id, nick, kind, level, body and at (CHAT-U-06)", %{bot: bot} do
    at = ~U[2026-11-12 10:00:00.000000Z]
    message = %Message{id: 7, room: "python", body: "hi", user: bot, inserted_at: at}

    assert Rooms.payload(message) == %{
             id: 7,
             room: "python",
             nick: bot.nick,
             kind: "bot",
             level: 1,
             body: "hi",
             at: at
           }
  end

  test "HTML is stored unchanged: escaping is the viewer's job", %{bot: bot} do
    body = "<script>alert(1)</script>"
    Rooms.subscribe("python")

    assert {:ok, %{body: ^body}} = Rooms.post_message("python", bot, body)
    assert_receive {:new_msg, %{body: ^body}}
    assert [%{body: ^body}] = Rooms.recent("python")
  end

  test "recent/2 returns the newest messages, oldest first", %{bot: bot} do
    for i <- 1..5, do: {:ok, _} = Rooms.post_message("python", bot, "msg #{i}")

    assert Enum.map(Rooms.recent("python", 3), & &1.body) == ["msg 3", "msg 4", "msg 5"]
  end
end
