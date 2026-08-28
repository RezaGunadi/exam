# Deploy cuandariponsel — repost.ragh.co.id

Aplikasi Laravel 12 di `https://github.com/RezaGunadi/cuan_dari_ponsel.git`,
dilayani dari `/var/www/repost` oleh nginx dan MySQL yang sudah dipasang setup
di direktori induk.

```bash
cd server-setup && sudo make server   # sekali, bila server masih kosong
cd repost-app   && sudo make deploy
```

Semua target **idempoten**. Yang sudah ada dilewati, bukan ditimpa; `.env`
aplikasi tidak pernah ditulis ulang setelah dibuat.

| Target | Guna |
|---|---|
| `sudo make deploy` | Kode → aset → nginx → HTTPS → penjadwal → antrean |
| `sudo make app` | Klon, composer, `.env`, database, migrasi, data awal, izin |
| `sudo make assets` | Node.js + `npm ci && npm run build` (Vite) |
| `sudo make uploads` | Batas unggahan PHP untuk clip portofolio 200MB |
| `sudo make site` | Server block nginx saja |
| `sudo make ssl` | Sertifikat Let's Encrypt + blok 443 |
| `sudo make cron` | Penjadwal Laravel (`schedule:run` tiap menit) |
| `sudo make queue` | Pekerja antrean sebagai layanan systemd |
| `sudo make update` | Rilis berikutnya: pull + composer + build + migrasi |
| `sudo make permissions` | Pasang ulang izin berkas Laravel |

Nilai bawaan bisa ditimpa dari baris perintah:

```bash
sudo make deploy DOMAIN=repost-staging.ragh.co.id SITE=repost_staging
sudo make app REPO=https://github.com/RezaGunadi/cuan_dari_ponsel.git
```

## Kenapa Makefile terpisah

Sama seperti `exam-v1/`: setup induk menulis server block lewat
`write_site_conf`, dan deteksi otomatis root-nya baru menemukan
`public/index.php` **setelah klonnya ada**. Pada `make nginx` yang dijalankan
sebelum itu, root-nya jatuh ke akar repo — seluruh kode sumber termasuk `.env`
berpindah ke dalam jangkauan web.

Situs ini juga butuh tiga hal yang tidak dimiliki setup induk sama sekali:
batas unggahan PHP 200MB, pekerja antrean, dan penjadwal harian.

Karena itu `repost` **tidak boleh** didaftarkan di `SITES`, `SITE_DOMAINS`,
maupun `NODE_SITES`. Skrip di sini memeriksa ketiganya dan berhenti bila
terlanjur ada. Konsekuensinya, HTTPS untuk domain ini juga diurus di sini
(`make ssl`), bukan oleh `make ssl` induk.

## Data awal: `SEED=minimal` adalah bawaannya

`DatabaseSeeder` repo ini membuat **delapan akun demo dengan password harfiah
`password`** — termasuk `owner@cuandariponsel.local` (role owner, akses penuh
ke pencairan dan saldo) dan `admin@test.com`. Dijalankan di produksi, situs ini
terbuka dengan kredensial yang bisa ditebak siapa pun yang pernah membaca
reponya, dan tidak ada satu pun pesan yang menyebutkan akun-akun itu ada.

Yang benar-benar dibutuhkan aplikasi hanya dua, dan itulah isi `SEED=minimal`:

1. **`TaskTypeSeeder`** — katalog jenis tugas. Idempoten (`updateOrCreate` per
   slug) dan hanya memperbarui kolom struktural, jadi harga yang sudah disetel
   owner lewat panel tidak ditimpa.
2. **Pengguna sistem platform** — pemilik dompet yang menampung komisi.
   `WalletService::platformWallet()` melemparkan `RuntimeException` tanpanya,
   dan itu terjadi pada kampanye **pertama yang disetujui**, bukan saat deploy.
   Dibuat dengan potongan kode yang sama seperti di seeder: password acak 40
   karakter, `is_active=false` — ia bukan akun untuk login.

Untuk staging yang tidak bisa dijangkau publik: `sudo make app SEED=all`.

## Aset Vite harus dibangun di server

`/public/build` ada di `.gitignore` repo aplikasi, jadi klon git tidak pernah
membawa hasil buildnya. Tanpa `make assets` setiap halaman melemparkan galat 500
`Vite manifest not found` — bukan halaman tanpa gaya, melainkan tidak tampil
sama sekali.

Ini berbeda dari `company-kelasprivat`, yang meng-commit `public/build/` dan
karena itu tidak butuh Node di server.

`install_node` dipakai bersama dengan `scripts/40-node.sh` induk — fungsinya ada
di `scripts/lib.sh`, bukan disalin, karena jebakan NodeSource-nya sama di mana
pun (paket `npm` Ubuntu menarik Node 12.22 dan bentrok dengan paket NodeSource).

## Batas unggahan 200MB

`PortfolioController` memvalidasi berkas video dengan `max:204800` — 200 MB.
Batas bawaan PHP adalah `upload_max_filesize=2M` dan `post_max_size=8M`, jadi
setiap unggahan clip ditolak jauh sebelum aturan validasi itu sempat dibaca.

**Dan kegagalannya tidak berbunyi seperti batas ukuran.** Begitu `post_max_size`
terlampaui, PHP mengosongkan `$_POST` seluruhnya — termasuk token CSRF. Yang
diterima pengunjung adalah **419 Page Expired**, yang membaca seperti masalah
sesi; orang lalu memeriksa `SESSION_DRIVER` dan cookie, padahal yang salah
adalah satu angka di `php.ini`.

`make uploads` menulis drop-in `99-repost-uploads.ini` ke `conf.d` **setiap**
versi PHP yang terpasang, karena `sudo make php` di direktori induk memindahkan
server ke versi lain dan berkas di conf.d versi lama ikut ditinggal tanpa pesan.
Jalankan ulang setelah menaikkan versi PHP — `make update` sudah melakukannya.

Batasnya berlaku untuk seluruh situs PHP di server, tetapi yang dinaikkan hanya
langit-langitnya; tiap situs tetap dibatasi `client_max_body_size` di server
block-nya masing-masing (32M untuk situs yang dikelola setup induk, 220M di
sini).

## Antrean bukan pelengkap

`QUEUE_CONNECTION=database`, dan yang masuk ke sana `CompressPortfolioClip`.
Tanpa pekerja, barisnya menumpuk di tabel `jobs` tanpa pernah dieksekusi — dan
tidak ada yang terlihat rusak. Unggahannya berhasil, clipnya tampil, hanya
ukurannya tidak pernah mengecil dan tagihan penyimpanan R2 naik diam-diam.

`DB_QUEUE_RETRY_AFTER` disetel **1800** di `.env` aplikasi, dan pekerja berjalan
dengan `--timeout=1500`. Urutan itu penting: `retry_after` bawaan 90 detik jauh
lebih pendek daripada waktu FFmpeg mengompres clip 200MB, dan begitu terlampaui
Laravel menganggap pekerjanya mati lalu **menyerahkan ulang pekerjaan yang
sama** — dua FFmpeg menulis berkas yang sama, dan yang selesai belakangan
menghapus keluaran yang sudah dipakai yang pertama.

`--max-time=3600` membuat pekerja berhenti sendiri tiap jam lalu dinyalakan
ulang systemd. Itulah yang membuat kode baru terpakai setelah deploy: PHP memuat
seluruh aplikasi sekali saat pekerja start. `make update` menyalakannya ulang
langsung, tidak menunggu satu jam.

## Penjadwal memindahkan uang

`routes/console.php` mendaftarkan lima perintah, dan setiap satunya memindahkan
uang atau melindungi orang dari kehilangan uang:

| Perintah | Jadwal | Bila tidak berjalan |
|---|---|---|
| `submissions:auto-accept` | 00:05 | Kiriman tak di-QC menggantung selamanya |
| `campaigns:auto-close` | 00:10 | Sisa escrow tidak pernah kembali ke pemberi kerja |
| `topups:expire` | tiap jam | Top-up menggantung menumpuk |
| `submissions:check-links` | 01:00 | Postingan yang sudah dihapus tetap dibayar |
| `earnings:settle` | 01:30 | Saldo freelancer tidak pernah cair |

Tidak satu pun mengeluarkan pesan error saat tidak berjalan. Buktinya bahwa ia
jalan ada di lognya:

```bash
tail -f /var/log/repost-schedule.log
```

## `config:cache` DIJALANKAN di sini

Berbeda dari `exam-v1`, dan bedanya bisa diperiksa, bukan soal selera: aplikasi
ini **tidak punya satu pun pemanggilan `env()` di luar `config/`**. Itu syarat
tunggal yang membuat `config:cache` aman.

**Konsekuensinya: menyunting `.env` tidak lagi berpengaruh sampai cache dibuat
ulang.** Setelah mengisi kredensial Xendit atau R2, jalankan `sudo make update`
(atau `sudo -u www-data php artisan config:cache` di `/var/www/repost`).

`route:cache` **tidak** dijalankan: `routes/web.php` memakai closure sebagai
aksi route (`fn () => view('welcome', ...)`), dan closure tidak bisa
diserialkan — perintahnya gagal.

## Yang perlu diperbaiki di repo aplikasi

**Disk `r2` tidak akan bekerja apa adanya.** `config/filesystems.php`
mendefinisikan disk `r2` dengan driver `s3`, tetapi `composer.lock` repo ini
tidak memuat `league/flysystem-aws-s3-v3` — hanya `flysystem` dan
`flysystem-local`. Begitu `CDP_PORTFOLIO_DISK=r2`, unggahan bukti kerja dan
portofolio gagal dengan `Driver [s3] is not supported`.

Perbaikannya ada di repo aplikasi, bukan di skrip deploy ini:

```bash
composer require league/flysystem-aws-s3-v3
```

`make app` memeriksanya dan memperingatkan bila disknya sudah disetel ke `r2`
sementara paketnya belum ada.

## Yang sengaja TIDAK dilakukan

**`php artisan route:cache`** — lihat di atas.

**Memasang FFmpeg.** `CDP_COMPRESS_VIDEO=false` adalah bawaannya, dan kompresi
utama memang dilakukan di sisi klien saat unggah. `VideoCompressor` mengembalikan
null bila FFmpeg tidak ada, dan berkas aslinya dibiarkan — tidak ada yang rusak.
Nyalakan sendiri bila memang mau: `apt install ffmpeg` lalu setel
`CDP_COMPRESS_VIDEO=true`.

**Menghapus paket atau data.** Tidak ada target yang menjatuhkan database,
menghapus `/var/www/repost`, atau mencabut paket.

## Setelah deploy

1. **Isi kredensial** di `/var/www/repost/.env`: Xendit (`XENDIT_SECRET_KEY`,
   `XENDIT_WEBHOOK_TOKEN`), R2, Fonnte. Lalu `sudo make update` — config sudah
   di-cache, menyunting `.env` saja tidak berpengaruh.
2. **Isi `MANUAL_BANK_*`**. Dengan `XENDIT_SECRET_KEY` kosong, transfer manual
   adalah satu-satunya jalur top-up yang aktif — dan tanpa nomor rekening,
   pemberi kerja tidak punya tujuan transfer.
3. **Buat akun owner sungguhan**, jangan pakai akun demo seeder.
4. **Arahkan DNS** `repost.ragh.co.id` ke IP server ini.
