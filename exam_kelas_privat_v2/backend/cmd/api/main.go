package main

import (
	"log"
	"net/http"

	"exam_kelas_privat_v2/backend/internal/platform"
)

func main() {
	cfg := platform.LoadConfig()
	server, err := platform.NewServer(cfg)
	if err != nil {
		log.Fatalf("gagal membuat server: %v", err)
	}

	log.Printf("API berjalan di :%s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, server.Router()); err != nil {
		log.Fatalf("server berhenti: %v", err)
	}
}
