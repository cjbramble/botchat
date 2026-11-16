"""End-to-end smoke test: two test bots play one full match through the real stack.

Usage:
    CHAT_URL=ws://localhost:4001 SMOKE_TOKEN_A=... SMOKE_TOKEN_B=... uv run python -m tests.smoke
Exit code 0 means pass. Create bots named smoke_a and smoke_b first (Step 2, admin from IEx).
"""

import asyncio
import os
import re
import sys

from bots.phx import PhoenixClient

TIMEOUT = float(os.environ.get("SMOKE_TIMEOUT", "480"))  # 5 rounds with default timers: 3-5 min
ROUND_START = re.compile(r"^Round \d+ of \d+\.")


async def run(url: str, token_a: str, token_b: str) -> int:
    seen: list[str] = []
    done = asyncio.Event()
    clients: dict[str, PhoenixClient] = {}

    async def watch(topic, event, payload):
        """Only smoke_a's socket reacts, so each GameServ line is handled once."""
        if event != "new_msg" or payload.get("nick") != "GameServ":
            return
        text = payload["body"]
        seen.append(text)
        print("GameServ:", text, flush=True)
        for nick, client in clients.items():
            if text.startswith(f"{nick}, you're up"):
                await client.push("room:games", "new_msg", {"body": "50"})
        if text.startswith(("Match over!", "Not enough players")):
            done.set()

    async def ignore(*_):
        pass

    clients["smoke_a"] = PhoenixClient(url, token_a, ["room:games"], watch)
    clients["smoke_b"] = PhoenixClient(url, token_b, ["room:games"], ignore)
    tasks = [asyncio.create_task(c.run_forever()) for c in clients.values()]
    a, b = clients["smoke_a"], clients["smoke_b"]
    try:
        await asyncio.sleep(2)  # let both sockets connect and join
        await a.push("room:games", "new_msg", {"body": "!start"})
        await asyncio.sleep(2.5)  # stay under the per-bot limit in #games
        await a.push("room:games", "new_msg", {"body": "!join"})
        await b.push("room:games", "new_msg", {"body": "!join"})
        await asyncio.wait_for(done.wait(), TIMEOUT)
    except TimeoutError:
        print("FAIL: the match did not finish in time", file=sys.stderr)
        return 1
    finally:
        for t in tasks:
            t.cancel()

    checks = {
        "lobby opened": any("!join" in s for s in seen),
        "5 rounds started": sum(bool(ROUND_START.match(s)) for s in seen) == 5,
        "both players prompted": all(any(s.startswith(f"{n}, you're up") for s in seen) for n in clients),
        "match ended with a winner": any(s.startswith("Match over!") and "wins" in s for s in seen),
    }
    for name, ok in checks.items():
        print(("PASS  " if ok else "FAIL  ") + name)
    return 0 if all(checks.values()) else 1


def main() -> None:
    url = os.environ.get("CHAT_URL", "ws://localhost:4001")
    sys.exit(asyncio.run(run(url, os.environ["SMOKE_TOKEN_A"], os.environ["SMOKE_TOKEN_B"])))


if __name__ == "__main__":
    main()
