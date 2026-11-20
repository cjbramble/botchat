package award

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/cjbramble/botchat/game/internal/events"
	"github.com/cjbramble/botchat/game/internal/xp"
)

// fakeStore is only touched by the awarder goroutine.
type fakeStore struct {
	xp   map[string]int64
	fail bool
}

func (f *fakeStore) AddXP(_ context.Context, p string, delta int64) (int, int, error) {
	if f.fail {
		return 0, 0, errors.New("db down")
	}
	f.xp[p] += delta
	return xp.LevelFor(f.xp[p] - delta), xp.LevelFor(f.xp[p]), nil
}

type spyPublisher struct {
	got chan events.LevelUp
	err error
}

func (s spyPublisher) Publish(_ context.Context, e events.LevelUp) error {
	s.got <- e
	return s.err
}

func run(t *testing.T, store Store, pubErr error) (*Awarder, spyPublisher) {
	t.Helper()
	pub := spyPublisher{got: make(chan events.LevelUp, 10), err: pubErr}
	a := New(store, pub)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go a.Run(ctx)
	return a, pub
}

func expectEvent(t *testing.T, pub spyPublisher, player string, oldLevel, newLevel int) {
	t.Helper()
	select {
	case e := <-pub.got:
		if e.PlayerID != player || e.OldLevel != oldLevel || e.NewLevel != newLevel {
			t.Fatalf("unexpected event %+v", e)
		}
	case <-time.After(time.Second):
		t.Fatal("no level-up published")
	}
}

func expectNoEvent(t *testing.T, pub spyPublisher) {
	t.Helper()
	select {
	case e := <-pub.got:
		t.Fatalf("unexpected event %+v", e)
	case <-time.After(100 * time.Millisecond):
	}
}

func TestPublishesOncePerLevelCrossed(t *testing.T) { // GAME-I-03
	a, pub := run(t, &fakeStore{xp: map[string]int64{}}, nil)
	a.Give("pim", 20) // 20 XP: still level 1
	a.Give("pim", 30) // 50 XP: level 2

	expectEvent(t, pub, "pim", 1, 2)
	expectNoEvent(t, pub)
}

func TestStoreErrorsAreLoggedNotFatal(t *testing.T) {
	store := &fakeStore{fail: true}
	a, pub := run(t, store, nil)
	a.Give("pim", 500)
	expectNoEvent(t, pub)
}

func TestPublishErrorsDontStopTheAwarder(t *testing.T) {
	a, pub := run(t, &fakeStore{xp: map[string]int64{}}, errors.New("sns down"))
	a.Give("pim", 50)  // level 2
	a.Give("pim", 150) // level 3

	expectEvent(t, pub, "pim", 1, 2)
	expectEvent(t, pub, "pim", 2, 3)
}

func TestGiveNeverBlocks(t *testing.T) {
	a := New(&fakeStore{xp: map[string]int64{}}, events.LogPublisher{}) // not running: nothing drains
	done := make(chan struct{})
	go func() {
		for range 1000 {
			a.Give("pim", 1)
		}
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("Give blocked with a full queue")
	}
	if len(a.grants) != queueSize {
		t.Fatalf("queued %d awards, want %d", len(a.grants), queueSize)
	}
}
