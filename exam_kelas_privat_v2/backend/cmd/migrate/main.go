package main

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"time"

	"exam_kelas_privat_v2/backend/internal/platform"
)

type migrationManifest struct {
	GeneratedAt       time.Time `json:"generated_at"`
	SourceProjectPath string    `json:"source_project_path"`
	SourceMigrations  []string  `json:"source_migrations"`
}

func main() {
	cfg := platform.LoadConfig()
	server, err := platform.NewServer(cfg)
	if err != nil {
		log.Fatalf("gagal membuka database: %v", err)
	}

	if err := server.DB.AutoMigrate(platform.AutoMigrateModels()...); err != nil {
		log.Fatalf("gagal menjalankan automigrate: %v", err)
	}
	if err := platform.ValidateLaravelSchema(server.DB); err != nil {
		log.Fatalf("schema hasil migrasi belum kompatibel: %v", err)
	}

	sourceRoot := filepath.Clean("..\\..\\..\\exam_kelas_privat\\database\\migrations")
	entries, err := filepath.Glob(filepath.Join(sourceRoot, "*.php"))
	if err != nil {
		log.Fatalf("gagal membaca source migrations: %v", err)
	}

	manifest := migrationManifest{
		GeneratedAt:       time.Now().UTC(),
		SourceProjectPath: filepath.Clean("..\\..\\..\\exam_kelas_privat"),
		SourceMigrations:  entries,
	}
	raw, _ := json.MarshalIndent(manifest, "", "  ")
	if err := os.WriteFile(filepath.Join("migrations", "manifest.generated.json"), raw, 0o644); err != nil {
		log.Fatalf("gagal menulis manifest: %v", err)
	}

	log.Printf("automigrate dan validasi schema selesai untuk %d model dan manifest %d migration Laravel", len(platform.AutoMigrateModels()), len(entries))
}
