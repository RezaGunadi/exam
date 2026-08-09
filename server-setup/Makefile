# Setup server sekali jalan — Debian/Ubuntu.
#
# Semua target IDEMPOTEN: aman dijalankan berulang kali, yang sudah ada
# dilewati. Menjalankan ulang setelah menambah situs di .env hanya membuat
# yang baru, tanpa menyentuh yang lama.
#
#   sudo make server     # seluruh rangkaian
#   sudo make docker     # Docker Engine + plugin Compose
#   sudo make mysql      # MySQL + pengguna + database per proyek
#   sudo make nginx      # nginx + PHP-FPM + situs + symlink
#   sudo make phpmyadmin # panel database (port terpisah + basic auth)
#   make status          # ringkasan keadaan server

SHELL := /bin/bash

.PHONY: help server preflight docker mysql nginx cloudflare phpmyadmin status env

help:
	@echo "Setup server — target yang tersedia:"
	@echo "  sudo make server       Pasang & konfigurasi semuanya"
	@echo "  sudo make docker       Docker Engine + plugin Compose saja"
	@echo "  sudo make mysql        MySQL saja"
	@echo "  sudo make nginx        nginx + situs saja"
	@echo "  sudo make cloudflare   Pulihkan IP asli di belakang proxy Cloudflare"
	@echo "  sudo make phpmyadmin   phpMyAdmin saja"
	@echo "  make status            Lihat keadaan sekarang"
	@echo ""
	@echo "Sesuaikan daftar situs & database di .env (dibuat otomatis dari .env.example)."

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

nginx: preflight
	@bash scripts/20-nginx.sh

# Dijalankan TERPISAH, bukan bagian dari `make server`: tidak semua situs
# berada di belakang Cloudflare, dan memasang real_ip untuk yang tidak akan
# membuat nginx mempercayai header dari pihak yang salah.
cloudflare: nginx
	@bash scripts/25-cloudflare-realip.sh

phpmyadmin: nginx
	@bash scripts/30-phpmyadmin.sh

# Urutannya penting: MySQL lebih dulu supaya phpMyAdmin punya yang dipantau,
# nginx sebelum phpMyAdmin karena panel itu disajikan lewat nginx.
server: preflight docker mysql nginx phpmyadmin
	@echo ""
	@echo "Setup selesai."
	@echo ""
	@echo "Langkah berikutnya — dilakukan manual dengan sengaja:"
	@echo "  1. Ganti password bawaan di .env, lalu jalankan ulang: sudo make mysql"
	@echo "  2. Isi server_name tiap situs di /etc/nginx/sites-available/"
	@echo "  3. Pasang SSL:  sudo certbot --nginx -d domain-anda"
	@echo "  4. Batasi akses phpMyAdmin ke IP Anda (lihat komentar di server block-nya)"

status:
	@bash scripts/status.sh
