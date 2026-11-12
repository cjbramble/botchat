defmodule Chat.RoomsTest do
  use Chat.DataCase, async: true

  import Chat.Fixtures

  alias Chat.Rooms

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

  test "bodies must be 1 to 400 characters", %{bot: bot} do
    assert {:error, _} = Rooms.post_message("python", bot, "")
    assert {:error, _} = Rooms.post_message("python", bot, "   ")
    assert {:error, _} = Rooms.post_message("python", bot, String.duplicate("a", 401))
    assert {:ok, _} = Rooms.post_message("python", bot, String.duplicate("a", 400))
  end

  test "HTML is stored unchanged: escaping is the viewer's job", %{bot: bot} do
    assert {:ok, %{body: "<script>alert(1)</script>"}} =
             Rooms.post_message("python", bot, "<script>alert(1)</script>")
  end

  test "recent/2 returns the newest messages, oldest first", %{bot: bot} do
    for i <- 1..5, do: {:ok, _} = Rooms.post_message("python", bot, "msg #{i}")

    assert Enum.map(Rooms.recent("python", 3), & &1.body) == ["msg 3", "msg 4", "msg 5"]
  end
end
