package app

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/nyver/test-assistant/server/internal/config"
)

const healthcheckTimeout = 5 * time.Second

// HealthCheck calls /health/ready on the local listener over HTTPS and returns
// an error unless the server answers 200. It verifies the served certificate
// against the configured certificate file: a self-signed leaf is the only trust
// anchor, and a CA-issued chain is verified against the system roots. It never
// skips verification.
func HealthCheck(ctx context.Context, cfg *config.Config) error {
	tlsCfg, err := healthcheckTLSConfig(cfg.TLS.CertFile)
	if err != nil {
		return err
	}
	_, port, err := net.SplitHostPort(cfg.Server.Listen)
	if err != nil {
		return fmt.Errorf("parse server.listen %q: %w", cfg.Server.Listen, err)
	}

	client := &http.Client{
		Timeout:   healthcheckTimeout,
		Transport: &http.Transport{TLSClientConfig: tlsCfg, DisableKeepAlives: true},
	}
	defer client.CloseIdleConnections()

	url := "https://" + net.JoinHostPort("127.0.0.1", port) + "/health/ready"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	resp, err := client.Do(req) // #nosec G704 -- the target is the local listener.
	if err != nil {
		return fmt.Errorf("call %s: %w", url, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("server is not ready: HTTP %d", resp.StatusCode)
	}
	return nil
}

func healthcheckTLSConfig(certFile string) (*tls.Config, error) {
	data, err := os.ReadFile(certFile) // #nosec G304 -- path comes from configuration.
	if err != nil {
		return nil, fmt.Errorf("read certificate %s: %w", certFile, err)
	}
	var leaf *x509.Certificate
	for rest := data; ; {
		var block *pem.Block
		block, rest = pem.Decode(rest)
		if block == nil {
			break
		}
		if block.Type != "CERTIFICATE" {
			continue
		}
		if leaf, err = x509.ParseCertificate(block.Bytes); err != nil {
			return nil, fmt.Errorf("parse certificate %s: %w", certFile, err)
		}
		break
	}
	if leaf == nil {
		return nil, fmt.Errorf("no certificate found in %s", certFile)
	}

	cfg := &tls.Config{MinVersion: tls.VersionTLS12}
	if len(leaf.DNSNames) > 0 {
		// The check dials 127.0.0.1, which a certificate for a public name does
		// not cover, so verify against the name the certificate is issued for.
		cfg.ServerName = leaf.DNSNames[0]
	}
	if isSelfSigned(leaf) {
		pool := x509.NewCertPool()
		pool.AddCert(leaf)
		cfg.RootCAs = pool
	}
	// Otherwise RootCAs stays nil and the system roots verify the chain.
	return cfg, nil
}

// isSelfSigned reports whether the certificate names itself as issuer and is
// signed with its own key. CheckSignatureFrom is not used because it rejects a
// non-CA parent, which is what a generated leaf certificate is.
func isSelfSigned(c *x509.Certificate) bool {
	return bytes.Equal(c.RawSubject, c.RawIssuer) &&
		c.CheckSignature(c.SignatureAlgorithm, c.RawTBSCertificate, c.Signature) == nil
}
