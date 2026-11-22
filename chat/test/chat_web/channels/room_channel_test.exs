defmodule ChatWeb.RoomChannelTest do
  # Not async: rate limits live in one shared ETS table.
  use ChatWeb.ChannelCase, async: false

  import Mox

  alias Chat.Accounts
  alias Chat.Game.MockClient
  alias ChatWeb.BotSocket
  alias Game.V1.SubmitInputRequest

  # Global: #games posts reach the game mock from a background task.
  setup :set_mox_global

  setup do
    test = self()

    stub(MockClient, :submit_input, fn request ->
      send(test, {:submitted, request})
      :ok
    end)

    Chat.RateLimit.reset()
    channel_fixture("python", "Python")
    channel_fixture("games", "Guess the Number")
    bot = bot_fixture()
    {:ok, socket} = connect(BotSocket, %{"token" => Accounts.issue_bot_token(bot)})
    %{socket: socket, bot: bot}
  end

  describe "connecting" do
    test "a valid token connects as its bot (CHAT-A-01)", %{socket: socket, bot: bot} do
      assert socket.assigns.user.id == bot.id
    end

    test "bad, missing and revoked tokens are refused (CHAT-A-02)", %{bot: bot} do
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

    test "revoking a connected bot closes its socket (CHAT-A-09)", %{socket: socket, bot: bot} do
      @endpoint.subscribe(BotSocket.id(socket))

      assert Accounts.revoke_bot_tokens(bot) == 1
      BotSocket.disconnect(bot)

      # Phoenix closes every transport of a socket id that gets this broadcast.
      assert_broadcast "disconnect", %{}
    end
  end

  describe "joining" do
    test "a seeded channel replies with its topic (CHAT-A-03)", %{socket: socket} do
      assert {:ok, %{topic: "Python", recent: []}, _socket} =
               subscribe_and_join(socket, "room:python", %{})
    end

    test "an unknown channel is refused (CHAT-A-04)", %{socket: socket} do
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

    test "a pushed message reaches every subscriber (CHAT-A-05)", %{python: python, bot: bot} do
      Chat.Rooms.subscribe("python")

      ref = push(python, "new_msg", %{"body" => "TaskGroup > gather"})
      assert_reply ref, :ok, %{id: id}

      nick = bot.nick

      assert_receive {:new_msg,
                      %{
                        id: ^id,
                        nick: ^nick,
                        kind: "bot",
                        level: 1,
                        body: "TaskGroup > gather",
                        at: %DateTime{}
                      }}
    end

    # Its own test: a refused body still counts against the rate limit.
    test "an empty body is refused (CHAT-A-06)", %{python: python} do
      ref = push(python, "new_msg", %{"body" => ""})
      assert_reply ref, :error, %{reason: "invalid"}
    end

    test "invalid bodies are refused (CHAT-A-06)", %{python: python} do
      ref = push(python, "new_msg", %{"body" => String.duplicate("a", 401)})
      assert_reply ref, :error, %{reason: "invalid"}

      ref = push(python, "new_msg", %{"body" => 42})
      assert_reply ref, :error, %{reason: "bad_request"}

      ref = push(python, "shout", %{"body" => "hi"})
      assert_reply ref, :error, %{reason: "bad_request"}
    end

    test "a second message within 30 s in a topic channel is rate limited (CHAT-A-07)",
         %{python: python} do
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

    test "#games allows quick turns (CHAT-A-08)", %{games: games} do
      assert_reply push(games, "new_msg", %{"body" => "50"}), :ok
      assert_reply push(games, "new_msg", %{"body" => "51"}), :error, %{reason: "rate_limited"}

      # test.exs sets the #games window to 200 ms
      Process.sleep(250)
      assert_reply push(games, "new_msg", %{"body" => "52"}), :ok

      # Let both forwards finish before the mock goes away with the test.
      assert_receive {:submitted, %SubmitInputRequest{text: "50"}}
      assert_receive {:submitted, %SubmitInputRequest{text: "52"}}
    end

    test "a #games post is forwarded to the game, a #python post is not",
         %{python: python, games: games, bot: bot} do
      assert_reply push(python, "new_msg", %{"body" => "hi"}), :ok
      assert_reply push(games, "new_msg", %{"body" => "!start"}), :ok, %{id: id}

      nick = bot.nick
      msg_id = to_string(id)

      assert_receive {:submitted,
                      %SubmitInputRequest{
                        channel: "games",
                        player_id: ^nick,
                        text: "!start",
                        msg_id: ^msg_id
                      }}

      refute_receive {:submitted, _request}, 50
    end

    test "a post's trace headers reach the game call", %{games: games} do
      test = self()

      stub(MockClient, :submit_input, fn _request ->
        send(test, {:headers, Chat.Tracing.headers()})
        :ok
      end)

      trace = %{"traceparent" => "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"}
      assert_reply push(games, "new_msg", %{"body" => "50", "trace" => trace}), :ok

      assert_receive {:headers, [{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-" <> _}]}
    end

    test "malformed trace headers don't stop a post", %{python: python} do
      for trace <- ["junk", 42, %{"traceparent" => 42}, %{"traceparent" => "junk"}] do
        Chat.RateLimit.reset()
        assert_reply push(python, "new_msg", %{"body" => "hi", "trace" => trace}), :ok
      end
    end
  end

  describe "level badges" do
    test "a level raised between connect and join shows on the next post", %{
      socket: socket,
      bot: bot
    } do
      # What the GetPlayer seed does when the game answers before the join.
      assert Accounts.bump_level_cache(bot.nick, 4) == :updated

      {:ok, _, python} = subscribe_and_join(socket, "room:python", %{})
      ref = push(python, "new_msg", %{"body" => "hi"})
      assert_reply ref, :ok, _

      assert_push "new_msg", %{body: "hi", level: 4}
    end

    test "a level raised after joining shows on the next post", %{socket: socket, bot: bot} do
      {:ok, _, python} = subscribe_and_join(socket, "room:python", %{})
      other = bot_fixture()

      assert Accounts.bump_level_cache(other.nick, 9) == :updated
      assert Accounts.bump_level_cache(bot.nick, 3) == :updated

      ref = push(python, "new_msg", %{"body" => "hi"})
      assert_reply ref, :ok, _

      assert_push "new_msg", %{body: "hi", level: 3}
    end
  end
end
