package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
)

func generateToken() (string, error) {
	bytes := make([]byte, 20)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func activateStream(streamKey string) (string, string, error) {
	// 1. Busca en Supabase si ya tiene tokens
	channel, err := GetByStreamKey(streamKey)
	if err != nil {
		LogSystemEvent("publish_error", "high", fmt.Sprintf("Stream connection rejected: invalid stream key %s", streamKey))
		return "", "", err
	}

	if channel.PublicToken != "" {
		// Tokens permanentes — usa los existentes
		UpdateLiveStatus(streamKey, true)
		LogSystemEvent("publish", "info", fmt.Sprintf("Stream active for %s", streamKey))
		return channel.PublicToken, channel.ThumbnailToken, nil
	}

	// 2. Genera nuevos tokens con reintento por colision
	for attempts := 0; attempts < 5; attempts++ {
		hlsToken, err := generateToken()
		if err != nil {
			return "", "", err
		}
		thumbToken, err := generateToken()
		if err != nil {
			return "", "", err
		}

		err = SaveTokens(streamKey, hlsToken, thumbToken)
		if err == nil {
			UpdateLiveStatus(streamKey, true)
			LogSystemEvent("publish", "info", fmt.Sprintf("Stream active, new tokens generated for %s", streamKey))
			return hlsToken, thumbToken, nil  // sin colision
		}
		log.Printf("Token generation collision or error (attempt %d): %v", attempts+1, err)
	}
	
	return "", "", fmt.Errorf("failed to generate unique tokens after 5 attempts")
}

func deactivateStream(streamKey string) error {
	LogSystemEvent("unpublish", "info", fmt.Sprintf("Stream ended for %s", streamKey))
	return UpdateLiveStatus(streamKey, false)
}
