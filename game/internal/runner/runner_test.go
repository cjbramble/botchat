package runner

import (
	"context"
	"math/rand/v2"
	"testing"
	"time"

	"github.com/cjbramble/botchat/game/internal/match"
)

func testConfig() match.Config {
	return match.Config{Rounds: 1, Lo: 1, Hi: 100, MinPlayers: 2,
		// The join window is long enough that the queued joins are read before it closes.
		JoinWindow: 200 * time.Millisecond, Turn: 20 * time.Millisecond,
		RevealPause: 10 * time.Millisecond, Intermission: 10 * time.Millisecond}
}

func TestRunnerPlaysToTheEnd(t *testing.T) {
	m, initial := match.New(testConfig(), rand.New(rand.NewPCG(1, 2)))

	var said []string
	timers := 0
	r := New(m, func(_ context.Context, e match.Effect) {
		switch v := e.(type) {
		case match.Say:
			said = append(said, v.Text)
		case match.StartTimer:
			timers++
		}
	})
	r.Inputs <- Input{Player: "pim", Text: "!join", MsgID: "1"}
	r.Inputs <- Input{Player: "vex", Text: "!join", MsgID: "2"}
	r.Inputs <- Input{Player: "vex", Text: "!join", MsgID: "2"} // duplicate delivery

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	r.Run(ctx, initial) // nobody guesses: turns time out and the match ends

	if m.Phase != match.Over {
		t.Fatalf("match did not finish; said: %v", said)
	}
	if len(m.Players) != 2 {
		t.Fatalf("players = %v, want 2 (duplicate ignored)", m.Players)
	}
	// Lobby, two turns and the reveal each start the timer once.
	if timers != 4 {
		t.Fatalf("StartTimer forwarded %d times, want 4; said: %v", timers, said)
	}
}

func TestRunnerStopsWhenContextIsDone(t *testing.T) {
	cfg := testConfig()
	cfg.JoinWindow = time.Hour
	m, initial := match.New(cfg, rand.New(rand.NewPCG(1, 2)))
	r := New(m, func(context.Context, match.Effect) {})

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	r.Run(ctx, initial)

	if m.Phase != match.Lobby {
		t.Fatalf("phase = %v, want the match left in the lobby", m.Phase)
	}
}

type ctxKey struct{}

func TestEffectsCarryTheContextOfTheirCause(t *testing.T) {
	cfg := testConfig()
	cfg.JoinWindow = time.Hour // nothing but the input below happens
	m, initial := match.New(cfg, rand.New(rand.NewPCG(1, 2)))

	runCtx, cancel := context.WithCancel(context.WithValue(context.Background(), ctxKey{}, "run"))
	defer cancel()

	var causes []any
	r := New(m, func(ctx context.Context, e match.Effect) {
		if _, ok := e.(match.Say); ok {
			causes = append(causes, ctx.Value(ctxKey{}))
		}
		if len(causes) == 3 {
			cancel() // the lobby line and both joins are in
		}
	})
	r.Inputs <- Input{Player: "pim", Text: "!join", MsgID: "1",
		Ctx: context.WithValue(context.Background(), ctxKey{}, "pim's join")}
	r.Inputs <- Input{Player: "vex", Text: "!join", MsgID: "2"} // no context of its own

	r.Run(runCtx, initial)

	want := []any{"run", "pim's join", "run"}
	if len(causes) != len(want) {
		t.Fatalf("contexts = %v, want %v", causes, want)
	}
	for i := range want {
		if causes[i] != want[i] {
			t.Fatalf("contexts = %v, want %v", causes, want)
		}
	}
}
