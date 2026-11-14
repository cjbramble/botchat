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
)

// Hub is safe for concurrent use.
type Hub struct {
	mu       sync.Mutex
	cfg      match.Config
	channels map[string]*channelState
}

type channelState struct {
	runner *runner.Runner // nil when no match is running
	subs   map[int]chan *gamev1.GameMessage
	nextID int
	seq    int64
}

// New creates a hub whose matches use cfg.
func New(cfg match.Config) *Hub {
	return &Hub{cfg: cfg, channels: map[string]*channelState{}}
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
	r := runner.New(m, func(e match.Effect) { h.handleEffect(ch, e) })
	st.runner = r
	go func() {
		r.Run(context.Background(), initial)
		h.mu.Lock()
		st.runner = nil
		h.mu.Unlock()
	}()
}

// handleEffect is the runner's output callback. It runs on the runner goroutine.
func (h *Hub) handleEffect(ch string, e match.Effect) {
	switch e := e.(type) {
	case match.Say:
		h.broadcast(ch, e.Text)
	}
}

func (h *Hub) broadcast(ch, text string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	st := h.state(ch)
	st.seq++
	msg := &gamev1.GameMessage{Channel: ch, Text: text, Seq: st.seq}
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
