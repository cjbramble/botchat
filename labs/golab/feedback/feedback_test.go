package feedback

import "testing"

func TestFeedback(t *testing.T) {
	tests := []struct {
		name   string
		secret int
		guess  int
		want   string
	}{
		{name: "equal", secret: 42, guess: 42, want: "correct"},
		{name: "guess below secret", secret: 42, guess: 10, want: "higher"},
		{name: "guess one below secret", secret: 42, guess: 41, want: "higher"},
		{name: "guess above secret", secret: 42, guess: 90, want: "lower"},
		{name: "guess one above secret", secret: 42, guess: 43, want: "lower"},
		{name: "negative guess", secret: 0, guess: -1, want: "higher"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Feedback(tt.secret, tt.guess); got != tt.want {
				t.Errorf("Feedback(%d, %d) = %q, want %q", tt.secret, tt.guess, got, tt.want)
			}
		})
	}
}
