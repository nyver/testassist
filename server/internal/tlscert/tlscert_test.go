package tlscert

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"
	"time"
)

var fingerprintPattern = regexp.MustCompile(`^([0-9A-F]{2}:){31}[0-9A-F]{2}$`)

func newOpts(t *testing.T) Options {
	t.Helper()
	dir := t.TempDir()
	return Options{
		CertFile: filepath.Join(dir, "certs", "server.crt"),
		KeyFile:  filepath.Join(dir, "certs", "server.key"),
		Name:     "Test Server",
	}
}

func TestFingerprintMatchesFixture(t *testing.T) {
	t.Parallel()

	certPath := filepath.Join("..", "..", "..", "protocol", "fixtures", "tls", "fingerprint_cert.pem")
	wantRaw, err := os.ReadFile(filepath.Join("..", "..", "..", "protocol", "fixtures", "tls", "fingerprint_cert.sha256.txt"))
	if err != nil {
		t.Fatal(err)
	}
	want := strings.TrimSpace(string(wantRaw))

	got, err := FingerprintFromFile(certPath)
	if err != nil {
		t.Fatalf("FingerprintFromFile: %v", err)
	}
	if got != want {
		t.Errorf("fingerprint = %s, want %s (from openssl)", got, want)
	}
	if len(got) != 95 || !fingerprintPattern.MatchString(got) {
		t.Errorf("fingerprint %q is not 32 upper-case hex pairs separated by colons", got)
	}
}

func TestFingerprintFromFileErrors(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	if _, err := FingerprintFromFile(filepath.Join(dir, "absent.crt")); err == nil {
		t.Error("expected an error for a missing file")
	}
	empty := filepath.Join(dir, "empty.crt")
	if err := os.WriteFile(empty, []byte("not pem"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := FingerprintFromFile(empty); !errors.Is(err, ErrConfiguration) {
		t.Errorf("err = %v, want ErrConfiguration", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "server.key")); err == nil {
		t.Error("FingerprintFromFile must not create files")
	}
}

func TestGenerate(t *testing.T) {
	t.Parallel()

	opts := newOpts(t)
	opts.Hosts = []string{"192.168.1.10", "assistant.home.arpa"}
	fixed := time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)
	opts.Now = func() time.Time { return fixed }

	res, err := LoadOrGenerate(opts)
	if err != nil {
		t.Fatalf("LoadOrGenerate: %v", err)
	}
	if !res.Generated {
		t.Error("Generated should be true on first start")
	}

	leaf := res.Certificate.Leaf
	if leaf == nil {
		t.Fatal("leaf not set")
	}
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok || pub.Curve != elliptic.P256() {
		t.Errorf("public key = %T, want ECDSA P-256", leaf.PublicKey)
	}
	if leaf.IsCA {
		t.Error("generated certificate must not be a CA")
	}
	if leaf.Subject.CommonName != "Test Server" {
		t.Errorf("CN = %q", leaf.Subject.CommonName)
	}
	if got := leaf.NotAfter.Sub(fixed); got < 9*365*24*time.Hour {
		t.Errorf("validity = %v, want about 10 years", got)
	}
	if !leaf.NotBefore.Before(fixed) {
		t.Errorf("NotBefore %v should tolerate clock skew", leaf.NotBefore)
	}
	assertSANs(t, leaf, []string{"localhost", "assistant.home.arpa"}, []string{"127.0.0.1", "192.168.1.10"})

	if err := leaf.VerifyHostname("192.168.1.10"); err != nil {
		t.Errorf("certificate does not verify for a configured IP: %v", err)
	}
	if !fingerprintPattern.MatchString(res.Fingerprint) {
		t.Errorf("fingerprint format: %q", res.Fingerprint)
	}

	for _, f := range []string{opts.CertFile, opts.KeyFile} {
		if _, err := os.Stat(f); err != nil {
			t.Errorf("expected %s to exist: %v", f, err)
		}
	}
	assertNoTempFiles(t, filepath.Dir(opts.CertFile))
	if runtime.GOOS != "windows" {
		info, err := os.Stat(opts.KeyFile)
		if err != nil {
			t.Fatal(err)
		}
		if perm := info.Mode().Perm(); perm != 0o600 {
			t.Errorf("key mode = %o, want 600", perm)
		}
	}

	keyPEM, err := os.ReadFile(opts.KeyFile)
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(keyPEM)
	if block == nil || block.Type != "PRIVATE KEY" {
		t.Errorf("key file should be PKCS#8 PEM, got %v", block)
	}
}

func assertSANs(t *testing.T, cert *x509.Certificate, dns, ips []string) {
	t.Helper()
	for _, name := range dns {
		found := false
		for _, n := range cert.DNSNames {
			found = found || n == name
		}
		if !found {
			t.Errorf("DNS SAN %q missing from %v", name, cert.DNSNames)
		}
	}
	for _, want := range ips {
		found := false
		for _, ip := range cert.IPAddresses {
			found = found || ip.Equal(net.ParseIP(want))
		}
		if !found {
			t.Errorf("IP SAN %s missing from %v", want, cert.IPAddresses)
		}
	}
}

func assertNoTempFiles(t *testing.T, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if strings.Contains(e.Name(), ".tmp-") {
			t.Errorf("leftover temporary file %s", e.Name())
		}
	}
}

func TestReloadKeepsFingerprintAndFiles(t *testing.T) {
	t.Parallel()

	opts := newOpts(t)
	first, err := LoadOrGenerate(opts)
	if err != nil {
		t.Fatalf("first start: %v", err)
	}
	certBefore, _ := os.ReadFile(opts.CertFile)
	keyBefore, _ := os.ReadFile(opts.KeyFile)

	second, err := LoadOrGenerate(opts)
	if err != nil {
		t.Fatalf("second start: %v", err)
	}
	if second.Generated {
		t.Error("second start must load, not generate")
	}
	if first.Fingerprint != second.Fingerprint {
		t.Errorf("fingerprint changed: %s -> %s", first.Fingerprint, second.Fingerprint)
	}
	certAfter, _ := os.ReadFile(opts.CertFile)
	keyAfter, _ := os.ReadFile(opts.KeyFile)
	if !bytes.Equal(certBefore, certAfter) || !bytes.Equal(keyBefore, keyAfter) {
		t.Error("existing files were modified")
	}

	fromFile, err := FingerprintFromFile(opts.CertFile)
	if err != nil {
		t.Fatal(err)
	}
	if fromFile != first.Fingerprint {
		t.Errorf("CLI fingerprint %s differs from served %s", fromFile, first.Fingerprint)
	}
}

func TestPartialStateIsRejected(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		removeCert bool
	}{
		{"key missing", false},
		{"certificate missing", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			opts := newOpts(t)
			if _, err := LoadOrGenerate(opts); err != nil {
				t.Fatal(err)
			}
			removed, kept := opts.KeyFile, opts.CertFile
			if tt.removeCert {
				removed, kept = opts.CertFile, opts.KeyFile
			}
			keptBefore, _ := os.ReadFile(kept)
			if err := os.Remove(removed); err != nil {
				t.Fatal(err)
			}

			_, err := LoadOrGenerate(opts)
			if !errors.Is(err, ErrConfiguration) {
				t.Fatalf("err = %v, want ErrConfiguration", err)
			}
			if _, statErr := os.Stat(removed); statErr == nil {
				t.Error("the missing file must not be regenerated")
			}
			keptAfter, _ := os.ReadFile(kept)
			if !bytes.Equal(keptBefore, keptAfter) {
				t.Error("the remaining file was modified")
			}
		})
	}
}

func TestKeyMismatchIsRejectedWithoutKeyMaterial(t *testing.T) {
	t.Parallel()

	a, b := newOpts(t), newOpts(t)
	if _, err := LoadOrGenerate(a); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadOrGenerate(b); err != nil {
		t.Fatal(err)
	}
	// Pair certificate A with key B.
	mixed := Options{CertFile: a.CertFile, KeyFile: b.KeyFile}
	_, err := LoadOrGenerate(mixed)
	if !errors.Is(err, ErrConfiguration) {
		t.Fatalf("err = %v, want ErrConfiguration", err)
	}
	msg := err.Error()
	if !strings.Contains(msg, "TLS_CONFIGURATION_ERROR") || !strings.Contains(msg, a.CertFile) || !strings.Contains(msg, b.KeyFile) {
		t.Errorf("message should name the code and both files: %q", msg)
	}
	keyPEM, _ := os.ReadFile(b.KeyFile)
	block, _ := pem.Decode(keyPEM)
	if strings.Contains(msg, "PRIVATE KEY") || strings.Contains(msg, string(block.Bytes)) {
		t.Errorf("message leaks key material: %q", msg)
	}
}

func TestLoadChainUsesFirstCertificateAsLeaf(t *testing.T) {
	t.Parallel()

	leafOpts, otherOpts := newOpts(t), newOpts(t)
	leaf, err := LoadOrGenerate(leafOpts)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := LoadOrGenerate(otherOpts); err != nil {
		t.Fatal(err)
	}
	leafPEM, _ := os.ReadFile(leafOpts.CertFile)
	otherPEM, _ := os.ReadFile(otherOpts.CertFile)
	chainFile := filepath.Join(t.TempDir(), "chain.crt")
	if err := os.WriteFile(chainFile, append(leafPEM, otherPEM...), 0o600); err != nil {
		t.Fatal(err)
	}

	res, err := Load(chainFile, leafOpts.KeyFile)
	if err != nil {
		t.Fatalf("Load chain: %v", err)
	}
	if res.Fingerprint != leaf.Fingerprint {
		t.Errorf("fingerprint = %s, want leaf %s", res.Fingerprint, leaf.Fingerprint)
	}
	if len(res.Certificate.Certificate) != 2 {
		t.Errorf("chain length = %d, want 2", len(res.Certificate.Certificate))
	}
	fromFile, err := FingerprintFromFile(chainFile)
	if err != nil || fromFile != leaf.Fingerprint {
		t.Errorf("FingerprintFromFile = %q, %v; want the leaf fingerprint", fromFile, err)
	}
}

func TestTLSConfigMinVersion(t *testing.T) {
	t.Parallel()

	res, err := LoadOrGenerate(newOpts(t))
	if err != nil {
		t.Fatal(err)
	}
	cfg := res.TLSConfig()
	if cfg.MinVersion < 0x0303 { // tls.VersionTLS12
		t.Errorf("MinVersion = %x, want at least TLS 1.2", cfg.MinVersion)
	}
	if len(cfg.Certificates) != 1 {
		t.Errorf("certificates = %d, want 1", len(cfg.Certificates))
	}
}
