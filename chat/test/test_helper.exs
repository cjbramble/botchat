Mox.defmock(Chat.Game.MockClient, for: Chat.Game.Client)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Chat.Repo, :manual)
