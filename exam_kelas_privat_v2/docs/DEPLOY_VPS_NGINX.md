.

## 1. Persiapan DNS

Sebelum menyentuh server, arahkan domain ke IP VPS.

Tambahkan record:

- `A` → `exam.kelasprivat.id` → `IP_VPS`

Kalau ingin nanti memisahkan API ke subdomain, itu bisa dilakukan belakangan. Untuk konfigurasi sekarang, satu domain sudah cukup.

## 2. Login ke VPS

Masuk ke server:

```bash
ssh root@IP_VPS
```

Kalau Anda menggunakan user non-root dengan sudo, semua perintah root di bawah bisa dijalankan lewat `sudo`.

## 3. Install paket dasar

```bash
apt update && apt upgrade -y
apt install -y nginx git curl unzip build-essential certbot python3-certbot-nginx mysql-client
```

## 4. Install Node.js

Next.js perlu Node.js modern. Gunakan Node.js 22 LTS:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
node -v
npm -v
```

## 5. Install Go

Project backend saat ini memakai Go `1.25`.

```bash
cd /tmp
curl -LO https://go.dev/dl/go1.25.0.linux-amd64.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz
ln -sf /usr/local/go/bin/go /usr/local/bin/go
go version
```

## 6. Buat struktur folder aplikasi

```bash
mkdir -p /var/www/exam_kelas_privat_v2
mkdir -p /var/log/exam_kelas_privat_v2
```

Kalau source code akan di-clone dari git:

```bash
cd /var/www
git clone <URL_REPOSITORY_ANDA> exam_kelas_privat_v2
```

Kalau source code disalin manual, pastikan hasil akhirnya ada di:

```text
/var/www/exam_kelas_privat_v2/backend
/var/www/exam_kelas_privat_v2/frontend
```

## 7. Siapkan environment backend

Masuk ke folder backend:

```bash
cd /var/www/exam_kelas_privat_v2/backend
cp .env.example .env
```

Isi file `.env` backend:

```env
APP_PORT=8080
APP_URL=https://exam.kelasprivat.id
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USERNAME=USER_DB
DB_PASSWORD=PASSWORD_DB
DB_NAME=exam_kelas_privat
DB_PARAMS=parseTime=true
JWT_SECRET=GANTI_DENGAN_SECRET_PANJANG_DAN_ACAK
SCHEDULER_TOKEN=GANTI_DENGAN_TOKEN_SCHEDULER_PANJANG
UPLOAD_DIR=data/uploads
```

Opsional: set `UPLOAD_DIR` ke path absolut (mis. `/var/www/exam_kelas_privat_v2/backend/data/uploads`) dan pastikan direktori itu **persisten** (backup) serta dapat ditulis oleh user yang menjalankan service API — di situ disimpan gambar ilustrasi soal, dilayani lewat `/api/files/...`.

Catatan:

- Backend mendukung `MYSQL_DSN`, tetapi untuk deploy baru lebih disarankan memakai format terpisah `DB_*` agar password kosong maupun terisi sama-sama aman ditangani.
- Jika MySQL berada di server lain, ganti `DB_HOST` dan `DB_PORT` sesuai host DB Anda.
- Karena targetnya tetap DB existing Laravel, `DB_NAME` harus menunjuk database lama yang aktif.
- `APP_URL` sebaiknya domain publik final.

## 8. Jalankan migrasi Go

Walau database existing tetap dipakai, tool migrasi Go tetap perlu disiapkan agar ownership deploy baru konsisten.

```bash
cd /var/www/exam_kelas_privat_v2/backend
go run ./cmd/migrate
```

Penting:

- Pastikan Anda paham status DB existing sebelum migrasi.
- Jika DB produksi sudah berisi data Laravel, lakukan backup terlebih dahulu.
- Untuk first deploy ke production, sangat disarankan ambil snapshot database sebelum langkah ini.

Contoh backup cepat:

```bash
mysqldump -u USER_DB -p exam_kelas_privat > /root/backup_exam_kelas_privat_$(date +%F_%H-%M-%S).sql
```

## 9. Build backend Go

```bash
cd /var/www/exam_kelas_privat_v2/backend
go mod download
go build -o /var/www/exam_kelas_privat_v2/bin/api ./cmd/api
go build -o /var/www/exam_kelas_privat_v2/bin/worker ./cmd/worker
```

Pastikan folder binary ada:

```bash
mkdir -p /var/www/exam_kelas_privat_v2/bin
```

Jika belum ada, jalankan dulu sebelum `go build`.

## 10. Siapkan environment frontend

```bash
cd /var/www/exam_kelas_privat_v2/frontend
cp .env.example .env.local
```

Isi `.env.local`:

```env
NEXT_PUBLIC_API_URL=https://exam.kelasprivat.id
```

Karena backend diproxy lewat domain yang sama dengan prefix `/api`, nilai ini cukup diarahkan ke domain utama.

## 11. Install dependency dan build frontend

```bash
cd /var/www/exam_kelas_privat_v2/frontend
npm ci
npm run lint
npm run build
```

## 12. Buat service `systemd` backend API

Buat file:

```bash
nano /etc/systemd/system/exam-kelas-privat-api.service
```

Isi dengan:

```ini
[Unit]
Description=Exam Kelas Privat Go API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/exam_kelas_privat_v2/backend
EnvironmentFile=/var/www/exam_kelas_privat_v2/backend/.env
ExecStart=/var/www/exam_kelas_privat_v2/bin/api
Restart=always
RestartSec=5
StandardOutput=append:/var/log/exam_kelas_privat_v2/api.log
StandardError=append:/var/log/exam_kelas_privat_v2/api-error.log

[Install]
WantedBy=multi-user.target
```

## 13. Buat service `systemd` worker scheduler

Buat file:

```bash
nano /etc/systemd/system/exam-kelas-privat-worker.service
```

Isi dengan:

```ini
[Unit]
Description=Exam Kelas Privat Go Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/exam_kelas_privat_v2/backend
EnvironmentFile=/var/www/exam_kelas_privat_v2/backend/.env
ExecStart=/var/www/exam_kelas_privat_v2/bin/worker
Restart=always
RestartSec=5
StandardOutput=append:/var/log/exam_kelas_privat_v2/worker.log
StandardError=append:/var/log/exam_kelas_privat_v2/worker-error.log

[Install]
WantedBy=multi-user.target
```

## 14. Buat service `systemd` frontend Next.js

Buat file:

```bash
nano /etc/systemd/system/exam-kelas-privat-frontend.service
```

Isi dengan:

```ini
[Unit]
Description=Exam Kelas Privat Frontend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/exam_kelas_privat_v2/frontend
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm run start -- --hostname 127.0.0.1 --port 3000
Restart=always
RestartSec=5
StandardOutput=append:/var/log/exam_kelas_privat_v2/frontend.log
StandardError=append:/var/log/exam_kelas_privat_v2/frontend-error.log

[Install]
WantedBy=multi-user.target
```

## 15. Aktifkan semua service

```bash
systemctl daemon-reload
systemctl enable exam-kelas-privat-api
systemctl enable exam-kelas-privat-worker
systemctl enable exam-kelas-privat-frontend

systemctl start exam-kelas-privat-api
systemctl start exam-kelas-privat-worker
systemctl start exam-kelas-privat-frontend
```

Cek status:

```bash
systemctl status exam-kelas-privat-api
systemctl status exam-kelas-privat-worker
systemctl status exam-kelas-privat-frontend
```

Kalau ada error, lihat log:

```bash
journalctl -u exam-kelas-privat-api -n 100 --no-pager
journalctl -u exam-kelas-privat-worker -n 100 --no-pager
journalctl -u exam-kelas-privat-frontend -n 100 --no-pager
```

## 16. Cek proses lokal sebelum Nginx

Pastikan semua service benar-benar hidup:

```bash
curl http://127.0.0.1:8080/healthz
curl http://127.0.0.1:8080/api/landing/stats
curl -I http://127.0.0.1:3000
```

Jika semua normal:

- backend `/healthz` harus mengembalikan status `200`
- frontend port `3000` harus mengembalikan respons HTTP

## 17. Konfigurasi Nginx

Buat file:

```bash
nano /etc/nginx/sites-available/exam.kelasprivat.id
```

Isi dengan konfigurasi berikut:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name exam.kelasprivat.id;

    client_max_body_size 50M;

    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location = /healthz {
        proxy_pass http://127.0.0.1:8080/healthz;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Aktifkan site:

```bash
ln -sf /etc/nginx/sites-available/exam.kelasprivat.id /etc/nginx/sites-enabled/exam.kelasprivat.id
nginx -t
systemctl reload nginx
```

## 18. Aktifkan HTTPS dengan Let's Encrypt

```bash
certbot --nginx -d exam.kelasprivat.id
```

Ikuti prompt sampai selesai. Setelah itu test auto-renew:

```bash
certbot renew --dry-run
```

## 19. Verifikasi akhir

Setelah HTTPS aktif, cek:

```bash
curl -I https://exam.kelasprivat.id
curl https://exam.kelasprivat.id/healthz
curl https://exam.kelasprivat.id/api/landing/stats
```

Buka di browser:

- `https://exam.kelasprivat.id`
- `https://exam.kelasprivat.id/login`

Checklist deploy:

- homepage tampil
- login page tampil
- request frontend ke `/api/*` berhasil
- backend `/healthz` normal
- worker scheduler hidup
- sertifikat HTTPS valid

## 20. Cara update aplikasi setelah ada perubahan code

Setiap kali ada update:

```bash
cd /var/www/exam_kelas_privat_v2
git pull
```

Build ulang backend:

```bash
cd /var/www/exam_kelas_privat_v2/backend
go mod download
go build -o /var/www/exam_kelas_privat_v2/bin/api ./cmd/api
go build -o /var/www/exam_kelas_privat_v2/bin/worker ./cmd/worker
```

Build ulang frontend:

```bash
cd /var/www/exam_kelas_privat_v2/frontend
npm ci
npm run lint
npm run build
```

Restart service:

```bash
systemctl restart exam-kelas-privat-api
systemctl restart exam-kelas-privat-worker
systemctl restart exam-kelas-privat-frontend
systemctl status exam-kelas-privat-api --no-pager
systemctl status exam-kelas-privat-worker --no-pager
systemctl status exam-kelas-privat-frontend --no-pager
```

## 21. Troubleshooting cepat

### Frontend tidak bisa memanggil API

Cek:

- `NEXT_PUBLIC_API_URL` di `frontend/.env.local`
- Nginx location `/api/`
- backend service aktif di port `8080`

Tes cepat:

```bash
curl http://127.0.0.1:8080/api/landing/stats
curl https://exam.kelasprivat.id/api/landing/stats
```

### Backend gagal konek MySQL

Tes:

```bash
mysql -h 127.0.0.1 -u USER_DB -p exam_kelas_privat
```

Kalau gagal:

- cek host DB
- cek user/password
- cek firewall
- cek apakah DB existing Laravel memang bisa diakses dari VPS ini

### Service mati setelah reboot

Pastikan `enable` sudah dijalankan:

```bash
systemctl is-enabled exam-kelas-privat-api
systemctl is-enabled exam-kelas-privat-worker
systemctl is-enabled exam-kelas-privat-frontend
```

### Nginx error 502

Berarti upstream mati atau salah port.

Tes:

```bash
curl http://127.0.0.1:3000
curl http://127.0.0.1:8080/healthz
```

## 22. Rekomendasi production

Untuk production yang lebih aman, sebaiknya:

- gunakan user Linux khusus deploy, jangan selalu `root`
- simpan secret kuat dan jangan commit file `.env`
- backup database sebelum migrasi atau update besar
- pasang firewall dasar, misalnya hanya buka `22`, `80`, `443`
- monitor log worker karena scheduler penting untuk parity dengan Laravel
- lakukan cutover per modul jika Laravel lama masih aktif menulis ke DB yang sama

## Ringkasan singkat

Urutan paling aman:

1. Arahkan DNS `exam.kelasprivat.id` ke VPS.
2. Install Nginx, Node.js, Go, dan dependency sistem.
3. Upload source code ke `/var/www/exam_kelas_privat_v2`.
4. Isi `.env` backend dan `.env.local` frontend.
5. Jalankan migrasi Go dengan hati-hati ke DB existing.
6. Build backend dan frontend.
7. Buat service `systemd` untuk API, worker, dan frontend.
8. Proxy semua trafik lewat Nginx.
9. Aktifkan HTTPS dengan Let's Encrypt.
10. Verifikasi route frontend, `/api`, `/healthz`, dan scheduler.
