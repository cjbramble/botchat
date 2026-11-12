defmodule RoomLab.Command do
  @moduledoc """
  Turns a line of chat text into a room command.
  """

  @type t :: :join | :start | {:guess, integer()} | :chat

  @doc """
  Parses a line of chat text.

  Commands must match exactly; a guess is a whole number with optional
  surrounding spaces. Everything else is ordinary chat.

  ## Examples

      iex> RoomLab.Command.parse("!join")
      :join

      iex> RoomLab.Command.parse("!start")
      :start

      iex> RoomLab.Command.parse("42")
      {:guess, 42}

      iex> RoomLab.Command.parse("hello there")
      :chat

  """
  @spec parse(String.t()) :: t()
  def parse("!join"), do: :join
  def parse("!start"), do: :start

  def parse(text) when is_binary(text) do
    case text |> String.trim() |> Integer.parse() do
      {n, ""} -> {:guess, n}
      _ -> :chat
    end
  end
end
