defmodule Chat.RateLimitTest do
  use ExUnit.Case, async: true

  alias Chat.RateLimit

  @window_ms 200

  # Windows are fixed slices of the clock, so start right after a boundary
  # to keep every hit of one burst in the same window.
  defp wait_for_next_window do
    elapsed = Integer.mod(System.monotonic_time(:millisecond), @window_ms)
    Process.sleep(@window_ms - elapsed)
  end

  test "allow?/3 allows up to the limit, then again in the next window (CHAT-U-04)" do
    key = {:test, make_ref()}
    wait_for_next_window()

    assert RateLimit.allow?(key, 2, @window_ms)
    assert RateLimit.allow?(key, 2, @window_ms)
    refute RateLimit.allow?(key, 2, @window_ms)

    wait_for_next_window()
    assert RateLimit.allow?(key, 2, @window_ms)
  end
end
