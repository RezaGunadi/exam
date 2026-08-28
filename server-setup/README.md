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

Tidak semua situs di server ini dikelola dari `.env`. Aplikasi yang butuh
langkah di luar "buat direktori dan tulis server block" punya direktori deploy
sendiri:

| Direktori | Aplikasi | Domain | Kenapa terpisah |
|---|---|---|---|
| `exam-v1/` | Laravel | ujian.kelasprivat.id | root `public/`, composer, penjadwal |
| `repost-app/` | Laravel 12 | repost.ragh.co.id | + build Vite, unggahan 200MB, antrean |
| `junior-app/` | FastAPI (container) | junior-app.ragh.co.id | database & `.env` sendiri, Python, compose |

Dua yang pertama **tidak boleh** didaftarkan di `SITES`/`SITE_DOMAINS` — server
block Laravel-nya akan ditimpa `sudo make nginx`. `junior-app` justru
**harus** terdaftar (sebagai situs container); nginx dan HTTPS-nya memang diurus
dari sini, hanya bagian aplikasinya yang tidak. Masing-masing punya README.

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
| `PHP_VERSION` | Versi PHP untuk semua situs — dipasang & diaktifkan `sudo make php` |
| `NODE_SITES`, `NODE_VERSION` | Situs yang harus di-`npm run build` di server, dan versi Node-nya |
| `SITES` | Direktori `/var/www/<nama>` + server block + symlink |
| `PROXY_SITES`, `PROXY_PORTS` | Situs yang dilayani container, dan port lokal masing-masing |
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

## Versi PHP

Paket `php-fpm` tanpa nomor versi selalu mengikuti bawaan distro, dan bawaan
distro tidak selalu cukup:

| Distro | `php-fpm` → |
|---|---|
| Ubuntu 22.04 | **8.1** |
| Ubuntu 24.04 | 8.3 |
| Debian 11 | 7.4 |
| Debian 12 | 8.2 |

Laravel 11 butuh minimal **8.2**, jadi di Ubuntu 22.04 setup ini tidak cukup apa
adanya. Isi `PHP_VERSION` di `.env` lalu:

```bash
sudo make php
```

Satu perintah itu mengerjakan tiga hal yang biasanya dilakukan terpisah — dan
yang ketiga hampir selalu terlupa:

1. memasang paketnya, menambahkan repo `ondrej` (Ubuntu) atau `sury` (Debian)
   lebih dulu bila distro belum menyediakan versi tersebut;
2. menjadikannya `php` di terminal, lewat `update-alternatives`;
3. **mengarahkan seluruh server block nginx** — termasuk phpMyAdmin — ke socket
   FPM versi itu, lalu mematikan FPM versi lama.

Langkah 3 yang menentukan versi mana yang benar-benar melayani pengunjung.
Tanpa itu `php -v` menjawab 8.2 dengan meyakinkan sementara setiap halaman web
masih dijalankan 8.1 — selisih yang tidak menimbulkan satu pun pesan error.

`PHP_VERSION` yang belum ada di `.env` **ditambahkan otomatis** saat target ini
dijalankan. `.env` dibuat sekali lalu tidak pernah disentuh lagi, sehingga
variabel baru hasil `git pull` tidak akan pernah sampai ke server yang sudah
berjalan; peringatan saja tidak cukup untuk itu.

Target ini **sengaja tidak masuk `make server`**: memasang versi yang diminta
bisa berarti menambahkan repo pihak ketiga, dan itu pantas diketik sendiri.
`make nginx` yang dijalankan lebih dulu tetap aman — ia memakai PHP bawaan
distro selama versi yang diminta belum tersedia, sambil menyebutkan `make php`.

Paket versi lama hanya **dimatikan, tidak dihapus** — `apt purge php8.1-*` bisa
ikut mencabut paket meta beserta apa pun yang bergantung padanya. Setelah semua
situs terbukti sehat, buang sendiri:

```bash
sudo apt purge 'php8.1-*' && sudo apt autoremove
```

## Situs yang perlu di-build (Node.js)

Sebagian situs menyimpan hasil buildnya di git, sebagian tidak. Yang menentukan
hanya itu:

| Situs | Hasil build | Butuh Node di server? |
|---|---|---|
| `company-kelasprivat` | `public/build/` ikut ke repo | **tidak** |
| `ragh` | `out/` di-`.gitignore` | **ya** |

Tanpa build, `/var/www/ragh` tidak punya apa pun untuk disajikan dan nginx
menjawab 403.

Daftarnya di `.env`, dan **eksplisit**:

```bash
NODE_SITES=ragh
NODE_VERSION=22
SITE_ROOTS=ragh=out
```

`sudo make node` — sudah termasuk dalam `sudo make server` — memasang Node lalu
menjalankan `npm ci && npm run build` di `/var/www/<nama>` untuk tiap nama di
`NODE_SITES`.

**Kenapa tidak ditebak dari ada-tidaknya `package.json`.** Hampir semua proyek
PHP di sini punya `package.json` untuk perkakas pengembangan. Menjalankan
`npm run build` di sana bukan cuma mubazir — ia bisa menimpa aset yang sudah
benar dengan hasil build setengah jadi.

`NODE_SITES` kosong berarti skripnya tidak mengerjakan apa pun, termasuk **tidak
menambahkan repo NodeSource**. Itu sebabnya target ini aman ikut dalam
`make server`, tidak seperti `make php`.

**Jangan pakai `apt install npm`.** Paket bawaan Ubuntu 22.04 menarik Node 12.22
— di bawah syarat minimum hampir semua kerangka yang masih dirawat (Next.js 16
butuh 20.9+). Kegagalannya bukan "versi terlalu lama" yang jelas, melainkan
galat sintaks di dalam `node_modules` yang terbaca seperti paketnya yang rusak.
`make node` mencabut paket apt itu lebih dulu, karena ia bentrok dengan paket
NodeSource yang sudah memuat npm sendiri.

**Isi `SITE_ROOTS` untuk tiap situs di `NODE_SITES`.** Deteksi otomatis mencari
`out/index.html`; pada `make server` pertama direktori itu belum ada saat server
block ditulis, sehingga root-nya jatuh ke akar repo. Skripnya menulis ulang
server block setelah build berhasil, tetapi entri `SITE_ROOTS` membuat root-nya
benar sejak awal dan tidak bergantung pada urutan sama sekali.

Build yang gagal **tidak menghentikan setup** — sama seperti HTTPS. Situsnya
menjawab 403 sampai berhasil, dan namanya disebut di akhir. Kode keluar 137 atau
`Killed` berarti kehabisan memori, bukan kode yang salah; tambahkan swap.

## Situs yang dilayani container

Situs di `PROXY_SITES` tidak disajikan dari berkas. nginx hanya meneruskan
permintaannya ke `127.0.0.1`, dan direktori `/var/www/<nama>` tidak dibuat sama
sekali — kecuali bila ada entri `SITE_REPOS`, karena di sanalah
`docker-compose.yml` berada.

Port tujuannya ditentukan `PROXY_PORTS`:

```bash
PROXY_SITES=exam_v2,junior_app
PROXY_PORTS=junior_app=8000
```

Situs **tanpa** entri di `PROXY_PORTS` memakai bentuk lama milik Exam v2: `/api/`
diteruskan ke 8080 (API Go) dan sisanya ke 3000 (Next.js). Bentuk itu tetap jadi
bawaan supaya server yang sudah berjalan tidak berubah diam-diam saat repo ini
di-pull — tetapi ia **salah** untuk aplikasi yang mendengar di satu port saja.

Kegagalannya kalau dibiarkan menebak tidak terlihat di halaman depan: situsnya
terbuka normal, dan yang menjawab 502 hanya alamat di bawah `/api/` — yang pada
backend Kelas Junior berarti seluruh isi aplikasinya.

`PROXY_PORTS` yang belum ada di `.env` **ditambahkan otomatis** saat
`sudo make nginx` dijalankan, dengan alasan yang sama seperti `PHP_VERSION`:
`.env` dibuat sekali lalu tidak pernah disentuh lagi, sehingga variabel baru
hasil `git pull` tidak akan pernah sampai ke server yang sudah berjalan.

### Port container tidak pernah terbuka ke internet

`ports: "8000:8000"` di sebuah `docker-compose.yml` **bukan** berarti localhost.
Docker mengartikannya `0.0.0.0:8000` — aplikasi terjangkau langsung dari
internet, tanpa HTTPS dan tanpa melewati nginx.

Dan **ufw tidak menghalanginya**. Docker menulis aturan DNAT-nya sendiri di
rantai yang diproses sebelum aturan ufw, sehingga `ufw deny 8000` tidak
berpengaruh sementara `ufw status` tetap tampak meyakinkan. Kesalahan jenis ini
tidak pernah muncul di log mana pun.

`sudo make docker` menulis `/etc/docker/daemon.json`:

```json
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" }
}
```

`"ip"` mengubah alamat **bawaan** untuk port yang dipublikasikan tanpa menyebut
IP, sehingga arsitektur di atas berlaku secara bawaan alih-alih bergantung pada
tiap compose file mengingatnya sendiri. Container yang memang perlu terbuka
tetap bisa menulis `"0.0.0.0:port:port"` dengan sengaja.

`log-opts` mengurus hal kedua yang tidak kalah diam: driver `json-file` bawaan
tumbuh **tanpa batas**. Container yang menulis beberapa baris per detik memenuhi
partisi dalam hitungan bulan — dan partisi penuh mematikan MySQL beserta seluruh
situs di server ini.

`daemon.json` yang **sudah ada tidak pernah ditimpa**; yang kurang hanya
disebutkan agar ditambahkan sendiri. Menggabungkan JSON dengan aman butuh `jq`
yang belum tentu ada, dan menimpa berkas yang disunting orang lebih buruk
daripada memberi tahu.

Perubahan ini baru berlaku setelah daemon di-restart, dan restart itu hanya
dilakukan pada saat berkasnya baru ditulis — bukan tiap `make server`, karena
restart menjatuhkan container yang sedang melayani.

## HTTPS

`sudo make server` sudah memasang HTTPS sendiri. Yang menentukan hanya
`SITE_DOMAINS` — situs yang terdaftar di sana dapat sertifikat, yang tidak
terdaftar dilewati dan tetap dilayani lewat HTTP.

Ada dua cara mendapatkan sertifikatnya, dipilih lewat `SSL_METHOD`:

| | `letsencrypt` | `cloudflare` (bawaan) |
|---|---|---|
| Kredensial | tidak perlu | Origin CA Key / API Token |
| Masa berlaku | 90 hari, diperpanjang otomatis | 15 tahun, tanpa perpanjangan |
| Dipercaya browser | ya | **hanya** di belakang proxy Cloudflare |
| Syarat | domain sudah mengarah ke server, port 80 terbuka | akun Cloudflare |

### Let's Encrypt

```bash
SSL_METHOD=letsencrypt
CERTBOT_EMAIL=anda@contoh.com
SITE_DOMAINS=exam_v2=exam.kelasprivat.id
```

`sudo make ssl` memanggil `certbot certonly` — hanya **mengambil** sertifikat;
server block tetap ditulis skrip ini. Dua pihak yang sama-sama menyunting berkas
yang sama akan saling menimpa, dan `make nginx` berikutnya akan menghapus
pekerjaan certbot tanpa memberi tahu siapa pun.

Sekalian dipasang hook `renewal-hooks/deploy` yang memuat ulang nginx setelah
perpanjangan. **Tanpa itu jalur ini berbahaya**: nginx membaca sertifikat sekali
saat start, jadi perpanjangan berhasil di disk tetapi pengunjung tetap menerima
sertifikat lama sampai benar-benar kedaluwarsa — tanpa satu pun pesan error di
sepanjang jalan.

### Cloudflare Origin Certificate

```bash
SSL_METHOD=cloudflare
CF_ORIGIN_CA_KEY=v1.0-...
```

Ambil di dash.cloudflare.com → My Profile → API Tokens → **Origin CA Key**.
API Token dengan izin *SSL and Certificates* juga diterima — keduanya dicoba,
karena Cloudflare menjawab header yang salah dengan "Authentication failed" yang
tidak menyinggung jenis kunci sama sekali.

Sertifikat ini **hanya sah di belakang proxy Cloudflare**. Awan diubah jadi
abu-abu (*DNS only*), browser langsung menolaknya.

Tidak ingin menaruh kredensial di server? Buat manual di dashboard (SSL/TLS →
Origin Server → Create Certificate), simpan sebagai `certs/<domain>.pem` dan
`certs/<domain>.key`. `sudo make ssl` akan memakainya, dan mencocokkan modulus
keduanya lebih dulu — tempelan lewat konsol web sering terpotong. Direktori
`certs/` tidak ikut ke git.

Satu domain yang gagal tidak menghentikan yang lain.

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

## "API tidak bisa konek ke MySQL padahal .env sudah benar"

Gejala paling membingungkan di setup ini, dan sebabnya hampir selalu sama:
**MySQL tidak mendengar di alamat yang dituju container.**

`docker0` hanyalah jembatan bawaan Docker. Setiap proyek docker-compose membuat
jembatannya SENDIRI (`br-xxxxxxxx`) dengan subnet berbeda — 172.18, 172.19, dan
seterusnya. Baris `extra_hosts: host.docker.internal:host-gateway` di container
menunjuk gateway jaringan **itu**, bukan docker0. Jadi container menyambung ke
172.18.0.1 sementara MySQL hanya mendengar di 127.0.0.1 dan 172.17.0.1.

Sambungannya ditolak sebelum urusan pengguna atau password dimulai — itulah
kenapa memperbaiki `.env` tidak pernah menolong, dan kenapa grant `'172.%'`
juga tidak: permintaannya tidak pernah sampai.

Periksa dengan:

```bash
sudo make status
```

Bagian "MySQL terjangkau dari container?" menyebut tiap jembatan beserta
jawabannya. Bila ada yang BEDA:

```bash
sudo make mysql
```

Perintah itu menambahkan alamat gateway tersebut ke `bind-address` dan
me-restart MySQL. Aman diulang.

**Kenapa jaringannya dibuat server-setup, bukan compose.** MySQL menolak START
bila disuruh mendengar di alamat yang belum ada, jadi jembatannya harus lahir
lebih dulu. `05-docker.sh` membuat jaringan `exam-v2` dengan subnet tetap
(172.28.0.0/24) sebelum `10-mysql.sh` menentukan bind-address, dan
`docker-compose.yml` proyek memakai ulang jaringan bernama sama.

## Berapa siswa bisa ujian bersamaan?

Uji beban aplikasi (`php artisan exam:stress`) mengukur **biaya per operasi**,
bukan kapasitas bersamaan — ia menempuh kode dari dalam proses, bukan lewat
PHP-FPM. Angkanya bisa sangat bagus sementara server sungguhan sudah antre.

Contoh hasil nyata pada 500 siswa (11.200 permintaan, 0 galat):

| Endpoint | p95 |
|---|---|
| heartbeat | 5,7 ms |
| autosave | 8,2 ms |
| start | 23 ms |
| submit | 29 ms |

Yang bisa disimpulkan: **biaya per permintaan bukan penghambatnya.** Dengan
heartbeat tiap 60 detik dan autosave berkala tiap 5 menit, satu siswa hanya
menghasilkan sekitar 0,03 permintaan/detik. Bahkan 5.000 siswa serentak hanya
menghasilkan sekitar **satu permintaan yang sedang diproses** pada satu waktu.

Yang TIDAK bisa disimpulkan dari angka itu, dan justru menjadi plafonnya:

1. **`pm.max_children` PHP-FPM.** Bawaan distro adalah **5** — seluruh situs
   hanya melayani lima permintaan PHP bersamaan. Lalu lintas mantap tidak
   menyentuhnya, tetapi LONJAKAN dan permintaan LAMBAT menyentuhnya langsung:
   satu kelas menekan "Mulai" berbarengan, atau lima unggahan foto proktor dari
   jaringan siswa yang lambat, sudah cukup membuat seluruh situs berhenti
   menjawab — termasuk siswa yang sedang menyimpan jawaban.
   `15-php.sh` kini menyetelnya dari RAM yang ada.
2. **`max_connections` MySQL** (disetel 300). Tiap proses PHP memegang satu
   koneksi, jadi plafon FPM dijaga tetap jauh di bawahnya — kalau tidak,
   kegagalannya berpindah menjadi "Too many connections", yang jauh lebih
   membingungkan daripada antrean.

Periksa keduanya dengan:

```bash
sudo make status
```

Bagian "Kapasitas permintaan bersamaan" menyebut angka yang sedang berlaku dan
memperingatkan bila masih bawaan distro.
