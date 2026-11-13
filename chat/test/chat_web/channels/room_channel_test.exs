defmodule ChatWeb.RoomChannelTest do
  # Not async: rate limits live in one shared ETS table.
  use ChatWeb.ChannelCase, async: false

  alias Chat.Accounts
  alias ChatWeb.BotSocket

  setup do
    Chat.RateLimit.reset()
    channel_fixture("python", "Python")
    channel_fixture("games", "Guess the Number")
    bot = bot_fixture()
    {:ok, socket} = connect(BotSocket, %{"token" => Accounts.issue_bot_token(bot)})
    %{socket: socket, bot: bot}
  end

  describe "connecting" do
    test "bad, missing and revoked tokens are refused", %{bot: bot} do
      assert :error = connect(BotSocket, %{"token" => "nope"})
      assert :error = connect(BotSocket, %{})

      token = Accounts.issue_bot_token(bot)
      Accounts.revoke_bot_tokens(bot)
      assert :error = connect(BotSocket, %{"token" => token})
    end

    test "disconnect/1 broadcasts to the bot's socket id", %{socket: socket, bot: bot} do
      assert BotSocket.id(socket) == "bot_socket:#{bot.id}"

      @endpoint.subscribe(BotSocket.id(socket))
      BotSocket.disconnect(bot)
      assert_broadcast "disconnect", %{}
    end
  end

  describe "joining" do
    test "a seeded channel replies with its topic", %{socket: socket} do
      assert {:ok, %{topic: "Python", recent: []}, _socket} =
               subscribe_and_join(socket, "room:python", %{})
    end

    test "an unknown channel is refused", %{socket: socket} do
      assert {:error, %{reason: "no_such_channel"}} =
               subscribe_and_join(socket, "room:nope", %{})
    end
  end

  describe "posting" do
    setup %{socket: socket} do
      {:ok, _, python} = subscribe_and_join(socket, "room:python", %{})
      {:ok, _, games} = subscribe_and_join(socket, "room:games", %{})
      %{python: python, games: games}
    end

    test "a message is stored and pushed back to the room", %{python: python, bot: bot} do
      ref = push(python, "new_msg", %{"body" => "hi"})
      assert_reply ref, :ok, %{id: id}

      nick = bot.nick
      assert_push "new_msg", %{body: "hi", nick: ^nick}
      assert [%{id: ^id, body: "hi"}] = Chat.Rooms.recent("python", 20)
    end

    # Its own test: a refused body still counts against the rate limit.
    test "an empty body is refused", %{python: python} do
      ref = push(python, "new_msg", %{"body" => ""})
      assert_reply ref, :error, %{reason: "invalid"}
    end

    test "invalid bodies are refused", %{python: python} do
      ref = push(python, "new_msg", %{"body" => String.duplicate("a", 401)})
      assert_reply ref, :error, %{reason: "invalid"}

      ref = push(python, "new_msg", %{"body" => 42})
      assert_reply ref, :error, %{reason: "bad_request"}

      ref = push(python, "shout", %{"body" => "hi"})
      assert_reply ref, :error, %{reason: "bad_request"}
    end

    test "a second message within 30 s in a topic channel is rate limited", %{python: python} do
      assert_reply push(python, "new_msg", %{"body" => "one"}), :ok
      assert_reply push(python, "new_msg", %{"body" => "two"}), :error, %{reason: "rate_limited"}
    end

    test "the channel limit applies across bots", %{python: python} do
      assert_reply push(python, "new_msg", %{"body" => "one"}), :ok

      other = bot_fixture()
      {:ok, socket2} = connect(BotSocket, %{"token" => Accounts.issue_bot_token(other)})
      {:ok, _, python2} = subscribe_and_join(socket2, "room:python", %{})

      assert_reply push(python2, "new_msg", %{"body" => "me too"}), :error, %{
        reason: "rate_limited"
      }
    end

    test "#games allows quick turns", %{games: games} do
      assert_reply push(games, "new_msg", %{"body" => "50"}), :ok
      assert_reply push(games, "new_msg", %{"body" => "51"}), :error, %{reason: "rate_limited"}

      # test.exs sets the #games window to 200 ms
      Process.sleep(250)
      assert_reply push(games, "new_msg", %{"body" => "52"}), :ok
    end
  end
end
