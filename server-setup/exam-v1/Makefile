# Deploy Exam v1 (Laravel) — ujian.kelasprivat.id
#
# TERPISAH dari Makefile utama dengan sengaja, bukan karena kerapian.
#
# Setup di direktori induk mengelola situs lewat SITES/SITE_DOMAINS di .env, dan
# server block-nya ditulis write_site_conf dengan `root /var/www/<situs>`.
# Laravel butuh `root /var/www/<situs>/public` — selisih satu direktori yang
# membuat seluruh kode sumber, termasuk .env, berada di dalam jangkauan web.
# Menitipkan situs ini ke sana berarti server block Laravel-nya DITIMPA diam-diam
# setiap kali `sudo make nginx` dijalankan.
#
# Karena itu situs ini tidak boleh didaftarkan di SITES maupun SITE_DOMAINS.
# Skrip di sini memeriksanya dan berhenti bila terlanjur terdaftar.
#
#   sudo make deploy   # seluruh rangkaian: kode → nginx → HTTPS → cron
#   sudo make app      # klon/dependensi/.env/migrasi/izin
#   sudo make site     # server block nginx saja
#   sudo make ssl      # sertifikat Let's Encrypt + blok 443
#   sudo make cron     # penjadwal Laravel (schedule:run tiap menit)
#   sudo make update   # tarik perubahan lalu migrasi — untuk rilis berikutnya
#
# Semua target IDEMPOTEN. Yang sudah ada dilewati, bukan ditimpa; .env aplikasi
# tidak pernah ditulis ulang setelah dibuat.

SHELL := /bin/bash

# Semuanya bisa ditimpa dari baris perintah:
#   sudo make deploy DOMAIN=ujian-staging.kelasprivat.id SITE=exam_v1_staging
SITE    ?= exam_v1
DOMAIN  ?= ujian.kelasprivat.id
REPO    ?= https://github.com/RezaGunadi/exam_kelas_privat.git
DB_NAME ?= exam_admin_system

# Pemilik berkas aplikasi. Kosong = pengguna yang mengetik sudo (SUDO_USER).
# $$USER tidak dipakai: di dalam `sudo make` nilainya sudah root.
DEPLOY_USER ?=

export SITE DOMAIN REPO DB_NAME DEPLOY_USER

.PHONY: help deploy app site ssl cron update permissions

help:
	@echo "Deploy Exam v1 — $(DOMAIN)"
	@echo ""
	@echo "  sudo make deploy   Kode, nginx, HTTPS, dan penjadwal sekaligus"
	@echo "  sudo make app      Klon/dependensi/.env/migrasi/izin saja"
	@echo "  sudo make site     Server block nginx saja"
	@echo "  sudo make ssl      Sertifikat Let's Encrypt + blok 443"
	@echo "  sudo make cron     Penjadwal Laravel (schedule:run tiap menit)"
	@echo "  sudo make update      Rilis berikutnya: git pull + composer + migrasi"
	@echo "  sudo make permissions Pasang ulang izin berkas Laravel"
	@echo ""
	@echo "Situs   : $(SITE)  (/var/www/$(SITE))"
	@echo "Repo    : $(REPO)"
	@echo "Database: $(DB_NAME)"
	@echo ""
	@echo "Butuh MySQL & nginx dari direktori induk lebih dulu: sudo make server"

app:
	@bash scripts/10-app.sh

site:
	@bash scripts/20-site.sh

# Berjalan SETELAH site: certbot memvalidasi lewat port 80, dan port itu baru
# menjawab untuk domain ini setelah server block-nya ada.
ssl:
	@bash scripts/40-ssl.sh

cron:
	@bash scripts/30-cron.sh

update:
	@bash scripts/50-update.sh

# Ikut dijalankan `make app` dan `make update`; berdiri sendiri untuk saat izin
# rusak di luar deploy — misalnya setelah menyalin berkas ke server dengan scp,
# atau setelah menyunting kode langsung di sana sebagai root.
permissions:
	@bash scripts/permissions.sh

# Urutannya penting: kode lebih dulu (nginx menunjuk ke public/ yang baru ada
# setelah klon), lalu HTTPS (butuh server block port 80), penjadwal terakhir
# karena ia menjalankan artisan yang butuh .env dan vendor/ sudah siap.
deploy: app site ssl cron
	@echo ""
	@echo "Deploy selesai — PERIKSA, jangan berhenti di baris ini:"
	@echo "  1. Buka https://$(DOMAIN) dan pastikan halamannya tampil"
	@echo "  2. Isi kredensial R2 & AWS di /var/www/$(SITE)/.env bila unggahan dipakai"
	@echo "  3. Pastikan penjadwal jalan: grep CRON /var/log/syslog | tail"
	@echo ""
