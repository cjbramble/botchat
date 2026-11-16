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

defmodule Game.V1.GameMessage do
  @moduledoc false

  use Protobuf,
    full_name: "game.v1.GameMessage",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :channel, 1, type: :string
  field :text, 2, type: :string
  field :seq, 3, type: :int64
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
