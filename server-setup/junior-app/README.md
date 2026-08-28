# Deploy Kelas Junior — junior-app.ragh.co.id

Backend FastAPI di `https://github.com/RezaGunadi/kelas_junior.git`, dijalankan
sebagai container (api + Celery worker + beat + Redis) dan diproksikan nginx
host dari `https://junior-app.ragh.co.id` ke `127.0.0.1:8000`.

```bash
cd server-setup && sudo make server   # sekali, bila server masih kosong
cd junior-app   && sudo make deploy
```

Semua target **idempoten**. Yang sudah ada dilewati, bukan ditimpa; `.env`
aplikasi tidak pernah ditulis ulang setelah dibuat.

| Target | Guna |
|---|---|
| `sudo make deploy` | Seluruh rangkaian: kode → Python → stack container |
| `sudo make app` | Klon, database `kidlearn`, `.env` aplikasi |
| `sudo make python` | Python host + virtualenv untuk skrip perawatan |
| `sudo make stack` | `docker compose up -d --build` + tunggu sampai sehat |
| `sudo make update` | Rilis berikutnya: `git pull` + build ulang |
| `sudo make logs` | Ikuti log api/worker/beat |
| `sudo make seed` | Seed idempoten di dalam container |
| `sudo make reseed` | Seed paksa + rakit ulang modul (setelah art ikon berubah) |

## Pembagian dengan setup induk

Berbeda dari `exam-v1/`, situs ini **tetap dikelola setup induk** untuk nginx
dan HTTPS. Aplikasinya tidak menyajikan berkas, jadi server block hasil
`write_site_conf` — yang meneruskan seluruh permintaan ke `127.0.0.1:8000` —
memang bentuk yang benar. Tidak ada `root` yang bisa salah menunjuk.

Yang harus ada di `.env` induk:

```bash
SITES=...,junior_app
PROXY_SITES=exam_v2,junior_app
PROXY_PORTS=junior_app=8000
SITE_DOMAINS=...,junior_app=junior-app.ragh.co.id
SITE_REPOS=...,junior_app=git@github.com:RezaGunadi/kelas_junior.git
DATABASES=...,kidlearn
```

lalu `sudo make nginx && sudo make ssl` di direktori induk.

**`PROXY_PORTS` bukan hiasan.** Tanpa entri itu, situs container memakai bentuk
lama Exam v2: `/api/` diteruskan ke 8080 dan sisanya ke 3000. Halaman depan
tampak normal — yang menjawab 502 hanya alamat di bawah `/api/`, yaitu seluruh
isi aplikasi ini. Skrip di sini memeriksanya dan memperingatkan.

**Setengah terdaftar lebih berbahaya daripada tidak terdaftar sama sekali.**
`junior_app` yang ada di `SITES` tetapi tidak di `PROXY_SITES` membuat nginx
menyajikan `/var/www/junior_app` sebagai berkas biasa — termasuk
`game_backend/.env` berisi password MySQL, `JWT_SECRET`, dan kredensial R2.
Keadaan itu **menghentikan** skrip, bukan sekadar diperingatkan.

## Port container dikunci ke loopback

`docker-compose.yml` di repo aplikasi memetakan `"8000:8000"`, dan Docker
mengartikannya sebagai `0.0.0.0:8000` — API terbuka langsung ke internet, tanpa
HTTPS dan tanpa melewati nginx. Publikasi port Docker juga menulis aturan DNAT
sendiri di iptables, sehingga `ufw deny 8000` **tidak menghalanginya** dan
`ufw status` tetap tampak meyakinkan.

Yang membatasinya adalah `"ip": "127.0.0.1"` di `/etc/docker/daemon.json`,
dipasang `scripts/05-docker.sh` di direktori induk. Itu mengubah alamat
**bawaan** untuk setiap port yang dipublikasikan tanpa menyebut IP, sehingga
arsitektur "nginx host satu-satunya pintu depan" berlaku secara bawaan alih-alih
bergantung pada tiap compose file mengingatnya sendiri.

**Bukan lewat override compose, dan itu bukan pilihan gaya.** Untuk `ports`,
Compose **menggabungkan** daftar dari berkas dasar dan override — tidak
menggantikannya. Menulis `"127.0.0.1:8000:8000"` di override menghasilkan dua
pemetaan sekaligus: yang lama ke `0.0.0.0` tetap ada, dan yang kedua gagal
mengikat port yang sudah dipakai.

`05-docker.sh` sengaja **tidak menimpa** `daemon.json` yang sudah ada — berkas
itu bisa memuat pengaturan yang disunting orang. Pada server seperti itu,
pengaturannya hanya diperingatkan, tidak dipasang. Karena itu `make stack`
**memeriksa hasilnya** setelah stack menyala: kalau port 8000 ternyata terbuka
di semua antarmuka, ia menyebutkannya terang-terangan. Tanpa pemeriksaan itu,
situsnya tetap bekerja normal lewat HTTPS sementara API yang sama juga terbuka
di `http://IP-SERVER:8000` — keadaan yang tidak muncul di log mana pun.

## Restart setelah reboot

`docker-compose.yml` tidak menyetel `restart:` untuk satu service pun. Setelah
server di-reboot, tidak satu pun container kembali hidup, dan situsnya menjawab
502 sampai ada yang login dan mengetik `docker compose up -d`.

`make stack` menulis `docker-compose.override.yml` berisi
`restart: unless-stopped` untuk keempatnya. Override, bukan suntingan langsung:
`docker-compose.yml` milik repo aplikasi dan suntingan di sana akan bentrok pada
`git pull` berikutnya. Berkasnya didaftarkan ke `.git/info/exclude` supaya
working tree tetap bersih — `make update` menolak menarik perubahan bila ada
berkas yang belum di-commit.

`unless-stopped`, bukan `always`: container yang sengaja dimatikan dengan
`docker compose stop` tetap mati setelah reboot. `always` akan menghidupkannya
kembali dan membatalkan keputusan yang diambil sadar.

Restart policy tidak berarti apa-apa bila daemonnya sendiri tidak dinyalakan
saat boot — dua hal berbeda, dan yang kedua diam-diam mematikan yang pertama.
`make stack` memeriksa `systemctl is-enabled docker` juga.

## Python: yang dipasang dan untuk apa

Backend **tidak** memakai Python host. Ia berjalan di dalam container dari image
`python:3.12-slim`, jadi runtime-nya ikut image dan versinya tidak bergantung
pada distro server sama sekali.

`make python` memasang `python3` + virtualenv di
`/var/www/junior_app/.venv` untuk skrip di `game_backend/scripts/` yang memang
dijalankan dari host — `export_bundled_svgs.py`, `engine_smoke.py`,
`vendor_openmoji.py`. Kegagalannya tidak menghentikan deploy: layanan tidak
bergantung pada apa pun yang dipasang di sana.

Venv-nya di **akar repo**, bukan di dalam `game_backend/`. Konteks build image
adalah `game_backend/`, dan venv berisi ribuan berkas yang tidak ada gunanya di
sana — `.dockerignore` memang sudah menutupnya, tetapi menaruhnya di luar
konteks membuat itu tidak lagi bergantung pada satu baris yang bisa hilang.

**Skrip dari host memakai `DATABASE_URL` yang hostnya `host.docker.internal`** —
nama itu hanya dikenal di dalam container. Dari host, timpa nilainya:

```bash
sudo DATABASE_URL='mysql+pymysql://USER:PASS@127.0.0.1:3306/kidlearn?charset=utf8mb4' \
     /var/www/junior_app/.venv/bin/python scripts/seed_all.py
```

Atau lewati venv sama sekali dan jalankan di dalam container: `sudo make seed`.

## Database

`kidlearn` — **terpisah** dari database Laravel, di instans MySQL yang sama.
`utf8mb4` wajib: kontennya dwibahasa dan memuat emoji.

Container menyambung lewat `host.docker.internal`, yang dipetakan compose ke
gateway jembatan Docker (biasanya `172.17.0.1`). Supaya itu bekerja, MySQL harus
**mendengar** di alamat itu, bukan cuma di loopback. Setup induk sudah
mengurusnya — tetapi hanya bila `docker0` sudah ada saat `make mysql`
dijalankan. Server yang Dockernya dipasang belakangan tetap terikat loopback,
dan kegagalannya muncul sebagai "Can't connect to MySQL server" di log
container, jauh dari penyebabnya. `make app` memeriksanya dan menyebutkan
perbaikannya.

Skema dan konten dibuat **otomatis** saat service `api` start: `RUN_MIGRATIONS=1`
memanggil `create_all` (bukan alembic — riwayat alembic lama memakai VARCHAR
tanpa panjang, yang tidak valid di MySQL), dan `SEED_ON_START=1` menjalankan
`seed_all`. Keduanya idempoten dan ber-guard: mengisi yang kosong, melewati yang
sudah ada, tidak menimpa kurasi admin.

## Yang sengaja TIDAK dikerjakan

**Membangun app Flutter.** `game/` di repo yang sama adalah aplikasi Android,
dan servernya tidak punya Flutter SDK maupun alasan untuk memilikinya. Sebelum
rilis APK, arahkan `game/lib/config/api_config.dart` ke
`https://junior-app.ragh.co.id/api/v1` — lihat `game/RELEASE.md`.

**Menjalankan seed dari host saat deploy.** Seed sudah berjalan di dalam
container saat start, dan menjalankannya dua kali dari dua tempat berbeda
berarti dua proses menulis tabel yang sama.

**Menghapus paket, data, atau volume.** Tidak ada target yang menjatuhkan
database, menghapus `/var/www/junior_app`, atau `docker compose down -v`.

## Setelah deploy

Yang tidak bisa dikerjakan skrip ini:

1. **Isi `R2_*`** di `game_backend/.env` bila aset mau disajikan dari Cloudflare
   R2. Dikosongkan tetap jalan — 184 ikon SVG disajikan dari `/media` di dalam
   container — tetapi asetnya ikut hilang bila volume container hilang.
2. **Isi `SMTP_*`**. Kosong berarti kode reset password hanya **dicetak ke log**,
   tidak dikirim; orang tua yang lupa password tidak akan pernah menerimanya.
3. **Ganti `ADMIN_PASSWORD`** bila mau nilai yang diingat. Yang dibuat skrip ini
   acak: `sudo grep ADMIN_ /var/www/junior_app/game_backend/.env`.

Keduanya butuh `sudo make restart` setelah disunting.
