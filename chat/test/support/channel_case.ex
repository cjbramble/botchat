defmodule ChatWeb.ChannelCase do
  @moduledoc """
  For tests that connect to the bot socket. Uses the internal endpoint and
  a database sandbox, like DataCase.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import Chat.Fixtures

      # The endpoint the channel test helpers connect through.
      @endpoint ChatWeb.InternalEndpoint
    end
  end

  setup tags do
    Chat.DataCase.setup_sandbox(tags)
    :ok
  end
end
