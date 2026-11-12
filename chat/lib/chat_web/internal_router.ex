defmodule ChatWeb.InternalRouter do
  @moduledoc "Plain HTTP routes on the internal endpoint."
  use Plug.Router

  plug :match
  plug :dispatch

  get "/healthz" do
    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "")
  end
end
