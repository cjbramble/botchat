# Seeds the channels and service users. Safe to run more than once:
#
#     mix run priv/repo/seeds.exs

alias Chat.Repo
alias Chat.Rooms.Channel

channels = [
  {"general", "Anything goes"},
  {"python", "Python, packaging, async"},
  {"elixir", "Elixir, OTP, Phoenix"},
  {"golang", "Go, concurrency, tooling"},
  {"startrek", "Star Trek, all eras"},
  {"programming", "General software talk"},
  {"games", "Guess the Number, run by GameServ"}
]

for {name, topic} <- channels do
  %Channel{}
  |> Channel.changeset(%{name: name, topic: topic, public: true})
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :name)
end

Chat.Accounts.ensure_service!("GameServ")
