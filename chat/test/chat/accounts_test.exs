defmodule Chat.AccountsTest do
  use Chat.DataCase, async: true

  import Chat.Fixtures

  alias Chat.Accounts
  alias Chat.Accounts.BotToken

  describe "create_bot/1" do
    test "creates a bot at level 1" do
      assert {:ok, bot} = Accounts.create_bot("pim")
      assert bot.kind == "bot"
      assert bot.level_cache == 1
    end

    test "rejects duplicate and malformed nicks" do
      bot_fixture("pim")
      assert {:error, changeset} = Accounts.create_bot("pim")
      assert "has already been taken" in errors_on(changeset).nick

      assert {:error, _} = Accounts.create_bot("no spaces")
      assert {:error, _} = Accounts.create_bot("9lives")
    end
  end

  describe "users" do
    test "get_user!/1 and get_user_by_nick/1 find a user" do
      bot = bot_fixture("pim")
      assert Accounts.get_user!(bot.id).nick == "pim"
      assert Accounts.get_user_by_nick("pim").id == bot.id
      assert Accounts.get_user_by_nick("nobody") == nil
    end

    test "list_bots/0 returns bots by nick, without services" do
      bot_fixture("zed")
      bot_fixture("amy")
      Accounts.ensure_service!("GameServ")

      assert Enum.map(Accounts.list_bots(), & &1.nick) == ["amy", "zed"]
    end

    test "ensure_service!/1 creates the service once" do
      first = Accounts.ensure_service!("GameServ")
      assert first.kind == "service"
      assert Accounts.ensure_service!("GameServ").id == first.id
    end
  end

  describe "bot tokens" do
    test "an issued token verifies to its bot (CHAT-U-01)" do
      bot = bot_fixture()
      token = Accounts.issue_bot_token(bot)
      assert {:ok, %{id: id}} = Accounts.verify_bot_token(token)
      assert id == bot.id
    end

    test "revoked tokens, junk and nil don't verify (CHAT-U-02)" do
      bot = bot_fixture()
      token = Accounts.issue_bot_token(bot)
      assert Accounts.revoke_bot_tokens(bot) == 1

      assert :error = Accounts.verify_bot_token(token)
      assert :error = Accounts.verify_bot_token("not-a-token")
      assert :error = Accounts.verify_bot_token("")
      assert :error = Accounts.verify_bot_token(nil)
      assert :error = Accounts.verify_bot_token(123)
    end

    test "only a 32-byte hash is stored (CHAT-U-03)" do
      token = Accounts.issue_bot_token(bot_fixture())
      [row] = Repo.all(BotToken)
      refute row.token_hash == token
      assert byte_size(row.token_hash) == 32
      assert row.token_hash == :crypto.hash(:sha256, token)
    end

    test "service users can't use bot tokens" do
      game_serv = Accounts.ensure_service!("GameServ")
      assert_raise FunctionClauseError, fn -> Accounts.issue_bot_token(game_serv) end
    end
  end
end
