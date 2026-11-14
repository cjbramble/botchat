package hub

import (
	"testing"
	"time"

	"github.com/cjbramble/botchat/game/internal/match"
	"github.com/cjbramble/botchat/game/internal/runner"
)

func fastConfig() match.Config {
	return match.Config{Rounds: 1, Lo: 1, Hi: 100, MinPlayers: 2,
		JoinWindow: 50 * time.Millisecond, Turn: 20 * time.Millisecond,
		RevealPause: 10 * time.Millisecond, Intermission: 10 * time.Millisecond}
}

func TestStartAndSubscribe(t *testing.T) {
	h := New(fastConfig())
	msgs, stop := h.Subscribe("games")
	defer stop()

	h.Submit("games", runner.Input{Player: "pim", Text: "!start"})

	select {
	case m := <-msgs:
		if m.Seq != 1 {
			t.Fatalf("first message should have seq 1, got %d", m.Seq)
		}
	case <-time.After(time.Second):
		t.Fatal("no announcement received")
	}
}

func TestInputsWithoutAMatchAreIgnored(t *testing.T) {
	h := New(fastConfig())
	msgs, stop := h.Subscribe("games")
	defer stop()

	h.Submit("games", runner.Input{Player: "pim", Text: "50"})

	select {
	case m := <-msgs:
		t.Fatalf("expected silence, got %q", m.Text)
	case <-time.After(100 * time.Millisecond):
	}
}

func TestSlowSubscriberDoesNotBlock(t *testing.T) {
	h := New(fastConfig())
	_, stopSlow := h.Subscribe("games") // never reads
	defer stopSlow()

	done := make(chan struct{})
	go func() {
		for i := 0; i < 1000; i++ { // far more than the 32-message buffer
			h.broadcast("games", "line")
		}
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("broadcast blocked on a slow subscriber")
	}
}
