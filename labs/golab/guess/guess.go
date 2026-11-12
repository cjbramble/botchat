// Package guess parses a player's guess from chat text.
package guess

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
)

// ErrOutOfRange reports a guess that is a number but outside the allowed range.
var ErrOutOfRange = errors.New("guess out of range")

// ParseGuess parses text as a whole number in the inclusive range lo..hi.
//
// Surrounding spaces are ignored. Text that is not a number returns an error
// wrapping the strconv error; a number outside the range returns an error
// wrapping ErrOutOfRange.
func ParseGuess(text string, lo, hi int) (int, error) {
	n, err := strconv.Atoi(strings.TrimSpace(text))
	if err != nil {
		return 0, fmt.Errorf("parse guess %q: %w", text, err)
	}
	if n < lo || n > hi {
		return 0, fmt.Errorf("guess %d not in %d..%d: %w", n, lo, hi, ErrOutOfRange)
	}
	return n, nil
}
