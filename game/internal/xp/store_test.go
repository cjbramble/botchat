package xp

import (
	"context"
	"os"
	"sync"
	"testing"
)

// newTestStore connects, migrates and empties the table, or skips the test.
func newTestStore(t *testing.T) *Store {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	s, err := Open(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.Close)
	if err := s.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(ctx, "TRUNCATE players"); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestConcurrentAwardsDontLoseXP(t *testing.T) { // GAME-I-01
	s := newTestStore(t)
	var wg sync.WaitGroup
	for range 100 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, _, err := s.AddXP(context.Background(), "pim", 20); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()

	got, err := s.GetXP(context.Background(), "pim")
	if err != nil {
		t.Fatal(err)
	}
	if got != 2000 {
		t.Fatalf("lost updates: xp = %d, want 2000", got)
	}
}

func TestAddXPReportsLevels(t *testing.T) { // GAME-I-02
	s := newTestStore(t)
	ctx := context.Background()
	steps := []struct {
		delta              int64
		oldLevel, newLevel int
	}{
		{49, 1, 1},  // 49 XP
		{1, 1, 2},   // 50 XP: level 2
		{150, 2, 3}, // 200 XP: level 3
	}
	for _, st := range steps {
		o, n, err := s.AddXP(ctx, "vex", st.delta)
		if err != nil || o != st.oldLevel || n != st.newLevel {
			t.Fatalf("AddXP(+%d) = %d, %d, %v; want %d, %d", st.delta, o, n, err, st.oldLevel, st.newLevel)
		}
	}
}

func TestGetXPIsZeroForUnknownPlayers(t *testing.T) {
	s := newTestStore(t)
	got, err := s.GetXP(context.Background(), "nobody")
	if err != nil || got != 0 {
		t.Fatalf("GetXP(nobody) = %d, %v; want 0, nil", got, err)
	}
}
