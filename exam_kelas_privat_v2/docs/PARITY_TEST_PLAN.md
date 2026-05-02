# Parity Test Plan

Gunakan dokumen ini untuk verifikasi migrasi terhadap DB Laravel yang sama.

## Automated Checks

- Backend compile dan unit test: `cd backend && go test ./...`
- Frontend production build dan type-check: `cd frontend && npm run build`
- Schema contract: `STRICT_SCHEMA_CHECK=true` saat API start atau `go run ./cmd/migrate` setelah backup DB.

## Smoke Test Role

1. Admin login, cek redirect ke home role, update sekolah, CRUD siswa/kelas/mapel, update KKM, import template.
2. Admin buat paket soal, soal PG/essay, upload gambar, buat ujian, publish, assign siswa.
3. Student login, mulai ujian, autosave, tab hidden cheating event, proctor snapshot, submit, lihat hasil.
4. Admin cek hasil, update catatan, koreksi essay, export CSV/XLSX, unduh answer sheet PDF, mark finished.
5. Admin jalankan report config reset, generate raport siswa/kelas/sekolah, publish/archive raport.
6. Tutor login, cek akses hasil ujian, absensi, tugas, kelas dan siswa saya.
7. Scheduler manual: AI scoring, double checker, recovery, sync semester.

## DB Parity Assertions

- Tabel/kolom Laravel terbaru ada: `slug`, `is_coachmark_showing`, `subscription_type`, `token_balance`, `proctor_snapshots`, `exam_attempt_configs`, `report_configs`, `raports`.
- Data lama tetap terbaca setelah API Go berjalan tanpa `AUTO_MIGRATE=true`.
- Perubahan status ujian, skor, raport, dan absensi masuk ke tabel yang sama dengan Laravel.
