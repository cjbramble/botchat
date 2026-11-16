"""Post-deploy smoke test for chat.

Usage: VIEWER_URL=https://botchat.example.com INTERNAL_URL=ws://localhost:4001 \
       SMOKE_TOKEN=... uv run --with websockets python scripts/smoke.py

Against the cluster, first: kubectl -n botchat port-forward svc/chat 4001:4001
"""

import asyncio
import json
import os
import sys
import urllib.request

from websockets.asyncio.client import connect
from websockets.exceptions import InvalidStatus

VIEWER = os.environ.get("VIEWER_URL", "http://localhost:4000")
INTERNAL = os.environ.get("INTERNAL_URL", "ws://localhost:4001")
TOKEN = os.environ["SMOKE_TOKEN"]

results = []


def check(name, ok):
    results.append(ok)
    print(("PASS  " if ok else "FAIL  ") + name)


def http_status(url):
    try:
        return urllib.request.urlopen(url, timeout=10).status
    except OSError as exc:  # HTTPError carries a status; refused or timed out doesn't
        return getattr(exc, "code", None)


async def socket_accepts(token):
    url = f"{INTERNAL}/socket/websocket?vsn=2.0.0&token={token}"
    try:
        async with connect(url, open_timeout=10) as ws:
            await ws.send(json.dumps(["1", "1", "room:general", "phx_join", {}]))
            reply = json.loads(await asyncio.wait_for(ws.recv(), 10))
            return reply[3] == "phx_reply" and reply[4]["status"] == "ok"
    except InvalidStatus:
        return False


async def main():
    check("viewer loads", http_status(f"{VIEWER}/c/general") == 200)
    check(
        "internal health",
        http_status(INTERNAL.replace("ws", "http", 1) + "/healthz") == 200,
    )
    check("valid token joins #general", await socket_accepts(TOKEN))
    check("bad token is refused", not await socket_accepts("not-a-token"))
    check(
        "bot socket is not public",
        http_status(f"{VIEWER}/socket/websocket") in (404, None),
    )
    sys.exit(0 if all(results) else 1)


asyncio.run(main())
