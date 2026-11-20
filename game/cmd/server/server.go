package main

import (
	"context"
	"log/slog"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	gamev1 "github.com/cjbramble/botchat/game/gen/game/v1"
	"github.com/cjbramble/botchat/game/internal/hub"
	"github.com/cjbramble/botchat/game/internal/match"
	"github.com/cjbramble/botchat/game/internal/runner"
	"github.com/cjbramble/botchat/game/internal/xp"
)

// PlayerStore is the part of xp.Store that GetPlayer needs.
type PlayerStore interface {
	GetXP(ctx context.Context, playerID string) (int64, error)
}

// server implements gamev1.GameServiceServer.
type server struct {
	// Embedding this makes unimplemented methods return codes.Unimplemented
	// instead of failing to compile.
	gamev1.UnimplementedGameServiceServer
	hub     *hub.Hub
	players PlayerStore // nil when XP is disabled
	// done closes when the server shuts down. GracefulStop waits for open
	// streams, and a Subscribe stream never ends by itself. Nil never closes.
	done <-chan struct{}
}

func (s *server) SubmitInput(ctx context.Context, req *gamev1.SubmitInputRequest) (*gamev1.SubmitInputResponse, error) {
	if req.GetChannel() == "" || req.GetPlayerId() == "" {
		return nil, status.Error(codes.InvalidArgument, "channel and player_id are required")
	}
	if err := ctx.Err(); err != nil {
		return nil, status.FromContextError(err).Err() // the caller already gave up
	}
	s.hub.Submit(req.GetChannel(), runner.Input{
		Player: match.PlayerID(req.GetPlayerId()),
		Text:   req.GetText(),
		MsgID:  req.GetMsgId(),
	})
	return &gamev1.SubmitInputResponse{}, nil
}

func (s *server) Subscribe(req *gamev1.SubscribeRequest, stream grpc.ServerStreamingServer[gamev1.GameMessage]) error {
	if req.GetChannel() == "" {
		return status.Error(codes.InvalidArgument, "channel is required")
	}
	msgs, stop := s.hub.Subscribe(req.GetChannel())
	defer stop()
	for {
		select {
		case <-stream.Context().Done():
			return nil // the client hung up
		case <-s.done:
			return status.Error(codes.Unavailable, "server is shutting down")
		case msg := <-msgs:
			if err := stream.Send(msg); err != nil {
				return err
			}
		}
	}
}

func (s *server) GetPlayer(ctx context.Context, req *gamev1.GetPlayerRequest) (*gamev1.GetPlayerResponse, error) {
	id := req.GetPlayerId()
	if id == "" {
		return nil, status.Error(codes.InvalidArgument, "player_id is required")
	}
	if s.players == nil {
		return nil, status.Error(codes.Unavailable, "xp is disabled on this server")
	}
	total, err := s.players.GetXP(ctx, id)
	if err != nil {
		// The details stay in the log: internal errors don't belong in a response.
		slog.Error("get player", "player", id, "err", err)
		return nil, status.Error(codes.Unavailable, "xp store unavailable")
	}
	return &gamev1.GetPlayerResponse{PlayerId: id, Level: int32(xp.LevelFor(total)), Xp: total}, nil
}
