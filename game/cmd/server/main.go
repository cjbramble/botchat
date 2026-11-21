// Command server runs the game service over gRPC.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	gamev1 "github.com/cjbramble/botchat/game/gen/game/v1"
	"github.com/cjbramble/botchat/game/internal/award"
	"github.com/cjbramble/botchat/game/internal/events"
	"github.com/cjbramble/botchat/game/internal/hub"
	"github.com/cjbramble/botchat/game/internal/match"
	"github.com/cjbramble/botchat/game/internal/xp"
)

func main() {
	token := os.Getenv("GAME_INTERNAL_TOKEN")
	if token == "" {
		slog.Error("GAME_INTERNAL_TOKEN is required")
		os.Exit(1)
	}
	addr := envOr("GAME_ADDR", "[::]:50051") // [::] accepts IPv6 and IPv4

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pub, err := newPublisher(ctx)
	if err != nil {
		slog.Error("events", "err", err)
		os.Exit(1)
	}

	srv := &server{done: ctx.Done()}
	var opts []hub.Option
	if url := os.Getenv("DATABASE_URL"); url != "" {
		store, err := xp.Open(ctx, url)
		if err != nil {
			slog.Error("xp store", "err", err)
			os.Exit(1)
		}
		defer store.Close()
		if err := store.Migrate(ctx); err != nil {
			slog.Error("xp store", "err", err)
			os.Exit(1)
		}
		awarder := award.New(store, pub)
		go awarder.Run(ctx)
		opts = append(opts, hub.WithAwards(awarder))
		// Assigned only here: a nil *xp.Store in the interface would not
		// compare equal to nil in GetPlayer.
		srv.players = store
	} else {
		slog.Warn("DATABASE_URL not set: XP and GetPlayer are disabled")
	}
	srv.hub = hub.New(match.DefaultConfig(), opts...)

	creds, err := transportCreds() // mutual TLS when GAME_TLS_DIR is set
	if err != nil {
		slog.Error("tls", "err", err)
		os.Exit(1)
	}
	s := grpc.NewServer(
		creds,
		grpc.UnaryInterceptor(unaryAuth(token)),
		grpc.StreamInterceptor(streamAuth(token)),
	)
	gamev1.RegisterGameServiceServer(s, srv)
	reflection.Register(s) // lets grpcurl discover methods (calls still need the token)

	lis, err := net.Listen("tcp", addr)
	if err != nil {
		slog.Error("listen", "addr", addr, "err", err)
		os.Exit(1)
	}

	go func() {
		<-ctx.Done()
		slog.Info("shutting down")
		s.GracefulStop() // finish in-flight calls (Subscribe streams end on ctx), then stop
	}()

	slog.Info("game listening", "addr", lis.Addr().String())
	if err := s.Serve(lis); err != nil {
		slog.Error("serve", "err", err)
		os.Exit(1)
	}
}

// newPublisher returns an SNS publisher when EVENTS=sns, otherwise one that logs.
func newPublisher(ctx context.Context) (events.Publisher, error) {
	if os.Getenv("EVENTS") != "sns" {
		return events.LogPublisher{}, nil
	}
	topic := os.Getenv("GAME_EVENTS_TOPIC_ARN")
	if topic == "" {
		return nil, errors.New("EVENTS=sns needs GAME_EVENTS_TOPIC_ARN")
	}
	cfg, err := config.LoadDefaultConfig(ctx) // AWS_REGION and credentials from the environment
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}
	return events.SNSPublisher{Client: sns.NewFromConfig(cfg), TopicARN: topic}, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
