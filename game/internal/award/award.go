// Package award applies XP awards in their own goroutine and publishes
// level-ups, so the match runner never waits on the database or the network.
package award

import (
	"context"
	"log/slog"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"

	"github.com/cjbramble/botchat/game/internal/events"
)

var tracer = otel.Tracer("github.com/cjbramble/botchat/game/internal/award")

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
	cause  trace.SpanContext // the span that earned the XP; invalid when there is none
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
// award is dropped and logged. Only the trace is kept from ctx: the award is
// applied later, under the awarder's own context.
func (a *Awarder) Give(ctx context.Context, player string, delta int64) {
	select {
	case a.grants <- grant{player, delta, trace.SpanContextFromContext(ctx)}:
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
// Its span continues the trace of the guess that earned the XP, so a level-up
// can be followed from the bot to the notice; without one it is a root span.
func (a *Awarder) apply(ctx context.Context, g grant) {
	ctx, cancel := context.WithTimeout(ctx, applyTimeout)
	defer cancel()
	if g.cause.IsValid() {
		ctx = trace.ContextWithSpanContext(ctx, g.cause)
	}
	ctx, span := tracer.Start(ctx, "award xp")
	defer span.End()
	span.SetAttributes(attribute.String("player.id", g.player), attribute.Int64("xp.delta", g.delta))

	oldLevel, newLevel, err := a.store.AddXP(ctx, g.player, g.delta)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "add xp")
		slog.Error("add xp", "player", g.player, "err", err)
		return
	}
	if newLevel > oldLevel {
		span.SetAttributes(attribute.Int("level.new", newLevel))
		if err := a.pub.Publish(ctx, events.NewLevelUp(g.player, oldLevel, newLevel)); err != nil {
			span.RecordError(err)
			span.SetStatus(codes.Error, "publish")
			slog.Error("publish level-up", "player", g.player, "level", newLevel, "err", err)
		}
	}
}
