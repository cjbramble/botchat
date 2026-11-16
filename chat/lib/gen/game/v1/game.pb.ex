defmodule Game.V1.SubmitInputRequest do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.SubmitInputRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :channel, 1, type: :string
  field :player_id, 2, type: :string, json_name: "playerId"
  field :text, 3, type: :string
  field :msg_id, 4, type: :string, json_name: "msgId"
end

defmodule Game.V1.SubmitInputResponse do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.SubmitInputResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3
end

defmodule Game.V1.SubscribeRequest do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.SubscribeRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :channel, 1, type: :string
end

defmodule Game.V1.MatchState.RoundWinsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.MatchState.RoundWinsEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :int32
end

defmodule Game.V1.MatchState do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.MatchState",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :phase, 1, type: :string
  field :round, 2, type: :int32
  field :total_rounds, 3, type: :int32, json_name: "totalRounds"
  field :lo, 4, type: :int32
  field :hi, 5, type: :int32
  field :current_player, 6, type: :string, json_name: "currentPlayer"
  field :turn_deadline_unix_ms, 7, type: :int64, json_name: "turnDeadlineUnixMs"

  field :round_wins, 8,
    repeated: true,
    type: Game.V1.MatchState.RoundWinsEntry,
    json_name: "roundWins",
    map: true
end

defmodule Game.V1.GameMessage do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.GameMessage",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :channel, 1, type: :string
  field :text, 2, type: :string
  field :seq, 3, type: :int64
  field :state, 4, type: Game.V1.MatchState
end

defmodule Game.V1.GetPlayerRequest do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.GetPlayerRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :player_id, 1, type: :string, json_name: "playerId"
end

defmodule Game.V1.GetPlayerResponse do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.GetPlayerResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :player_id, 1, type: :string, json_name: "playerId"
  field :level, 2, type: :int32
  field :xp, 3, type: :int64
end

defmodule Game.V1.GameService.Service do
  @moduledoc false

  use GRPC.Service, name: "game.v1.GameService", protoc_gen_elixir_version: "0.17.1"

  rpc :SubmitInput, Game.V1.SubmitInputRequest, Game.V1.SubmitInputResponse

  rpc :Subscribe, Game.V1.SubscribeRequest, stream(Game.V1.GameMessage)

  rpc :GetPlayer, Game.V1.GetPlayerRequest, Game.V1.GetPlayerResponse
end

defmodule Game.V1.GameService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Game.V1.GameService.Service
end
