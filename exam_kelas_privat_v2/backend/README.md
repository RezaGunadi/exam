# Backend Go

Backend ini mem-port modul utama `exam_kelas_privat` ke Go:

- auth, register, reset password
- siswa, kelas, mapel, paket soal, soal
- ujian, assignment, attempt management
- sync jawaban ujian dengan satu endpoint autosave
- hasil ujian, penilaian essay, export CSV
- absensi per tanggal/kelas/siswa
- tugas sekolah admin/tutor/siswa
- referral, tutor management, scheduler worker

## Menjalankan API

```powershell
copy .env.example .env
go run ./cmd/api
```

Konfigurasi database bisa memakai dua pola:

- `MYSQL_DSN`
- atau variabel terpisah `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`, `DB_PARAMS`

Saat startup, backend akan:

- membuat database jika belum ada,
- menjalankan `AutoMigrate` untuk membuat tabel yang belum ada,
- melewati tabel yang sudah ada.

## Menjalankan worker

```powershell
go run ./cmd/worker
```

## Menjalankan migrasi Go

```powershell
go run ./cmd/migrate
```
