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
| `SITE_DOMAINS` | `nama=domain` — mengisi `server_name` dan menentukan situs mana yang dapat HTTPS |
| `SITE_REPOS` | `nama=url` — situs yang terdaftar akan **diklon dari git** |
| `CF_ORIGIN_CA_KEY` | Origin CA Key Cloudflare — sertifikat diterbitkan sendiri, tanpa dashboard |
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

## HTTPS

`sudo make server` sudah memasang HTTPS sendiri. Yang perlu Anda isi di `.env`
hanya dua baris:

```bash
SITE_DOMAINS=exam_kelas_privat_v2=exam.kelasprivat.id
CF_ORIGIN_CA_KEY=v1.0-...        # My Profile → API Tokens → Origin CA Key
```

Dari situ `sudo make ssl` menerbitkan sendiri **Cloudflare Origin Certificate**
tiap domain lewat API, menulis server block 443, mengalihkan port 80 ke HTTPS,
dan memasang `real_ip` sekalian. Tanpa membuka dashboard.

Tidak ingin menaruh kunci akun di server? Kosongkan `CF_ORIGIN_CA_KEY`, buat
sertifikatnya manual di dashboard (SSL/TLS → Origin Server → Create
Certificate), lalu simpan sebagai `certs/<domain>.pem` dan `certs/<domain>.key`
di direktori ini. `sudo make ssl` akan memakainya. Direktori `certs/` tidak ikut
ke git.

**Bukan certbot, dan itu disengaja.** certbot memvalidasi lewat port 80 yang di
sini sudah diproksikan Cloudflare. Pemasangan pertama biasanya berhasil, lalu
perpanjangan otomatisnya gagal diam-diam berbulan-bulan kemudian — tepat saat
tidak ada yang memperhatikan. Origin Certificate berlaku 15 tahun dan tidak
punya jadwal perpanjangan yang bisa gagal sama sekali.

Situs yang tidak punya entri di `SITE_DOMAINS` dilewati, dan yang belum punya
sertifikat tetap dilayani lewat HTTP disertai peringatan. Satu domain bermasalah
tidak menghentikan setup situs lain.

## Setelah `make server`

Empat langkah ini **sengaja tidak diotomatiskan**, karena butuh keputusan Anda
atau akses yang tidak dimiliki server:

1. **Ganti password bawaan** di `.env`, lalu `sudo make mysql` lagi.
2. **Arahkan DNS** tiap domain ke IP server ini, dalam keadaan *proxied*
   (awan oranye).
3. **Cloudflare → SSL/TLS → Overview → Full (strict)** — setelah langkah 2
   selesai. Dinaikkan lebih awal, pengunjung menerima error 525.
4. **Batasi phpMyAdmin** ke IP Anda — lihat komentar `allow`/`deny` di server
   block-nya.

Periksa hasilnya kapan saja dengan `make status`; kolom terakhirnya menunjukkan
situs mana yang sudah `https` dan mana yang masih `http saja`.

## Di belakang Cloudflare

`make ssl` sudah memanggil ini otomatis begitu ada Origin Certificate yang
diterbitkan. Jalankan sendiri bila situs Anda diproksikan Cloudflare tetapi
sertifikatnya diurus di luar skrip ini:

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
