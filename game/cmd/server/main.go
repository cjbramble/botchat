// Command server runs the game service over gRPC.
package main

import (
	"context"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	gamev1 "github.com/cjbramble/botchat/game/gen/game/v1"
	"github.com/cjbramble/botchat/game/internal/hub"
	"github.com/cjbramble/botchat/game/internal/match"
)

func main() {
	token := os.Getenv("GAME_INTERNAL_TOKEN")
	if token == "" {
		slog.Error("GAME_INTERNAL_TOKEN is required")
		os.Exit(1)
	}
	addr := envOr("GAME_ADDR", "[::]:50051") // [::] accepts IPv6 and IPv4

	s := grpc.NewServer(
		grpc.UnaryInterceptor(unaryAuth(token)),
		grpc.StreamInterceptor(streamAuth(token)),
	)
	gamev1.RegisterGameServiceServer(s, &server{hub: hub.New(match.DefaultConfig())})
	reflection.Register(s) // lets grpcurl discover methods (calls still need the token)

	lis, err := net.Listen("tcp", addr)
	if err != nil {
		slog.Error("listen", "addr", addr, "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		slog.Info("shutting down")
		s.GracefulStop() // finish in-flight calls, then stop
	}()

	slog.Info("game listening", "addr", lis.Addr().String())
	if err := s.Serve(lis); err != nil {
		slog.Error("serve", "err", err)
		os.Exit(1)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
