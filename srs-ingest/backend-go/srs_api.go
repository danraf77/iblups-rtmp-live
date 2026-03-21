package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const srsAPIBase = "http://127.0.0.1:1985"

var srsClient = &http.Client{Timeout: 5 * time.Second}

type srsStream struct {
	Name    string `json:"name"`
	Publish struct {
		Active bool   `json:"active"`
		Cid    string `json:"cid"`
	} `json:"publish"`
}

type srsStreamsResponse struct {
	Code    int         `json:"code"`
	Streams []srsStream `json:"streams"`
}

type srsClient_ struct {
	ID string `json:"id"`
	IP string `json:"ip"`
}

type srsClientResponse struct {
	Code   int        `json:"code"`
	Client srsClient_ `json:"client"`
}

func srsRequest(method, path string) ([]byte, error) {
	req, err := http.NewRequest(method, srsAPIBase+path, nil)
	if err != nil {
		return nil, err
	}
	resp, err := srsClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("SRS API error %d: %s", resp.StatusCode, string(body))
	}
	return body, nil
}

// FindPublisherCid busca el client_id del publisher activo de un stream dado su nombre.
func FindPublisherCid(streamName string) (string, error) {
	body, err := srsRequest("GET", "/api/v1/streams?count=100")
	if err != nil {
		return "", err
	}

	var result srsStreamsResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return "", err
	}

	for _, s := range result.Streams {
		if s.Name == streamName && s.Publish.Active {
			return s.Publish.Cid, nil
		}
	}
	return "", fmt.Errorf("no active publisher found for stream: %s", streamName)
}

// GetClientIP obtiene el IP de un cliente por su cid.
func GetClientIP(cid string) (string, error) {
	body, err := srsRequest("GET", "/api/v1/clients/"+cid)
	if err != nil {
		return "", err
	}

	var result srsClientResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return "", err
	}
	return result.Client.IP, nil
}

// KickoffClient elimina al cliente de SRS, cortando su conexion RTMP.
func KickoffClient(cid string) error {
	_, err := srsRequest("DELETE", "/api/v1/clients/"+cid)
	return err
}
