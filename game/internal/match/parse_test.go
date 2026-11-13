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
