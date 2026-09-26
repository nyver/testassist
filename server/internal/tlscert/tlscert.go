// Package tlscert loads or generates the server's TLS certificate and computes
// its fingerprint.
//
// State machine: if both files exist they are loaded unchanged; if neither
// exists a self-signed ECDSA P-256 certificate is generated and persisted; if
// exactly one exists the package refuses to continue, because regenerating
// could silently replace a certificate the operator provided.
package tlscert

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ErrConfiguration marks every certificate configuration problem. Its text is
// the stable code the spec requires in log output.
var ErrConfiguration = errors.New("TLS_CONFIGURATION_ERROR")

// selfSignedValidity is deliberately long: clients pin the fingerprint and do
// not depend on expiry, so a short validity would only cause an unwanted
// certificate-changed event. Rotation is an explicit operator action.
const selfSignedValidity = 10 * 365 * 24 * time.Hour

// Options configures LoadOrGenerate.
type Options struct {
	CertFile string
	KeyFile  string
	// Name becomes the subject common name of a generated certificate.
	Name string
	// Hosts are extra host names or IP addresses for a generated certificate,
	// in addition to "localhost" and "127.0.0.1".
	Hosts []string
	// Now returns the current time. It defaults to time.Now.
	Now func() time.Time
}

// Result is a loaded certificate ready to serve.
type Result struct {
	Certificate tls.Certificate
	// Fingerprint is the SHA-256 fingerprint of the leaf certificate.
	Fingerprint string
	// Generated reports whether this call created a new certificate.
	Generated bool
}

// TLSConfig returns a server configuration that requires TLS 1.2 or newer.
func (r *Result) TLSConfig() *tls.Config {
	return &tls.Config{
		MinVersion:   tls.VersionTLS12,
		Certificates: []tls.Certificate{r.Certificate},
	}
}

// Fingerprint returns the SHA-256 digest of the DER-encoded certificate as
// upper-case hexadecimal byte pairs separated by colons.
func Fingerprint(der []byte) string {
	sum := sha256.Sum256(der)
	pairs := make([]string, len(sum))
	for i, b := range sum {
		pairs[i] = strings.ToUpper(hex.EncodeToString([]byte{b}))
	}
	return strings.Join(pairs, ":")
}

// FingerprintFromFile returns the fingerprint of the first certificate in a PEM
// file without touching any other state. It never generates a certificate.
func FingerprintFromFile(certFile string) (string, error) {
	der, err := leafDER(certFile)
	if err != nil {
		return "", err
	}
	return Fingerprint(der), nil
}

// LoadOrGenerate implements the certificate state machine described in the
// package documentation.
func LoadOrGenerate(opts Options) (*Result, error) {
	certExists, err := exists(opts.CertFile)
	if err != nil {
		return nil, err
	}
	keyExists, err := exists(opts.KeyFile)
	if err != nil {
		return nil, err
	}

	switch {
	case certExists && keyExists:
		return Load(opts.CertFile, opts.KeyFile)
	case !certExists && !keyExists:
		return generate(opts)
	default:
		present, missing := opts.CertFile, opts.KeyFile
		if keyExists {
			present, missing = opts.KeyFile, opts.CertFile
		}
		return nil, fmt.Errorf("%w: %s exists but %s does not; refusing to generate a new certificate "+
			"(provide both files, or remove %s to generate a new pair)",
			ErrConfiguration, present, missing, present)
	}
}

// Load reads a certificate chain and private key and verifies that they match.
// The first certificate in the file is the leaf.
func Load(certFile, keyFile string) (*Result, error) {
	pair, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		// The message of LoadX509KeyPair names files or a mismatch, never key bytes.
		return nil, fmt.Errorf("%w: load certificate %s with key %s: %v", ErrConfiguration, certFile, keyFile, err)
	}
	leaf, err := x509.ParseCertificate(pair.Certificate[0])
	if err != nil {
		return nil, fmt.Errorf("%w: parse leaf certificate in %s: %v", ErrConfiguration, certFile, err)
	}
	pair.Leaf = leaf
	return &Result{Certificate: pair, Fingerprint: Fingerprint(leaf.Raw)}, nil
}

func generate(opts Options) (*Result, error) {
	now := time.Now
	if opts.Now != nil {
		now = opts.Now
	}

	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate ECDSA key: %w", err)
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, fmt.Errorf("generate serial number: %w", err)
	}

	dnsNames := []string{"localhost"}
	ips := []net.IP{net.ParseIP("127.0.0.1")}
	for _, h := range opts.Hosts {
		if ip := net.ParseIP(h); ip != nil {
			ips = append(ips, ip)
		} else {
			dnsNames = append(dnsNames, h)
		}
	}

	issued := now()
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: opts.Name},
		NotBefore:             issued.Add(-5 * time.Minute), // tolerate small clock skew on clients
		NotAfter:              issued.Add(selfSignedValidity),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		IsCA:                  false,
		DNSNames:              dnsNames,
		IPAddresses:           ips,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return nil, fmt.Errorf("create self-signed certificate: %w", err)
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return nil, fmt.Errorf("encode private key: %w", err)
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})
	if err := persistPair(opts.CertFile, certPEM, opts.KeyFile, keyPEM); err != nil {
		return nil, err
	}

	res, err := Load(opts.CertFile, opts.KeyFile)
	if err != nil {
		return nil, err
	}
	res.Generated = true
	return res, nil
}

// persistPair writes both files to temporary names in their target
// directories, then renames the certificate before the key, so a crash cannot
// leave a valid key without a certificate.
func persistPair(certFile string, certPEM []byte, keyFile string, keyPEM []byte) error {
	certTmp, err := writeTemp(certFile, certPEM, 0o644) // #nosec G302 -- the certificate is public.
	if err != nil {
		return err
	}
	keyTmp, err := writeTemp(keyFile, keyPEM, 0o600)
	if err != nil {
		_ = os.Remove(certTmp)
		return err
	}
	if err := os.Rename(certTmp, certFile); err != nil {
		_ = os.Remove(certTmp)
		_ = os.Remove(keyTmp)
		return fmt.Errorf("install certificate %s: %w", certFile, err)
	}
	if err := os.Rename(keyTmp, keyFile); err != nil {
		_ = os.Remove(keyTmp)
		return fmt.Errorf("install private key %s: %w", keyFile, err)
	}
	return nil
}

func writeTemp(target string, data []byte, perm os.FileMode) (string, error) {
	dir := filepath.Dir(target)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return "", fmt.Errorf("create directory %s: %w", dir, err)
	}
	f, err := os.CreateTemp(dir, filepath.Base(target)+".tmp-*")
	if err != nil {
		return "", fmt.Errorf("create temporary file in %s: %w (is the directory writable by this user?)", dir, err)
	}
	name := f.Name()
	fail := func(step string, err error) (string, error) {
		_ = f.Close()
		_ = os.Remove(name)
		return "", fmt.Errorf("%s %s: %w", step, target, err)
	}
	if _, err := f.Write(data); err != nil {
		return fail("write", err)
	}
	if err := f.Sync(); err != nil {
		return fail("sync", err)
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(name)
		return "", fmt.Errorf("close %s: %w", target, err)
	}
	if err := os.Chmod(name, perm); err != nil {
		_ = os.Remove(name)
		return "", fmt.Errorf("set permissions on %s: %w", target, err)
	}
	return name, nil
}

func exists(path string) (bool, error) {
	_, err := os.Stat(path)
	switch {
	case err == nil:
		return true, nil
	case errors.Is(err, os.ErrNotExist):
		return false, nil
	default:
		return false, fmt.Errorf("%w: inspect %s: %v", ErrConfiguration, path, err)
	}
}

func leafDER(certFile string) ([]byte, error) {
	data, err := os.ReadFile(certFile) // #nosec G304 -- path comes from configuration.
	if err != nil {
		return nil, fmt.Errorf("read certificate %s: %w", certFile, err)
	}
	for {
		var block *pem.Block
		block, data = pem.Decode(data)
		if block == nil {
			return nil, fmt.Errorf("%w: no certificate found in %s", ErrConfiguration, certFile)
		}
		if block.Type == "CERTIFICATE" {
			return block.Bytes, nil
		}
	}
}
