package match

import (
	"math/rand/v2"
	"slices"
	"strings"
	"testing"
	"time"
)

func testConfig(rounds int) Config {
	return Config{Rounds: rounds, Lo: 1, Hi: 100, MinPlayers: 2,
		JoinWindow: time.Second, Turn: time.Second, RevealPause: time.Second, Intermission: time.Second}
}

// started returns a match in round 1 with the given players and a forced secret.
func started(t *testing.T, rounds, secret int, players ...PlayerID) *Match {
	t.Helper()
	m, _ := New(testConfig(rounds), rand.New(rand.NewPCG(1, 2)))
	for _, p := range players {
		m.HandleInput(p, "!join")
	}
	m.HandleTimeout() // lobby closes, round 1 starts
	if m.Phase != TurnActive {
		t.Fatalf("match did not start: phase=%v", m.Phase)
	}
	m.Secret = secret
	return m
}

// find returns the first effect of type T.
func find[T Effect](effects []Effect) (T, bool) {
	for _, e := range effects {
		if v, ok := e.(T); ok {
			return v, true
		}
	}
	var zero T
	return zero, false
}

// said reports whether any Say effect contains text.
func said(effects []Effect, text string) bool {
	return slices.ContainsFunc(effects, func(e Effect) bool {
		s, ok := e.(Say)
		return ok && strings.Contains(s.Text, text)
	})
}

func TestDefaultConfig(t *testing.T) {
	want := Config{Rounds: 5, Lo: 1, Hi: 100, MinPlayers: 2,
		JoinWindow: 20 * time.Second, Turn: 15 * time.Second,
		RevealPause: 5 * time.Second, Intermission: 10 * time.Second}
	if got := DefaultConfig(); got != want {
		t.Fatalf("DefaultConfig() = %+v, want %+v", got, want)
	}
}

func TestNewOpensLobbyWithTimerFirst(t *testing.T) {
	m, effects := New(testConfig(1), rand.New(rand.NewPCG(1, 2)))
	if m.Phase != Lobby || len(effects) != 2 {
		t.Fatalf("phase=%v effects=%v", m.Phase, effects)
	}
	if st, ok := effects[0].(StartTimer); !ok || st.After != time.Second {
		t.Fatalf("first effect = %#v, want StartTimer for the join window", effects[0])
	}
	if _, ok := effects[1].(Say); !ok {
		t.Fatalf("second effect = %#v, want Say", effects[1])
	}
}

func TestInputRules(t *testing.T) {
	cases := []struct {
		name     string
		who      int // index into Order
		text     string
		wantTurn int
		wantSay  string // "" means no effects at all
	}{
		{"out of turn is ignored", 1, "50", 0, ""},
		{"chatter is ignored", 0, "hello", 0, ""},
		{"join during a turn is ignored", 0, "!join", 0, ""},
		{"out of range does not use the turn", 0, "500", 0, "pick a number from 1-100"},
		{"zero is out of range", 0, "0", 0, "pick a number from 1-100"},
		{"too big for an int is out of range", 0, "99999999999999999999", 0, "pick a number from 1-100"},
		{"too low gets higher", 0, "30", 1, "Higher than 30."},
		{"too high gets lower", 0, "50", 1, "Lower than 50."},
		{"spaces around a guess are fine", 0, "  50 ", 1, "Lower than 50."},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := started(t, 1, 40, "pim", "vex")
			effects := m.HandleInput(m.Order[tc.who], tc.text)
			if m.TurnIdx != tc.wantTurn {
				t.Fatalf("turn = %d, want %d", m.TurnIdx, tc.wantTurn)
			}
			if tc.wantSay == "" && effects != nil {
				t.Fatalf("effects = %v, want none", effects)
			}
			if tc.wantSay != "" && !said(effects, tc.wantSay) {
				t.Fatalf("effects = %v, want a Say containing %q", effects, tc.wantSay)
			}
		})
	}
}

func TestPromptTurnStartsTimerBeforeSay(t *testing.T) {
	m := started(t, 1, 40, "pim", "vex")
	effects := m.HandleInput("pim", "50") // hint, then vex's prompt
	if len(effects) != 3 {
		t.Fatalf("effects = %v, want hint, timer, prompt", effects)
	}
	if st, ok := effects[1].(StartTimer); !ok || st.After != time.Second {
		t.Fatalf("effects[1] = %#v, want StartTimer for the turn", effects[1])
	}
	if s, ok := effects[2].(Say); !ok || !strings.HasPrefix(s.Text, "vex, you're up") {
		t.Fatalf("effects[2] = %#v, want vex's prompt", effects[2])
	}
}

func TestJoinAnnouncesPlayerCount(t *testing.T) {
	m, _ := New(testConfig(1), rand.New(rand.NewPCG(1, 2)))
	if effects := m.HandleInput("pim", "!join"); !said(effects, "pim joined (1 player).") {
		t.Fatalf("first join = %v", effects)
	}
	if effects := m.HandleInput("vex", "!join"); !said(effects, "vex joined (2 players).") {
		t.Fatalf("second join = %v", effects)
	}
}

func TestEmptyLobbyEndsTheMatchWhateverMinPlayersIs(t *testing.T) {
	cfg := testConfig(1)
	cfg.MinPlayers = 0
	m, _ := New(cfg, rand.New(rand.NewPCG(1, 2)))
	effects := m.HandleTimeout()
	if m.Phase != Over || !said(effects, "Not enough players joined") {
		t.Fatalf("an empty lobby should end the match: %v phase=%v", effects, m.Phase)
	}
}

func TestDuplicateJoinIsIgnored(t *testing.T) {
	m, _ := New(testConfig(1), rand.New(rand.NewPCG(1, 2)))
	m.HandleInput("pim", "!join")
	if effects := m.HandleInput("pim", "!join"); effects != nil || len(m.Players) != 1 {
		t.Fatalf("second join should do nothing, got %v", effects)
	}
}

func TestLobbyIgnoresEverythingButJoin(t *testing.T) {
	m, _ := New(testConfig(1), rand.New(rand.NewPCG(1, 2)))
	if effects := m.HandleInput("pim", "50"); effects != nil || len(m.Players) != 0 {
		t.Fatalf("a guess in the lobby should do nothing, got %v", effects)
	}
}

func TestClosestGuessWinsAndTiesGoToFirst(t *testing.T) {
	cases := []struct {
		name         string
		first, last  string // guesses by Order[0] and Order[1]
		wantWinner   int    // index into Order
		wantDistance int
	}{
		{"tie goes to the earlier guess", "35", "45", 0, 5},
		{"tie goes to the earlier guess, sides swapped", "45", "35", 0, 5},
		{"closer first guess wins", "38", "50", 0, 2},
		{"closer second guess wins", "10", "41", 1, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			// Repeat so a tie-break that leaned on map order would flake here.
			for range 50 {
				m := started(t, 1, 40, "pim", "vex")
				m.HandleInput(m.Order[0], tc.first)
				effects := m.HandleInput(m.Order[1], tc.last)
				won, ok := find[RoundWon](effects)
				want := m.Order[tc.wantWinner]
				if !ok || won.Player != want || won.Distance != tc.wantDistance || won.Exact || won.Round != 1 {
					t.Fatalf("RoundWon = %+v (found=%t), want %s off by %d", won, ok, want, tc.wantDistance)
				}
				if m.RoundWins[want] != 1 || m.Phase != Reveal {
					t.Fatalf("wins=%v phase=%v", m.RoundWins, m.Phase)
				}
			}
		})
	}
}

func TestExactHitEndsRoundEarly(t *testing.T) {
	m := started(t, 1, 40, "pim", "vex", "grim")
	effects := m.HandleInput(m.Order[0], "40")
	won, ok := find[RoundWon](effects)
	if !ok || !won.Exact || won.Distance != 0 || m.Phase != Reveal {
		t.Fatalf("exact hit should end the round: %+v phase=%v", won, m.Phase)
	}
	if st, ok := find[StartTimer](effects); !ok || st.After != time.Second {
		t.Fatalf("exact hit should start the reveal timer, got %v", effects)
	}
	if effects := m.HandleInput(m.Order[1], "41"); effects != nil {
		t.Fatalf("guesses during the reveal should be ignored, got %v", effects)
	}
}

func TestEveryoneTimesOut(t *testing.T) {
	m := started(t, 1, 40, "pim", "vex")
	if effects := m.HandleTimeout(); !said(effects, "pim ran out of time.") || m.TurnIdx != 1 {
		t.Fatalf("first timeout should pass the turn: %v", effects)
	}
	effects := m.HandleTimeout()
	if _, ok := find[RoundWon](effects); ok || m.Phase != Reveal {
		t.Fatalf("no winner expected, phase=%v", m.Phase)
	}
	if !said(effects, "vex ran out of time.") || !said(effects, "Nobody guessed. The number was 40.") {
		t.Fatalf("effects = %v", effects)
	}
	effects = m.HandleTimeout() // reveal -> match over, nobody won
	if _, ok := find[MatchWon](effects); ok || m.Phase != Over {
		t.Fatalf("no match winner expected: %v phase=%v", effects, m.Phase)
	}
	if effects := m.HandleTimeout(); effects != nil {
		t.Fatalf("a finished match should ignore timeouts, got %v", effects)
	}
}

func TestLateJoinWaits(t *testing.T) {
	m := started(t, 1, 40, "pim", "vex")
	effects := m.HandleInput("late", "!join")
	if effects != nil || len(m.Order) != 2 || len(m.Players) != 2 {
		t.Fatalf("late joiner should not be in this match: order=%v players=%v", m.Order, m.Players)
	}
}

func TestFullMatchAndRotation(t *testing.T) {
	m := started(t, 2, 40, "pim", "vex")
	m.HandleInput("pim", "40") // round 1 won exactly
	if effects := m.HandleTimeout(); m.Phase != Intermission || !said(effects, "Round 2 starts in") {
		t.Fatalf("reveal should lead to intermission: %v phase=%v", effects, m.Phase)
	}
	m.HandleTimeout() // intermission -> round 2
	if want := []PlayerID{"vex", "pim"}; !slices.Equal(m.Order, want) || m.Round != 2 || m.TurnIdx != 0 {
		t.Fatalf("order = %v round = %d, want %v in round 2", m.Order, m.Round, want)
	}
	if want := []PlayerID{"pim", "vex"}; !slices.Equal(m.Players, want) {
		t.Fatalf("rotation must not change join order: %v", m.Players)
	}
	m.Secret = 10
	m.HandleInput("vex", "10")
	effects := m.HandleTimeout() // reveal -> match over
	won, ok := find[MatchWon](effects)
	// One round each: pim joined first, so pim takes the tie.
	if !ok || won.Player != "pim" || won.RoundWins != 1 || m.Phase != Over {
		t.Fatalf("MatchWon = %+v (found=%t) phase=%v", won, ok, m.Phase)
	}
}

func TestMostRoundWinsTakesTheMatch(t *testing.T) {
	m := started(t, 3, 40, "pim", "vex")
	m.HandleInput("pim", "40") // round 1: pim, exactly
	m.HandleTimeout()          // reveal -> intermission
	m.HandleTimeout()          // intermission -> round 2, vex first
	m.Secret = 10
	m.HandleInput("vex", "10") // round 2: vex, exactly
	m.HandleTimeout()
	m.HandleTimeout() // round 3, pim first again
	m.Secret = 10
	m.HandleInput("pim", "50")
	m.HandleInput("vex", "12") // round 3: vex, closest
	won, ok := find[MatchWon](m.HandleTimeout())
	if !ok || won.Player != "vex" || won.RoundWins != 2 {
		t.Fatalf("MatchWon = %+v (found=%t), want vex with 2", won, ok)
	}
}

func TestNotEnoughPlayers(t *testing.T) {
	m, _ := New(testConfig(1), rand.New(rand.NewPCG(1, 2)))
	m.HandleInput("pim", "!join")
	effects := m.HandleTimeout()
	if m.Phase != Over || !said(effects, "Type !start to try again") {
		t.Fatalf("one player should not start a match: %v phase=%v", effects, m.Phase)
	}
	if _, ok := find[StartTimer](effects); ok {
		t.Fatalf("a finished match should not start a timer: %v", effects)
	}
}

func TestRangeNarrows(t *testing.T) {
	m := started(t, 1, 40, "pim", "vex", "grim")
	m.HandleInput(m.Order[0], "50")
	m.HandleInput(m.Order[1], "30")
	if m.Lo != 31 || m.Hi != 49 {
		t.Fatalf("range = %d-%d, want 31-49", m.Lo, m.Hi)
	}
}

func TestRangeResetsEachRound(t *testing.T) {
	m := started(t, 2, 40, "pim", "vex")
	m.HandleInput("pim", "50")
	m.HandleInput("vex", "30")
	m.HandleTimeout() // reveal -> intermission
	m.HandleTimeout() // intermission -> round 2
	if m.Lo != 1 || m.Hi != 100 || len(m.Guesses) != 0 {
		t.Fatalf("round 2 should start fresh: range %d-%d guesses %v", m.Lo, m.Hi, m.Guesses)
	}
}

func TestSameSeedSameSecrets(t *testing.T) {
	secrets := func(seed uint64) []int {
		m, _ := New(testConfig(3), rand.New(rand.NewPCG(seed, seed)))
		m.HandleInput("pim", "!join")
		m.HandleInput("vex", "!join")
		var got []int
		for m.Phase != Over {
			m.HandleTimeout()
			if m.Phase == TurnActive && len(got) < m.Round {
				got = append(got, m.Secret)
			}
		}
		return got
	}
	a, b := secrets(7), secrets(7)
	if len(a) != 3 || !slices.Equal(a, b) {
		t.Fatalf("same seed should give the same secrets: %v vs %v", a, b)
	}
	for _, s := range a {
		if s < 1 || s > 100 {
			t.Fatalf("secret %d outside 1-100", s)
		}
	}
}
