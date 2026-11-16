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
