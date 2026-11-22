import asyncio

import pytest

from bots import llm
from bots.bot import Bot
from bots.budget import Budget


class FakeClient:
    """Records what the bot sends. Replies with each item of `outcomes` in turn, then "ok"."""

    def __init__(self, outcomes=()):
        self.pushed = []
        self.outcomes = list(outcomes)

    async def request(self, topic, event, payload):
        self.pushed.append((topic, event, payload))
        outcome = self.outcomes.pop(0) if self.outcomes else "ok"
        if outcome == "lost":
            raise TimeoutError
        if outcome == "down":
            raise ConnectionError("not connected")
        if outcome == "refused":
            return {"status": "error", "response": {"reason": "rate_limited"}}
        return {"status": "ok", "response": {"id": len(self.pushed)}}


def fake_llm(text, cost=0.001):
    async def complete(model, system, lines, max_tokens):
        return llm.Reply(text=text, cost_usd=cost, tokens=10)

    return complete


@pytest.fixture
def bot():
    b = Bot(nick="pim", persona="You are Pim, a cheerful Pythonista.", model="m", home={"python", "games"})
    b.turn_delay = (0, 0)
    b.client = FakeClient()
    b.budget = Budget(1.0)
    return b


async def test_turn_uses_llm_number_in_range(bot, monkeypatch):
    monkeypatch.setattr(llm, "complete", fake_llm("I'll say 42."))
    bot.match = {"lo": 31, "hi": 49}
    await bot.take_turn("games")
    assert bot.client.pushed[-1][2] == {"body": "42"}


async def test_turn_asks_for_five_tokens(bot, monkeypatch):
    asked = {}

    async def complete(model, system, lines, max_tokens):
        asked["max_tokens"] = max_tokens
        return llm.Reply(text="40", cost_usd=0.0, tokens=1)

    monkeypatch.setattr(llm, "complete", complete)
    await bot.take_turn("games")
    assert asked == {"max_tokens": 5}


@pytest.mark.parametrize("text", ["hmm, tough one", "99", "", "-5", "30", "50", "<script>alert(1)</script>"])
async def test_turn_falls_back_to_midpoint(bot, monkeypatch, text):
    monkeypatch.setattr(llm, "complete", fake_llm(text))
    bot.match = {"lo": 31, "hi": 49}
    await bot.take_turn("games")
    assert bot.client.pushed[-1][2] == {"body": "40"}


async def test_turn_falls_back_when_the_llm_fails(bot, monkeypatch):
    async def complete(model, system, lines, max_tokens):
        raise RuntimeError("HTTP 402")

    monkeypatch.setattr(llm, "complete", complete)
    bot.match = {"lo": 31, "hi": 49}
    await bot.take_turn("games")
    assert bot.client.pushed == [("room:games", "new_msg", {"body": "40"})]


async def test_turn_skips_the_llm_when_the_budget_is_spent(bot, monkeypatch):
    async def complete(model, system, lines, max_tokens):
        raise AssertionError("the LLM must not be called")

    monkeypatch.setattr(llm, "complete", complete)
    bot.budget.charge(1.0)
    bot.match = {"lo": 31, "hi": 49}
    await bot.take_turn("games")
    assert bot.client.pushed[-1][2] == {"body": "40"}


async def test_turn_pauses_before_guessing(bot, monkeypatch):
    slept = []

    async def fake_sleep(seconds):
        slept.append(seconds)
        assert bot.client.pushed == []  # the pause comes before the guess

    monkeypatch.setattr(asyncio, "sleep", fake_sleep)
    monkeypatch.setattr(llm, "complete", fake_llm("42"))
    bot.turn_delay = (1.5, 3.5)
    await bot.take_turn("games")
    assert len(slept) == 1 and 1.5 <= slept[0] <= 3.5
    assert bot.client.pushed[-1][2] == {"body": "42"}


async def test_turn_charges_the_budget(bot, monkeypatch):
    monkeypatch.setattr(llm, "complete", fake_llm("40", cost=0.25))
    await bot.take_turn("games")
    assert bot.budget.spent == 0.25


async def test_speak_posts_one_line_and_returns_cost(bot, monkeypatch):
    async def complete(model, system, lines, max_tokens):
        assert "#python" in system
        return llm.Reply(text="asyncio.TaskGroup is great\nsecond line dropped", cost_usd=0.002, tokens=50)

    monkeypatch.setattr(llm, "complete", complete)
    cost = await bot.speak("python")
    assert cost == 0.002
    assert bot.client.pushed == [("room:python", "new_msg", {"body": "asyncio.TaskGroup is great"})]


async def test_speak_tells_the_model_the_channel_topic_comes_first(bot, monkeypatch):
    seen = {}

    async def complete(model, system, lines, max_tokens):
        seen["system"] = system
        return llm.Reply(text="hi", cost_usd=0.0, tokens=1)

    monkeypatch.setattr(llm, "complete", complete)
    bot.topics["python"] = "Python, packaging, async"
    await bot.speak("python")
    character, where, rules = seen["system"].split("\n")
    assert character == bot.persona
    assert where == "You are in #python. Its topic: Python, packaging, async"
    assert "The channel decides WHAT you talk about" in rules


@pytest.mark.parametrize(
    ("channel", "expected"),
    [
        ("golang", "You are Brisk, energetic. You are a Go contributor."),
        ("music", "You are Brisk, energetic. You run marathons."),
        ("general", "You are Brisk, energetic. You are a Go contributor. You run marathons."),
        ("unlisted", "You are Brisk, energetic. You are a Go contributor. You run marathons."),
    ],
)
async def test_speak_shows_the_model_only_the_side_that_fits_the_channel(monkeypatch, channel, expected):
    seen = {}

    async def complete(model, system, lines, max_tokens):
        seen["system"] = system
        return llm.Reply(text="hi", cost_usd=0.0, tokens=1)

    monkeypatch.setattr(llm, "complete", complete)
    brisk = Bot(
        nick="brisk",
        persona="You are Brisk, energetic.",
        work="You are a Go contributor.",
        interests="You run marathons.",
        about={"golang": "work", "music": "life", "general": "both"},
        model="m",
        home={"golang", "music", "general"},
        client=FakeClient(),
    )
    await brisk.speak(channel)
    assert seen["system"].split("\n")[0] == expected


async def test_speak_falls_back_to_the_channel_name_without_a_topic(bot, monkeypatch):
    seen = {}

    async def complete(model, system, lines, max_tokens):
        seen["system"] = system
        return llm.Reply(text="hi", cost_usd=0.0, tokens=1)

    monkeypatch.setattr(llm, "complete", complete)
    await bot.speak("python")
    assert "You are in #python. Its topic: python\n" in seen["system"]


async def test_speak_caps_a_line_at_300_chars(bot, monkeypatch):
    monkeypatch.setattr(llm, "complete", fake_llm("x" * 5000))
    await bot.speak("python")
    assert bot.client.pushed[-1][2] == {"body": "x" * 300}


async def test_speak_posts_nothing_for_an_empty_reply(bot, monkeypatch):
    monkeypatch.setattr(llm, "complete", fake_llm(""))
    assert await bot.speak("python") == 0.001
    assert bot.client.pushed == []


async def test_lost_guess_is_sent_once_more(bot, monkeypatch):
    monkeypatch.setattr(llm, "complete", fake_llm("42"))
    bot.client = FakeClient(outcomes=["lost"])
    await bot.take_turn("games")
    assert [p[2] for p in bot.client.pushed] == [{"body": "42"}, {"body": "42"}]


async def test_guess_lost_twice_gives_up(bot, monkeypatch):
    monkeypatch.setattr(llm, "complete", fake_llm("42"))
    bot.client = FakeClient(outcomes=["lost", "lost", "lost"])
    await bot.take_turn("games")
    assert len(bot.client.pushed) == 2


async def test_refused_guess_is_not_resent(bot, monkeypatch):
    monkeypatch.setattr(llm, "complete", fake_llm("42"))
    bot.client = FakeClient(outcomes=["refused"])
    await bot.take_turn("games")
    assert len(bot.client.pushed) == 1


async def test_lost_chat_line_is_not_resent(bot, monkeypatch):
    monkeypatch.setattr(llm, "complete", fake_llm("hello #python"))
    bot.client = FakeClient(outcomes=["lost"])
    assert await bot.speak("python") == 0.001  # the model call was still paid for
    assert len(bot.client.pushed) == 1


@pytest.mark.parametrize(
    ("outcome", "result"), [("ok", "ok"), ("refused", "refused"), ("lost", "lost"), ("down", "lost")]
)
async def test_post_reports_what_chat_answered(bot, outcome, result):
    bot.client = FakeClient(outcomes=[outcome])
    assert await bot.post("python", "hi") == result


async def test_join_reply_seeds_topic_and_history(bot):
    reply = {
        "status": "ok",
        "response": {"topic": "Python", "recent": [{"id": 1, "nick": "vex", "body": "hi"}]},
    }
    await bot.on_event("room:python", "phx_reply", reply)
    assert bot.topics["python"] == "Python"
    assert list(bot.history["python"]) == ["<vex> hi"]


async def test_rejoin_skips_messages_already_seen(bot):
    await bot.on_event("room:python", "new_msg", {"id": 1, "nick": "vex", "body": "hi"})
    await bot.on_event("room:python", "new_msg", {"id": 2, "nick": "grim", "body": "hey"})
    recent = [
        {"id": 1, "nick": "vex", "body": "hi"},
        {"id": 2, "nick": "grim", "body": "hey"},
        {"id": 3, "nick": "luna", "body": "missed this one while away"},
    ]
    await bot.on_event(
        "room:python", "phx_reply", {"status": "ok", "response": {"topic": "Python", "recent": recent}}
    )
    assert list(bot.history["python"]) == ["<vex> hi", "<grim> hey", "<luna> missed this one while away"]


async def test_history_keeps_the_last_30_lines(bot):
    for i in range(40):
        await bot.on_event("room:python", "new_msg", {"id": i, "nick": "vex", "body": str(i)})
    assert list(bot.history["python"]) == [f"<vex> {i}" for i in range(10, 40)]


async def test_match_state_is_stored(bot):
    await bot.on_event("room:games", "match_state", {"lo": 31, "hi": 49})
    assert bot.fallback_guess() == 40


async def test_gameserv_prompt_triggers_turn(bot, monkeypatch):
    called = asyncio.Event()

    async def fake_turn(channel):
        called.set()

    monkeypatch.setattr(bot, "take_turn", fake_turn)
    await bot.on_event("room:games", "new_msg", {"nick": "GameServ", "body": "pim, you're up (15s)."})
    await asyncio.wait_for(called.wait(), 1)


@pytest.mark.parametrize(
    "msg",
    [
        {"nick": "GameServ", "body": "vex, you're up (15s)."},  # someone else's turn
        {"nick": "vex", "body": "pim, you're up (15s)."},  # not from GameServ
    ],
)
async def test_other_lines_do_not_trigger_a_turn(bot, msg):
    await bot.on_event("room:games", "new_msg", msg)
    assert bot.tasks == set()


async def test_post_carries_the_current_trace_to_chat(bot):
    from opentelemetry.sdk.trace import TracerProvider

    tracer = TracerProvider().get_tracer("test")
    with tracer.start_as_current_span("bot.take_turn") as span:
        await bot.post("games", "50")

    _topic, _event, payload = bot.client.pushed[0]
    ctx = span.get_span_context()
    traceparent = f"00-{ctx.trace_id:032x}-{ctx.span_id:016x}-{ctx.trace_flags:02x}"
    assert payload == {"body": "50", "trace": {"traceparent": traceparent}}


async def test_post_adds_no_trace_when_tracing_is_off(bot):
    await bot.post("games", "50")

    assert bot.client.pushed[0][2] == {"body": "50"}
