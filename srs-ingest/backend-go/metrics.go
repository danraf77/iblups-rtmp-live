package main

import (
    "log"
    "time"
)

func InitServerInfo() {
    serverID = "ingest-01" // In a real env, load from os.Getenv
    serverIP = "127.0.0.1"
}

func StartMetricsWorker() {
    ticker := time.NewTicker(30 * time.Second)
    for {
        select {
        case <-ticker.C:
            log.Printf("Collecting metrics: (noop stub)")
            // TODO: Query SRS API :1985
            // TODO: Post payload to Supabase tables
        }
    }
}
