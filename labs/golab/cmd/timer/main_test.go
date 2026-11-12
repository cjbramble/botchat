package main

import (
	"context"
	"io"
	"strings"
	"testing"
	"time"
)

func TestRun(t *testing.T) {
	// Long enough that a limit a case does not exercise never fires.
	const never = time.Minute

	// silent returns a reader that never yields data, like an idle terminal.
	silent := func(t *testing.T) io.Reader {
		r, w := io.Pipe()
		t.Cleanup(func() { w.Close() })
		return r
	}

	tests := []struct {
		name    string
		in      func(t *testing.T) io.Reader
		idle    time.Duration
		timeout time.Duration
		want    string
	}{
		{
			name:    "echoes upper-cased until stop",
			in:      func(*testing.T) io.Reader { return strings.NewReader("hello\nGo lab\nstop\nignored\n") },
			idle:    never,
			timeout: never,
			want:    "HELLO\nGO LAB\nstopped; echoed 2 line(s)\n",
		},
		{
			name:    "stop with surrounding spaces",
			in:      func(*testing.T) io.Reader { return strings.NewReader("  stop \n") },
			idle:    never,
			timeout: never,
			want:    "stopped; echoed 0 line(s)\n",
		},
		{
			name:    "stop inside a longer line is echoed",
			in:      func(*testing.T) io.Reader { return strings.NewReader("stop it\n") },
			idle:    never,
			timeout: never,
			want:    "STOP IT\nend of input; echoed 1 line(s)\n",
		},
		{
			name:    "end of input",
			in:      func(*testing.T) io.Reader { return strings.NewReader("a\n") },
			idle:    never,
			timeout: never,
			want:    "A\nend of input; echoed 1 line(s)\n",
		},
		{
			name:    "idle limit",
			in:      silent,
			idle:    20 * time.Millisecond,
			timeout: never,
			want:    "no input for 20ms; echoed 0 line(s)\n",
		},
		{
			name:    "context timeout",
			in:      silent,
			idle:    never,
			timeout: 20 * time.Millisecond,
			want:    "time limit reached; echoed 0 line(s)\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), tt.timeout)
			defer cancel()

			var out strings.Builder
			if err := run(ctx, tt.in(t), &out, tt.idle); err != nil {
				t.Fatalf("run() unexpected error: %v", err)
			}
			if got := out.String(); got != tt.want {
				t.Errorf("run() output = %q, want %q", got, tt.want)
			}
		})
	}
}
