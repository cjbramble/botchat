defmodule RoomLab.Room do
  @moduledoc """
  A chat room process holding its members and most recent messages.

  Rooms are registered by name in `RoomLab.Registry` and supervised by
  `RoomLab.RoomSup`.
  """

  use GenServer

  @max_messages 100

  @type message :: {user :: String.t(), text :: String.t()}

  # Client API

  @doc "Starts a supervised room called `name`."
  @spec start(String.t()) :: DynamicSupervisor.on_start_child()
  def start(name) do
    DynamicSupervisor.start_child(RoomLab.RoomSup, {__MODULE__, name})
  end

  @doc "Starts a room called `name`, registered in `RoomLab.Registry`."
  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(name) do
    GenServer.start_link(__MODULE__, name, name: via(name))
  end

  @doc "Returns the registered name used to reach the room called `name`."
  @spec via(String.t()) :: {:via, Registry, {RoomLab.Registry, String.t()}}
  def via(name), do: {:via, Registry, {RoomLab.Registry, name}}

  @doc "Adds `user` to the room's members."
  @spec join(String.t(), String.t()) :: :ok
  def join(name, user), do: GenServer.call(via(name), {:join, user})

  @doc "Posts `text` as `user`; only members may post."
  @spec say(String.t(), String.t(), String.t()) :: :ok | {:error, :not_joined}
  def say(name, user, text), do: GenServer.call(via(name), {:say, user, text})

  @doc "Returns the room's retained messages, oldest first."
  @spec history(String.t()) :: [message()]
  def history(name), do: GenServer.call(via(name), :history)

  # Server callbacks

  @impl true
  def init(name) do
    {:ok, %{name: name, members: MapSet.new(), messages: []}}
  end

  @impl true
  def handle_call({:join, user}, _from, state) do
    {:reply, :ok, %{state | members: MapSet.put(state.members, user)}}
  end

  def handle_call({:say, user, text}, _from, state) do
    if MapSet.member?(state.members, user) do
      # Newest first, so capping the list drops the oldest messages.
      messages = Enum.take([{user, text} | state.messages], @max_messages)
      {:reply, :ok, %{state | messages: messages}}
    else
      {:reply, {:error, :not_joined}, state}
    end
  end

  def handle_call(:history, _from, state) do
    {:reply, Enum.reverse(state.messages), state}
  end
end
