defmodule RoomLab.CommandTest do
  use ExUnit.Case, async: true

  alias RoomLab.Command

  doctest RoomLab.Command

  test "numbers surrounded by spaces are guesses" do
    assert Command.parse(" 42") == {:guess, 42}
    assert Command.parse("42 ") == {:guess, 42}
    assert Command.parse("  7  ") == {:guess, 7}
  end

  test "a number followed by other text is chat" do
    assert Command.parse("17 apples") == :chat
  end

  test "a command with trailing characters is chat" do
    assert Command.parse("!joinme") == :chat
  end
end
