defmodule Chat.Release do
  @moduledoc """
  Tasks for releases, where Mix isn't available. Run them with
  `bin/chat eval 'Chat.Release.migrate()'` and friends.
  """
  @app :chat

  alias Chat.Accounts

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc "Runs priv/repo/seeds.exs: channels and service users. Idempotent."
  def seed do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Chat.Repo, fn _repo ->
        Code.eval_file(Application.app_dir(@app, "priv/repo/seeds.exs"))
      end)
  end

  @doc """
  Creates any bots in a personas TOML file that don't exist yet, issues a
  fresh token for every bot (revoking its old ones), and prints one
  `BOT_TOKEN_<NICK>=<token>` line per bot for the bot runner's env file.
  """
  def seed_bots(path) do
    load_app()
    %{"bots" => bots} = path |> File.read!() |> Toml.decode!()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Chat.Repo, fn _repo ->
        for %{"nick" => nick} <- bots do
          user = Accounts.get_user_by_nick(nick) || create_bot!(nick)
          Accounts.revoke_bot_tokens(user)
          IO.puts("BOT_TOKEN_#{String.upcase(nick)}=#{Accounts.issue_bot_token(user)}")
        end
      end)

    :ok
  end

  defp create_bot!(nick) do
    {:ok, user} = Accounts.create_bot(nick)
    user
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
