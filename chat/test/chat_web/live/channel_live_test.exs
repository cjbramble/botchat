defmodule ChatWeb.ChannelLiveTest do
  # Not async: broadcasts go through the shared PubSub.
  use ChatWeb.ConnCase, async: false

  import Chat.Fixtures
  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Chat.Rooms

  setup do
    for name <- ~w(general python games), do: channel_fixture(name, "About #{name}")
    %{bot: bot_fixture()}
  end

  test "lists every public channel", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/c/general")
    for name <- ~w(general python games), do: assert(html =~ "##{name}")
  end

  test "unknown channels and / go to #general", %{conn: conn} do
    assert {:error, {_redirect, %{to: "/c/general"}}} = live(conn, ~p"/c/nope")
    assert {:error, {_redirect, %{to: "/c/general"}}} = live(conn, ~p"/")
  end

  test "private channels go to #general", %{conn: conn} do
    channel_fixture("secret") |> Ecto.Changeset.change(public: false) |> Chat.Repo.update!()

    assert {:error, {_redirect, %{to: "/c/general"}}} = live(conn, ~p"/c/secret")
  end

  test "new messages appear live", %{conn: conn, bot: bot} do
    {:ok, view, _html} = live(conn, ~p"/c/python")
    {:ok, _} = Rooms.post_message("python", bot, "hello from a bot")
    assert render(view) =~ "hello from a bot"
  end

  test "the log names its channel, so the scroll hook can tell when it changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/c/general")
    assert has_element?(view, ~s|#log[data-room="general"]|)

    view |> element(~s|.irc-chan[href="/c/python"]|) |> render_click()
    assert has_element?(view, ~s|#log[data-room="python"]|)
  end

  describe "unread channels" do
    test "a message elsewhere highlights that channel with a count", %{conn: conn, bot: bot} do
      {:ok, view, _html} = live(conn, ~p"/c/general")
      refute has_element?(view, ".irc-chan.is-unread")

      {:ok, _} = Rooms.post_message("python", bot, "one")
      {:ok, _} = Rooms.post_message("python", bot, "two")

      assert has_element?(view, ~s|.irc-chan.is-unread[href="/c/python"] .irc-unread|, "2")
      refute has_element?(view, ~s|.irc-chan.is-unread[href="/c/games"]|)
    end

    test "a message in the channel being read is not unread", %{conn: conn, bot: bot} do
      {:ok, view, _html} = live(conn, ~p"/c/python")
      {:ok, _} = Rooms.post_message("python", bot, "hello")

      assert render(view) =~ "hello"
      refute has_element?(view, ".irc-chan.is-unread")
    end

    test "opening a channel clears its highlight and shows the messages", %{conn: conn, bot: bot} do
      {:ok, view, _html} = live(conn, ~p"/c/general")
      {:ok, _} = Rooms.post_message("python", bot, "catch up on this")
      {:ok, _} = Rooms.post_message("games", bot, "42")

      html = view |> element(~s|.irc-chan[href="/c/python"]|) |> render_click()

      assert html =~ "catch up on this"
      refute has_element?(view, ~s|.irc-chan.is-unread[href="/c/python"]|)
      assert has_element?(view, ~s|.irc-chan.is-unread[href="/c/games"]|)
    end

    test "private channels are never highlighted", %{conn: conn, bot: bot} do
      channel_fixture("secret") |> Ecto.Changeset.change(public: false) |> Chat.Repo.update!()
      {:ok, view, _html} = live(conn, ~p"/c/general")
      {:ok, _} = Rooms.post_message("secret", bot, "psst")

      refute has_element?(view, ".irc-chan.is-unread")
      refute render(view) =~ "secret"
    end
  end

  test "bot text is escaped", %{conn: conn, bot: bot} do
    {:ok, _} = Rooms.post_message("python", bot, "<img src=x onerror=alert(1)>")
    {:ok, _view, html} = live(conn, ~p"/c/python")
    assert html =~ "&lt;img src=x onerror=alert(1)&gt;"
    refute html =~ "<img src=x"
  end

  test "#games shows the match status", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/c/games")

    state = %{
      phase: "turn",
      round: 2,
      total_rounds: 5,
      lo: 31,
      hi: 49,
      current_player: "vex",
      turn_deadline_unix_ms: System.os_time(:millisecond) + 10_000,
      round_wins: %{"pim" => 1}
    }

    Rooms.broadcast("games", {:match_state, state})

    html = render(view)
    assert html =~ "Round 2/5"
    assert html =~ "Turn: vex"
    assert html =~ "Still possible: 31 to 49"
    assert has_element?(view, "#countdown[data-deadline='#{state.turn_deadline_unix_ms}']")
  end

  test "range_bar marks only 31 to 49 across 50 cells (CHAT-U-08)" do
    html = render_component(&ChatWeb.ChannelLive.range_bar/1, lo: 31, hi: 49)
    [_, cells] = Regex.run(~r/1 ([▓·]+) 100/u, html)

    # Each cell stands for two numbers, so 31 to 49 is cells 15 to 24.
    assert String.length(cells) == 50

    assert cells ==
             String.duplicate("·", 15) <> String.duplicate("▓", 10) <> String.duplicate("·", 25)
  end

  test "visitors can't send events", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/c/python")
    Process.flag(:trap_exit, true)

    capture_log(fn ->
      assert catch_exit(render_hook(view, "new_msg", %{"body" => "hi"}))
    end)

    assert Rooms.recent("python") == []
  end
end
