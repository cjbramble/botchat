defmodule Chat.Game.ConnTest do
  use ExUnit.Case, async: true

  alias Chat.Game.Conn

  test "plaintext without a TLS folder" do
    assert Conn.connect_opts(nil) == []
  end

  test "with a folder: our certificate, and the game's checked against our CA" do
    [cred: %GRPC.Credential{ssl: ssl}] = Conn.connect_opts("/etc/chat-tls")

    assert ssl[:certfile] == "/etc/chat-tls/tls.crt"
    assert ssl[:keyfile] == "/etc/chat-tls/tls.key"
    assert ssl[:cacertfile] == "/etc/chat-tls/ca.crt"
    assert ssl[:verify] == :verify_peer
  end
end
