defmodule Chat.Game.Conn do
  @moduledoc """
  Holds the one gRPC channel to the game service. It connects on the first
  `get/0`, so chat boots and keeps running while the game is down. Uses mutual
  TLS when `:game_tls_dir` is set.
  """
  use GenServer

  # Shorter than the default GenServer.call timeout, so a slow connect comes
  # back as an error instead of exiting the caller.
  @connect_timeout 3_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Returns `{:ok, channel}`, connecting first if needed, or `{:error, reason}`."
  def get, do: GenServer.call(__MODULE__, :get)

  @doc "Forgets the channel so the next `get/0` connects again."
  def reset, do: GenServer.cast(__MODULE__, :reset)

  @doc """
  Options for `GRPC.Stub.connect/2`. With a folder holding tls.crt, tls.key and
  ca.crt, chat shows its certificate and checks the game's against the same CA.
  Without one (dev, test, Compose), the connection is plaintext.
  """
  def connect_opts(nil), do: []

  def connect_opts(dir) do
    [
      cred:
        GRPC.Credential.new(
          ssl: [
            certfile: Path.join(dir, "tls.crt"),
            keyfile: Path.join(dir, "tls.key"),
            cacertfile: Path.join(dir, "ca.crt"),
            verify: :verify_peer,
            versions: [:"tlsv1.3"]
          ]
        )
    ]
  end

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call(:get, _from, nil) do
    case connect() do
      {:ok, channel} -> {:reply, {:ok, channel}, channel}
      {:error, _reason} = error -> {:reply, error, nil}
    end
  end

  def handle_call(:get, _from, channel), do: {:reply, {:ok, channel}, channel}

  @impl true
  def handle_cast(:reset, _channel), do: {:noreply, nil}

  defp connect do
    GRPC.Stub.connect(
      Application.fetch_env!(:chat, :game_addr),
      [
        # Mint is already a dependency (through Req); the default Gun adapter is not.
        adapter: GRPC.Client.Adapters.Mint,
        # A named connection is reused if it is still running, so a reset
        # neither leaks the old one nor cuts a Subscribe stream that is using it.
        name: __MODULE__,
        connect_timeout: @connect_timeout
      ] ++ connect_opts(Application.get_env(:chat, :game_tls_dir))
    )
  end
end
