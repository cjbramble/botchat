// Command timer echoes stdin lines upper-cased until it is told to stop,
// input goes quiet, or the overall deadline passes.
package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"strings"
	"time"
)

const (
	idleLimit  = 5 * time.Second
	totalLimit = 30 * time.Second
)

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), totalLimit)
	defer cancel()

	if err := run(ctx, os.Stdin, os.Stdout, idleLimit); err != nil {
		fmt.Fprintln(os.Stderr, "timer:", err)
		os.Exit(1)
	}
}

// run echoes lines from in to out upper-cased and returns when a line says
// "stop", in ends, no line arrives for idle, or ctx is done.
//
// The line counter lives only in this goroutine; the reader goroutine hands
// lines over a channel and shares no memory with it.
func run(ctx context.Context, in io.Reader, out io.Writer, idle time.Duration) error {
	lines := make(chan string)
	readErr := make(chan error, 1)
	done := make(chan struct{})
	defer close(done)

	go readLines(in, lines, readErr, done)

	timer := time.NewTimer(idle)
	defer timer.Stop()

	count := 0
	finish := func(reason string) error {
		_, err := fmt.Fprintf(out, "%s; echoed %d line(s)\n", reason, count)
		return err
	}

	for {
		select {
		case line, ok := <-lines:
			if !ok {
				if err := <-readErr; err != nil {
					return fmt.Errorf("read input: %w", err)
				}
				return finish("end of input")
			}
			if strings.TrimSpace(line) == "stop" {
				return finish("stopped")
			}
			if _, err := fmt.Fprintln(out, strings.ToUpper(line)); err != nil {
				return fmt.Errorf("write output: %w", err)
			}
			count++
			timer.Reset(idle)
		case <-timer.C:
			return finish(fmt.Sprintf("no input for %s", idle))
		case <-ctx.Done():
			return finish("time limit reached")
		}
	}
}

// readLines sends each line of in on lines, then reports the scan error (nil
// at a clean end of input) on readErr and closes lines. It gives up when done
// is closed so it never blocks on a receiver that has gone away. A read that
// is already blocked on in cannot be interrupted; process exit ends it.
func readLines(in io.Reader, lines chan<- string, readErr chan<- error, done <-chan struct{}) {
	defer close(lines)

	scanner := bufio.NewScanner(in)
	for scanner.Scan() {
		select {
		case lines <- scanner.Text():
		case <-done:
			return
		}
	}
	readErr <- scanner.Err()
}
