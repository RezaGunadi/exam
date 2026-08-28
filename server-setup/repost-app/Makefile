# Deploy cuandariponsel (Laravel 12) — repost.ragh.co.id
#
# TERPISAH dari Makefile utama dengan sengaja, bukan karena kerapian.
#
# Setup di direktori induk mengelola situs lewat SITES/SITE_DOMAINS di .env, dan
# server block-nya ditulis write_site_conf. Deteksi otomatisnya memang menemukan
# public/index.php — tetapi HANYA setelah klonnya ada; pada `make nginx` yang
# dijalankan sebelum itu, root-nya jatuh ke akar repo, dan seluruh kode sumber
# termasuk .env berada di dalam jangkauan web.
#
# Situs ini juga butuh hal-hal yang tidak dimiliki setup induk: batas unggahan
# PHP 200MB untuk clip portofolio, pekerja antrean, dan penjadwal yang
# memindahkan uang tiap hari.
#
# Karena itu situs ini tidak boleh didaftarkan di SITES, SITE_DOMAINS, maupun
# NODE_SITES. Skrip di sini memeriksanya dan berhenti bila terlanjur terdaftar.
#
#   sudo make deploy   # seluruh rangkaian: kode → aset → nginx → HTTPS → cron → antrean
#   sudo make app      # klon/dependensi/.env/migrasi/data awal/izin
#   sudo make assets   # Node.js + 'npm ci && npm run build' (Vite)
#   sudo make uploads  # batas unggahan PHP (200MB clip portofolio)
#   sudo make site     # server block nginx saja
#   sudo make ssl      # sertifikat Let's Encrypt + blok 443
#   sudo make cron     # penjadwal Laravel (schedule:run tiap menit)
#   sudo make queue    # pekerja antrean sebagai layanan systemd
#   sudo make update   # tarik perubahan, bangun ulang, migrasi — rilis berikutnya
#
# Semua target IDEMPOTEN. Yang sudah ada dilewati, bukan ditimpa; .env aplikasi
# tidak pernah ditulis ulang setelah dibuat.

SHELL := /bin/bash

# Semuanya bisa ditimpa dari baris perintah:
#   sudo make deploy DOMAIN=repost-staging.ragh.co.id SITE=repost_staging
SITE    ?= repost
DOMAIN  ?= repost.ragh.co.id
REPO    ?= git@github.com:RezaGunadi/cuan_dari_ponsel.git
DB_NAME ?= cuandariponsel

# Pemilik berkas aplikasi. Kosong = pengguna yang mengetik sudo (SUDO_USER).
# $$USER tidak dipakai: di dalam `sudo make` nilainya sudah root.
DEPLOY_USER ?=

# Jalankan `php artisan migrate`? BAWAANNYA YA — kebalikan dari exam-v1.
#
# Databasenya baru dan memang dibangun dari nol, dan riwayat migrasinya rapi:
# 34 berkas dengan penamaan berurut, tidak ada yang merujuk tabel yang baru
# dibuat migrasi bertanggal lebih akhir.
MIGRATE ?= yes

# Data awal. BAWAANNYA `minimal`, dan itu bukan kehati-hatian berlebihan:
# DatabaseSeeder repo ini membuat DELAPAN akun demo berpassword harfiah
# "password" — termasuk owner@cuandariponsel.local dengan akses penuh.
#
#   minimal  katalog jenis tugas + pengguna sistem platform (yang benar-benar
#            dibutuhkan aplikasi agar bisa jalan)
#   all      DatabaseSeeder penuh — HANYA untuk staging yang tidak publik
#   no       tidak ada data awal sama sekali
SEED ?= minimal

export SITE DOMAIN REPO DB_NAME DEPLOY_USER MIGRATE SEED

.PHONY: help deploy app assets uploads site ssl cron queue update permissions status logs

help:
	@echo "Deploy cuandariponsel — $(DOMAIN)"
	@echo ""
	@echo "  sudo make deploy   Kode, aset, nginx, HTTPS, penjadwal, antrean"
	@echo "  sudo make app      Klon/dependensi/.env/migrasi/data awal/izin"
	@echo "  sudo make assets   Node.js + 'npm ci && npm run build' (Vite)"
	@echo "  sudo make uploads  Batas unggahan PHP (clip portofolio 200MB)"
	@echo "  sudo make site     Server block nginx saja"
	@echo "  sudo make ssl      Sertifikat Let's Encrypt + blok 443"
	@echo "  sudo make cron     Penjadwal Laravel (schedule:run tiap menit)"
	@echo "  sudo make queue    Pekerja antrean (systemd)"
	@echo "  sudo make update      Rilis berikutnya: pull + composer + build + migrasi"
	@echo "  sudo make permissions Pasang ulang izin berkas Laravel"
	@echo "  make status / make logs"
	@echo ""
	@echo "Situs   : $(SITE)  (/var/www/$(SITE))"
	@echo "Repo    : $(REPO)"
	@echo "Database: $(DB_NAME)  (migrate=$(MIGRATE), seed=$(SEED))"
	@echo ""
	@echo "Butuh MySQL & nginx dari direktori induk lebih dulu: sudo make server"

app:
	@bash scripts/10-app.sh

assets:
	@bash scripts/15-assets.sh

uploads:
	@bash scripts/18-uploads.sh

site:
	@bash scripts/20-site.sh

# Berjalan SETELAH site: certbot memvalidasi lewat port 80, dan port itu baru
# menjawab untuk domain ini setelah server block-nya ada.
ssl:
	@bash scripts/40-ssl.sh

cron:
	@bash scripts/30-cron.sh

queue:
	@bash scripts/35-queue.sh

update:
	@bash scripts/50-update.sh

# Ikut dijalankan `make app`, `make assets`, dan `make update`; berdiri sendiri
# untuk saat izin rusak di luar deploy — misalnya setelah menyalin berkas ke
# server dengan scp, atau menyunting kode langsung di sana sebagai root.
permissions:
	@bash scripts/permissions.sh

# Urutannya penting: kode lebih dulu, lalu aset (manifest Vite harus ada sebelum
# halaman mana pun bisa dirender), batas unggahan sebelum nginx supaya keduanya
# konsisten, nginx berikutnya, HTTPS setelah port 80 menjawab, dan penjadwal +
# antrean terakhir karena keduanya menjalankan artisan yang butuh .env dan
# vendor/ sudah siap.
deploy: app assets uploads site ssl cron queue
	@echo ""
	@echo "Deploy selesai — PERIKSA, jangan berhenti di baris ini:"
	@echo "  1. Buka https://$(DOMAIN) dan pastikan halamannya tampil BERGAYA"
	@echo "     (tanpa CSS = manifest Vite tidak terbaca, jalankan: sudo make assets)"
	@echo "  2. Isi kredensial Xendit, R2, dan Fonnte di /var/www/$(SITE)/.env"
	@echo "     lalu WAJIB: sudo make update  (config sudah di-cache)"
	@echo "  3. Isi MANUAL_BANK_* — tanpa itu top-up manual tidak punya tujuan transfer"
	@echo "  4. Pastikan penjadwal jalan: tail -f /var/log/$(SITE)-schedule.log"
	@echo "  5. Pastikan antrean jalan: systemctl status $(SITE)-queue --no-pager"
	@echo "  6. Buat akun owner sungguhan; jangan pakai akun demo seeder"

status:
	@systemctl status $(SITE)-queue --no-pager --lines=5 || true
	@echo ""
	@echo "Penjadwal (5 baris terakhir):"
	@tail -5 /var/log/$(SITE)-schedule.log 2>/dev/null || echo "  (belum ada log)"

logs:
	@tail -f /var/log/$(SITE)-queue.log
