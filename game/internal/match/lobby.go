package match

import (
	"fmt"
	"slices"
	"strings"
)

func (m *Match) join(p PlayerID) []Effect {
	if slices.Contains(m.Players, p) {
		return nil // a second !join does nothing
	}
	m.Players = append(m.Players, p)
	return []Effect{Say{fmt.Sprintf("%s joined (%d players).", p, len(m.Players))}}
}

func (m *Match) startRound() []Effect {
	m.Round++
	m.Secret = m.cfg.Lo + m.rng.IntN(m.cfg.Hi-m.cfg.Lo+1)
	m.Lo, m.Hi = m.cfg.Lo, m.cfg.Hi
	m.Guesses = map[PlayerID]guess{}
	m.TurnIdx = 0
	m.Phase = TurnActive

	names := make([]string, len(m.Order))
	for i, p := range m.Order {
		names[i] = string(p)
	}
	head := Say{fmt.Sprintf("Round %d of %d. I'm thinking of a number from %d-%d. Turn order: %s.",
		m.Round, m.cfg.Rounds, m.cfg.Lo, m.cfg.Hi, strings.Join(names, ", "))}
	return append([]Effect{head}, m.promptTurn()...)
}

func (m *Match) promptTurn() []Effect {
	p := m.Order[m.TurnIdx]
	return []Effect{
		StartTimer{m.cfg.Turn}, // first, so anything announcing the turn knows the new deadline
		Say{fmt.Sprintf("%s, you're up (%s).", p, m.cfg.Turn)},
	}
}
