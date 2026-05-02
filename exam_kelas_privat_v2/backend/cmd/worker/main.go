package main

import (
	"log"

	"exam_kelas_privat_v2/backend/internal/platform"
)

func main() {
	cfg := platform.LoadConfig()
	server, err := platform.NewServer(cfg)
	if err != nil {
		log.Fatalf("gagal membuat worker: %v", err)
	}

	cron := server.StartWorker()
	defer cron.Stop()

	log.Println("worker scheduler aktif")
	select {}
}
