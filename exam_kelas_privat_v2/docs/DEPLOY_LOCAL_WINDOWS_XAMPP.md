# Deploy Lokal Windows + XAMPP

Dokumentasi ini menjelaskan cara menjalankan `exam_kelas_privat_v2` di komputer Windows untuk development lokal, dengan database MySQL dari XAMPP:

- OS: Windows
- MySQL: XAMPP
- user database: `root`
- password database: kosong
- backend Go API: `http://localhost:8080`
- frontend Next.js: `http://localhost:3000`

Panduan ini cocok untuk skenario:

- testing lokal,
- development fitur baru,
- verifikasi parity migrasi Laravel ke Go + Next.js,
- menjalankan project dengan DB existing atau dump dari sistem lama.

## Arsitektur lokal

```text
Browser
  |- http://localhost:3000      -> Frontend Next.js
  `- request /api ke backend    -> http://localhost:8080

Backend Go
  `- konek ke MySQL XAMPP       -> 127.0.0.1:3306
```

## 1. Prasyarat

Pastikan di Windows Anda sudah terpasang:

- XAMPP
- Node.js
- Go
- Git

Versi yang disarankan:

- Node.js 22 LTS
- Go 1.25.x

## 2. Jalankan XAMPP

Buka XAMPP Control Panel, lalu start:

- `Apache` opsional
- `MySQL` wajib

Untuk project ini, yang wajib hanya `MySQL`.

Pastikan MySQL berjalan di port default:

- `3306`

## 3. Siapkan database di XAMPP

Ada dua opsi:

### Opsi A: pakai database existing

Kalau Anda sudah punya database lama `exam_kelas_privat`, gunakan database itu langsung.

### Opsi B: buat database baru

Buka:

- [http://localhost/phpmyadmin](http://localhost/phpmyadmin)

Buat database baru, misalnya:

```text
exam_kelas_privat
```

Gunakan collation yang umum, misalnya:

```text
utf8mb4_unicode_ci
```

## 4. Import dump database lama jika perlu

Kalau Anda punya file dump `.sql`, import lewat phpMyAdmin:

1. buka database `exam_kelas_privat`
2. pilih tab `Import`
3. pilih file dump
4. klik `Go`

Alternatif lewat terminal:

```powershell
"C:\xampp\mysql\bin\mysql.exe" -u root exam_kelas_privat < "C:\path\ke\backup.sql"
```

Karena user `root` tanpa password, tidak perlu flag `-p`.

## 5. Buka project

Pastikan project ada di folder kerja Anda, misalnya:

```text
c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2
```

## 6. Setup backend Go

Masuk ke folder backend:

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\backend"
copy .env.example .env
```

Edit file `.env` menjadi seperti ini:

```env
APP_PORT=8080
APP_URL=http://localhost:8080
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USERNAME=root
DB_PASSWORD=
DB_NAME=exam_kelas_privat
DB_PARAMS=parseTime=true
JWT_SECRET=dev-local-secret
SCHEDULER_TOKEN=dev-local-scheduler-token
```

Penting:

- backend sekarang mendukung dua mode konfigurasi database:

1. `MYSQL_DSN`
2. `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`, `DB_PARAMS`

- jika Anda memakai XAMPP lokal, lebih aman pakai format terpisah `DB_*`
- `DB_PASSWORD` boleh kosong atau berisi password, jadi fleksibel untuk XAMPP maupun server lain
- DSN internal yang dibentuk untuk `root` tanpa password setara dengan:

```text
root:@tcp(127.0.0.1:3306)/nama_db?parseTime=true
```

- jangan pakai password palsu seperti `root` kalau MySQL XAMPP Anda memang kosong

## 7. Jalankan migrasi Go

Walau database bisa berasal dari sistem lama, tooling migrasi Go tetap perlu tersedia untuk sinkronisasi struktur baru.

Jalankan:

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\backend"
go run ./cmd/migrate
```

Catatan:

- kalau database sudah existing dan berisi data produksi/salinan produksi, sangat disarankan backup dulu
- kalau ini database baru kosong, langkah ini membantu membangun skema yang kompatibel
- saat backend dijalankan, aplikasi juga akan mencoba membuat database jika belum ada, lalu menjalankan `AutoMigrate` untuk membuat tabel yang belum ada dan melewati yang sudah ada

## 8. Jalankan backend API

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\backend"
go run ./cmd/api
```

Kalau berhasil, backend akan aktif di:

- [http://localhost:8080](http://localhost:8080)

Tes cepat:

```powershell
Invoke-WebRequest "http://localhost:8080/healthz"
```

## 9. Jalankan worker scheduler

Buka terminal PowerShell baru, lalu jalankan:

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\backend"
go run ./cmd/worker
```

Worker ini penting karena scheduler Laravel sudah dipindah ke worker Go.

Kalau worker tidak dijalankan, maka job seperti cleanup exam, update status result, QR, referral token, dan job lain tidak akan ikut berjalan.

## 10. Setup frontend Next.js

Masuk ke folder frontend:

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\frontend"
copy .env.example .env.local
```

Isi `.env.local`:

```env
NEXT_PUBLIC_API_URL=http://localhost:8080
```

## 11. Install dependency frontend

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\frontend"
npm install
```

## 12. Jalankan frontend

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\frontend"
npm run dev
```

Frontend akan aktif di:

- [http://localhost:3000](http://localhost:3000)

## 13. Urutan terminal yang disarankan

Supaya tidak bingung, pakai 3 terminal:

### Terminal 1

Backend API:

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\backend"
go run ./cmd/api
```

### Terminal 2

Worker scheduler:

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\backend"
go run ./cmd/worker
```

### Terminal 3

Frontend Next.js:

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\frontend"
npm run dev
```

## 14. Checklist verifikasi lokal

Setelah semua hidup, cek:

- `http://localhost:8080/healthz`
- `http://localhost:8080/api/landing/stats`
- `http://localhost:3000`
- `http://localhost:3000/login`

Lalu uji:

- login
- register
- dashboard
- absensi
- ujian siswa
- autosave jawaban
- scheduler worker tetap berjalan

## 15. Perintah build untuk memastikan tidak ada error

### Backend

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\backend"
go build ./...
```

### Frontend lint

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\frontend"
npm run lint
```

### Frontend build

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\frontend"
npm run build
```

## 16. Troubleshooting

### MySQL XAMPP tidak bisa dikoneksi

Cek apakah MySQL XAMPP benar-benar aktif.

Tes:

```powershell
"C:\xampp\mysql\bin\mysql.exe" -u root -e "SHOW DATABASES;"
```

Kalau gagal:

- cek service MySQL di XAMPP
- cek apakah port `3306` dipakai aplikasi lain
- cek apakah password root benar-benar kosong

### Error DSN backend

Untuk XAMPP root tanpa password, gunakan:

```text
root:@tcp(127.0.0.1:3306)/exam_kelas_privat?parseTime=true
```

Bukan:

```text
root:root@tcp(127.0.0.1:3306)/exam_kelas_privat?parseTime=true
```

### Frontend jalan tapi API gagal

Cek file:

- `frontend/.env.local`

Harus mengarah ke:

```env
NEXT_PUBLIC_API_URL=http://localhost:8080
```

Lalu restart `npm run dev`.

### Port 3000 atau 8080 sudah dipakai

Kalau port bentrok:

- ganti `APP_PORT` backend, misalnya `8081`
- sesuaikan `NEXT_PUBLIC_API_URL`

Contoh:

```env
APP_PORT=8081
NEXT_PUBLIC_API_URL=http://localhost:8081
```

### Scheduler tidak jalan

Pastikan Anda membuka terminal kedua dan menjalankan:

```powershell
go run ./cmd/worker
```

Karena worker tidak otomatis ikut hidup saat API dijalankan.

## 17. Workflow harian development

Setiap mulai kerja:

1. start `MySQL` di XAMPP
2. jalankan backend API
3. jalankan worker
4. jalankan frontend

Kalau ada update dependency atau perubahan besar:

```powershell
cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\backend"
go mod download

cd "c:\Users\rezag\OneDrive\Documents\Cursor\exam_kelas_privat_v2\frontend"
npm install
```

## 18. Ringkasan cepat

Urutan paling singkat untuk local run:

1. Start MySQL di XAMPP.
2. Pastikan database `exam_kelas_privat` ada.
3. Isi backend `.env` dengan DSN `root:@tcp(127.0.0.1:3306)/exam_kelas_privat?parseTime=true`.
3. Isi backend `.env` dengan `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, dan `DB_NAME`.
4. Jalankan `go run ./cmd/migrate`.
5. Jalankan `go run ./cmd/api`.
6. Jalankan `go run ./cmd/worker`.
7. Isi frontend `.env.local` dengan `NEXT_PUBLIC_API_URL=http://localhost:8080`.
8. Jalankan `npm install`.
9. Jalankan `npm run dev`.
10. Buka `http://localhost:3000`.
