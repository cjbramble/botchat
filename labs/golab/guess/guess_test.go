package guess

import (
	"errors"
	"strconv"
	"testing"
)

func TestParseGuess(t *testing.T) {
	const lo, hi = 1, 100

	tests := []struct {
		name    string
		text    string
		want    int
		wantErr error // nil means success; otherwise matched with errors.Is
	}{
		{name: "plain number", text: "42", want: 42},
		{name: "surrounding spaces", text: "  42 ", want: 42},
		{name: "lower bound", text: "1", want: 1},
		{name: "upper bound", text: "100", want: 100},
		{name: "inner space", text: "4 2", wantErr: strconv.ErrSyntax},
		{name: "word", text: "forty", wantErr: strconv.ErrSyntax},
		{name: "empty", text: "", wantErr: strconv.ErrSyntax},
		{name: "below range", text: "0", wantErr: ErrOutOfRange},
		{name: "above range", text: "101", wantErr: ErrOutOfRange},
		{name: "negative", text: "-3", wantErr: ErrOutOfRange},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseGuess(tt.text, lo, hi)

			if tt.wantErr == nil {
				if err != nil {
					t.Fatalf("ParseGuess(%q) unexpected error: %v", tt.text, err)
				}
				if got != tt.want {
					t.Errorf("ParseGuess(%q) = %d, want %d", tt.text, got, tt.want)
				}
				return
			}

			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("ParseGuess(%q) error = %v, want errors.Is %v", tt.text, err, tt.wantErr)
			}
			// Syntax errors must not be mistaken for range errors, or vice versa.
			if isRange := errors.Is(err, ErrOutOfRange); isRange != (tt.wantErr == ErrOutOfRange) {
				t.Errorf("ParseGuess(%q) errors.Is(err, ErrOutOfRange) = %t", tt.text, isRange)
			}
			if got != 0 {
				t.Errorf("ParseGuess(%q) = %d on error, want 0", tt.text, got)
			}
		})
	}
}
