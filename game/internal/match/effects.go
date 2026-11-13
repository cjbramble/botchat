package match

import "time"

// Effect describes something that should happen. The runner carries it out.
// The unexported method means only this package can define effects.
type Effect interface{ effect() }

// Say posts a line in the game channel as GameServ.
type Say struct{ Text string }

// StartTimer replaces the match's single timer: when it fires, the runner
// calls HandleTimeout.
type StartTimer struct{ After time.Duration }

// RoundWon reports a round result, for awarding XP.
type RoundWon struct {
	Player   PlayerID
	Round    int
	Exact    bool
	Distance int
}

// MatchWon reports the match winner, for awarding XP.
type MatchWon struct {
	Player    PlayerID
	RoundWins int
}

func (Say) effect()        {}
func (StartTimer) effect() {}
func (RoundWon) effect()   {}
func (MatchWon) effect()   {}
