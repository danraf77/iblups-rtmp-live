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
		return "", "", err
	}

	if channel.PublicToken != "" {
		// Tokens permanentes — usa los existentes
		UpdateLiveStatus(streamKey, true)
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
			return hlsToken, thumbToken, nil
		}
		log.Printf("Token generation collision or error (attempt %d): %v", attempts+1, err)
	}

	return "", "", fmt.Errorf("failed to generate unique tokens after 5 attempts")
}

func deactivateStream(streamKey string) error {
	return UpdateLiveStatus(streamKey, false)
}
