# Setup Server

Penyiapan server sekali jalan untuk Debian/Ubuntu: **Docker**, MySQL, nginx,
PHP-FPM, phpMyAdmin, dan direktori situs untuk semua proyek.

Satu-satunya yang perlu ada lebih dulu: `make` dan `git`.

```bash
sudo apt update && sudo apt install -y make git
```

```bash
sudo make server
```

Seluruh target **idempoten** — aman dijalankan berulang kali. Yang sudah ada
dilewati, bukan ditimpa. Menambah situs baru cukup dengan menyuntingnya di
`.env` lalu menjalankan ulang.

## Bentuk arsitekturnya

Satu nginx dan satu MySQL di **host**, dipakai bersama semua proyek:

```
Internet ──▶ nginx host (80/443) ──┬──▶ /var/www/<situs>        (statis / PHP)
                                   └──▶ 127.0.0.1:3000, :8080   (container)

                MySQL host (127.0.0.1:3306) ──▶ database terpisah per proyek
```

Aplikasi berbasis container **tidak membuka port publik sendiri**. Mereka hanya
mendengar di `127.0.0.1` dan diteruskan oleh nginx host. Alasannya:

- tidak ada rebutan port 80/443 antara nginx host dan nginx container;
- sertifikat SSL cukup diurus di satu tempat;
- satu phpMyAdmin memantau seluruh database, bukan sebagian.

MySQL dikunci ke `127.0.0.1`. Container tetap bisa menyambung lewat jaringan
Docker, tetapi port 3306 tidak pernah terbuka ke internet.

## Menyesuaikan

Semua diatur dari `.env` (dibuat otomatis dari `.env.example` saat pertama
kali dijalankan, dan tidak ikut ke git):

| Variabel | Guna |
|---|---|
| `DB_USER`, `DB_PASSWORD` | Pengguna MySQL untuk semua aplikasi |
| `DATABASES` | Database yang dibuat, satu per proyek |
| `SITES` | Direktori `/var/www/<nama>` + server block + symlink |
| `SITE_REPOS` | `nama=url` — situs yang terdaftar akan **diklon dari git** |
| `PMA_*` | phpMyAdmin: port dan basic-auth |

Situs yang punya entri di `SITE_REPOS` diklon dari git; sisanya cukup dibuatkan
direktori kosong. Klon yang sudah ada **tidak pernah di-pull otomatis** —
menarik perubahan diam-diam ke situs yang sedang melayani pengunjung bisa
menyalakan versi yang belum diuji. Pembaruan adalah keputusan sadar:

```bash
git -C /var/www/<situs> pull
```

Docker dipasang dari repositori resminya, bukan lewat `curl … | sh`. Skrip
sekali-jalan itu tidak memberi jalur pembaruan: paketnya tidak ikut
`apt upgrade`, sehingga perbaikan keamanan Docker tidak pernah sampai.

**Urutannya penting** dan sudah dipaksakan di Makefile: Docker dipasang SEBELUM
MySQL. Skrip MySQL menentukan alamat yang didengarkan dari ada-tidaknya
jembatan `docker0`; bila Docker menyusul belakangan, MySQL sudah terlanjur
terikat ke loopback saja dan container tidak akan pernah bisa menyambung.

## Setelah `make server`

Empat langkah ini **sengaja tidak diotomatiskan**, karena butuh keputusan Anda:

1. **Ganti password bawaan** di `.env`, lalu `sudo make mysql` lagi.
2. **Isi `server_name`** tiap situs di `/etc/nginx/sites-available/`.
3. **Pasang SSL**: `sudo certbot --nginx -d domain-anda`.
4. **Batasi phpMyAdmin** ke IP Anda — lihat komentar `allow`/`deny` di server
   block-nya.

Periksa hasilnya kapan saja dengan `make status`.

## Di belakang Cloudflare

Situs yang diproksikan Cloudflare butuh satu langkah tambahan:

```bash
sudo make cloudflare
```

**Tanpa ini pembatasan laju tidak bekerja, dan diamnya berbahaya.** Setiap
permintaan tiba dari alamat edge Cloudflare, sehingga seluruh dunia terlihat
berasal dari segelintir IP. Pembatas "3 kali salah login" lalu mengunci semua
orang sekaligus, sementara penyerang sungguhan tidak pernah terpisahkan dari
pengguna biasa.

Perintah itu memasang daftar rentang IP Cloudflare dan menyuruh nginx membaca
`CF-Connecting-IP` — tetapi **hanya** untuk koneksi yang memang datang dari
rentang tersebut. Tanpa syarat itu, siapa pun yang menghubungi IP server secara
langsung bisa mengarang header dan menyamar sebagai alamat mana pun.

Jalankan ulang sesekali; rentang Cloudflare bertambah dari waktu ke waktu.

Untuk HTTPS-nya, pakai **Origin Certificate** (SSL/TLS → Origin Server →
Create Certificate), bukan certbot: certbot memvalidasi lewat port 80 yang
sudah diproksikan Cloudflare, sehingga perpanjangannya bisa gagal diam-diam
berbulan-bulan kemudian — tepat saat tidak ada yang memperhatikan. Origin
Certificate berlaku 15 tahun. Templat server block-nya ada di
[`templates/site-ssl-cloudflare.conf.example`](templates/site-ssl-cloudflare.conf.example).

## Catatan keamanan

- Password root MySQL dibuat **acak** dan disimpan di `.mysql-root-password`
  (mode 600) bila `MYSQL_ROOT_PASSWORD` dikosongkan. Nilai bawaan yang bisa
  ditebak adalah cara paling umum sebuah server dibobol.
- phpMyAdmin memberi akses penuh ke **seluruh** database, termasuk data pribadi
  siswa. Karena itu ia berada di port terpisah dan dilindungi basic-auth
  sebelum permintaan sampai ke PHP. Alamat yang tidak dipublikasikan bukan
  pengaman — pemindai otomatis rutin mencoba `/phpmyadmin` di setiap IP.
- Konfigurasi yang sudah ada tidak pernah ditimpa diam-diam; berkas lama
  dicadangkan sebagai `<nama>.orig`.
