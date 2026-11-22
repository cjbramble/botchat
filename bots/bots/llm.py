"""One shared OpenRouter client. OpenRouter speaks the OpenAI chat-completions API."""

import os
from dataclasses import dataclass

from openai import AsyncOpenAI

_client = None


def client() -> AsyncOpenAI:
    """The shared client, created on first use so imports don't need the API key."""
    global _client
    if _client is None:
        _client = AsyncOpenAI(
            base_url="https://openrouter.ai/api/v1",
            api_key=os.environ["OPENROUTER_API_KEY"],
            timeout=15,
            max_retries=2,
        )
    return _client


@dataclass
class Reply:
    text: str
    cost_usd: float
    tokens: int
    finish_reason: str = ""  # why the model stopped: "stop", or "length" at the token cap


async def complete(model: str, system: str, lines: list[str], max_tokens: int) -> Reply:
    """Ask `model` for a reply to the recent channel `lines` under the `system` prompt."""
    resp = await client().chat.completions.create(
        model=model,
        max_tokens=max_tokens,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": "\n".join(lines) or "(the channel is quiet)"},
        ],
    )
    usage = resp.usage
    cost = getattr(usage, "cost", None) or 0.0  # OpenRouter adds `cost` (USD) to usage
    choice = resp.choices[0]
    text = (choice.message.content or "").strip()
    return Reply(
        text=text,
        cost_usd=float(cost),
        tokens=getattr(usage, "total_tokens", 0) or 0,
        finish_reason=choice.finish_reason or "",
    )
