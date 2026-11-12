defmodule Chat.Accounts do
  @moduledoc """
  Bots, services and the tokens bots connect with.
  """
  import Ecto.Query, warn: false

  alias Chat.Accounts.{BotToken, User}
  alias Chat.Repo

  @token_bytes 32

  ## Users

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_nick(nick) when is_binary(nick), do: Repo.get_by(User, nick: nick)

  def list_bots do
    Repo.all(from u in User, where: u.kind == "bot", order_by: u.nick)
  end

  def create_bot(nick), do: create_user(%{nick: nick, kind: "bot"})

  @doc "Returns the service user (e.g. GameServ), creating it if needed."
  def ensure_service!(nick) do
    case get_user_by_nick(nick) do
      %User{kind: "service"} = user -> user
      nil -> Repo.insert!(User.changeset(%User{}, %{nick: nick, kind: "service"}))
    end
  end

  defp create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  ## Bot tokens

  @doc """
  Creates a new token for a bot and returns it. This is the only time the
  raw token exists: only its hash is stored, so copy it now.
  """
  def issue_bot_token(%User{kind: "bot", id: user_id}) do
    raw = :crypto.strong_rand_bytes(@token_bytes) |> Base.url_encode64(padding: false)
    Repo.insert!(%BotToken{user_id: user_id, token_hash: hash(raw)})
    raw
  end

  @doc "Returns `{:ok, bot}` for a valid token, otherwise `:error`."
  def verify_bot_token(raw) when is_binary(raw) and byte_size(raw) > 0 do
    query =
      from t in BotToken,
        join: u in assoc(t, :user),
        where: t.token_hash == ^hash(raw) and u.kind == "bot",
        select: u

    case Repo.one(query) do
      %User{} = user -> {:ok, user}
      nil -> :error
    end
  end

  def verify_bot_token(_other), do: :error

  @doc "Deletes all of a bot's tokens and returns how many there were."
  def revoke_bot_tokens(%User{id: user_id}) do
    {count, _} = Repo.delete_all(from t in BotToken, where: t.user_id == ^user_id)
    count
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw)
end
