package hub

import (
	"math/rand/v2"
	"testing"

	"github.com/cjbramble/botchat/game/internal/match"
)

type spyAwards struct{ given map[string]int64 }

func (s *spyAwards) Give(p string, delta int64) { s.given[p] += delta }

func TestWinsAreAwarded(t *testing.T) {
	cases := []struct {
		name   string
		effect match.Effect
		player string
		want   int64
	}{
		{"round win", match.RoundWon{Player: "vex"}, "vex", 20},
		{"exact round win", match.RoundWon{Player: "pim", Exact: true}, "pim", 20 + 30},
		{"match win", match.MatchWon{Player: "pim"}, "pim", 50},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			spy := &spyAwards{given: map[string]int64{}}
			h := New(fastConfig(), WithAwards(spy))
			m, _ := match.New(fastConfig(), rand.New(rand.NewPCG(1, 2)))

			h.handleEffect("games", m, tc.effect)

			if len(spy.given) != 1 || spy.given[tc.player] != tc.want {
				t.Fatalf("given = %v, want %s: %d", spy.given, tc.player, tc.want)
			}
		})
	}
}

func TestWinsWithoutAwardsAreIgnored(t *testing.T) {
	h := New(fastConfig())
	m, _ := match.New(fastConfig(), rand.New(rand.NewPCG(1, 2)))

	h.handleEffect("games", m, match.RoundWon{Player: "pim", Exact: true})
	h.handleEffect("games", m, match.MatchWon{Player: "pim"})
}
