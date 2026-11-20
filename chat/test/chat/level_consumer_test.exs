defmodule Chat.LevelConsumerTest do
  use Chat.DataCase, async: false

  import Chat.Fixtures
  import ExUnit.CaptureLog

  alias Chat.{Accounts, LevelConsumer}

  setup do
    bot = bot_fixture("pim")
    start_supervised!(LevelConsumer)
    %{bot: bot}
  end

  defp event(nick, level) do
    Jason.encode!(%{
      type: "player.leveled_up",
      version: 1,
      player_id: nick,
      old_level: level - 1,
      new_level: level
    })
  end

  describe "bump_level_cache/2" do
    test "only ever raises the level", %{bot: bot} do
      Accounts.subscribe_levels()

      assert Accounts.bump_level_cache(bot.nick, 3) == :updated
      assert_receive {:level_changed, "pim", 3}

      assert Accounts.bump_level_cache(bot.nick, 3) == :unchanged
      assert Accounts.bump_level_cache(bot.nick, 2) == :unchanged
      refute_receive {:level_changed, _, _}
      assert Accounts.get_user_by_nick!("pim").level_cache == 3
    end

    test "an unknown nick changes nothing" do
      Accounts.subscribe_levels()

      assert Accounts.bump_level_cache("nobody", 3) == :unchanged
      refute_receive {:level_changed, _, _}
    end
  end

  describe "the pipeline" do
    test "duplicates and late events change the badge once (CHAT-I-04)" do
      Accounts.subscribe_levels()

      for data <- [event("pim", 5), event("pim", 5), event("pim", 4)] do
        ref = Broadway.test_message(LevelConsumer, data)
        assert_receive {:ack, ^ref, [_successful], []}
      end

      assert_receive {:level_changed, "pim", 5}
      refute_receive {:level_changed, _, _}
      assert Accounts.get_user_by_nick!("pim").level_cache == 5
    end

    test "malformed messages fail, so SQS retries them and then dead-letters them" do
      malformed = [
        "not json",
        ~s({"player_id":"pim"}),
        ~s({"type":"player.leveled_up","version":1,"player_id":"pim"}),
        ~s({"type":"player.leveled_up","version":1,"player_id":"pim","new_level":"5"})
      ]

      for data <- malformed do
        ref = Broadway.test_message(LevelConsumer, data)
        assert_receive {:ack, ^ref, [], [_failed]}
      end

      assert Accounts.get_user_by_nick!("pim").level_cache == 1
    end

    test "unknown event types and versions are acknowledged and ignored" do
      unknown = [
        ~s({"type":"player.renamed","version":1}),
        ~s({"type":"player.leveled_up","version":2,"player_id":"pim","new_level":9})
      ]

      log =
        capture_log(fn ->
          for data <- unknown do
            ref = Broadway.test_message(LevelConsumer, data)
            assert_receive {:ack, ^ref, [_successful], []}
          end
        end)

      assert log =~ "ignoring event"
      assert Accounts.get_user_by_nick!("pim").level_cache == 1
    end
  end
end
