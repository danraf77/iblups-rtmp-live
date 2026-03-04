package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	log.Println("Starting IBLUPS Ingest Go Backend...")

	// Verify required ENV vars
	requiredVars := []string{
		"SUPABASE_URL",
		"SUPABASE_SERVICE_KEY",
		"SRS_HLS_URL",
		"SRS_THUMBNAIL_URL",
	}

	for _, v := range requiredVars {
		if os.Getenv(v) == "" {
			log.Printf("WARNING: Missing required environment variable: %s", v)
		}
	}

	// Initialize Supabase client config
	InitSupabaseEnv(os.Getenv("SUPABASE_URL"), os.Getenv("SUPABASE_SERVICE_KEY"))

	// Pre-load Server ID and fetch initial state
	InitServerInfo()

	// Start metrics goroutine
	go StartMetricsWorker()

	// Register SRS webhooks handlers
	http.HandleFunc("/api/on_publish", HandleOnPublish)
	http.HandleFunc("/api/on_unpublish", HandleOnUnpublish)
	http.HandleFunc("/api/on_forward", HandleOnForward)

	// Register Internal Dashboard API handlers
	http.HandleFunc("/api/streams", HandleListStreams)
	http.HandleFunc("/api/streams/token", HandleGetTokens)

	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}

	log.Printf("Server listening on :%s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
