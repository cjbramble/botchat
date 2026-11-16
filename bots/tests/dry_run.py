"""Cost dry run: simulate one day of the real director with fake LLM calls, in about a second.

Usage:  uv run python -m tests.dry_run prices.toml
prices.toml maps each model in config.toml to its USD price per 1M input/output tokens.
"""

import asyncio
import heapq
import random
import sys
import tomllib
from collections import Counter
from datetime import UTC, datetime, timedelta
from pathlib import Path

from bots.budget import Budget
from bots.director import run_channel

DAY = 24 * 3600
TOKENS_IN, TOKENS_OUT = 850, 120  # per call: persona + 15 lines of history in, one line out


class VirtualTime:
    """Fake asyncio.sleep: time jumps straight to the next wake-up instead of waiting."""

    def __init__(self):
        self.now, self._heap, self._n = 0.0, [], 0

    async def sleep(self, seconds: float) -> None:
        fut = asyncio.get_running_loop().create_future()
        heapq.heappush(self._heap, (self.now + seconds, self._n, fut))
        self._n += 1
        await fut

    async def run_until(self, end: float) -> None:
        while True:
            for _ in range(10):  # let woken tasks run to their next sleep
                await asyncio.sleep(0)
            if not self._heap or self._heap[0][0] > end:
                return
            self.now, _, fut = heapq.heappop(self._heap)
            fut.set_result(None)


class SimBot:
    def __init__(self, nick, home, model, price, log):
        self.nick, self.home, self.model, self.price, self.log = nick, set(home), model, price, log

    async def speak(self, channel: str) -> float:
        cost = (TOKENS_IN * self.price["input"] + TOKENS_OUT * self.price["output"]) / 1_000_000
        self.log.append((channel, self.model, cost))
        return cost


async def simulate(config: dict, personas: list[dict], prices: dict) -> dict:
    vt = VirtualTime()
    start = datetime(2026, 1, 1, tzinfo=UTC)
    budget = Budget(config["budget"]["daily_usd"], clock=lambda: start + timedelta(seconds=vt.now))
    budget.wait_for_reset = lambda: vt.sleep(budget.seconds_until_reset() + 1)

    models = [g["model"] for g in config["model_groups"] for _ in range(g["bots"])]
    log: list = []
    bots = [SimBot(p["nick"], p["home"], m, prices[m], log) for p, m in zip(personas, models)]
    rng = random.Random(7)
    tasks = [
        asyncio.create_task(
            run_channel(
                ch["name"],
                ch["per_hour"],
                [b for b in bots if ch["name"] in b.home],
                budget,
                lambda _c: [],
                rng=rng,
                sleep=vt.sleep,
            )
        )
        for ch in config["channels"]
    ]
    await vt.run_until(DAY)
    for t in tasks:
        t.cancel()
    return {
        "calls_per_channel": Counter(c for c, _, _ in log),
        "cost_per_model": {m: sum(x for _, mm, x in log if mm == m) for m in {m for _, m, _ in log}},
        "total_usd": sum(x for _, _, x in log),
    }


def main() -> None:
    root = Path(__file__).resolve().parents[1] / "bots"
    config = tomllib.loads((root / "config.toml").read_text())
    personas = tomllib.loads((root / "personas.toml").read_text())["bots"]
    prices = tomllib.loads(Path(sys.argv[1]).read_text())
    result = asyncio.run(simulate(config, personas, prices))
    limits = {c["name"]: c["per_hour"] * 24 for c in config["channels"]}
    print("channel        calls/day  limit")
    for ch, n in sorted(result["calls_per_channel"].items()):
        print(f"#{ch:<13} {n:>9}  {limits[ch]:>5}")
    for m, usd in sorted(result["cost_per_model"].items()):
        print(f"{m:<28} ${usd:7.3f}")
    print(f"total ${result['total_usd']:.3f} / budget ${config['budget']['daily_usd']:.2f}")


if __name__ == "__main__":
    main()
