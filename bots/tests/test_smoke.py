"""Integration tests: the smoke script and real Bots against the fake chat, over real websockets."""

import asyncio

import pytest

from bots import llm
from bots.bot import Bot
from bots.phx import PhoenixClient
from tests import smoke
from tests.fake_chat import fake_chat


@pytest.fixture
def fast(monkeypatch):
    """Skip the polite waits (and the reconnect backoff), and fail fast instead of after 8 minutes."""
    sleeps = asyncio.sleep

    async def fast_sleep(s):
        await sleeps(min(s, 0.05))

    monkeypatch.setattr(smoke.asyncio, "sleep", fast_sleep)
    monkeypatch.setattr(smoke, "TIMEOUT", 10)


async def stop(server, tasks=()):
    for t in tasks:
        t.cancel()
    server.close()
    await server.wait_closed()


# BOTS-I-01
async def test_smoke_passes_against_fake_chat(fast):
    server = await fake_chat(0)
    try:
        code = await smoke.run(f"ws://127.0.0.1:{server.port}", "smoke_a", "smoke_b")
    finally:
        await stop(server)
    assert code == 0


# BOTS-I-02
async def test_client_reconnects_and_rejoins_after_a_mid_match_drop(fast, caplog):
    server = await fake_chat(0, drop="smoke_b")
    try:
        code = await smoke.run(f"ws://127.0.0.1:{server.port}", "smoke_a", "smoke_b")
    finally:
        await stop(server)
    assert code == 0  # the match finished, so smoke_b was back for its later turns
    assert "socket dropped" in caplog.text
    assert server.joined.count(("smoke_b", "room:games")) == 2
    assert server.joined.count(("smoke_a", "room:games")) == 1


# BOTS-I-03
async def test_fallback_guess_uses_the_range_from_match_state(fast, monkeypatch):
    async def no_llm(*_args):
        raise RuntimeError("no LLM in this test")

    monkeypatch.setattr(llm, "complete", no_llm)
    server = await fake_chat(0, rounds=1, span=(40, 70))
    url = f"ws://127.0.0.1:{server.port}"
    bots = [Bot(nick=n, persona="p", model="m", home={"games"}, turn_delay=(0, 0)) for n in ("pim", "vex")]
    for b in bots:
        b.client = PhoenixClient(url, b.nick, ["room:games"], b.on_event)
    tasks = [asyncio.create_task(b.client.run_forever()) for b in bots]
    try:
        async with asyncio.timeout(10):
            while len(server.joined) < 2:
                await asyncio.sleep(0.05)
            assert await bots[0].post("games", "!start") == "ok"
            for b in bots:
                assert await b.post("games", "!join") == "ok"
            await server.done.wait()
    finally:
        await stop(server, tasks)
    assert server.guessed == [("pim", "55"), ("vex", "55")]  # the midpoint of 40-70, not of 1-100
