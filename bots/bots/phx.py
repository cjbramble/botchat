"""A minimal Phoenix Channels client (V2 JSON serializer) on top of websockets."""

import asyncio
import itertools
import json
import logging
import random
from collections.abc import Awaitable, Callable

from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed

log = logging.getLogger(__name__)

Handler = Callable[[str, str, dict], Awaitable[None]]  # (topic, event, payload)

REPLY_TIMEOUT = 3.0  # seconds to wait for chat's phx_reply before calling a push lost


class PhoenixClient:
    def __init__(self, base_url: str, token: str, topics: list[str], on_event: Handler):
        self.url = f"{base_url}/socket/websocket?vsn=2.0.0&token={token}"
        self.topics = topics
        self.on_event = on_event
        self.refs = itertools.count(1)
        self.join_refs: dict[str, str] = {}
        self.pending: dict[str, asyncio.Future] = {}  # ref -> future waiting for its reply
        self.ws = None

    async def push(self, topic: str, event: str, payload: dict) -> None:
        """Send one frame and return. Nothing tells you whether chat got it."""
        await self._send(topic, str(next(self.refs)), event, payload)

    async def request(self, topic: str, event: str, payload: dict, timeout: float = REPLY_TIMEOUT) -> dict:
        """Send one frame and wait for chat's reply: {"status": "ok" | "error", "response": {...}}.

        Raises TimeoutError if no reply comes in time, ConnectionError if the socket is down.
        After a timeout the frame may or may not have arrived.
        """
        ref = str(next(self.refs))
        reply = asyncio.get_running_loop().create_future()
        self.pending[ref] = reply
        try:
            await self._send(topic, ref, event, payload)
            return await asyncio.wait_for(reply, timeout)
        finally:
            self.pending.pop(ref, None)

    async def _send(self, topic: str, ref: str, event: str, payload: dict) -> None:
        if self.ws is None:
            raise ConnectionError("not connected")
        try:
            await self.ws.send(json.dumps([self.join_refs.get(topic), ref, topic, event, payload]))
        except ConnectionClosed as exc:
            raise ConnectionError("socket closed while sending") from exc

    async def run_forever(self) -> None:
        """Connect, join every topic, dispatch events; reconnect with backoff on failure."""
        backoff = 1.0
        while True:
            try:
                async with connect(self.url) as ws:
                    self.ws = ws
                    self.join_refs = {}
                    for topic in self.topics:
                        ref = str(next(self.refs))
                        self.join_refs[topic] = ref
                        await ws.send(json.dumps([ref, ref, topic, "phx_join", {}]))
                    backoff = 1.0
                    heartbeat = asyncio.create_task(self._heartbeat(ws))
                    try:
                        async for raw in ws:
                            await self._dispatch(raw)
                    finally:
                        heartbeat.cancel()
            except (OSError, ConnectionClosed) as exc:
                log.warning("socket dropped (%s); reconnecting in %.0fs", exc, backoff)
            finally:
                self.ws = None
                self._fail_pending()
            # Jitter: 42 bots mustn't reconnect in sync.
            await asyncio.sleep(backoff + random.uniform(0, backoff))
            backoff = min(backoff * 2, 60)

    async def _dispatch(self, raw: str | bytes) -> None:
        _join_ref, ref, topic, event, payload = json.loads(raw)
        waiting = self.pending.get(ref) if event == "phx_reply" else None
        if waiting is None:
            await self.on_event(topic, event, payload)
        elif not waiting.done():
            waiting.set_result(payload)  # wakes up request()

    def _fail_pending(self) -> None:
        """The socket is gone, so no reply is coming: fail every waiting request now."""
        for reply in self.pending.values():
            if not reply.done():
                reply.set_exception(ConnectionError("socket closed before chat replied"))

    async def _heartbeat(self, ws) -> None:
        try:
            while True:
                await asyncio.sleep(30)
                await ws.send(json.dumps([None, str(next(self.refs)), "phoenix", "heartbeat", {}]))
        except ConnectionClosed:
            pass  # the receive loop sees the same close and reconnects
