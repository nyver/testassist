// Package identity persists the server's stable identity (server.json) and its
// Bearer token (auth.json). Both files carry a format version so readers can
// reject formats they do not understand instead of misreading them.
package identity

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/google/uuid"
)

const (
	serverFile = "server.json"
	authFile   = "auth.json"

	formatVersion = 1
	// tokenBytes gives a 256-bit token.
	tokenBytes = 32
)

// Info is the server identity shown to clients.
type Info struct {
	ServerID string
	Name     string
}

type serverRecord struct {
	Version  int    `json:"version"`
	ServerID string `json:"serverId"`
	Name     string `json:"name"`
}

type authRecord struct {
	Version int    `json:"version"`
	Token   string `json:"token"`
}

// LoadOrCreateServer returns the identity stored in <dataDir>/server.json. On
// first start it creates the file with a new UUIDv7 server id. A changed name
// updates the file while keeping the id. A corrupted file is reported and never
// overwritten.
func LoadOrCreateServer(dataDir, name string) (Info, error) {
	path := filepath.Join(dataDir, serverFile)

	var rec serverRecord
	err := readJSON(path, &rec)
	switch {
	case errors.Is(err, os.ErrNotExist):
		id, idErr := uuid.NewV7()
		if idErr != nil {
			return Info{}, fmt.Errorf("generate server id: %w", idErr)
		}
		rec = serverRecord{Version: formatVersion, ServerID: id.String(), Name: name}
		if err := writeJSON(path, rec); err != nil {
			return Info{}, err
		}
	case err != nil:
		return Info{}, err
	default:
		if rec.Version != formatVersion {
			return Info{}, fmt.Errorf("%s has unsupported version %d (expected %d)", path, rec.Version, formatVersion)
		}
		if _, parseErr := uuid.Parse(rec.ServerID); parseErr != nil {
			return Info{}, fmt.Errorf("%s is corrupted: serverId is not a valid UUID", path)
		}
		if rec.Name != name {
			rec.Name = name
			if err := writeJSON(path, rec); err != nil {
				return Info{}, err
			}
		}
	}
	return Info{ServerID: rec.ServerID, Name: rec.Name}, nil
}

// LoadOrCreateToken returns the token stored in <dataDir>/auth.json, creating
// it on first use.
func LoadOrCreateToken(dataDir string) (string, error) {
	path := filepath.Join(dataDir, authFile)

	var rec authRecord
	err := readJSON(path, &rec)
	switch {
	case errors.Is(err, os.ErrNotExist):
		return RotateToken(dataDir)
	case err != nil:
		return "", err
	}
	if rec.Version != formatVersion {
		return "", fmt.Errorf("%s has unsupported version %d (expected %d)", path, rec.Version, formatVersion)
	}
	if rec.Token == "" {
		return "", fmt.Errorf("%s is corrupted: token is empty", path)
	}
	return rec.Token, nil
}

// RotateToken replaces the persisted token with a new random one and returns it.
func RotateToken(dataDir string) (string, error) {
	buf := make([]byte, tokenBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generate token: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(buf)
	rec := authRecord{Version: formatVersion, Token: token}
	if err := writeJSON(filepath.Join(dataDir, authFile), rec); err != nil {
		return "", err
	}
	return token, nil
}

func readJSON(path string, v any) error {
	data, err := os.ReadFile(path) // #nosec G304 -- path is <data_dir>/<fixed name>.
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}
	if err := json.Unmarshal(data, v); err != nil {
		return fmt.Errorf("%s is corrupted and was left untouched: %w", path, err)
	}
	return nil
}

// writeJSON writes atomically: temp file, fsync, rename. os.CreateTemp creates
// the file with mode 0600, which is what auth.json needs and server.json can
// share.
func writeJSON(path string, v any) error {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return fmt.Errorf("encode %s: %w", path, err)
	}
	data = append(data, '\n')

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return fmt.Errorf("create directory %s: %w", dir, err)
	}
	f, err := os.CreateTemp(dir, filepath.Base(path)+".tmp-*")
	if err != nil {
		return fmt.Errorf("create temporary file in %s: %w (is the directory writable by this user?)", dir, err)
	}
	name := f.Name()
	cleanup := func(err error) error {
		_ = f.Close()
		_ = os.Remove(name)
		return fmt.Errorf("write %s: %w", path, err)
	}
	if _, err := f.Write(data); err != nil {
		return cleanup(err)
	}
	if err := f.Sync(); err != nil {
		return cleanup(err)
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(name)
		return fmt.Errorf("close %s: %w", path, err)
	}
	if err := os.Rename(name, path); err != nil {
		_ = os.Remove(name)
		return fmt.Errorf("replace %s: %w", path, err)
	}
	return nil
}

// ResolveToken returns the token the API must accept: envToken when it is set
// (AUTH_TOKEN), in which case auth.json is neither read nor created, otherwise
// the persisted token.
func ResolveToken(dataDir, envToken string) (string, error) {
	if envToken != "" {
		return envToken, nil
	}
	return LoadOrCreateToken(dataDir)
}
