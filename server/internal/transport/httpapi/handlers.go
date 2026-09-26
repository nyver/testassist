package httpapi

import (
	"net/http"

	"github.com/nyver/test-assistant/server/internal/apierr"
)

type serverInfoResponse struct {
	ServerID string `json:"serverId"`
	Name     string `json:"name"`
	Version  string `json:"version"`
}

type providerResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	IsDefault bool   `json:"isDefault"`
}

type capabilitiesResponse struct {
	Text   bool `json:"text"`
	Vision bool `json:"vision"`
}

type modelResponse struct {
	ID           string               `json:"id"`
	Name         string               `json:"name"`
	Capabilities capabilitiesResponse `json:"capabilities"`
	IsDefault    bool                 `json:"isDefault"`
}

func (s *Server) serverInfo(w http.ResponseWriter, _ *http.Request) error {
	writeJSON(w, http.StatusOK, serverInfoResponse{
		ServerID: s.deps.Identity.ServerID,
		Name:     s.deps.Identity.Name,
		Version:  s.deps.Version,
	})
	return nil
}

func (s *Server) listProviders(w http.ResponseWriter, _ *http.Request) error {
	providers := s.deps.Registry.Providers()
	out := make([]providerResponse, 0, len(providers))
	for _, p := range providers {
		out = append(out, providerResponse{ID: p.ID, Name: p.Name, IsDefault: p.IsDefault})
	}
	writeJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) listModels(w http.ResponseWriter, r *http.Request) error {
	reg := s.deps.Registry
	providerID := r.URL.Query().Get("provider")
	if providerID == "" {
		providerID = reg.DefaultProviderID()
	}
	if providerID == "" || !reg.Has(providerID) {
		return apierr.New(apierr.ProviderNotFound, "Provider not found.")
	}

	models, err := reg.Models(r.Context(), providerID)
	if err != nil {
		return apierr.Wrap(apierr.Internal, "Internal server error.", err)
	}
	defaultModel := reg.DefaultModel(providerID)
	out := make([]modelResponse, 0, len(models))
	for _, m := range models {
		out = append(out, modelResponse{
			ID:           m.ID,
			Name:         m.Name,
			Capabilities: capabilitiesResponse{Text: m.Capabilities.Text, Vision: m.Capabilities.Vision},
			IsDefault:    m.ID == defaultModel,
		})
	}
	writeJSON(w, http.StatusOK, out)
	return nil
}
