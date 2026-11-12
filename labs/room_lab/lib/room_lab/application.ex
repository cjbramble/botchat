defmodule RoomLab.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: RoomLab.Registry},
      {DynamicSupervisor, name: RoomLab.RoomSup, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: RoomLab.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
