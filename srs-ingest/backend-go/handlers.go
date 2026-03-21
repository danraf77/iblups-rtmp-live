package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
)

// SRS Webhook payload
type SrsRequest struct {
	Action   string `json:"action"`
	ClientId string `json:"client_id"`
	Ip       string `json:"ip"`
	Vhost    string `json:"vhost"`
	App      string `json:"app"`
	Stream   string `json:"stream"` // This is the stream_key
	Param    string `json:"param"`
}

func parseSrsRequest(r *http.Request) (*SrsRequest, error) {
	var req SrsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		return nil, err
	}
	return &req, nil
}

func HandleOnPublish(w http.ResponseWriter, r *http.Request) {
	req, err := parseSrsRequest(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	banned, err := IsIPBanned(req.Ip)
	if err != nil {
		log.Printf("on_publish: failed to check ban for %s: %v", req.Ip, err)
	}
	if banned {
		log.Printf("on_publish: rejected banned IP %s (stream: %s)", req.Ip, req.Stream)
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"code": 1, "data": "ip banned"}`))
		return
	}

	hlsToken, thumbToken, err := activateStream(req.Stream)
	if err != nil {
		log.Printf("on_publish rejected for %s: %v", req.Stream, err)
		
		// Retornar 1 le indica a SRS que cierre la conexion RTMP
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"code": 1, "data": "auth failed"}`))
		return
	}

	log.Printf("on_publish approved for %s. HLS: %s, Thumb: %s", req.Stream, hlsToken, thumbToken)

	if err := LogPublishSession(req.Stream, req.Ip); err != nil {
		log.Printf("on_publish: failed to log session for %s: %v", req.Stream, err)
	}

	// Retornar 0 le permite al cliente continuar publicando
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"code": 0, "data": "ok"}`))
}

func HandleOnUnpublish(w http.ResponseWriter, r *http.Request) {
	req, err := parseSrsRequest(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if err := deactivateStream(req.Stream); err != nil {
		log.Printf("on_unpublish error for %s: %v", req.Stream, err)
	}

	log.Printf("on_unpublish processed for %s", req.Stream)

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"code": 0, "data": "ok"}`))
}

func HandleListStreams(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status": "ok", "streams": []}`))
}

func HandleGetTokens(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status": "ok", "tokens": {}}`))
}

type KickoffRequest struct {
	StreamID string `json:"stream_id"`
	Reason   string `json:"reason"`
}

func HandleKickoff(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	token := os.Getenv("INTERNAL_TOKEN")
	if token == "" || r.Header.Get("X-Internal-Token") != token {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error": "unauthorized"}`))
		return
	}

	var req KickoffRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.StreamID == "" {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	cid, err := FindPublisherCid(req.StreamID)
	if err != nil {
		log.Printf("kickoff: publisher not found for %s: %v", req.StreamID, err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte(`{"error": "stream not found or not active"}`))
		return
	}

	clientIP, err := GetClientIP(cid)
	if err != nil {
		log.Printf("kickoff: failed to get IP for cid %s: %v", cid, err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(`{"error": "failed to get client IP"}`))
		return
	}

	if err := BanIP(clientIP, req.Reason); err != nil {
		log.Printf("kickoff: failed to ban IP %s: %v", clientIP, err)
	}

	if err := KickoffClient(cid); err != nil {
		log.Printf("kickoff: failed to kick cid %s: %v", cid, err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(`{"error": "failed to kickoff client"}`))
		return
	}

	log.Printf("kickoff: stream %s (cid %s, ip %s) kicked and banned", req.StreamID, cid, clientIP)
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"ok": true}`))
}

func HandleOnForward(w http.ResponseWriter, r *http.Request) {
	req, err := parseSrsRequest(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	channel, err := GetByStreamKey(req.Stream)
	if err != nil || channel.PublicToken == "" {
		log.Printf("on_forward rejected: active token not found for %s", req.Stream)
		// Empty array means don't forward
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"code": 0, "data": {"urls": []}}`))
		return
	}

	hlsServer := os.Getenv("SRS_HLS_URL")
	thumbServer := os.Getenv("SRS_THUMBNAIL_URL")
	
	hlsUrl := fmt.Sprintf("%s/live/%s", hlsServer, channel.PublicToken)
	thumbUrl := fmt.Sprintf("%s/live/%s", thumbServer, channel.ThumbnailToken)

	urls := []string{}
	if hlsServer != "" {
		urls = append(urls, hlsUrl)
	}
	if thumbServer != "" {
		urls = append(urls, thumbUrl)
	}

	response := map[string]interface{}{
		"code": 0,
		"data": map[string]interface{}{
			"urls": urls,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
	log.Printf("on_forward success for %s", req.Stream)
}
