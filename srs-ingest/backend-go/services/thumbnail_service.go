package services

import (
	"log"
	"os"
	"os/exec"
	"sync"
	"time"
)

type ThumbnailService struct {
	activeProcesses map[string]*time.Ticker
	mu              sync.Mutex
}

func NewThumbnailService() *ThumbnailService {
	return &ThumbnailService{
		activeProcesses: make(map[string]*time.Ticker),
	}
}

// StartCapture inicia los procesos de extracción cada 2 minutos en segundo plano (Go Routine).
// Se quitó "appName" de la firma porque en SRS el RTMP url ya lo incluye (e.g., rtmp://{host}/live/{stream})
func (s *ThumbnailService) StartCapture(streamID, rtmpURL, outputPath, fileName string) {
	s.mu.Lock()
	if _, exists := s.activeProcesses[streamID]; exists {
		s.mu.Unlock()
		log.Printf("⚠️ Ya existe una captura activa para %s. Ignorando.", streamID)
		return
	}
	
	ticker := time.NewTicker(2 * time.Minute)
	s.activeProcesses[streamID] = ticker
	s.mu.Unlock()

	log.Printf("⏰ Iniciando flujo de captura de thumbnail para %s", streamID)

	// 🔥 CORRECCIÓN CRUCIAL:
	// Toda la lógíca temporal (time.Sleep) MUST ejecutarse de manera asíncrona dentro
	// de una goroutine para NO bloquear al webhook "on_publish" ni provocar que
	// el servidor SRS cierre temporalmente la conexión RTMP por timeout (> 3-5 seg).
	go func() {
		// Captura inicial tras 5 segundos para darle tiempo de arranque al stream
		time.Sleep(5 * time.Second)
		log.Printf("📸 Capturando thumbnail inicial para %s...", streamID)
		s.captureThumbnail(rtmpURL, outputPath, fileName)

		// Loop que captura periódicamente
		for range ticker.C {
			log.Printf("🔄 Actualizando thumbnail para %s", streamID)
			s.captureThumbnail(rtmpURL, outputPath, fileName)
		}
	}()
}

func (s *ThumbnailService) StopCapture(streamID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if ticker, ok := s.activeProcesses[streamID]; ok {
		ticker.Stop()
		delete(s.activeProcesses, streamID)
		log.Printf("🛑 Ticker de thumbnails detenido para %s", streamID)
	}
}

func (s *ThumbnailService) captureThumbnail(rtmpURL, outputPath, fileName string) {
	cmd := exec.Command("ffmpeg",
		"-y",
		"-i", rtmpURL,
		// Cambio: tamaño 245x142 con menor costo CPU (Firma: Cursor)
		"-vf", "scale=245:142:flags=bilinear",
		"-vframes", "1",
		// Cambio: forzar salida JPG (Firma: Cursor)
		"-f", "image2",
		"-vcodec", "mjpeg",
		// Cambio: calidad JPG balanceada peso/calidad (Firma: Cursor)
		"-q:v", "4",
		outputPath)

	if err := cmd.Run(); err != nil {
		if _, statErr := os.Stat(outputPath); statErr == nil {
			log.Printf("✅ Thumbnail actualizado: %s", fileName)
		} else {
			log.Printf("❌ Error FFmpeg para %s: %v", fileName, err)
		}
	} else {
		log.Printf("✅ Thumbnail generado: %s", fileName)
	}
}
