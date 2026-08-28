# Deploy backend Kelas Junior (FastAPI + Celery + Redis) — junior-app.ragh.co.id
#
# TERPISAH dari Makefile utama, tetapi TIDAK dengan alasan yang sama seperti
# exam-v1/.
#
# Situs ini justru TETAP dikelola setup induk untuk urusan nginx dan HTTPS:
# aplikasinya tidak menyajikan berkas, jadi server block hasil write_site_conf
# — yang meneruskan seluruh permintaan ke 127.0.0.1:8000 — memang bentuk yang
# benar. Yang tidak dimiliki setup induk adalah bagian aplikasinya: database
# terpisah, .env, image container, dan Python untuk skrip perawatan.
#
# Jadi pembagiannya:
#   .env induk (SITES/PROXY_SITES/PROXY_PORTS/SITE_DOMAINS)  → nginx & HTTPS
#   direktori ini                                            → aplikasi
#
#   sudo make deploy   # seluruh rangkaian: kode → Python → stack container
#   sudo make app      # klon, database, .env
#   sudo make python   # Python host + virtualenv untuk skrip perawatan
#   sudo make stack    # docker compose up -d --build + tunggu sehat
#   sudo make update   # rilis berikutnya: git pull + build ulang
#
# Semua target IDEMPOTEN. Yang sudah ada dilewati, bukan ditimpa; .env aplikasi
# tidak pernah ditulis ulang setelah dibuat.

SHELL := /bin/bash

# Semuanya bisa ditimpa dari baris perintah:
#   sudo make deploy DOMAIN=junior-staging.ragh.co.id SITE=junior_app_staging PORT=8001
SITE    ?= junior_app
DOMAIN  ?= junior-app.ragh.co.id
REPO    ?= git@github.com:RezaGunadi/kelas_junior.git
DB_NAME ?= kidlearn
PORT    ?= 8000

# Backend ada di SUBDIREKTORI repo. Repo yang sama juga memuat app Flutter
# (game/), yang tidak pernah di-deploy ke server ini.
SUBDIR  ?= game_backend

export SITE DOMAIN REPO DB_NAME PORT SUBDIR

APP_ROOT    := /var/www/$(SITE)
BACKEND_DIR := $(APP_ROOT)/$(SUBDIR)

.PHONY: help deploy app python stack update up down restart logs ps seed reseed shell

help:
	@echo "Deploy backend Kelas Junior — $(DOMAIN)"
	@echo ""
	@echo "  sudo make deploy   Kode, Python, dan stack container sekaligus"
	@echo "  sudo make app      Klon, database $(DB_NAME), .env aplikasi"
	@echo "  sudo make python   Python host + virtualenv (skrip perawatan)"
	@echo "  sudo make stack    docker compose up -d --build + tunggu sehat"
	@echo "  sudo make update   Rilis berikutnya: git pull + build ulang"
	@echo ""
	@echo "  sudo make up/down/restart   Kendalikan container"
	@echo "  sudo make logs              Ikuti log api/worker/beat"
	@echo "  sudo make ps                Status container"
	@echo "  sudo make seed              Jalankan seed_all di dalam container"
	@echo "  sudo make reseed            Seed paksa + rakit ulang modul"
	@echo ""
	@echo "Situs   : $(SITE)  (nginx & HTTPS diurus setup induk)"
	@echo "Backend : $(BACKEND_DIR)  → 127.0.0.1:$(PORT)"
	@echo "Database: $(DB_NAME)  (MySQL host, terpisah dari database Laravel)"
	@echo ""
	@echo "Butuh Docker, MySQL & nginx dari direktori induk lebih dulu:"
	@echo "  cd .. && sudo make server"

app:
	@bash scripts/10-app.sh

python:
	@bash scripts/20-python.sh

stack:
	@bash scripts/30-stack.sh

update:
	@bash scripts/50-update.sh

# Urutannya penting: kode lebih dulu (compose file baru ada setelah klon),
# Python berikutnya karena ia membaca requirements.txt dari klon itu, dan stack
# paling akhir karena ia butuh .env yang dibuat `make app`.
#
# `make python` sengaja ikut: permintaannya adalah Python terpasang otomatis.
# Kegagalannya tidak menghentikan rangkaian — lihat kepala 20-python.sh.
deploy: app python stack
	@echo ""
	@echo "Deploy selesai — PERIKSA, jangan berhenti di baris ini:"
	@echo "  1. Pastikan .env induk memuat SITE_DOMAINS=$(SITE)=$(DOMAIN),"
	@echo "     lalu: cd .. && sudo make nginx && sudo make ssl"
	@echo "  2. Buka https://$(DOMAIN)/api/v1/health — harus {\"status\":\"ok\"}"
	@echo "  3. Panel kurasi: https://$(DOMAIN)/admin (password acak di .env)"
	@echo "     sudo grep ADMIN_ $(BACKEND_DIR)/.env"
	@echo "  4. Isi R2_* & SMTP_* di $(BACKEND_DIR)/.env bila dipakai,"
	@echo "     lalu: sudo make restart"
	@echo "  5. Arahkan app Flutter ke https://$(DOMAIN)/api/v1"
	@echo "     (game/lib/config/api_config.dart, lalu rilis APK baru)"

# ── Operasi harian ─────────────────────────────────────────────────────────
# Semuanya lewat wrapper compose() di scripts/common.sh, yang memilih sendiri
# antara `docker compose` (plugin v2) dan `docker-compose` (skrip v1 lama).
up:
	@bash -c 'source scripts/common.sh; compose up -d'

down:
	@bash -c 'source scripts/common.sh; compose down'

restart:
	@bash -c 'source scripts/common.sh; compose restart'

logs:
	@bash -c 'source scripts/common.sh; compose logs -f --tail=100'

ps:
	@bash -c 'source scripts/common.sh; compose ps'

# Seed idempoten: mengisi yang kosong, melewati yang sudah ada. Aman diulang.
seed:
	@bash -c 'source scripts/common.sh; compose exec api python scripts/seed_all.py'

# Seed PAKSA lalu rakit ulang modul. Dipakai setelah art ikon berubah: modul
# lama menyimpan path ikon lama, dan seed biasa tidak menyentuhnya karena
# tabelnya sudah terisi.
reseed:
	@bash -c 'source scripts/common.sh; compose exec -e SEED_FORCE=1 api python scripts/seed_all.py'
	@bash -c 'source scripts/common.sh; compose exec api python scripts/assemble_cli.py'

shell:
	@bash -c 'source scripts/common.sh; compose exec api /bin/sh'
