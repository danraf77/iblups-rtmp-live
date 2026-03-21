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
