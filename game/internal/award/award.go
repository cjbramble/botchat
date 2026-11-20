// Package award applies XP awards in their own goroutine and publishes
// level-ups, so the match runner never waits on the database or the network.
package award

import (
	"context"
	"log/slog"
	"time"

	"github.com/cjbramble/botchat/game/internal/events"
)

const (
	queueSize    = 100
	applyTimeout = 5 * time.Second
)

// Store is the part of xp.Store the awarder needs.
type Store interface {
	AddXP(ctx context.Context, playerID string, delta int64) (oldLevel, newLevel int, err error)
}

type grant struct {
	player string
	delta  int64
}

// Awarder queues awards and applies them one at a time.
type Awarder struct {
	store  Store
	pub    events.Publisher
	grants chan grant
}

// New creates an awarder with room for 100 queued awards.
func New(store Store, pub events.Publisher) *Awarder {
	return &Awarder{store: store, pub: pub, grants: make(chan grant, queueSize)}
}

// Give queues XP for a player. It never blocks: if the queue is full, the
// award is dropped and logged.
func (a *Awarder) Give(player string, delta int64) {
	select {
	case a.grants <- grant{player, delta}:
	default:
		slog.Warn("award dropped: queue full", "player", player, "delta", delta)
	}
}

// Run applies queued awards until ctx is cancelled.
func (a *Awarder) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case g := <-a.grants:
			a.apply(ctx, g)
		}
	}
}

// apply is bounded by a timeout so a hung database can't stall the queue.
func (a *Awarder) apply(ctx context.Context, g grant) {
	ctx, cancel := context.WithTimeout(ctx, applyTimeout)
	defer cancel()

	oldLevel, newLevel, err := a.store.AddXP(ctx, g.player, g.delta)
	if err != nil {
		slog.Error("add xp", "player", g.player, "err", err)
		return
	}
	if newLevel > oldLevel {
		if err := a.pub.Publish(ctx, events.NewLevelUp(g.player, oldLevel, newLevel)); err != nil {
			slog.Error("publish level-up", "player", g.player, "level", newLevel, "err", err)
		}
	}
}
