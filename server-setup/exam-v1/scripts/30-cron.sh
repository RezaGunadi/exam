#!/usr/bin/env bash
# Penjadwal Laravel untuk Exam v1.
#
# INI BUKAN PELENGKAP. app/Console/Kernel.php mendaftarkan 16 perintah
# terjadwal, di antaranya ai:score-essays (koreksi esai), exam-results:*
# (menutup hasil ujian yang selesai atau terputus), dan exams:cleanup-expired.
# Tanpa satu baris cron ini, semuanya tidak pernah berjalan — dan tidak ada satu
# pun pesan error yang muncul. Yang terlihat hanya hasil ujian yang menggantung
# selamanya, berhari-hari setelah deploy yang dinyatakan berhasil.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_apt

[ -f "$APP_ROOT/artisan" ] || die "$APP_ROOT/artisan tidak ada — jalankan dulu: sudo make app"

apt_install cron
systemctl enable --now cron >/dev/null 2>&1 || true

CRON_FILE="/etc/cron.d/${APP_SITE}-scheduler"
LOG_FILE="/var/log/${APP_SITE}-schedule.log"

# Log dibuat lebih dulu dan dimiliki www-data. Cron menjalankan perintahnya
# sebagai www-data, dan pengalihan `>>` dilakukan oleh shell MILIK PENGGUNA ITU —
# berkas milik root berarti setiap menit gagal dibuka, isinya hilang, dan
# satu-satunya jejak ada di syslog.
[ -f "$LOG_FILE" ] || : > "$LOG_FILE"
chown www-data:www-data "$LOG_FILE"
chmod 640 "$LOG_FILE"

TMP="$(mktemp)"
cat > "$TMP" <<CRON
# Penjadwal Laravel ${APP_SITE} — dibuat oleh server-setup/exam-v1.
#
# Laravel menjalankan SELURUH jadwalnya dari satu entri per menit; jadwal
# masing-masing perintah ditentukan di app/Console/Kernel.php, bukan di sini.
#
# PATH ditulis eksplisit: cron memberi PATH yang sangat pendek, dan php yang
# tidak ditemukan menghasilkan kegagalan senyap tiap menit.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""

* * * * * www-data cd ${APP_ROOT} && php artisan schedule:run >> ${LOG_FILE} 2>&1
CRON

if [ -f "$CRON_FILE" ] && cmp -s "$TMP" "$CRON_FILE"; then
  rm -f "$TMP"
  skip "penjadwal $APP_SITE"
else
  backup_once "$CRON_FILE"
  mv "$TMP" "$CRON_FILE"
  # cron MENOLAK berkas di /etc/cron.d yang bisa ditulis selain root, dan
  # menolaknya tanpa memberi tahu siapa pun kecuali lewat syslog.
  chown root:root "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  ok "penjadwal $APP_SITE (tiap menit → $LOG_FILE)"
fi

# Rotasi log, karena entri tiap menit tumbuh terus. Tanpa ini berkasnya
# membesar diam-diam sampai partisi penuh — dan partisi penuh mematikan MySQL
# beserta seluruh situs lain di server ini, bukan hanya yang satu ini.
LOGROTATE_FILE="/etc/logrotate.d/${APP_SITE}-schedule"
if [ -f "$LOGROTATE_FILE" ]; then
  skip "rotasi log penjadwal"
else
  cat > "$LOGROTATE_FILE" <<ROTATE
${LOG_FILE} {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 www-data www-data
}
ROTATE
  chmod 644 "$LOGROTATE_FILE"
  ok "rotasi log penjadwal (mingguan, simpan 4)"
fi

echo ""
warn "Penjadwal baru terbukti jalan setelah satu menit. Periksa:"
warn "  tail -f ${LOG_FILE}"
