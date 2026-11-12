package effects

import (
	"testing"
	"time"
)

func TestDescribe(t *testing.T) {
	tests := []struct {
		name   string
		effect Effect
		want   string
	}{
		{name: "say", effect: Say{Text: "hello"}, want: `say "hello"`},
		{name: "say empty", effect: Say{}, want: `say ""`},
		{name: "start timer seconds", effect: StartTimer{After: 5 * time.Second}, want: "start timer for 5s"},
		{name: "start timer mixed units", effect: StartTimer{After: 90 * time.Second}, want: "start timer for 1m30s"},
		{name: "nil", effect: nil, want: "unknown effect <nil>"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Describe(tt.effect); got != tt.want {
				t.Errorf("Describe(%#v) = %q, want %q", tt.effect, got, tt.want)
			}
		})
	}
}
