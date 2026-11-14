package main

import (
	"context"
	"crypto/subtle"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

const tokenHeader = "x-internal-token"

// checkToken returns an Unauthenticated error unless ctx carries the right token.
func checkToken(ctx context.Context, want string) error {
	md, _ := metadata.FromIncomingContext(ctx)
	got := md.Get(tokenHeader)
	if len(got) != 1 || subtle.ConstantTimeCompare([]byte(got[0]), []byte(want)) != 1 {
		return status.Error(codes.Unauthenticated, "missing or bad internal token")
	}
	return nil
}

func unaryAuth(token string) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, _ *grpc.UnaryServerInfo, next grpc.UnaryHandler) (any, error) {
		if err := checkToken(ctx, token); err != nil {
			return nil, err
		}
		return next(ctx, req)
	}
}

func streamAuth(token string) grpc.StreamServerInterceptor {
	return func(srv any, ss grpc.ServerStream, _ *grpc.StreamServerInfo, next grpc.StreamHandler) error {
		if err := checkToken(ss.Context(), token); err != nil {
			return err
		}
		return next(srv, ss)
	}
}
