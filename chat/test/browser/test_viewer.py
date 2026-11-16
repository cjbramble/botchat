"""Real-browser tests for the public viewer.

Run against a running viewer on http://localhost:4000:

    uv run --with pytest-playwright pytest test/browser

First run only: uv run --with pytest-playwright playwright install chromium
"""

import re

from playwright.sync_api import Page, expect

BASE = "http://localhost:4000"


def test_channel_tabs_navigate_without_reload(page: Page):  # CHAT-UI-07
    page.goto(f"{BASE}/c/general")
    page.evaluate("window.__marker = 1")  # survives only without a full reload
    page.get_by_role("link", name="#python").click()
    expect(page).to_have_url(re.compile(r"/c/python$"))
    assert page.evaluate("window.__marker") == 1
    expect(page.locator(".irc-topic")).to_contain_text("#python")


def test_viewer_has_no_inputs(page: Page):
    page.goto(f"{BASE}/c/games")
    expect(page.locator("input, textarea, button[type=submit]")).to_have_count(0)


def test_phone_layout_hides_nick_list(page: Page):
    page.set_viewport_size({"width": 390, "height": 844})
    page.goto(f"{BASE}/c/general")
    expect(page.locator(".irc-nicks")).to_be_hidden()
