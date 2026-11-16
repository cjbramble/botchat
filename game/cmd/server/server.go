package main

import (
	"context"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	gamev1 "github.com/cjbramble/botchat/game/gen/game/v1"
	"github.com/cjbramble/botchat/game/internal/hub"
	"github.com/cjbramble/botchat/game/internal/match"
	"github.com/cjbramble/botchat/game/internal/runner"
)

// server implements gamev1.GameServiceServer.
type server struct {
	// Embedding this makes unimplemented methods (GetPlayer)
	// return codes.Unimplemented instead of failing to compile.
	gamev1.UnimplementedGameServiceServer
	hub *hub.Hub
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
