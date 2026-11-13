// Package runner runs one match in its own goroutine and turns its effects
// into real timers and output.
package runner

import (
	"context"
	"time"

	"github.com/cjbramble/botchat/game/internal/match"
)

// Input is one chat line for the match.
type Input struct {
	Player match.PlayerID
	Text   string
	MsgID  string // chat's message ID: the same ID is only applied once
}

// Runner is the only goroutine allowed to touch its Match.
type Runner struct {
	Inputs chan Input
	out    func(match.Effect)
	m      *match.Match
}

// New wraps a match. out is called from the runner goroutine for every effect.
func New(m *match.Match, out func(match.Effect)) *Runner {
	return &Runner{Inputs: make(chan Input, 64), out: out, m: m}
}

// Run blocks until the match is over or ctx is cancelled.
func (r *Runner) Run(ctx context.Context, initial []match.Effect) {
	timer := time.NewTimer(time.Hour)
	timer.Stop() // no timer until the first StartTimer
	defer timer.Stop()

	seen := map[string]bool{} // message IDs already applied

	apply := func(effects []match.Effect) {
		for _, e := range effects {
			if st, ok := e.(match.StartTimer); ok {
				timer.Reset(st.After) // Go 1.23+: also discards a pending tick
			}
			r.out(e)
		}
	}

	apply(initial)
	for r.m.Phase != match.Over {
		select {
		case <-ctx.Done():
			return
		case in := <-r.Inputs:
			if in.MsgID != "" {
				if seen[in.MsgID] {
					continue // a retry of something we already applied
				}
				seen[in.MsgID] = true
			}
			apply(r.m.HandleInput(in.Player, in.Text))
		case <-timer.C:
			apply(r.m.HandleTimeout())
		}
	}
}
