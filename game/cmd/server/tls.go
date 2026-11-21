package main

import (
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
)

// transportCreds picks how the gRPC server talks on the wire.
//
// With GAME_TLS_DIR set, it requires mutual TLS: the folder must hold tls.crt,
// tls.key and ca.crt (the layout cert-manager writes into a Kubernetes Secret),
// and only a client whose certificate names GAME_TLS_CLIENT (default "chat") is
// accepted. Without it, the server speaks plaintext, for your laptop and Compose.
func transportCreds() (grpc.ServerOption, error) {
	dir := os.Getenv("GAME_TLS_DIR")
	if dir == "" {
		return grpc.Creds(insecure.NewCredentials()), nil
	}
	cfg, err := mutualTLSConfig(dir, envOr("GAME_TLS_CLIENT", "chat"))
	if err != nil {
		return nil, err
	}
	return grpc.Creds(credentials.NewTLS(cfg)), nil
}

// mutualTLSConfig returns a server config that demands a client certificate
// signed by ca.crt and issued to allowedClient. It rereads the files on every
// handshake, so certificates renewed on disk are used without a restart.
func mutualTLSConfig(dir, allowedClient string) (*tls.Config, error) {
	if _, err := loadMaterial(dir); err != nil { // fail at startup, not on the first call
		return nil, err
	}
	return &tls.Config{
		MinVersion: tls.VersionTLS13,
		GetConfigForClient: func(*tls.ClientHelloInfo) (*tls.Config, error) {
			m, err := loadMaterial(dir)
			if err != nil {
				return nil, err
			}
			return &tls.Config{
				MinVersion:   tls.VersionTLS13,
				NextProtos:   []string{"h2"}, // gRPC runs over HTTP/2
				Certificates: []tls.Certificate{m.cert},
				ClientAuth:   tls.RequireAndVerifyClientCert,
				ClientCAs:    m.ca,
				// The chain is already checked against our CA. This checks who it is.
				VerifyConnection: func(cs tls.ConnectionState) error {
					if len(cs.PeerCertificates) == 0 {
						return errors.New("no client certificate")
					}
					if err := cs.PeerCertificates[0].VerifyHostname(allowedClient); err != nil {
						return fmt.Errorf("client is not %q: %w", allowedClient, err)
					}
					return nil
				},
			}, nil
		},
	}, nil
}

type material struct {
	cert tls.Certificate
	ca   *x509.CertPool
}

func loadMaterial(dir string) (material, error) {
	cert, err := tls.LoadX509KeyPair(filepath.Join(dir, "tls.crt"), filepath.Join(dir, "tls.key"))
	if err != nil {
		return material{}, fmt.Errorf("load server certificate: %w", err)
	}
	caPEM, err := os.ReadFile(filepath.Join(dir, "ca.crt"))
	if err != nil {
		return material{}, fmt.Errorf("read CA: %w", err)
	}
	ca := x509.NewCertPool()
	if !ca.AppendCertsFromPEM(caPEM) {
		return material{}, errors.New("ca.crt holds no PEM certificates")
	}
	return material{cert: cert, ca: ca}, nil
}
