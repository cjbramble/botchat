package match

import (
	"errors"
	"fmt"
)

func (m *Match) handleGuess(p PlayerID, text string) []Effect {
	if p != m.Order[m.TurnIdx] {
		return nil // not your turn
	}
	n, err := ParseGuess(text, m.cfg.Lo, m.cfg.Hi)
	if errors.Is(err, ErrOutOfRange) {
		return []Effect{Say{fmt.Sprintf("%s, pick a number from %d-%d.", p, m.cfg.Lo, m.cfg.Hi)}}
	}
	if err != nil {
		return nil // chatter, not a guess
	}

	m.Guesses[p] = guess{value: n, order: len(m.Guesses)}
	if n == m.Secret {
		return m.endRound()
	}

	var hint string
	if n < m.Secret {
		hint = fmt.Sprintf("Higher than %d.", n)
		m.Lo = max(m.Lo, n+1)
	} else {
		hint = fmt.Sprintf("Lower than %d.", n)
		m.Hi = min(m.Hi, n-1)
	}
	return append([]Effect{Say{hint}}, m.advanceTurn()...)
}

func (m *Match) advanceTurn() []Effect {
	m.TurnIdx++
	if m.TurnIdx >= len(m.Order) {
		return m.endRound() // everyone has guessed once
	}
	return m.promptTurn()
}
