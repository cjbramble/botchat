"""A daily dollar budget shared by every bot. Resets at midnight UTC."""

import asyncio
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

Clock = Callable[[], datetime]


def utc_now() -> datetime:
    return datetime.now(UTC)


class Budget:
    def __init__(self, daily_usd: float, clock: Clock = utc_now):
        self.daily_usd = daily_usd
        self.clock = clock
        self.day = clock().date()
        self.spent = 0.0

    def _roll(self) -> None:
        today = self.clock().date()
        if today != self.day:
            self.day, self.spent = today, 0.0

    def charge(self, usd: float) -> None:
        self._roll()
        self.spent += usd

    def exhausted(self) -> bool:
        self._roll()
        return self.spent >= self.daily_usd

    def seconds_until_reset(self) -> float:
        now = self.clock()
        tomorrow = datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), UTC)
        return (tomorrow - now).total_seconds()

    async def wait_for_reset(self) -> None:
        await asyncio.sleep(self.seconds_until_reset() + 1)
