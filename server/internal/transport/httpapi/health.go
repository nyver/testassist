package httpapi

import (
	"errors"
	"net/http"
	"os"
)

type healthResponse struct {
	Status string   `json:"status"`
	Failed []string `json:"failed,omitempty"`
}

// healthLive reports that the process is running.
func (s *Server) healthLive(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, healthResponse{Status: "ok"})
}

// healthReady succeeds only when the data directory is writable, a certificate
// is loaded and at least one provider is enabled. Configuration was validated
// at startup, or the process would not be running. It never calls an LLM.
func (s *Server) healthReady(w http.ResponseWriter, _ *http.Request) {
	var failed []string
	if err := checkWritable(s.deps.Config.Server.DataDir); err != nil {
		failed = append(failed, "data_dir")
	}
	if !s.deps.CertLoaded {
		failed = append(failed, "certificate")
	}
	if !s.deps.Registry.Enabled() {
		failed = append(failed, "providers")
	}

	if len(failed) > 0 {
		writeJSON(w, http.StatusServiceUnavailable, healthResponse{Status: "not_ready", Failed: failed})
		return
	}
	writeJSON(w, http.StatusOK, healthResponse{Status: "ready"})
}

// checkWritable creates and removes a temporary file in dir.
func checkWritable(dir string) error {
	f, err := os.CreateTemp(dir, ".ready-*")
	if err != nil {
		return err
	}
	return errors.Join(f.Close(), os.Remove(f.Name()))
}
