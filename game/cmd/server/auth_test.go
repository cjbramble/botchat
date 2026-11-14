package main

import (
	"context"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

func TestCheckToken(t *testing.T) {
	cases := []struct {
		name string
		md   metadata.MD
		ok   bool
	}{
		{"right token", metadata.Pairs(tokenHeader, "secret"), true},
		{"wrong token", metadata.Pairs(tokenHeader, "nope"), false},
		{"no token", metadata.MD{}, false},
		{"two tokens", metadata.Pairs(tokenHeader, "secret", tokenHeader, "secret"), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ctx := metadata.NewIncomingContext(context.Background(), tc.md)
			err := checkToken(ctx, "secret")
			if tc.ok != (err == nil) {
				t.Fatalf("err = %v", err)
			}
			if err != nil && status.Code(err) != codes.Unauthenticated {
				t.Fatalf("code = %v, want Unauthenticated", status.Code(err))
			}
		})
	}
}
