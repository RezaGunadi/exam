#!/usr/bin/env bash
# Pekerja antrean cuandariponsel sebagai layanan systemd.
#
# QUEUE_CONNECTION=database, dan yang masuk ke sana CompressPortfolioClip:
# kompresi clip portofolio yang dijalankan setelah unggahan. Tanpa pekerja,
# barisnya menumpuk di tabel `jobs` tanpa pernah dieksekusi — dan tidak ada
# yang terlihat rusak. Unggahannya berhasil, clipnya tampil, hanya ukurannya
# tidak pernah mengecil dan tagihan penyimpanan R2 naik diam-diam.
#
# systemd, bukan entri cron: `queue:work` adalah proses yang HIDUP TERUS. Cron
# yang memanggilnya tiap menit akan menumpuk pekerja yang tidak pernah mati.
# Alternatif lain adalah supervisor, tetapi itu berarti satu paket dan satu
# format konfigurasi lagi untuk dirawat, sementara systemd sudah ada.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root

[ -f "$APP_ROOT/artisan" ] || die "$APP_ROOT/artisan tidak ada — jalankan dulu: sudo make app"

PHP_BIN="$(command -v php || true)"
[ -n "$PHP_BIN" ] || die "php tidak ditemukan di PATH"

UNIT="/etc/systemd/system/${APP_SITE}-queue.service"

log "pekerja antrean ${APP_SITE}"

TMP="$(mktemp)"
cat > "$TMP" <<UNITFILE
# Ditulis oleh server-setup/repost-app — JANGAN disunting manual.
[Unit]
Description=Pekerja antrean ${APP_SITE} (Laravel queue:work)
# MySQL harus siap lebih dulu; antreannya ada DI DALAM database, jadi pekerja
# yang start duluan hanya menghasilkan galat koneksi berulang di log.
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
# Sama seperti PHP-FPM. Berkas yang dibuat pekerja (log, berkas sementara
# kompresi) harus bisa ditimpa proses web, dan sebaliknya.
User=www-data
Group=www-data
WorkingDirectory=${APP_ROOT}

# --max-time=3600: pekerja berhenti sendiri tiap jam lalu dinyalakan ulang
# systemd. Itu yang membuat KODE BARU terpakai setelah deploy — PHP memuat
# seluruh aplikasi sekali saat pekerja start, jadi pekerja yang hidup berhari-
# hari akan terus menjalankan versi lama meski berkasnya sudah berganti.
#
# --timeout=1500 harus DI BAWAH DB_QUEUE_RETRY_AFTER (1800 di .env aplikasi).
# Bila lebih besar, Laravel menganggap pekerjanya mati sebelum timeout tercapai
# dan menyerahkan ulang pekerjaan yang sama — dua FFmpeg menulis berkas yang
# sama, dan yang selesai belakangan menghapus keluaran yang sudah dipakai yang
# pertama.
#
# --tries=3 dengan backoff: kegagalan sementara (R2 tidak menjawab) dicoba lagi,
# bukan langsung masuk failed_jobs.
ExecStart=${PHP_BIN} artisan queue:work --sleep=3 --tries=3 --backoff=30 --max-time=3600 --timeout=1500

# Pekerja yang berhenti karena --max-time BUKAN kegagalan; restart selalu.
Restart=always
RestartSec=5

# Sinyal berhenti yang dipahami Laravel: pekerjaan yang sedang jalan
# diselesaikan dulu, baru prosesnya keluar. SIGKILL langsung akan
# meninggalkan pekerjaan setengah jadi yang tidak pernah dilepas kembali.
KillSignal=SIGTERM
TimeoutStopSec=90

StandardOutput=append:/var/log/${APP_SITE}-queue.log
StandardError=append:/var/log/${APP_SITE}-queue.log

[Install]
WantedBy=multi-user.target
UNITFILE

LOG_FILE="/var/log/${APP_SITE}-queue.log"
[ -f "$LOG_FILE" ] || : > "$LOG_FILE"
chown www-data:www-data "$LOG_FILE"
chmod 640 "$LOG_FILE"

if [ -f "$UNIT" ] && cmp -s "$TMP" "$UNIT"; then
  rm -f "$TMP"
  skip "unit ${APP_SITE}-queue.service"
else
  backup_once "$UNIT"
  mv "$TMP" "$UNIT"
  chmod 644 "$UNIT"
  systemctl daemon-reload
  ok "unit ${APP_SITE}-queue.service"
fi

systemctl enable "${APP_SITE}-queue.service" >/dev/null 2>&1 || true
systemctl restart "${APP_SITE}-queue.service" || {
  warn "pekerja antrean gagal start. Periksa:"
  warn "  systemctl status ${APP_SITE}-queue --no-pager"
  warn "  tail -30 ${LOG_FILE}"
  exit 0
}

# Diberi waktu sebentar sebelum diperiksa: unit yang langsung mati karena
# kredensial database salah tetap melaporkan "activating" pada milidetik
# pertama, dan deploy lalu selesai dengan laporan yang keliru.
sleep 2
if systemctl is-active --quiet "${APP_SITE}-queue.service"; then
  ok "pekerja antrean berjalan"
else
  warn "pekerja antrean berhenti sesaat setelah start:"
  systemctl status "${APP_SITE}-queue.service" --no-pager --lines=10 2>&1 | sed 's/^/       /' || true
fi

# Rotasi log — pekerja menulis satu baris per pekerjaan, dan tanpa rotasi
# berkasnya membesar diam-diam sampai partisi penuh.
LOGROTATE_FILE="/etc/logrotate.d/${APP_SITE}-queue"
if [ -f "$LOGROTATE_FILE" ]; then
  skip "rotasi log antrean"
else
  cat > "$LOGROTATE_FILE" <<ROTATE
${LOG_FILE} {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 640 www-data www-data
}
ROTATE
  chmod 644 "$LOGROTATE_FILE"
  ok "rotasi log antrean (mingguan, simpan 4)"
fi
