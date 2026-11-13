package match

import "fmt"

// closest returns the round's winner: smallest distance, ties to the earlier guess.
func (m *Match) closest() (PlayerID, int, bool) {
	var best PlayerID
	bestDist, bestOrder, found := 0, 0, false
	// Map order is random, so ties are broken by the stored guess order.
	for p, g := range m.Guesses {
		d := g.value - m.Secret
		if d < 0 {
			d = -d
		}
		if !found || d < bestDist || (d == bestDist && g.order < bestOrder) {
			best, bestDist, bestOrder, found = p, d, g.order, true
		}
	}
	return best, bestDist, found
}

func (m *Match) endRound() []Effect {
	m.Phase = Reveal
	winner, dist, ok := m.closest()
	if !ok {
		return []Effect{
			Say{fmt.Sprintf("Nobody guessed. The number was %d.", m.Secret)},
			StartTimer{m.cfg.RevealPause},
		}
	}
	m.RoundWins[winner]++
	msg := fmt.Sprintf("The number was %d! %s was closest (off by %d).", m.Secret, winner, dist)
	if dist == 0 {
		msg = fmt.Sprintf("%s got it exactly: %d!", winner, m.Secret)
	}
	return []Effect{
		Say{msg},
		RoundWon{Player: winner, Round: m.Round, Exact: dist == 0, Distance: dist},
		StartTimer{m.cfg.RevealPause},
	}
}

func (m *Match) endMatch() []Effect {
	m.Phase = Over
	var best PlayerID
	bestWins := 0
	for _, p := range m.Players { // Players is in join order, so the earliest joiner wins ties
		if w := m.RoundWins[p]; w > bestWins {
			best, bestWins = p, w
		}
	}
	if bestWins == 0 {
		return []Effect{Say{"Match over! Nobody won a round."}}
	}
	return []Effect{
		Say{fmt.Sprintf("Match over! %s wins with %d rounds.", best, bestWins)},
		MatchWon{Player: best, RoundWins: bestWins},
	}
}
