import re
import tomllib
from pathlib import Path

import pytest

from bots.main import load_bots

PKG = Path(__file__).parent.parent / "bots"


def shipped():
    config = tomllib.loads((PKG / "config.toml").read_text())
    personas = tomllib.loads((PKG / "personas.toml").read_text())["bots"]
    return config, personas


def test_shipped_config_and_personas_line_up():
    config, personas = shipped()
    bots = load_bots(config, personas)
    assert len(bots) == 42
    assert len({b.nick for b in bots}) == 42
    channels = {c["name"] for c in config["channels"]}
    assert all(b.home <= channels for b in bots)


def test_shipped_personas_fit_env_var_names_and_live_in_games():
    _config, personas = shipped()
    for p in personas:
        assert re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{1,19}", p["nick"]), p["nick"]  # chat's nick rule, no "-"
        assert "games" in p["home"]
        assert 2 <= len(set(p["home"]) - {"games"}) <= 4
        for line in (p["persona"], p.get("work", ""), p.get("interests", "")):
            assert "\n" not in line
        assert p["persona"].startswith("You are ")


def test_shipped_channels_say_what_they_are_about_and_bots_have_something_to_say():
    config, personas = shipped()
    about = {c["name"]: c["about"] for c in config["channels"]}
    assert set(about.values()) <= {"work", "life", "both"}
    for bot in load_bots(config, personas):
        assert bot.about == about
        if any(about[ch] == "work" for ch in bot.home):
            assert bot.work, f"{bot.nick} is in a work channel without a job"


def test_load_bots_passes_work_and_interests_through():
    config = {
        "model_groups": [{"model": "a", "bots": 1}],
        "budget": {"max_output_tokens": 10},
        "channels": [{"name": "music", "per_hour": 15, "about": "life"}],
    }
    personas = [{"nick": "pim", "persona": "p", "work": "w", "interests": "i", "home": ["music"]}]
    (bot,) = load_bots(config, personas)
    assert (bot.work, bot.interests, bot.about) == ("w", "i", {"music": "life"})


def test_model_groups_are_assigned_in_order():
    config = {
        "model_groups": [{"model": "a", "bots": 2}, {"model": "b", "bots": 1}],
        "budget": {"max_output_tokens": 10},
    }
    personas = [{"nick": n, "persona": "p", "home": ["general"]} for n in ("pim", "vex", "luna")]
    bots = load_bots(config, personas)
    assert [(b.nick, b.model, b.max_tokens) for b in bots] == [
        ("pim", "a", 10),
        ("vex", "a", 10),
        ("luna", "b", 10),
    ]


def test_mismatched_counts_fail_loudly():
    config = {"model_groups": [{"model": "m", "bots": 2}], "budget": {"max_output_tokens": 10}}
    with pytest.raises(SystemExit):
        load_bots(config, [{"nick": "pim", "persona": "p", "home": ["general"]}])


def test_shipped_games_config_fits_the_bots():
    config, personas = shipped()
    games = config["games"]
    assert games["channel"] in {c["name"] for c in config["channels"]}
    assert games["every_hours"] > 0
    assert 2 <= games["players"] <= sum(games["channel"] in p["home"] for p in personas)
