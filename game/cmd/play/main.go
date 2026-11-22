// Command play runs one match in the terminal. Type "<nick> <text>", e.g.
// "pim !join" or "vex 42".
package main

import (
	"bufio"
	"context"
	"fmt"
	"math/rand/v2"
	"os"
	"strings"
	"time"

	"github.com/cjbramble/botchat/game/internal/match"
	"github.com/cjbramble/botchat/game/internal/runner"
)

func main() {
	cfg := match.DefaultConfig()
	cfg.Rounds = 2
	cfg.JoinWindow = 15 * time.Second
	cfg.RevealPause, cfg.Intermission = 2*time.Second, 3*time.Second

	seed := uint64(time.Now().UnixNano())
	m, initial := match.New(cfg, rand.New(rand.NewPCG(seed, seed)))

	r := runner.New(m, func(_ context.Context, e match.Effect) {
		switch v := e.(type) {
		case match.Say:
			fmt.Println("GameServ:", v.Text)
		case match.RoundWon:
			fmt.Printf("  [round %d won by %s]\n", v.Round, v.Player)
		case match.MatchWon:
			fmt.Printf("  [match won by %s]\n", v.Player)
		}
	})

	go func() {
		sc := bufio.NewScanner(os.Stdin)
		for sc.Scan() {
			nick, text, ok := strings.Cut(sc.Text(), " ")
			if !ok {
				fmt.Println("type: <nick> <text>")
				continue
			}
			r.Inputs <- runner.Input{Player: match.PlayerID(nick), Text: text}
		}
		if err := sc.Err(); err != nil {
			fmt.Fprintln(os.Stderr, "reading stdin:", err)
		}
	}()

	r.Run(context.Background(), initial) // returns when the match is over
}
