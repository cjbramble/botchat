// Package hub maps chat channels to running matches and fans GameServ's
// lines out to subscribers.
package hub

import (
	"context"
	"log/slog"
	"math/rand/v2"
	"strings"
	"sync"
	"time"

	gamev1 "github.com/cjbramble/botchat/game/gen/game/v1"
	"github.com/cjbramble/botchat/game/internal/match"
	"github.com/cjbramble/botchat/game/internal/runner"
	"github.com/cjbramble/botchat/game/internal/xp"
)

// Awards receives XP for players. *award.Awarder implements it. ctx carries
// the trace of the input that earned the XP.
type Awards interface {
	Give(ctx context.Context, player string, delta int64)
}

// Hub is safe for concurrent use.
type Hub struct {
	mu       sync.Mutex
	cfg      match.Config
	awards   Awards // optional; set once by New, then only read
	channels map[string]*channelState
}

// Option configures a Hub.
type Option func(*Hub)

// WithAwards gives XP for round and match wins.
func WithAwards(a Awards) Option {
	return func(h *Hub) { h.awards = a }
}

type channelState struct {
	runner   *runner.Runner // nil when no match is running
	subs     map[int]chan *gamev1.GameMessage
	nextID   int
	seq      int64
	deadline time.Time // when the current timer fires, for the viewer's countdown
}

// New creates a hub whose matches use cfg.
func New(cfg match.Config, opts ...Option) *Hub {
	h := &Hub{cfg: cfg, channels: map[string]*channelState{}}
	for _, opt := range opts {
		opt(h)
	}
	return h
}

// state returns the channel's state, creating it on first use. Caller holds h.mu.
func (h *Hub) state(ch string) *channelState {
	st, ok := h.channels[ch]
	if !ok {
		st = &channelState{subs: map[int]chan *gamev1.GameMessage{}}
		h.channels[ch] = st
	}
	return st
}

// Submit routes one chat line to the channel's match, starting one on "!start".
func (h *Hub) Submit(ch string, in runner.Input) {
	h.mu.Lock()
	st := h.state(ch)
	if st.runner == nil {
		if strings.TrimSpace(in.Text) == "!start" {
			h.startMatch(ch, st)
		}
		h.mu.Unlock()
		return
	}
	r := st.runner
	h.mu.Unlock()

	select {
	case r.Inputs <- in:
	default:
		slog.Warn("input dropped: runner busy", "channel", ch)
	}
}

// startMatch creates a match and runs it in its own goroutine. Caller holds h.mu.
func (h *Hub) startMatch(ch string, st *channelState) {
	seed := uint64(time.Now().UnixNano())
	m, initial := match.New(h.cfg, rand.New(rand.NewPCG(seed, seed>>1)))
	// The callback runs on the runner goroutine, so reading m inside it is safe.
	r := runner.New(m, func(ctx context.Context, e match.Effect) { h.handleEffect(ctx, ch, m, e) })
	st.runner = r
	go func() {
		r.Run(context.Background(), initial)
		h.mu.Lock()
		st.runner = nil
		h.mu.Unlock()
	}()
}

// handleEffect is the runner's output callback. It runs on the runner goroutine.
func (h *Hub) handleEffect(ctx context.Context, ch string, m *match.Match, e match.Effect) {
	switch e := e.(type) {
	case match.StartTimer:
		h.mu.Lock()
		h.state(ch).deadline = time.Now().Add(e.After)
		h.mu.Unlock()
	case match.Say:
		h.broadcast(ch, e.Text, m.Snapshot())
	case match.RoundWon:
		delta := int64(xp.RoundWin)
		if e.Exact {
			delta += xp.ExactHit
		}
		h.give(ctx, e.Player, delta)
	case match.MatchWon:
		h.give(ctx, e.Player, xp.MatchWin)
	}
}

// give hands XP to the awarder without waiting for it.
func (h *Hub) give(ctx context.Context, p match.PlayerID, delta int64) {
	if h.awards != nil {
		h.awards.Give(ctx, string(p), delta)
	}
}

func toProto(s match.State, deadline time.Time) *gamev1.MatchState {
	wins := make(map[string]int32, len(s.RoundWins))
	for p, w := range s.RoundWins {
		wins[string(p)] = int32(w)
	}
	return &gamev1.MatchState{
		Phase: s.Phase, Round: int32(s.Round), TotalRounds: int32(s.TotalRounds),
		Lo: int32(s.Lo), Hi: int32(s.Hi), CurrentPlayer: string(s.CurrentPlayer),
		TurnDeadlineUnixMs: deadline.UnixMilli(), RoundWins: wins,
	}
}

func (h *Hub) broadcast(ch, text string, snap match.State) {
	h.mu.Lock()
	defer h.mu.Unlock()
	st := h.state(ch)
	st.seq++
	msg := &gamev1.GameMessage{Channel: ch, Text: text, Seq: st.seq, State: toProto(snap, st.deadline)}
	for _, sub := range st.subs {
		select {
		case sub <- msg:
		default: // slow subscriber: drop it; it will notice the seq gap
		}
	}
}

// Subscribe returns a stream of the channel's messages and a func to stop it.
func (h *Hub) Subscribe(ch string) (<-chan *gamev1.GameMessage, func()) {
	h.mu.Lock()
	defer h.mu.Unlock()
	st := h.state(ch)
	id := st.nextID
	st.nextID++
	c := make(chan *gamev1.GameMessage, 32)
	st.subs[id] = c
	return c, func() {
		h.mu.Lock()
		delete(st.subs, id)
		h.mu.Unlock()
	}
}
