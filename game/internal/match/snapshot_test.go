package match

import "testing"

func TestSnapshot(t *testing.T) {
	m := started(t, 1, 40, "pim", "vex")
	m.HandleInput(m.Order[0], "50")

	s := m.Snapshot()
	if s.Phase != "turn" || s.CurrentPlayer != m.Order[1] || s.Hi != 49 {
		t.Fatalf("unexpected snapshot %+v", s)
	}

	s.RoundWins["pim"] = 99
	if m.RoundWins["pim"] == 99 {
		t.Fatal("snapshot shares its map with the match")
	}
}
