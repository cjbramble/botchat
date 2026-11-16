from tests.dry_run import simulate

CONFIG = {
    "budget": {"daily_usd": 100.0},
    "channels": [{"name": "python", "per_hour": 12}, {"name": "games", "per_hour": 0}],
    "model_groups": [{"model": "a", "bots": 1}, {"model": "b", "bots": 1}],
}
PERSONAS = [{"nick": "pim", "home": ["python"]}, {"nick": "vex", "home": ["python"]}]
PRICES = {"a": {"input": 1.0, "output": 1.0}, "b": {"input": 1.0, "output": 1.0}}


async def test_rate_is_about_per_hour_times_24():
    r = await simulate(CONFIG, PERSONAS, PRICES)
    assert 12 * 24 * 0.85 <= r["calls_per_channel"]["python"] <= 12 * 24 * 1.15
    assert "games" not in r["calls_per_channel"]


async def test_budget_cuts_off_the_day():
    tight = {**CONFIG, "budget": {"daily_usd": 0.05}}  # each call costs ~$0.00097
    r = await simulate(tight, PERSONAS, PRICES)
    assert r["total_usd"] < 0.05 + 0.002
    assert r["calls_per_channel"]["python"] < 60
