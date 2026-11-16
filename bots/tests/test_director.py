import asyncio
import itertools
import random
from datetime import UTC, datetime, timedelta

import pytest

from bots.budget import Budget
from bots.director import pick_speaker, run_channel, run_matches, start_match


class FakeBot:
    def __init__(self, nick, home, cost=0.01, fails=False, log=None):
        self.nick, self.home, self.cost, self.fails, self.spoke = nick, set(home), cost, fails, []
        self.log = log  # shared between bots to record who spoke in which order

    async def speak(self, channel):
        self.spoke.append(channel)
        if self.log is not None:
            self.log.append(self.nick)
        if self.fails:
            raise RuntimeError("LLM is down")
        return self.cost


class FakeClock:
    def __init__(self):
        self.now = datetime(2026, 11, 11, 23, 0, tzinfo=UTC)

    def __call__(self):
        return self.now


def stop_after(count):
    """A fake sleep that records each delay and ends the endless loop after `count` of them."""
    sleeps = []

    async def fake_sleep(s):
        sleeps.append(s)
        if len(sleeps) > count:
            raise asyncio.CancelledError

    return sleeps, fake_sleep


def test_pick_only_from_channel_members_and_not_last():
    a, b, c = FakeBot("pim", ["python"]), FakeBot("vex", ["python"]), FakeBot("grim", ["elixir"])
    for _ in range(50):
        chosen = pick_speaker([a, b, c], "python", [], exclude=a, rng=random.Random(1))
        assert chosen is b


def test_pick_returns_none_when_nobody_lives_there():
    assert pick_speaker([FakeBot("pim", ["python"])], "elixir", []) is None


def test_mentions_are_favoured():
    bots = [FakeBot(n, ["general"]) for n in ("pim", "vex", "grim", "luna")]
    rng = random.Random(42)
    picks = [pick_speaker(bots, "general", ["<vex> hey pim, thoughts?"], rng=rng).nick for _ in range(2000)]
    assert picks.count("pim") > picks.count("grim") * 2


def test_mentions_older_than_five_lines_are_ignored():
    bots = [FakeBot(n, ["general"]) for n in ("pim", "grim")]
    rng = random.Random(42)
    lines = ["<luna> hey pim"] + ["<luna> anyway"] * 5
    picks = [pick_speaker(bots, "general", lines, rng=rng).nick for _ in range(2000)]
    assert 0.8 < picks.count("pim") / picks.count("grim") < 1.25


def test_budget_rolls_over_at_midnight_utc():
    clock = FakeClock()
    budget = Budget(1.0, clock=clock)
    budget.charge(1.5)
    assert budget.exhausted()
    assert budget.seconds_until_reset() == 3600
    clock.now += timedelta(hours=2)  # next UTC day
    assert not budget.exhausted()


async def test_director_respects_rate_and_budget():
    bots = [FakeBot("pim", ["python"], cost=0.4), FakeBot("vex", ["python"], cost=0.4)]
    clock = FakeClock()
    budget = Budget(1.0, clock=clock)
    sleeps, fake_sleep = stop_after(6)

    async def no_wait():
        raise asyncio.CancelledError

    budget.wait_for_reset = no_wait
    with pytest.raises(asyncio.CancelledError):
        await run_channel("python", 12, bots, budget, lambda ch: [], rng=random.Random(3), sleep=fake_sleep)
    spoken = sum(len(b.spoke) for b in bots)
    assert spoken == 3  # 3 x $0.40 crosses the $1.00 cap, then it pauses
    assert all(0.7 * 300 <= s <= 1.3 * 300 for s in sleeps)  # 12/hour = every ~300 s


async def test_director_never_picks_the_same_bot_twice_in_a_row():
    order = []
    bots = [FakeBot(n, ["python"], cost=0, log=order) for n in ("pim", "vex", "luna")]
    _sleeps, fake_sleep = stop_after(20)
    with pytest.raises(asyncio.CancelledError):
        await run_channel(
            "python", 12, bots, Budget(1.0), lambda ch: [], rng=random.Random(5), sleep=fake_sleep
        )
    assert len(order) == 20
    assert all(a != b for a, b in itertools.pairwise(order))


async def test_one_failed_speak_does_not_stop_the_channel():
    bots = [FakeBot("pim", ["python"], fails=True), FakeBot("vex", ["python"])]
    budget = Budget(1.0)
    _sleeps, fake_sleep = stop_after(4)
    with pytest.raises(asyncio.CancelledError):
        await run_channel("python", 12, bots, budget, lambda ch: [], rng=random.Random(3), sleep=fake_sleep)
    assert len(bots[0].spoke) == 2 and len(bots[1].spoke) == 2  # they alternate; the failures cost nothing
    assert budget.spent == pytest.approx(0.02)


async def test_zero_per_hour_channel_never_runs():
    bot = FakeBot("pim", ["games"])
    await run_channel("games", 0, [bot], Budget(1.0), lambda ch: [])
    assert bot.spoke == []


class FakePlayer:
    """Records what it posts. A game that is `up` opens a lobby when it hears !start."""

    def __init__(self, nick, home=("games",), up=True):
        self.nick, self.home, self.up, self.match, self.posted = nick, set(home), up, {}, []

    async def post(self, channel, body):
        self.posted.append((channel, body))
        if body == "!start" and self.up:
            self.match = {"phase": "lobby"}
        return "ok"


async def no_sleep(seconds):
    pass


async def test_match_has_one_starter_and_six_joiners():
    bots = [FakePlayer(f"bot{i}") for i in range(42)] + [FakePlayer("outsider", home=["python"])]
    assert await start_match("games", 6, bots, rng=random.Random(1), sleep=no_sleep)
    played = [b for b in bots if b.posted]
    assert len(played) == 6 and bots[-1] not in played
    starters = [b for b in played if b.posted == [("games", "!start"), ("games", "!join")]]
    joiners = [b for b in played if b.posted == [("games", "!join")]]
    assert len(starters) == 1 and len(joiners) == 5


async def test_match_players_change_from_match_to_match():
    bots = [FakePlayer(f"bot{i}") for i in range(42)]
    rng = random.Random(1)
    await start_match("games", 6, bots, rng=rng, sleep=no_sleep)
    first = {b.nick for b in bots if b.posted}
    for b in bots:
        b.posted, b.match = [], {}
    await start_match("games", 6, bots, rng=rng, sleep=no_sleep)
    assert {b.nick for b in bots if b.posted} != first


async def test_nobody_joins_when_no_lobby_opens():
    bots = [FakePlayer(f"bot{i}", up=False) for i in range(8)]
    assert not await start_match("games", 6, bots, rng=random.Random(1), sleep=no_sleep)
    assert [body for b in bots for _channel, body in b.posted] == ["!start"]


async def test_stale_lobby_state_does_not_count_after_a_match_ends():
    bots = [FakePlayer(f"bot{i}", up=False) for i in range(8)]
    for b in bots:
        b.match = {"phase": "over"}
    assert not await start_match("games", 6, bots, rng=random.Random(1), sleep=no_sleep)


async def test_too_few_players_posts_nothing():
    bot = FakePlayer("pim")
    assert not await start_match("games", 6, [bot], sleep=no_sleep)
    assert bot.posted == []


async def test_fewer_bots_than_players_all_play():
    bots = [FakePlayer(f"bot{i}") for i in range(3)]
    assert await start_match("games", 6, bots, rng=random.Random(1), sleep=no_sleep)
    assert all(("games", "!join") in b.posted for b in bots)


def long_sleeps(sleeps):
    """The waits between matches, without the short pause inside each start."""
    return [s for s in sleeps if s > 10]


async def test_first_match_starts_at_startup_then_every_interval():
    bots = [FakePlayer(f"bot{i}") for i in range(8)]
    sleeps, fake_sleep = stop_after(6)
    with pytest.raises(asyncio.CancelledError):
        await run_matches("games", 6 * 3600, 6, bots, rng=random.Random(1), sleep=fake_sleep)
    assert long_sleeps(sleeps) == [30, 21600, 21600, 21600]
    assert sum(body == "!start" for b in bots for _channel, body in b.posted) == 3


async def test_matches_retry_sooner_while_the_game_is_down():
    bots = [FakePlayer(f"bot{i}", up=False) for i in range(8)]
    sleeps, fake_sleep = stop_after(4)
    with pytest.raises(asyncio.CancelledError):
        await run_matches("games", 6 * 3600, 6, bots, rng=random.Random(1), sleep=fake_sleep)
    assert long_sleeps(sleeps) == [30, 300, 300]


async def test_one_failed_start_does_not_stop_matches():
    class Broken(FakePlayer):
        async def post(self, channel, body):
            raise RuntimeError("boom")

    bots = [Broken(f"bot{i}") for i in range(8)]
    sleeps, fake_sleep = stop_after(3)
    with pytest.raises(asyncio.CancelledError):
        await run_matches("games", 6 * 3600, 6, bots, rng=random.Random(1), sleep=fake_sleep)
    assert long_sleeps(sleeps) == [30, 300, 300, 300]
