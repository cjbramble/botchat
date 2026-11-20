package xp

import (
	"context"
	_ "embed"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed schema.sql
var schema string

// Store keeps each player's XP. It is safe for concurrent use.
type Store struct {
	db *pgxpool.Pool
}

// Open connects to Postgres and checks the connection.
func Open(ctx context.Context, url string) (*Store, error) {
	db, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}
	if err := db.Ping(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	return &Store{db: db}, nil
}

// Close releases every connection.
func (s *Store) Close() { s.db.Close() }

// Migrate creates the table if it doesn't exist.
func (s *Store) Migrate(ctx context.Context) error {
	if _, err := s.db.Exec(ctx, schema); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	return nil
}

// AddXP adds delta to a player's XP in one atomic statement, so concurrent
// awards can't lose an update, and reports the level before and after.
func (s *Store) AddXP(ctx context.Context, playerID string, delta int64) (oldLevel, newLevel int, err error) {
	var total int64
	err = s.db.QueryRow(ctx, `
		INSERT INTO players (player_id, xp) VALUES ($1, $2)
		ON CONFLICT (player_id) DO UPDATE
		  SET xp = players.xp + EXCLUDED.xp, updated_at = now()
		RETURNING xp`, playerID, delta).Scan(&total)
	if err != nil {
		return 0, 0, fmt.Errorf("add xp for %s: %w", playerID, err)
	}
	return LevelFor(total - delta), LevelFor(total), nil
}

// GetXP returns a player's XP, or 0 for a player who has never scored.
func (s *Store) GetXP(ctx context.Context, playerID string) (int64, error) {
	var total int64
	err := s.db.QueryRow(ctx, `SELECT xp FROM players WHERE player_id = $1`, playerID).Scan(&total)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("get xp for %s: %w", playerID, err)
	}
	return total, nil
}
