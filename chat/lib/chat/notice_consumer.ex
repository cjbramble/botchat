defmodule Chat.NoticeConsumer do
  @moduledoc """
  Reads notices from the chat-notices SQS queue (written by the announcer
  Lambda) and posts each one exactly once as GameServ.
  """
  use Broadway

  alias Broadway.Message
  alias Chat.{Accounts, Repo, Rooms}
  alias Chat.Notices.Notice

  def start_link(_opts) do
    {module, opts} = Application.fetch_env!(:chat, :notice_producer)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: {module, opts}, concurrency: 1],
      processors: [default: [concurrency: 1]]
    )
  end

  @impl true
  def handle_message(_processor, %Message{data: data} = message, _context) do
    Chat.Tracing.with_message_span("notice_consumer.handle", message, fn ->
      case post_once(data) do
        :ok -> message
        {:error, reason} -> Message.failed(message, reason)
      end
    end)
  end

  @doc "Posts a notice unless one with the same dedupe key was already posted."
  def post_once(data) do
    with {:ok, %{"room" => room, "text" => text, "dedupe_key" => key}} <- Jason.decode(data),
         {:ok, _} <- Repo.transaction(fn -> record_and_post(room, text, key) end) do
      :ok
    else
      {:error, :duplicate} -> :ok
      {:ok, _not_a_notice} -> {:error, :malformed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_and_post(room, text, key) do
    changeset = Notice.changeset(%Notice{}, %{room: room, text: text, dedupe_key: key})

    case Repo.insert(changeset) do
      {:ok, _notice} ->
        case Rooms.post_message(room, Accounts.ensure_service!("GameServ"), text) do
          {:ok, payload} -> payload
          {:error, changeset} -> Repo.rollback({:invalid, changeset.errors})
        end

      {:error, %{errors: [dedupe_key: _]}} ->
        Repo.rollback(:duplicate)

      {:error, changeset} ->
        Repo.rollback({:invalid, changeset.errors})
    end
  end
end
