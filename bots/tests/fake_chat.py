"""A tiny fake of chat + GameServ speaking Phoenix's V2 protocol, to test the smoke test itself."""

import asyncio
import json

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

TOPIC = "room:games"


async def fake_chat(port: int, rounds: int = 5, span: tuple[int, int] = (1, 100), drop: str | None = None):
    """Start the fake on `port` (0 picks a free one, see `server.port`) and return the server.

    `span` is the range sent as match_state before each turn. `drop` names a nick whose
    socket is closed once, at the start of round 2; the match waits for it to rejoin.
    The server records what it saw in `server.joined` and `server.guessed`, and sets
    `server.done` when the match is over.
    """
    conns = {}  # websocket -> nick (from the token)
    joins = []
    guesses = asyncio.Queue()
    joined = []  # (nick, topic) for every phx_join
    guessed = []  # (nick, body) for every guess
    done = asyncio.Event()
    matches = set()  # keeps the match task referenced while it runs

    async def send_all(event, payload):
        for ws in list(conns):
            await ws.send(json.dumps(["1", None, TOPIC, event, payload]))

    async def say(text):
        await send_all("new_msg", {"nick": "GameServ", "body": text})

    async def drop_and_wait_for_rejoin(nick):
        ws = next(w for w, n in conns.items() if n == nick)
        del conns[ws]
        await ws.close(1011)  # not a clean close, so the client sees a dropped socket
        while joined.count((nick, TOPIC)) < 2:
            await asyncio.sleep(0.05)

    async def gameserv():
        await say("New match of Guess the Number! Type !join in the next 1s.")
        while len(joins) < 2:
            await asyncio.sleep(0.05)
        lo, hi = span
        for r in range(1, rounds + 1):
            await say(f"Round {r} of {rounds}. I'm thinking of a number from 1-100.")
            if drop and r == 2:
                await drop_and_wait_for_rejoin(drop)
            for nick in joins:
                await send_all("match_state", {"phase": "playing", "lo": lo, "hi": hi})
                await say(f"{nick}, you're up (15s).")
                who, _ = await guesses.get()
                assert who == nick
            await say(f"The number was 50! {joins[0]} got it exactly: 50!")
        await say(f"Match over! {joins[0]} wins with {rounds} rounds.")
        done.set()

    async def handler(ws):
        nick = ws.request.path.split("token=")[1]
        conns[ws] = nick
        try:
            async for raw in ws:
                join_ref, ref, topic, event, payload = json.loads(raw)
                if event not in ("phx_join", "new_msg"):
                    continue
                await ws.send(
                    json.dumps([join_ref, ref, topic, "phx_reply", {"status": "ok", "response": {}}])
                )
                if event == "phx_join":
                    joined.append((nick, topic))
                elif payload["body"] == "!start":
                    task = asyncio.create_task(gameserv())
                    matches.add(task)
                    task.add_done_callback(matches.discard)
                elif payload["body"] == "!join":
                    joins.append(nick)
                else:
                    guessed.append((nick, payload["body"]))
                    await guesses.put((nick, payload["body"]))
        except ConnectionClosed:
            pass  # a client going away is part of the test
        finally:
            conns.pop(ws, None)

    server = await serve(handler, "127.0.0.1", port)
    server.port = server.sockets[0].getsockname()[1]
    server.joined, server.guessed, server.done = joined, guessed, done
    return server
