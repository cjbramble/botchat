package match

// State is a read-only copy of a match for viewers. It never includes the secret.
type State struct {
	Phase         string
	Round         int
	TotalRounds   int
	Lo, Hi        int
	CurrentPlayer PlayerID
	RoundWins     map[PlayerID]int
}

var phaseNames = map[Phase]string{
	Lobby: "lobby", TurnActive: "turn", Reveal: "reveal", Intermission: "intermission", Over: "over",
}

// Snapshot returns the current public state. The map is a copy, so the
// caller can't change the match through it.
func (m *Match) Snapshot() State {
	s := State{
		Phase: phaseNames[m.Phase], Round: m.Round, TotalRounds: m.cfg.Rounds,
		Lo: m.Lo, Hi: m.Hi, RoundWins: make(map[PlayerID]int, len(m.RoundWins)),
	}
	if m.Phase == TurnActive {
		s.CurrentPlayer = m.Order[m.TurnIdx]
	}
	for p, w := range m.RoundWins {
		s.RoundWins[p] = w
	}
	return s
}
