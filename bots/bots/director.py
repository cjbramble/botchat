"""Hands out speaking turns and starts matches: the only thing that decides when an LLM gets called."""

import asyncio
import logging
import random
from typing import Protocol

from .budget import Budget

log = logging.getLogger(__name__)

STARTUP_DELAY = 30.0  # seconds for the sockets to connect and join before the first match
LOBBY_WAIT = 2.5  # chat allows a bot one line per 2 s in #games; also lets the lobby's match_state arrive
RETRY_AFTER = 300.0  # seconds until the next try when no lobby opened (game down, or a match still running)


class Speaker(Protocol):
    nick: str
    home: set[str]

    async def speak(self, channel: str) -> float: ...  # returns cost in USD


def pick_speaker(bots, channel: str, recent_lines: list[str], exclude=None, rng=random):
    """Choose who talks next: someone who lives in this channel, not the last speaker,
    three times as likely if they were mentioned in the last 5 lines."""
    candidates = [b for b in bots if channel in b.home and b is not exclude]
    if not candidates:
        return None
    tail = " ".join(recent_lines[-5:]).lower()
    weights = [3 if b.nick.lower() in tail else 1 for b in candidates]
    return rng.choices(candidates, weights=weights, k=1)[0]


async def run_channel(
    channel: str, per_hour: int, bots, budget: Budget, history, rng=random, sleep=asyncio.sleep
):
    """Loop forever: wait ~3600/per_hour seconds, then let one bot speak."""
    if per_hour <= 0:
        return
    interval = 3600 / per_hour
    last = None
    while True:
        await sleep(interval * rng.uniform(0.7, 1.3))  # jitter so channels don't tick in lockstep
        if budget.exhausted():
            log.warning("daily budget spent; pausing #%s until midnight UTC", channel)
            await budget.wait_for_reset()
            continue
        speaker = pick_speaker(bots, channel, history(channel), exclude=last, rng=rng)
        if speaker is None:
            continue
        try:
            budget.charge(await speaker.speak(channel))
        except Exception:  # one bad LLM call must not stop the channel
            log.exception("%s failed to speak in #%s", speaker.nick, channel)
        last = speaker


class Player(Protocol):
    nick: str
    home: set[str]
    match: dict  # latest match_state

    async def post(self, channel: str, body: str) -> str: ...


async def start_match(channel: str, players: int, bots, rng=random, sleep=asyncio.sleep) -> bool:
    """One random bot posts !start, then `players` random bots (it included) post !join.

    Returns False if no lobby opened. The turns themselves are each bot's own business:
    GameServ names a bot and the bot answers.
    """
    candidates = [b for b in bots if channel in b.home]
    if len(candidates) < 2:
        log.warning("no match in #%s: a match needs 2 players, %d live there", channel, len(candidates))
        return False
    chosen = rng.sample(candidates, min(players, len(candidates)))
    starter = chosen[0]
    await starter.post(channel, "!start")
    await sleep(LOBBY_WAIT)
    # The reply to !start only says chat stored the line. The lobby's match_state is the proof
    # that the game heard it.
    if starter.match.get("phase") != "lobby":
        log.warning("no match in #%s: %s said !start but no lobby opened", channel, starter.nick)
        return False
    await asyncio.gather(*(b.post(channel, "!join") for b in chosen))
    log.info("match started in #%s players=%s", channel, ",".join(b.nick for b in chosen))
    return True


async def run_matches(
    channel: str,
    every_s: float,
    players: int,
    bots,
    rng=random,
    sleep=asyncio.sleep,
    startup_delay: float = STARTUP_DELAY,
    retry_after: float = RETRY_AFTER,
):
    """Loop forever: start a match soon after startup, then one every `every_s` seconds."""
    await sleep(startup_delay)
    while True:
        try:
            opened = await start_match(channel, players, bots, rng=rng, sleep=sleep)
        except Exception:  # one failed start must not end matches for good
            log.exception("failed to start a match in #%s", channel)
            opened = False
        await sleep(every_s if opened else retry_after)
