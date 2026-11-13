// Package match holds the rules of Guess the Number.
// It never sleeps, reads the clock, or does I/O: the runner does those.
package match

import (
	"fmt"
	"math/rand/v2"
	"slices"
	"strings"
)

// Phase is where the match is. Each phase ends with a timer, except Over.
type Phase int

const (
	Lobby Phase = iota
	TurnActive
	Reveal
	Intermission
	Over
)

// PlayerID is a player's chat nick.
type PlayerID string

type guess struct{ value, order int }

// Match is one game in one channel. Only the runner goroutine may touch it.
type Match struct {
	cfg       Config
	rng       *rand.Rand
	Phase     Phase
	Round     int
	Secret    int
	Lo, Hi    int // range still possible, narrowed by higher/lower feedback
	Players   []PlayerID
	Order     []PlayerID // this round's turn order
	TurnIdx   int
	Guesses   map[PlayerID]guess
	RoundWins map[PlayerID]int
}

// New creates a match in the lobby and returns the effects that open it.
func New(cfg Config, rng *rand.Rand) (*Match, []Effect) {
	m := &Match{cfg: cfg, rng: rng, Phase: Lobby, RoundWins: map[PlayerID]int{}}
	return m, []Effect{
		StartTimer{cfg.JoinWindow}, // timers first, so the announcement carries the deadline
		Say{fmt.Sprintf("New match of Guess the Number! Type !join in the next %s.", cfg.JoinWindow)},
	}
}

// HandleInput applies one chat line from a player.
func (m *Match) HandleInput(p PlayerID, text string) []Effect {
	text = strings.TrimSpace(text)
	switch m.Phase {
	case Lobby:
		if text == "!join" {
			return m.join(p)
		}
	case TurnActive:
		return m.handleGuess(p, text)
	}
	return nil
}

// HandleTimeout applies the match's timer firing.
func (m *Match) HandleTimeout() []Effect {
	switch m.Phase {
	case Lobby:
		if len(m.Players) < m.cfg.MinPlayers {
			m.Phase = Over
			return []Effect{Say{"Not enough players joined. Type !start to try again."}}
		}
		m.Order = slices.Clone(m.Players)
		return m.startRound()
	case TurnActive:
		p := m.Order[m.TurnIdx]
		return append([]Effect{Say{fmt.Sprintf("%s ran out of time.", p)}}, m.advanceTurn()...)
	case Reveal:
		if m.Round >= m.cfg.Rounds {
			return m.endMatch()
		}
		m.Phase = Intermission
		return []Effect{
			Say{fmt.Sprintf("Round %d starts in %s...", m.Round+1, m.cfg.Intermission)},
			StartTimer{m.cfg.Intermission},
		}
	case Intermission:
		m.Order = append(slices.Clone(m.Order[1:]), m.Order[0]) // rotate who goes first
		return m.startRound()
	}
	return nil
}
