// Package feedback tells a guesser how a guess compares to the secret.
package feedback

// Feedback reports "correct" when guess equals secret, otherwise the direction
// the next guess should move: "higher" or "lower".
func Feedback(secret, guess int) string {
	switch {
	case guess < secret:
		return "higher"
	case guess > secret:
		return "lower"
	default:
		return "correct"
	}
}
