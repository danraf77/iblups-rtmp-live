package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

var (
	sbURL string
	sbKey string
)

func InitSupabaseEnv(url, key string) {
	sbURL = url
	sbKey = key
}

type Channel struct {
	ID             string `json:"id"`
	StreamID       string `json:"stream_id"`
	PublicToken    string `json:"public_token"`
	ThumbnailToken string `json:"thumbnail_token"`
	IsOnLive       bool   `json:"is_on_live"`
}

func doRequest(method, endpoint string, body []byte) ([]byte, error) {
	req, err := http.NewRequest(method, sbURL+endpoint, bytes.NewBuffer(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("apikey", sbKey)
	req.Header.Set("Authorization", "Bearer "+sbKey)
	req.Header.Set("Content-Profile", "public")
	
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Prefer", "return=representation")
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("Supabase API error: %s - %s", resp.Status, string(respBody))
	}
	return respBody, err
}

func GetByStreamKey(streamKey string) (*Channel, error) {
	endpoint := fmt.Sprintf("/rest/v1/channels_channel?stream_id=eq.%s&select=id,stream_id,public_token,thumbnail_token,is_on_live", streamKey)
	resp, err := doRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	var channels []Channel
	if err := json.Unmarshal(resp, &channels); err != nil {
		return nil, err
	}
	if len(channels) == 0 {
		return nil, fmt.Errorf("channel not found for stream_key %s", streamKey)
	}

	return &channels[0], nil
}

func SaveTokens(streamKey, publicToken, thumbnailToken string) error {
	endpoint := fmt.Sprintf("/rest/v1/channels_channel?stream_id=eq.%s", streamKey)
	payload := map[string]string{
		"public_token":    publicToken,
		"thumbnail_token": thumbnailToken,
	}
	body, _ := json.Marshal(payload)
	_, err := doRequest("PATCH", endpoint, body)
	return err
}

func UpdateLiveStatus(streamKey string, isLive bool) error {
	endpoint := fmt.Sprintf("/rest/v1/channels_channel?stream_id=eq.%s", streamKey)
	payload := map[string]bool{
		"is_on_live": isLive,
	}
	body, _ := json.Marshal(payload)
	_, err := doRequest("PATCH", endpoint, body)
	return err
}

