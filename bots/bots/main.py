"""Entry point: load config, build 42 bots, run sockets and directors together."""

import asyncio
import logging
import os
import tomllib
from pathlib import Path

from . import tracing
from .bot import Bot
from .budget import Budget
from .director import run_channel, run_matches
from .phx import PhoenixClient


def load_bots(config: dict, personas: list[dict]) -> list[Bot]:
    """Assign personas to model groups in order: the first `bots` personas get the first model, and so on."""
    models = [g["model"] for g in config["model_groups"] for _ in range(g["bots"])]
    if len(models) != len(personas):
        raise SystemExit(f"{len(personas)} personas but model_groups add up to {len(models)} bots")
    max_tokens = config["budget"]["max_output_tokens"]
    about = {c["name"]: c["about"] for c in config.get("channels", [])}
    return [
        Bot(
            nick=p["nick"],
            persona=p["persona"],
            work=p.get("work", ""),
            interests=p.get("interests", ""),
            about=about,
            model=model,
            home=set(p["home"]),
            max_tokens=max_tokens,
        )
        for p, model in zip(personas, models)
    ]


async def main() -> None:
    tracing.setup()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    root = Path(__file__).parent
    config = tomllib.loads((root / "config.toml").read_text())
    personas = tomllib.loads((root / "personas.toml").read_text())["bots"]
    bots = load_bots(config, personas)
    budget = Budget(config["budget"]["daily_usd"])
    chat_url = os.environ.get("CHAT_URL", "ws://localhost:4001")

    def history(channel: str) -> list[str]:  # any member's view of the channel will do
        for b in bots:
            if b.history.get(channel):
                return list(b.history[channel])
        return []

    async with asyncio.TaskGroup() as tg:
        for b in bots:
            b.budget = budget
            token = os.environ[f"BOT_TOKEN_{b.nick.upper()}"]
            b.client = PhoenixClient(chat_url, token, [f"room:{c}" for c in sorted(b.home)], b.on_event)
            tg.create_task(b.client.run_forever())
        for ch in config["channels"]:
            members = [b for b in bots if ch["name"] in b.home]
            tg.create_task(run_channel(ch["name"], ch["per_hour"], members, budget, history))
        games = config["games"]
        tg.create_task(run_matches(games["channel"], games["every_hours"] * 3600, games["players"], bots))


if __name__ == "__main__":
    asyncio.run(main())
