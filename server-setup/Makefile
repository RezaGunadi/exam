# Setup server sekali jalan — Debian/Ubuntu.
#
# Semua target IDEMPOTEN: aman dijalankan berulang kali, yang sudah ada
# dilewati. Menjalankan ulang setelah menambah situs di .env hanya membuat
# yang baru, tanpa menyentuh yang lama.
#
#   sudo make server     # seluruh rangkaian
#   sudo make docker     # Docker Engine + plugin Compose
#   sudo make mysql      # MySQL + pengguna + database per proyek
#   sudo make php        # pindahkan seluruh server ke PHP_VERSION di .env
#   sudo make nginx      # nginx + PHP-FPM + situs + symlink
#   sudo make node       # Node.js + build situs di NODE_SITES
#   sudo make ssl        # Origin Certificate Cloudflare + server block 443
#   sudo make phpmyadmin # panel database (port terpisah + basic auth)
#   make status          # ringkasan keadaan server

SHELL := /bin/bash

.PHONY: help server preflight docker mysql php nginx node cloudflare ssl phpmyadmin status env brand-sync

help:
	@echo "Setup server — target yang tersedia:"
	@echo "  sudo make server       Pasang & konfigurasi semuanya, termasuk HTTPS"
	@echo "  sudo make docker       Docker Engine + plugin Compose saja"
	@echo "  sudo make mysql        MySQL saja"
	@echo "  sudo make php          Pindahkan PHP (CLI, FPM & server block) ke PHP_VERSION di .env"
	@echo "  sudo make nginx        nginx + situs saja"
	@echo "  sudo make node         Node.js + 'npm ci && npm run build' untuk NODE_SITES"
	@echo "  sudo make ssl          HTTPS: Origin Certificate + server block 443"
	@echo "  sudo make cloudflare   Pulihkan IP asli di belakang proxy Cloudflare"
	@echo "  sudo make phpmyadmin   phpMyAdmin saja"
	@echo "  sudo make brand-sync   Domain branding premium: vhost + SSL otomatis"
	@echo "  make status            Lihat keadaan sekarang"
	@echo ""
	@echo "Sesuaikan daftar situs, domain & database di .env (dibuat otomatis dari .env.example)."
	@echo ""
	@echo "Aplikasi dengan langkah deploy sendiri — masing-masing punya README:"
	@echo "  exam-v1/     Laravel   ujian.kelasprivat.id"
	@echo "  repost-app/  Laravel   repost.ragh.co.id      (build Vite, antrean, unggahan 200MB)"
	@echo "  junior-app/  FastAPI   junior-app.ragh.co.id  (container; nginx & HTTPS dari sini)"

env:
	@if [ ! -f .env ]; then \
		cp .env.example .env; chmod 600 .env; \
		echo "  .env dibuat dari .env.example — GANTI password bawaannya."; \
	fi

preflight: env
	@bash scripts/00-preflight.sh

docker: preflight
	@bash scripts/05-docker.sh

# Docker HARUS lebih dulu: skrip MySQL menentukan alamat yang didengarkan dari
# ada-tidaknya jembatan docker0. Dipasang belakangan, MySQL sudah terlanjur
# terikat ke loopback dan container tidak akan bisa menyambung.
mysql: docker
	@bash scripts/10-mysql.sh

# Dijalankan TERPISAH, bukan bagian dari `make server`: memasang versi PHP yang
# diminta bisa berarti menambahkan repo pihak ketiga (ondrej/sury), dan itu
# keputusan yang pantas diketik sendiri, bukan efek samping dari setup awal.
#
# `make nginx` tetap aman dijalankan lebih dulu — ia memakai PHP bawaan distro
# selama versi yang diminta belum tersedia, sambil menyebutkan target ini.
php: preflight
	@bash scripts/15-php.sh

nginx: preflight
	@bash scripts/20-nginx.sh

# IKUT dalam `make server`, tidak seperti `make php` — dan itu aman karena
# NODE_SITES kosong berarti skripnya tidak mengerjakan apa pun, termasuk tidak
# menambahkan repo NodeSource. Server yang tidak butuh Node tidak akan pernah
# kejatuhan repo pihak ketiga hanya karena setup dijalankan.
#
# Harus SESUDAH nginx: repositorinya baru ada setelah 20-nginx.sh mengklonnya.
node: nginx
	@bash scripts/40-node.sh

# Dijalankan TERPISAH, bukan bagian dari `make server`: tidak semua situs
# berada di belakang Cloudflare, dan memasang real_ip untuk yang tidak akan
# membuat nginx mempercayai header dari pihak yang salah.
cloudflare: nginx
	@bash scripts/25-cloudflare-realip.sh

# Ikut dalam `make server`, tapi tidak memaksa: situs tanpa entri di
# SITE_DOMAINS dilewati, dan yang belum punya sertifikat cukup diberi peringatan
# lalu tetap dilayani lewat HTTP. Setup tidak berhenti karena satu domain.
ssl: nginx
	@bash scripts/35-ssl.sh

phpmyadmin: nginx
	@bash scripts/30-phpmyadmin.sh

# Penyelaras domain branding premium.
#
# TIDAK ikut dalam `make server`: ia me-reload nginx yang melayani seluruh situs
# di mesin ini, termasuk v1, dan itu tidak pantas terjadi diam-diam di tengah
# setup awal. Jalankan sendiri setelah SCHEDULER_TOKEN dan CF_ORIGIN_CA_KEY
# terisi.
#
# Aman diulang: skripnya idempoten dan hanya menyentuh berkas berawalan
# `brand-`.
#
# TIDAK bergantung pada target `nginx`, meski jelas membutuhkannya. Target itu
# menulis ulang SELURUH vhost di mesin ini; menjadikannya prasyarat berarti
# "pasang timer branding" diam-diam membangun ulang konfigurasi semua situs.
# Skripnya memeriksa keberadaan nginx sendiri dan berhenti dengan pesan jelas
# bila belum ada.
brand-sync:
	@bash scripts/45-brand-sync.sh

# Urutannya penting: MySQL lebih dulu supaya phpMyAdmin punya yang dipantau,
# nginx sebelum phpMyAdmin karena panel itu disajikan lewat nginx, node setelah
# nginx karena repositorinya baru ada setelah diklon, dan SSL paling akhir
# karena ia menulis ulang server block yang sudah jadi.
#
# `php` SEBELUM `nginx`, dan sebelumnya ia TIDAK ada di daftar ini sama
# sekali. Akibatnya server baru berjalan dengan pool PHP-FPM bawaan distro:
# pm.max_children = 5, artinya seluruh situs hanya melayani lima permintaan
# PHP bersamaan. Itu tidak pernah terlihat di uji beban aplikasi — uji itu
# menempuh kode dari dalam proses, bukan lewat PHP-FPM — jadi plafonnya
# baru ketahuan saat satu kelas menekan "Mulai" berbarengan.
#
# Sebelum nginx karena 15-php.sh yang menambahkan repo dan memasang versi
# PHP yang diminta; nginx lalu menunjuk ke socket yang sudah benar.
server: preflight docker mysql php nginx node phpmyadmin ssl
	@echo ""
	@echo "Setup selesai — PERIKSA hasilnya, jangan berhenti di baris ini:"
	@echo ""
	@bash scripts/status.sh | sed -n '/Situs aktif:/,/^$$/p'
	@echo "Situs yang masih 'http saja' TIDAK akan terbuka bila mode SSL"
	@echo "Cloudflare sudah Full/Full (strict) — pengunjung menerima 521."
	@echo ""
	@echo "Langkah berikutnya — dilakukan manual dengan sengaja:"
	@echo "  1. Ganti password bawaan di .env, lalu jalankan ulang: sudo make mysql"
	@echo "  2. Arahkan DNS tiap domain ke IP server ini (proxied di Cloudflare)"
	@echo "  3. Cloudflare → SSL/TLS → Overview → mode Full (strict)"
	@echo "  4. Batasi akses phpMyAdmin ke IP Anda (lihat komentar di server block-nya)"

status:
	@bash scripts/status.sh
