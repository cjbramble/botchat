defmodule Chat.RefreshLevelTest do
  use Chat.DataCase, async: false

  import Mox
  import Chat.Fixtures

  alias Chat.Accounts
  alias Chat.Game.MockClient
  alias Game.V1.GetPlayerResponse

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    Application.put_env(:chat, :refresh_levels, true)
    on_exit(fn -> Application.put_env(:chat, :refresh_levels, false) end)
    Accounts.subscribe_levels()
    %{bot: bot_fixture("pim")}
  end

  test "seeds the badge from GetPlayer", %{bot: bot} do
    stub(MockClient, :get_player, fn "pim" ->
      {:ok, %GetPlayerResponse{player_id: "pim", level: 4, xp: 450}}
    end)

    assert Chat.Game.refresh_level(bot) == :ok
    assert_receive {:level_changed, "pim", 4}
    assert Accounts.get_user_by_nick!("pim").level_cache == 4
  end

  test "a down game changes nothing", %{bot: bot} do
    test = self()

    stub(MockClient, :get_player, fn "pim" ->
      send(test, :asked)
      {:error, :unavailable}
    end)

    assert Chat.Game.refresh_level(bot) == :ok
    assert_receive :asked
    refute_receive {:level_changed, _, _}, 200
    assert Accounts.get_user_by_nick!("pim").level_cache == 1
  end

  test "is skipped when :refresh_levels is false", %{bot: bot} do
    Application.put_env(:chat, :refresh_levels, false)
    # No stub: a call to the mock would crash the task and fail verify_on_exit!.
    assert Chat.Game.refresh_level(bot) == :ok
    refute_receive {:level_changed, _, _}, 100
  end
end
