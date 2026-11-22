"""One AI participant: a persona, a model, a memory of each channel, and a socket."""

import asyncio
import logging
import random
import re
from collections import defaultdict, deque
from dataclasses import dataclass, field

from opentelemetry import propagate

from . import llm
from .tracing import tracer

log = logging.getLogger(__name__)

RULES = (
    "You are chatting in an IRC channel. Reply with ONE short line (under 200 characters), "
    "no markdown, no lists, no greetings unless greeted. "
    "The channel decides WHAT you talk about; your character only decides HOW you say it. "
    "React to what others just said, and if the talk has drifted off topic, steer it back. "
    "Don't repeat yourself."
)


@dataclass
class Bot:
    nick: str
    persona: str  # who the bot is and how it talks; never its job
    model: str
    home: set[str]
    work: str = ""  # its job, for channels about work
    interests: str = ""  # its life outside work, for every other channel
    about: dict[str, str] = field(default_factory=dict)  # channel -> "work" | "life" | "both"
    max_tokens: int = 120
    # Seconds to wait before guessing, so a match reads like people playing. The worst case
    # (3.5 s here, 5 s for the model, two 3 s waits for chat) still fits a 15 s turn.
    turn_delay: tuple[float, float] = (1.5, 3.5)
    topics: dict[str, str] = field(default_factory=dict)
    history: dict[str, deque] = field(default_factory=lambda: defaultdict(lambda: deque(maxlen=30)))
    seen: dict[str, deque] = field(default_factory=lambda: defaultdict(lambda: deque(maxlen=100)))
    match: dict = field(default_factory=dict)  # latest match_state from #games
    client: object = None  # PhoenixClient, set by main
    budget: object = None  # Budget, set by main
    tasks: set = field(default_factory=set)  # running game turns

    # ---- incoming events -------------------------------------------------

    async def on_event(self, topic: str, event: str, payload: dict) -> None:
        channel = topic.removeprefix("room:")
        if event == "phx_reply" and payload.get("status") == "ok":
            response = payload.get("response", {})
            if "topic" in response:  # the reply to our join
                self.topics[channel] = response["topic"]
                for msg in response.get("recent", []):
                    self.remember(channel, msg)
        elif event == "match_state":
            self.match = payload
        elif event == "new_msg":
            self.remember(channel, payload)
            if payload["nick"] == "GameServ" and f"{self.nick}, you're up" in payload["body"]:
                task = asyncio.create_task(self.take_turn(channel))
                self.tasks.add(task)  # keep a reference so it isn't garbage-collected
                task.add_done_callback(self.tasks.discard)

    def remember(self, channel: str, msg: dict) -> None:
        # A rejoin replays the last 20 messages, most of which we already have.
        msg_id = msg.get("id")
        if msg_id is not None:
            if msg_id in self.seen[channel]:
                return
            self.seen[channel].append(msg_id)
        self.history[channel].append(f"<{msg['nick']}> {msg['body']}")

    # ---- posting -----------------------------------------------------------

    async def post(self, channel: str, body: str) -> str:
        """Send one line and wait for chat's answer. Returns "ok", "refused" (chat said no,
        for example rate_limited) or "lost" (no answer in 3 s, or the socket is down)."""
        payload = {"body": body}
        trace_headers: dict[str, str] = {}
        propagate.inject(trace_headers)  # adds "traceparent" when a recorded span is current
        if trace_headers:
            payload["trace"] = trace_headers  # chat continues the trace from this
        try:
            reply = await self.client.request(f"room:{channel}", "new_msg", payload)
        except (TimeoutError, ConnectionError):
            return "lost"
        if reply.get("status") == "ok":
            return "ok"
        log.warning("%s: chat refused a line in #%s: %s", self.nick, channel, reply.get("response"))
        return "refused"

    # ---- speaking (only when the director says so) ------------------------

    def character(self, channel: str) -> str:
        """The persona plus only the side of the bot that belongs in this channel.

        A job that the model never sees can't leak into #music.
        """
        about = self.about.get(channel, "both")
        parts = [self.persona]
        if about in ("work", "both"):
            parts.append(self.work)
        if about in ("life", "both"):
            parts.append(self.interests)
        return " ".join(p for p in parts if p)

    async def speak(self, channel: str) -> float:
        """Post one LLM-written line to the channel. Returns the model call's cost in USD."""
        with tracer.start_as_current_span("bot.speak") as span:
            span.set_attribute("bot.nick", self.nick)
            span.set_attribute("llm.model", self.model)
            span.set_attribute("chat.channel", channel)
            topic = self.topics.get(channel) or channel
            system = f"{self.character(channel)}\nYou are in #{channel}. Its topic: {topic}\n{RULES}"
            reply = await llm.complete(self.model, system, list(self.history[channel])[-15:], self.max_tokens)
            span.set_attribute("llm.cost_usd", reply.cost_usd)
            span.set_attribute("llm.tokens", reply.tokens)
            line = reply.text.splitlines()[0][:300] if reply.text else ""
            if line and await self.post(channel, line) == "lost":
                # Chatter isn't worth resending: a late duplicate would be worse than a gap.
                log.warning("%s: no reply from chat for a line in #%s; dropped", self.nick, channel)
            log.info(
                "spoke bot=%s model=%s channel=%s tokens=%d cost=%.6f",
                self.nick,
                self.model,
                channel,
                reply.tokens,
                reply.cost_usd,
            )
            return reply.cost_usd

    # ---- game turns (driven by GameServ, still charged to the budget) ----

    def fallback_guess(self) -> int:
        lo, hi = self.match.get("lo", 1), self.match.get("hi", 100)
        return (lo + hi) // 2

    async def take_turn(self, channel: str) -> None:
        """Post one guess: the model's if it is an in-range integer, else the midpoint."""
        with tracer.start_as_current_span("bot.take_turn") as span:
            span.set_attribute("bot.nick", self.nick)
            span.set_attribute("llm.model", self.model)
            guess = self.fallback_guess()
            await asyncio.sleep(random.uniform(*self.turn_delay))
            if self.budget is None or not self.budget.exhausted():
                lo, hi = self.match.get("lo", 1), self.match.get("hi", 100)
                system = (
                    f"{self.persona}\nYou are playing Guess the Number. The number is between "
                    f"{lo} and {hi}. Reply with ONLY one integer."
                )
                try:
                    reply = await asyncio.wait_for(
                        llm.complete(self.model, system, list(self.history[channel])[-10:], 5), timeout=5
                    )
                    if self.budget:
                        self.budget.charge(reply.cost_usd)
                    span.set_attribute("llm.cost_usd", reply.cost_usd)
                    m = re.search(r"-?\d+", reply.text)
                    if m and lo <= int(m.group()) <= hi:
                        guess = int(m.group())
                except Exception:  # timeouts, API errors, anything: fall back, never miss the turn
                    log.warning("%s: LLM turn failed, guessing the midpoint", self.nick, exc_info=True)
            span.set_attribute("game.guess", guess)
            # A lost guess loses the turn, so try once more. If the first one did arrive,
            # the game ignores the copy: by then it's no longer this bot's turn.
            if await self.post(channel, str(guess)) == "lost":
                log.warning("%s: guess got no reply from chat; sending it again", self.nick)
                if await self.post(channel, str(guess)) == "lost":
                    log.warning("%s: guess lost twice; this turn is gone", self.nick)
