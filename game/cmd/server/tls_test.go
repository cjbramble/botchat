package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
)

// testCA is a throwaway certificate authority, like the one cert-manager runs.
type testCA struct {
	cert *x509.Certificate
	key  *ecdsa.PrivateKey
	pem  []byte
}

func newCA(t *testing.T) testCA {
	t.Helper()
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "test CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, _ := x509.ParseCertificate(der)
	return testCA{cert: cert, key: key, pem: pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})}
}

// issue signs a leaf certificate for name and returns it as PEM (cert, key).
func (ca testCA) issue(t *testing.T, name string, serial int64, usage x509.ExtKeyUsage) ([]byte, []byte) {
	t.Helper()
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(serial),
		Subject:      pkix.Name{CommonName: name},
		DNSNames:     []string{name},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{usage},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, ca.cert, &key.PublicKey, ca.key)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, _ := x509.MarshalECPrivateKey(key)
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}),
		pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
}

// writeServerFiles lays out dir the way cert-manager's Secret looks when mounted.
func writeServerFiles(t *testing.T, dir string, ca testCA, serial int64) {
	t.Helper()
	certPEM, keyPEM := ca.issue(t, "game", serial, x509.ExtKeyUsageServerAuth)
	for name, data := range map[string][]byte{"tls.crt": certPEM, "tls.key": keyPEM, "ca.crt": ca.pem} {
		if err := os.WriteFile(filepath.Join(dir, name), data, 0o600); err != nil {
			t.Fatal(err)
		}
	}
}

// startServer runs a gRPC server with only the health service, behind mutual TLS.
func startServer(t *testing.T, dir string) string {
	t.Helper()
	cfg, err := mutualTLSConfig(dir, "chat")
	if err != nil {
		t.Fatal(err)
	}
	s := grpc.NewServer(grpc.Creds(credentials.NewTLS(cfg)))
	healthpb.RegisterHealthServer(s, health.NewServer())
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() { _ = s.Serve(lis) }()
	t.Cleanup(s.Stop)
	return lis.Addr().String()
}

// call makes one RPC as a client holding the given certificate (nil = none).
// It returns the error and the serial number of the server's certificate.
func call(t *testing.T, addr string, serverCA []byte, clientCert *tls.Certificate) (*big.Int, error) {
	t.Helper()
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(serverCA)
	var seen *big.Int
	cfg := &tls.Config{
		RootCAs:    roots,
		ServerName: "game", // the name chat checks in the server's certificate
		VerifyConnection: func(cs tls.ConnectionState) error {
			seen = cs.PeerCertificates[0].SerialNumber
			return nil
		},
	}
	if clientCert != nil {
		cfg.Certificates = []tls.Certificate{*clientCert}
	}
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(credentials.NewTLS(cfg)))
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, err = healthpb.NewHealthClient(conn).Check(ctx, &healthpb.HealthCheckRequest{})
	return seen, err
}

func clientCert(t *testing.T, ca testCA, name string) *tls.Certificate {
	t.Helper()
	certPEM, keyPEM := ca.issue(t, name, 100, x509.ExtKeyUsageClientAuth)
	cert, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		t.Fatal(err)
	}
	return &cert
}

func TestMutualTLS(t *testing.T) {
	ca, otherCA := newCA(t), newCA(t)
	dir := t.TempDir()
	writeServerFiles(t, dir, ca, 2)
	addr := startServer(t, dir)

	tests := []struct {
		name   string
		client *tls.Certificate
		wantOK bool
	}{
		{"chat with a certificate from our CA", clientCert(t, ca, "chat"), true},
		{"another service from our CA", clientCert(t, ca, "bots"), false},
		{"no client certificate", nil, false},
		{"chat's name from a different CA", clientCert(t, otherCA, "chat"), false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := call(t, addr, ca.pem, tt.client)
			if gotOK := err == nil; gotOK != tt.wantOK {
				t.Fatalf("ok = %v, want %v (err: %v)", gotOK, tt.wantOK, err)
			}
		})
	}
}

func TestRenewedCertificateIsUsedWithoutRestart(t *testing.T) {
	ca := newCA(t)
	dir := t.TempDir()
	writeServerFiles(t, dir, ca, 2)
	addr := startServer(t, dir)
	chat := clientCert(t, ca, "chat")

	serial, err := call(t, addr, ca.pem, chat)
	if err != nil || serial.Int64() != 2 {
		t.Fatalf("first call: serial %v, err %v", serial, err)
	}

	writeServerFiles(t, dir, ca, 3) // what cert-manager does when it renews

	serial, err = call(t, addr, ca.pem, chat)
	if err != nil || serial.Int64() != 3 {
		t.Fatalf("after renewal: serial %v, err %v; want the new certificate (3)", serial, err)
	}
}

func TestMissingFilesFailAtStartup(t *testing.T) {
	if _, err := mutualTLSConfig(t.TempDir(), "chat"); err == nil {
		t.Fatal("want an error for an empty folder")
	}
}
