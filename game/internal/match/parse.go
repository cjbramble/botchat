package match

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
)

// ErrOutOfRange means the input was a number, but outside the allowed range.
var ErrOutOfRange = errors.New("out of range")

// ParseGuess accepts a whole number between lo and hi, with optional spaces around it.
func ParseGuess(text string, lo, hi int) (int, error) {
	n, err := strconv.Atoi(strings.TrimSpace(text))
	if errors.Is(err, strconv.ErrRange) { // too big for an int is still a number
		return 0, fmt.Errorf("%q is not in %d-%d: %w", text, lo, hi, ErrOutOfRange)
	}
	if err != nil {
		return 0, fmt.Errorf("not a number %q: %w", text, err)
	}
	if n < lo || n > hi {
		return 0, fmt.Errorf("%d is not in %d-%d: %w", n, lo, hi, ErrOutOfRange)
	}
	return n, nil
}
