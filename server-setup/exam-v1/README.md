# Deploy Exam v1 — ujian.kelasprivat.id

Aplikasi Laravel di `https://github.com/RezaGunadi/exam_kelas_privat.git`,
dilayani dari `/var/www/exam_v1` oleh nginx dan MySQL yang sudah dipasang setup
di direktori induk.

```bash
cd server-setup && sudo make server   # sekali, bila server masih kosong
cd exam-v1       && sudo make deploy
```

Semua target **idempoten**. Yang sudah ada dilewati, bukan ditimpa; `.env`
aplikasi tidak pernah ditulis ulang setelah dibuat.

| Target | Guna |
|---|---|
| `sudo make deploy` | Seluruh rangkaian: kode → nginx → HTTPS → penjadwal |
| `sudo make app` | Klon, composer, `.env`, database, migrasi, izin |
| `sudo make site` | Server block nginx saja |
| `sudo make ssl` | Sertifikat Let's Encrypt + blok 443 |
| `sudo make cron` | Penjadwal Laravel (`schedule:run` tiap menit) |
| `sudo make update` | Rilis berikutnya: `git pull` + composer + migrasi |
| `sudo make permissions` | Pasang ulang izin berkas Laravel |

Nilai bawaan bisa ditimpa dari baris perintah:

```bash
sudo make deploy DOMAIN=ujian-staging.kelasprivat.id SITE=exam_v1_staging
sudo make app REPO=git@github.com:RezaGunadi/exam_kelas_privat.git
```

## Kenapa Makefile terpisah

Setup induk mengelola situs lewat `SITES`/`SITE_DOMAINS` di `.env`, dan server
block-nya ditulis `write_site_conf` dengan `root /var/www/<situs>`. Laravel butuh
`root /var/www/<situs>/public` — selisih satu direktori, tetapi akibatnya seluruh
kode sumber termasuk `.env` berada di dalam jangkauan web.

Kalau situs ini dititipkan ke sana, server block Laravel-nya **ditimpa diam-diam**
setiap kali `sudo make nginx` dijalankan — mungkin berminggu-minggu kemudian,
oleh orang yang sedang mengurus situs lain.

Karena itu `exam_v1` **tidak boleh** didaftarkan di `SITES` maupun
`SITE_DOMAINS`. Skrip di sini memeriksanya dan berhenti bila terlanjur ada.
Konsekuensinya, HTTPS untuk domain ini juga diurus di sini (`make ssl`), bukan
oleh `make ssl` induk.

## Yang sengaja TIDAK dilakukan

**`php artisan config:cache`.** Ini langkah baku deploy Laravel, dan di aplikasi
ini ia merusak. Ada 38 pemanggilan `env()` di luar `config/` — termasuk
`env('R2_DOMAIN')` di `app/helpers.php` yang menyusun URL berkas. Begitu config
di-cache, `env()` mengembalikan `null`: URL-nya rusak tanpa satu pun pesan error,
dan yang terlihat hanya gambar yang tidak muncul.

**`php artisan route:cache`.** `routes/web.php` memakai closure sebagai aksi
route, dan closure tidak bisa diserialkan — perintahnya gagal.

Keduanya bisa dinyalakan nanti, tetapi butuh perubahan di aplikasinya lebih
dulu: memindahkan `env()` ke `config/*.php` dan mengganti closure route dengan
controller.

**Menghapus paket atau data.** Tidak ada target yang menjatuhkan database,
menghapus `/var/www/exam_v1`, atau mencabut paket.

## Penjadwal bukan pelengkap

`app/Console/Kernel.php` mendaftarkan **16 perintah terjadwal**, di antaranya
`ai:score-essays`, `exam-results:mark-completed`, dan `exams:cleanup-expired`.
Tanpa entri cron dari `make cron`, semuanya tidak pernah berjalan — dan tidak
ada pesan error apa pun. Yang terlihat hanya hasil ujian yang menggantung.

Buktinya bahwa ia jalan ada di lognya, bukan di keluaran `make`:

```bash
tail -f /var/log/exam_v1-schedule.log
```

Lognya dirotasi mingguan. Tanpa itu, entri tiap menit membesar diam-diam sampai
partisi penuh — dan partisi penuh mematikan MySQL beserta seluruh situs lain di
server ini, bukan hanya yang ini.

## Izin berkas

`make app` dan `make update` memanggil `scripts/permissions.sh`, yang menerapkan
resep izin Laravel yang lazim dipakai:

```bash
chown -R $USER:www-data .
find . -type f -exec chmod 664 {} \;
find . -type d -exec chmod 775 {} \;
chgrp -R www-data storage bootstrap/cache
chmod -R ug+rwx storage bootstrap/cache
```

Pemiliknya `SUDO_USER` — pengguna yang mengetik `sudo`, bukan `$USER` yang di
dalam `sudo make` sudah bernilai `root`. Timpa dengan
`sudo make permissions DEPLOY_USER=nama`.

**Yang dibayar.** Direktori `775` dengan grup `www-data` berarti PHP boleh
membuat berkas baru di seluruh pohon aplikasi, termasuk `public/` yang
menjalankan `.php`. Satu celah pada unggahan berubah dari "penyerang menaruh
berkas" menjadi eksekusi kode jarak jauh. Aplikasi ini memakai
`FILESYSTEM_DISK=r2`, jadi unggahan seharusnya tidak pernah mendarat di
`public/` — jaga agar tetap begitu.

Tiga hal yang tidak ada di resep aslinya, dan ditambahkan karena tanpanya ada
yang rusak:

- **`.env` tetap `640`.** `chmod 664` membuatnya terbaca semua pengguna di
  server, sementara isinya password database, `APP_KEY`, dan kredensial SMTP.
- **`vendor/bin/*` dan `artisan` dikembalikan `775`.** `chmod 664` mencabut bit
  executable dari semua berkas; kegagalannya muncul kemudian sebagai
  *Permission denied* pada nama paket, tanpa menyinggung langkah chmod.
- **`git safe.directory`.** Repo tidak lagi milik root sementara `sudo make
  update` menjalankan git sebagai root — tanpa ini git menolak dengan *detected
  dubious ownership* dan membatalkan seluruh pembaruan.

`find … -exec … +`, bukan `\;`: hasilnya sama, tetapi `\;` memanggil `chmod`
sekali per berkas dan `vendor/` sendirian berisi puluhan ribu berkas.

`artisan` dijalankan sebagai `www-data` (lewat `runuser`), bukan root. Kalau
dijalankan sebagai root, log dan berkas cache yang dibuatnya jadi milik root —
lalu PHP-FPM tidak bisa menimpanya dan situsnya mati dengan *Permission denied*
berjam-jam setelah deploy yang terlihat berhasil.

## Setelah deploy

1. Buka `https://ujian.kelasprivat.id` dan pastikan halamannya tampil.
2. **Periksa `/var/www/exam_v1/.env`.** Berkas itu dibuat dari `.env.example`
   milik repo, yang memuat kredensial SMTP sungguhan. `APP_ENV=production`,
   `APP_DEBUG=false`, `APP_KEY` baru, dan kredensial database sudah disetel
   otomatis; sisanya keputusan Anda.
3. Isi kredensial R2/AWS bila unggahan berkas dipakai — `FILESYSTEM_DISK=r2`,
   jadi tanpa itu unggahan gagal.
4. Pastikan penjadwal jalan (lihat di atas).

Sertifikat gagal terbit? Itu tidak menghentikan deploy — situs tetap dilayani
lewat HTTP. Domainnya harus sudah mengarah ke server ini dan port 80 terbuka;
di belakang Cloudflare, awannya abu-abu saat verifikasi. Lalu ulangi
`sudo make ssl`.
