defmodule Chat.Fixtures do
  @moduledoc "Builds test data with unique names."

  alias Chat.{Accounts, Repo}
  alias Chat.Rooms.Channel

  def unique_nick, do: "bot#{System.unique_integer([:positive])}"

  def bot_fixture(nick \\ unique_nick()) do
    {:ok, bot} = Accounts.create_bot(nick)
    bot
  end

  def channel_fixture(name, topic \\ "A test channel") do
    %Channel{}
    |> Channel.changeset(%{name: name, topic: topic})
    |> Repo.insert!()
  end
end
