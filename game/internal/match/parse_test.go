package match

import (
	"errors"
	"testing"
)

func TestParseGuess(t *testing.T) {
	cases := []struct {
		in         string
		want       int
		wantErr    bool
		outOfRange bool
	}{
		{"42", 42, false, false},
		{"  42 ", 42, false, false},
		{"1", 1, false, false},
		{"100", 100, false, false},
		{"4 2", 0, true, false},
		{"forty", 0, true, false},
		{"", 0, true, false},
		{"0", 0, true, true},
		{"101", 0, true, true},
		{"-3", 0, true, true},
		{"+42", 42, false, false},
		{"99999999999999999999", 0, true, true},
		{"-99999999999999999999", 0, true, true},
	}
	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			got, err := ParseGuess(tc.in, 1, 100)
			if (err != nil) != tc.wantErr || errors.Is(err, ErrOutOfRange) != tc.outOfRange || got != tc.want {
				t.Fatalf("ParseGuess(%q) = %d, %v", tc.in, got, err)
			}
		})
	}
}

func FuzzParseGuess(f *testing.F) {
	for _, seed := range []string{"42", "  42 ", "+42", "0", "101", "-3", "4 2", "forty", "", "99999999999999999999"} {
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
