package main

import (
	"context"
	"net"
	"testing"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"

	gamev1 "github.com/cjbramble/botchat/game/gen/game/v1"
	"github.com/cjbramble/botchat/game/internal/hub"
	"github.com/cjbramble/botchat/game/internal/match"
)

const testToken = "test-token"

// newClient serves the game in memory behind the production auth interceptors
// and returns a client connected to it.
func newClient(t *testing.T) gamev1.GameServiceClient {
	t.Helper()
	lis := bufconn.Listen(1 << 20)
	s := grpc.NewServer(
		grpc.UnaryInterceptor(unaryAuth(testToken)),
		grpc.StreamInterceptor(streamAuth(testToken)),
	)
	cfg := match.DefaultConfig()
	cfg.JoinWindow = 200 * time.Millisecond
	gamev1.RegisterGameServiceServer(s, &server{hub: hub.New(cfg)})

	serveErr := make(chan error, 1)
	go func() { serveErr <- s.Serve(lis) }()
	t.Cleanup(func() {
		s.Stop()
		if err := <-serveErr; err != nil {
			t.Errorf("serve: %v", err)
		}
	})

	conn, err := grpc.NewClient("passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) { return lis.DialContext(ctx) }),
		grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := conn.Close(); err != nil {
			t.Errorf("close client: %v", err)
		}
	})
	return gamev1.NewGameServiceClient(conn)
}

// timeout returns a context that keeps a broken test from hanging.
func timeout(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	t.Cleanup(cancel)
	return ctx
}

func authed(t *testing.T) context.Context {
	t.Helper()
	return metadata.AppendToOutgoingContext(timeout(t), tokenHeader, testToken)
}

func TestNoTokenIsUnauthenticated(t *testing.T) { // GAME-A-01
	cases := []struct {
		name string
		call func(context.Context, gamev1.GameServiceClient) error
	}{
		{"unary", func(ctx context.Context, c gamev1.GameServiceClient) error {
			_, err := c.SubmitInput(ctx, &gamev1.SubmitInputRequest{Channel: "games", PlayerId: "pim", Text: "!start"})
			return err
		}},
		{"stream", func(ctx context.Context, c gamev1.GameServiceClient) error {
			stream, err := c.Subscribe(ctx, &gamev1.SubscribeRequest{Channel: "games"})
			if err != nil {
				return err
			}
			_, err = stream.Recv() // a stream's status arrives with the first receive
			return err
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.call(timeout(t), newClient(t))
			if status.Code(err) != codes.Unauthenticated {
				t.Fatalf("want Unauthenticated, got %v", err)
			}
		})
	}
}

func TestStartIsStreamedWithSeq1(t *testing.T) { // GAME-A-03
	c := newClient(t)
	ctx := authed(t)
	stream, err := c.Subscribe(ctx, &gamev1.SubscribeRequest{Channel: "games"})
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(50 * time.Millisecond) // let the subscription register
	if _, err := c.SubmitInput(ctx, &gamev1.SubmitInputRequest{Channel: "games", PlayerId: "pim", Text: "!start", MsgId: "1"}); err != nil {
		t.Fatal(err)
	}
	msg, err := stream.Recv()
	if err != nil || msg.GetSeq() != 1 {
		t.Fatalf("want seq 1, got %v / %v", msg, err)
	}
}
