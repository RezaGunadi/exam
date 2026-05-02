# exam_kelas_privat_v2

Migrasi bertahap dari `exam_kelas_privat` ke:

- `backend/` → Go API + worker scheduler + tool migrasi
- `frontend/` → Next.js App Router

## Struktur utama

- `backend/cmd/api` → entrypoint API
- `backend/cmd/worker` → entrypoint scheduler/cron
- `backend/cmd/migrate` → Go migration ownership via AutoMigrate + manifest Laravel
- `backend/migrations/manifest.generated.json` → daftar 71 migration source dari Laravel
- `frontend/src/app` → halaman per tema fitur

## Catatan implementasi

- DB tetap menggunakan skema existing yang kompatibel.
- Generate raport lama sengaja tidak dibawa; modul itu disiapkan untuk ditulis ulang terpisah.
- Autosave ujian siswa dipusatkan ke satu queue klien dan satu endpoint sync backend.
- Detail absensi sekarang dirancang per tanggal, per kelas, dan per siswa.

## Dokumentasi deploy

- Panduan deploy VPS + Nginx + HTTPS + domain `exam.kelasprivat.id` tersedia di `docs/DEPLOY_VPS_NGINX.md`.
- Panduan deploy lokal Windows + XAMPP + MySQL `root` tanpa password tersedia di `docs/DEPLOY_LOCAL_WINDOWS_XAMPP.md`.
