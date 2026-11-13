package match

import "time"

// Config holds the tunable rules. Tests use short durations; production
// uses DefaultConfig.
type Config struct {
	Rounds                    int
	Lo, Hi                    int // the secret is in Lo..Hi inclusive
	MinPlayers                int
	JoinWindow, Turn          time.Duration
	RevealPause, Intermission time.Duration
}

// DefaultConfig is the pacing described in the rules.
func DefaultConfig() Config {
	return Config{
		Rounds: 5, Lo: 1, Hi: 100, MinPlayers: 2,
		JoinWindow: 20 * time.Second, Turn: 15 * time.Second,
		RevealPause: 5 * time.Second, Intermission: 10 * time.Second,
	}
}
