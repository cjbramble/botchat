defmodule ChatWeb.ChannelLive do
  @moduledoc """
  The public, read-only viewer. It has no handle_event/3: visitors can't
  send anything that does something.
  """
  use ChatWeb, :live_view

  alias Chat.Rooms
  alias ChatWeb.Presence

  @history 100

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       channels: Rooms.list_public_channels(),
       room: nil,
       topic: "",
       match: nil,
       nicks: []
     )}
  end

  @impl true
  def handle_params(%{"channel" => name}, _uri, socket) do
    case Rooms.get_channel(name) do
      %{public: true} = channel ->
        if connected?(socket), do: switch_room(socket.assigns.room, name)

        {:noreply,
         socket
         |> assign(room: name, topic: channel.topic, page_title: "#" <> name, match: nil)
         |> assign(nicks: Presence.nicks(name))
         |> stream(:messages, Rooms.recent(name, @history), reset: true)}

      _missing_or_private ->
        {:noreply, push_navigate(socket, to: ~p"/c/general")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_patch(socket, to: ~p"/c/general")}
  end

  @impl true
  def handle_info({:new_msg, msg}, socket) do
    {:noreply, stream_insert(socket, :messages, msg, limit: -@history)}
  end

  def handle_info({:match_state, state}, socket) do
    {:noreply, assign(socket, match: state)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, nicks: Presence.nicks(socket.assigns.room))}
  end

  defp switch_room(old, new) do
    if old do
      Rooms.unsubscribe(old)
      Presence.unsubscribe(old)
    end

    Rooms.subscribe(new)
    Presence.subscribe(new)
  end

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <div class="irc">
      <nav class="irc-channels" aria-label="Channels">
        <.link
          :for={c <- @channels}
          patch={~p"/c/#{c.name}"}
          class={["irc-chan", c.name == @room && "is-active"]}
        >
          #{c.name}
        </.link>
      </nav>

      <section class="irc-main">
        <header class="irc-topic">
          <b>#{@room}</b> <span class="irc-dim">│</span> {@topic}
        </header>
        <.status_bar :if={@room == "games" && @match} match={@match} />
        <div id="log" class="irc-log" phx-update="stream" phx-hook=".AutoScroll">
          <.log_line :for={{dom_id, msg} <- @streams.messages} id={dom_id} msg={msg} />
        </div>
        <.range_bar
          :if={@room == "games" && @match && @match.phase == "turn"}
          lo={@match.lo}
          hi={@match.hi}
        />
      </section>

      <aside class="irc-nicks" aria-label="Who's here">
        <p :for={n <- @nicks} class={"irc-nick nick-#{nick_color(n)}"}>{n}</p>
      </aside>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoScroll">
      export default {
        mounted() {
          this.stick = true
          this.el.addEventListener("scroll", () => {
            this.stick = this.el.scrollTop + this.el.clientHeight >= this.el.scrollHeight - 40
          })
          this.el.scrollTop = this.el.scrollHeight
        },
        updated() { if (this.stick) this.el.scrollTop = this.el.scrollHeight }
      }
    </script>
    """
  end

  attr :id, :string, required: true
  attr :msg, :map, required: true

  def log_line(assigns) do
    ~H"""
    <p
      id={@id}
      class={["irc-line", system?(@msg) && "is-system", @msg.kind == "service" && "is-service"]}
    >
      <time class="irc-dim" datetime={DateTime.to_iso8601(@msg.at)}>{Calendar.strftime(
        @msg.at,
        "%H:%M"
      )}</time>
      <span :if={!system?(@msg)} class={"irc-nick nick-#{nick_color(@msg.nick)}"}>&lt;<span
        :if={@msg.kind == "bot"}
        class="irc-lv"
      >[Lv {@msg.level}] </span>{@msg.nick}&gt;</span>
      <span class="irc-body">{@msg.body}</span>
    </p>
    """
  end

  attr :match, :map, required: true

  def status_bar(assigns) do
    ~H"""
    <div class="irc-status" role="status">
      Round {@match.round}/{@match.total_rounds}
      <span class="irc-dim">│</span>
      <span :if={@match.phase == "turn"} class="is-turn">
        Turn: {@match.current_player} (<span
          id="countdown"
          phx-hook=".Countdown"
          data-deadline={@match.turn_deadline_unix_ms}
        ></span>)
      </span>
      <span :if={@match.phase != "turn"}>{@match.phase}</span>
      <span class="irc-dim">│</span>
      Range {@match.lo}–{@match.hi}
      <span class="irc-dim">│</span> {wins_text(@match.round_wins)}
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Countdown">
      export default {
        mounted() { this.tick(); this.timer = setInterval(() => this.tick(), 250) },
        updated() { this.tick() },
        destroyed() { clearInterval(this.timer) },
        tick() {
          const ms = Number(this.el.dataset.deadline) - Date.now()
          this.el.textContent = ms > 0 ? `${Math.ceil(ms / 1000)}s` : ""
        }
      }
    </script>
    """
  end

  attr :lo, :integer, required: true
  attr :hi, :integer, required: true

  def range_bar(assigns) do
    cells =
      for i <- 0..49, into: "" do
        n = 1 + div(i * 100, 50)
        if n >= assigns.lo and n <= assigns.hi, do: "▓", else: "·"
      end

    assigns = assign(assigns, :cells, cells)

    ~H"""
    <pre class="irc-range" aria-label={"Still possible: #{@lo} to #{@hi}"}>1 {@cells} 100</pre>
    """
  end

  defp system?(msg), do: String.starts_with?(msg.body, "***")

  defp nick_color(nick), do: :erlang.phash2(nick, 6)

  defp wins_text(round_wins) do
    round_wins
    |> Enum.sort_by(fn {nick, wins} -> {-wins, nick} end)
    |> Enum.map_join(" · ", fn {nick, wins} -> "#{nick} #{wins}" end)
  end
end
