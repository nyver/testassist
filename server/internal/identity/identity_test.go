package identity

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestServerFirstStartCreatesIdentity(t *testing.T) {
	t.Parallel()

	dir := filepath.Join(t.TempDir(), "data") // does not exist yet
	info, err := LoadOrCreateServer(dir, "Home")
	if err != nil {
		t.Fatalf("LoadOrCreateServer: %v", err)
	}
	id, err := uuid.Parse(info.ServerID)
	if err != nil {
		t.Fatalf("serverId %q is not a UUID: %v", info.ServerID, err)
	}
	if id.Version() != 7 {
		t.Errorf("UUID version = %d, want 7", id.Version())
	}
	if info.Name != "Home" {
		t.Errorf("name = %q", info.Name)
	}

	raw, err := os.ReadFile(filepath.Join(dir, "server.json"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`"version": 1`, `"serverId": "` + info.ServerID + `"`, `"name": "Home"`} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("server.json lacks %s:\n%s", want, raw)
		}
	}
}

func TestServerRestartKeepsIDAndNameChangeUpdatesFile(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	first, err := LoadOrCreateServer(dir, "Home")
	if err != nil {
		t.Fatal(err)
	}
	again, err := LoadOrCreateServer(dir, "Home")
	if err != nil {
		t.Fatal(err)
	}
	if again != first {
		t.Errorf("restart changed identity: %+v -> %+v", first, again)
	}

	renamed, err := LoadOrCreateServer(dir, "Office")
	if err != nil {
		t.Fatal(err)
	}
	if renamed.ServerID != first.ServerID || renamed.Name != "Office" {
		t.Errorf("rename result = %+v", renamed)
	}
	reread, err := LoadOrCreateServer(dir, "Office")
	if err != nil || reread != renamed {
		t.Errorf("name change was not persisted: %+v, %v", reread, err)
	}
}

func TestServerRejectsBadFilesWithoutOverwriting(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		content string
	}{
		{"not json", "{not json"},
		{"future version", `{"version":2,"serverId":"019d2f6e-8a3c-7c1e-9b41-5d2a6f0e1c77","name":"x"}`},
		{"invalid uuid", `{"version":1,"serverId":"abc","name":"x"}`},
		{"empty object", `{}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			path := filepath.Join(dir, "server.json")
			if err := os.WriteFile(path, []byte(tt.content), 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := LoadOrCreateServer(dir, "Home"); err == nil {
				t.Fatal("expected an error")
			}
			got, _ := os.ReadFile(path)
			if string(got) != tt.content {
				t.Errorf("file was overwritten: %q", got)
			}
		})
	}
}

func TestTokenGenerationAndPersistence(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	token, err := LoadOrCreateToken(dir)
	if err != nil {
		t.Fatalf("LoadOrCreateToken: %v", err)
	}
	raw, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil {
		t.Fatalf("token is not base64url: %v", err)
	}
	if len(raw) < 32 {
		t.Errorf("token carries %d bytes, want at least 32 (256 bits)", len(raw))
	}

	again, err := LoadOrCreateToken(dir)
	if err != nil || again != token {
		t.Errorf("token changed on reload: %q, %v", again, err)
	}
	if runtime.GOOS != "windows" {
		info, err := os.Stat(filepath.Join(dir, "auth.json"))
		if err != nil {
			t.Fatal(err)
		}
		if perm := info.Mode().Perm(); perm != 0o600 {
			t.Errorf("auth.json mode = %o, want 600", perm)
		}
	}
}

func TestTokenRotation(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	old, err := LoadOrCreateToken(dir)
	if err != nil {
		t.Fatal(err)
	}
	rotated, err := RotateToken(dir)
	if err != nil {
		t.Fatalf("RotateToken: %v", err)
	}
	if rotated == old {
		t.Error("rotation returned the same token")
	}
	current, err := LoadOrCreateToken(dir)
	if err != nil || current != rotated {
		t.Errorf("persisted token = %q, %v; want the rotated one", current, err)
	}
}

func TestTokenRejectsBadFiles(t *testing.T) {
	t.Parallel()

	for name, content := range map[string]string{
		"not json":       "nope",
		"empty token":    `{"version":1,"token":""}`,
		"future version": `{"version":9,"token":"abc"}`,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			path := filepath.Join(dir, "auth.json")
			if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := LoadOrCreateToken(dir); err == nil {
				t.Fatal("expected an error")
			}
			if got, _ := os.ReadFile(path); string(got) != content {
				t.Errorf("file was overwritten: %q", got)
			}
		})
	}
}

func TestWriteLeavesNoTempFiles(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	if _, err := LoadOrCreateServer(dir, "Home"); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadOrCreateToken(dir); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		names := make([]string, 0, len(entries))
		for _, e := range entries {
			names = append(names, e.Name())
		}
		t.Errorf("unexpected files in data dir: %v", names)
	}
}

func TestResolveTokenPrefersEnvironmentAndSkipsFile(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	got, err := ResolveToken(dir, "from-env")
	if err != nil || got != "from-env" {
		t.Fatalf("ResolveToken = %q, %v", got, err)
	}
	if _, err := os.Stat(filepath.Join(dir, "auth.json")); err == nil {
		t.Error("auth.json must not be created when AUTH_TOKEN is set")
	}

	generated, err := ResolveToken(dir, "")
	if err != nil || generated == "" || generated == "from-env" {
		t.Errorf("ResolveToken without env = %q, %v", generated, err)
	}
}
