// Package effects models the side effects a pure rules function asks its caller to perform.
package effects

import (
	"fmt"
	"time"
)

// Effect is a closed set of side effects: the unexported method stops other
// packages from adding implementations, so a type switch here can be exhaustive.
type Effect interface {
	isEffect()
}

// Say asks the caller to post Text.
type Say struct {
	Text string
}

// StartTimer asks the caller to start a timer that fires once After has elapsed.
type StartTimer struct {
	After time.Duration
}

func (Say) isEffect()        {}
func (StartTimer) isEffect() {}

// Describe returns a human-readable description of e.
func Describe(e Effect) string {
	switch e := e.(type) {
	case Say:
		return fmt.Sprintf("say %q", e.Text)
	case StartTimer:
		return fmt.Sprintf("start timer for %s", e.After)
	default:
		// Reached only by a nil Effect or a new variant missing a case above.
		return fmt.Sprintf("unknown effect %T", e)
	}
}
