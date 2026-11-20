// Package xp turns match results into experience points and levels, and
// stores players' XP in Postgres.
package xp

import "math"

// XP awarded per result.
const (
	RoundWin = 20
	ExactHit = 30 // on top of RoundWin
	MatchWin = 50
)

// LevelFor: level 1 at 0 XP, level 2 at 50, level 3 at 200, level 4 at 450...
func LevelFor(xp int64) int {
	if xp < 0 {
		xp = 0
	}
	return int(math.Sqrt(float64(xp)/50)) + 1
}
