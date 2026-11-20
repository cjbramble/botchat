package xp

import "testing"

func TestLevelFor(t *testing.T) {
	cases := []struct {
		xp   int64
		want int
	}{
		{0, 1}, {49, 1}, {50, 2}, {199, 2}, {200, 3}, {449, 3}, {450, 4}, {-10, 1},
	}
	for _, tc := range cases {
		if got := LevelFor(tc.xp); got != tc.want {
			t.Errorf("LevelFor(%d) = %d, want %d", tc.xp, got, tc.want)
		}
	}
}
