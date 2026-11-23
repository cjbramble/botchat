"""API tests for the OpenRouter client: the real openai SDK against a fake server on localhost."""

import logging

import openai
import pytest
from openai import AsyncOpenAI

from bots import llm
from bots.bot import Bot
from bots.budget import Budget
from bots.director import run_channel
from tests.fake_openrouter import FakeOpenRouter

OK_BODY = {
    "id": "gen-1",
    "object": "chat.completion",
    "created": 0,
    "model": "vendor-a/cheap-model",
    "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": " 42 \n"}}],
    "usage": {"prompt_tokens": 800, "completion_tokens": 3, "total_tokens": 803, "cost": 0.00012},
}
OUT_OF_CREDIT = {"error": {"message": "Insufficient credits", "code": 402}}
RATE_LIMITED = {"error": {"message": "Rate limit exceeded", "code": 429}}


class Sink:
    """Stands in for the Phoenix client: records every post and says chat accepted it."""

    def __init__(self):
        self.pushed = []

    async def request(self, *args):
        self.pushed.append(args)
        return {"status": "ok", "response": {"id": 1}}


@pytest.fixture
def server(monkeypatch):
    fake = FakeOpenRouter()
    monkeypatch.setattr(
        llm, "_client", AsyncOpenAI(base_url=fake.base_url, api_key="test-key", max_retries=0)
    )
    yield fake
    fake.close()


# BOTS-A-01
async def test_request_shape_and_cost_parsing(server):
    server.reply(200, OK_BODY)
    reply = await llm.complete("vendor-a/cheap-model", "be brief", ["<pim> hi"], max_tokens=5)

    path, auth, sent = server.requests[0]
    assert path == "/api/v1/chat/completions" and auth == "Bearer test-key"
    assert sent["model"] == "vendor-a/cheap-model" and sent["max_tokens"] == 5
    assert sent["messages"][0] == {"role": "system", "content": "be brief"}
    assert sent["messages"][1] == {"role": "user", "content": "<pim> hi"}
    assert reply.text == "42" and reply.cost_usd == pytest.approx(0.00012) and reply.tokens == 803
    assert reply.finish_reason == "stop"


# BOTS-A-02
async def test_missing_cost_counts_as_zero(server):
    server.reply(200, {**OK_BODY, "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}})
    assert (await llm.complete("m", "s", [], 5)).cost_usd == 0.0


# BOTS-A-03 and the status half of BOTS-A-05
@pytest.mark.parametrize(
    ("status", "body", "error"),
    [
        (402, OUT_OF_CREDIT, openai.APIStatusError),
        (429, RATE_LIMITED, openai.RateLimitError),
        (500, {"error": {"message": "Internal error", "code": 500}}, openai.InternalServerError),
    ],
)
async def test_error_status_raises(server, status, body, error):
    server.reply(status, body)
    with pytest.raises(error) as err:
        await llm.complete("m", "s", [], 5)
    assert err.value.status_code == status
    assert len(server.requests) == 1  # the fixture's client doesn't retry


# BOTS-A-04
async def test_turn_survives_out_of_credit(server):
    server.reply(402, OUT_OF_CREDIT)
    bot = Bot(nick="pim", persona="p", model="m", home={"games"})
    bot.turn_delay = (0, 0)
    bot.client, bot.budget, bot.match = Sink(), Budget(1.0), {"lo": 10, "hi": 20}
    await bot.take_turn("games")
    assert bot.client.pushed[-1][2] == {"body": "15"}  # fell back to the midpoint


# BOTS-A-05
async def test_channel_keeps_going_when_rate_limited(server, caplog):
    server.reply(429, RATE_LIMITED)
    bots = [Bot(nick=n, persona="p", model="m", home={"python"}) for n in ("pim", "vex")]
    for b in bots:
        b.client = Sink()
    budget = Budget(1.0)

    class Stop(Exception):
        pass

    sleeps = 0

    async def sleep(_seconds):  # let the loop go round twice, then end it
        nonlocal sleeps
        sleeps += 1
        if sleeps > 2:
            raise Stop

    with caplog.at_level(logging.ERROR, logger="bots.director"), pytest.raises(Stop):
        await run_channel("python", 12, bots, budget, lambda _c: [], sleep=sleep)

    assert len(server.requests) == 2  # the second turn still called the model
    assert caplog.text.count("failed to speak in #python") == 2
    assert all(b.client.pushed == [] for b in bots)
    assert budget.spent == 0.0
