package match

import "testing"

// FuzzParseGuess checks that the parser never panics, accepts only values
// inside the range, and returns zero with every error.
func FuzzParseGuess(f *testing.F) {
	seeds := []string{
		"42", "  42 ", " 7 ", "+42", "0", "101", "-3", "4 2", "forty", "",
		"99999999999999999999", "9999999999999999999999", "٤٢",
	}
	for _, seed := range seeds {
		f.Add(seed, 1, 100)
	}
	f.Fuzz(func(t *testing.T, text string, lo, hi int) {
		got, err := ParseGuess(text, lo, hi) // must not panic
		if err == nil && (got < lo || got > hi) {
			t.Fatalf("ParseGuess(%q, %d, %d) accepted %d, outside the range", text, lo, hi, got)
		}
		if err != nil && got != 0 {
			t.Fatalf("ParseGuess(%q, %d, %d) = %d with error %v, want 0", text, lo, hi, got, err)
		}
	})
}

// FuzzMatchAlwaysEnds checks that a whole match ends, whatever players type.
func FuzzMatchAlwaysEnds(f *testing.F) {
	f.Add("50", "abc", "101", uint64(1))
	f.Fuzz(func(t *testing.T, a, b, c string, seed uint64) {
		m := started(t, 2, int(seed%100)+1, "pim", "vex")
		inputs := []string{a, b, c}
		for steps := 0; m.Phase != Over && steps < 200; steps++ {
			if m.Phase == TurnActive {
				m.HandleInput(m.Order[m.TurnIdx], inputs[steps%3])
			}
			m.HandleTimeout()
		}
		if m.Phase != Over {
			t.Fatalf("match did not end with inputs %q %q %q", a, b, c)
		}
	})
}
