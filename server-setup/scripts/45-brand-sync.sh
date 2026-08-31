#!/usr/bin/env bash
# ============================================================================
# 45-brand-sync.sh — memasang penyelaras domain branding premium.
#
# Menyalin brand-sync.sh ke /usr/local/sbin dan menjadwalkannya lewat systemd
# timer. Timer, bukan cron: systemd mencatat keluarannya ke journal, dan
# `systemctl status brand-sync` langsung menunjukkan jalannya yang terakhir —
# sementara cron yang gagal hanya mengirim surel ke tempat yang tidak dibaca
# siapa pun.
#
# Dijalankan SESUDAH nginx dan SSL disiapkan (20 dan 35): penyelaras ini
# menulis vhost dan memanggil certbot, jadi keduanya harus sudah ada.
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
load_env "$ROOT_DIR"

require_root

# Diperiksa di sini, bukan lewat prasyarat `make nginx` - target itu menulis
# ulang seluruh vhost di mesin ini, dan itu jauh lebih besar daripada yang
# diminta orang yang mengetik `make brand-sync`.
if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx belum terpasang - jalankan \`make nginx\` lebih dulu." >&2
  exit 1
fi

echo ""
echo "── Penyelaras domain branding premium ──────────────────────────────────"

TOKEN="${SCHEDULER_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  # Tanpa token, penyelarasnya tidak bisa memanggil API sama sekali. Dipasang
  # tetapi tidak dijadwalkan — memasang timer yang pasti gagal setiap lima
  # menit hanya memenuhi journal dengan galat yang sama.
  warn "SCHEDULER_TOKEN belum diisi di .env — timer TIDAK diaktifkan"
  warn "  Isi SCHEDULER_TOKEN (sama dengan yang dipakai API), lalu jalankan ulang."
fi

# KEDUANYA disalin: brand-sync.sh menyumber lib-cert.sh dari direktori yang
# sama dengan dirinya. Menyalin satu saja membuat penyelarasnya gagal sejak
# baris pertama, dengan pesan yang menyebut berkas yang tidak pernah ada.
install -m 0750 -o root -g root "$SCRIPT_DIR/lib-cert.sh"   /usr/local/sbin/lib-cert.sh
install -m 0750 -o root -g root "$SCRIPT_DIR/brand-sync.sh" /usr/local/sbin/brand-sync.sh
ok "/usr/local/sbin/brand-sync.sh (+ lib-cert.sh)"

if [ "${SSL_METHOD:-cloudflare}" = "letsencrypt" ]; then
  echo "     Sertifikat lewat Let's Encrypt, mengikuti SSL_METHOD di .env."
  echo "     Domainnya HARUS sudah mengarah ke server ini sebelum sertifikatnya"
  echo "     bisa terbit - Let's Encrypt memverifikasi dengan menghubunginya"
  echo "     dari luar. Sebelum itu, situsnya sudah bisa dibuka lewat HTTP."
elif [ -z "${CF_ORIGIN_CA_KEY:-}" ]; then
  warn "CF_ORIGIN_CA_KEY belum diisi — domain baru akan berhenti di status"
  warn "  \"menunggu\" karena sertifikatnya tidak bisa diterbitkan."
  warn "  Server block-nya tetap dipasang, jadi situsnya sudah bisa dibuka"
  warn "  lewat Cloudflare mode Flexible sementara kuncinya menyusul."
fi

install -d -m 0750 /var/lib/brand-sync

cat > /etc/default/brand-sync <<CONF
# Dibaca systemd sebelum menjalankan brand-sync.
# Berkas ini memuat DUA kredensial — izinnya sengaja 0640.
API_BASE=${BRAND_SYNC_API_BASE:-http://127.0.0.1:8080}
SCHEDULER_TOKEN=${TOKEN}
# CF_ORIGIN_CA_KEY WAJIB diteruskan: penyelaras menerbitkan Cloudflare Origin
# Certificate lewat lib-cert.sh, dan tanpa kunci ini setiap domain baru berhenti
# di status "menunggu" tanpa sebab yang terlihat dari panel.
CF_ORIGIN_CA_KEY=${CF_ORIGIN_CA_KEY:-}
# SSL_METHOD WAJIB diteruskan dan harus sama dengan yang dipakai 35-ssl.sh.
# Bawaan brand-sync adalah "cloudflare"; bila server ini sebenarnya memakai
# letsencrypt, domain branding akan menjadi satu-satunya yang dicoba dengan
# cara berbeda - dan bila kunci API-nya kosong, satu-satunya yang tidak punya
# TLS sama sekali.
SSL_METHOD=${SSL_METHOD:-cloudflare}
CERTBOT_EMAIL=${CERTBOT_EMAIL:-}
WEB_PORT=${BRAND_SYNC_WEB_PORT:-3000}
API_PORT=${BRAND_SYNC_API_PORT:-8080}
CONF
chmod 0640 /etc/default/brand-sync
ok "/etc/default/brand-sync"

cat > /etc/systemd/system/brand-sync.service <<'CONF'
[Unit]
Description=Selaraskan domain branding premium dengan nginx dan SSL
# Nginx harus sudah jalan: penyelaras menguji dan me-reload konfigurasinya.
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/default/brand-sync
ExecStart=/usr/local/sbin/brand-sync.sh
# Gagal TIDAK menjatuhkan apa pun: penyelaras dijalankan lagi pada tick
# berikutnya, dan penyebab tersering (DNS belum diarahkan) memang hanya bisa
# diselesaikan di luar server ini.
SuccessExitStatus=0 1
CONF

cat > /etc/systemd/system/brand-sync.timer <<'CONF'
[Unit]
Description=Jalankan penyelaras domain branding secara berkala

[Timer]
# Lima menit: cukup cepat supaya domain yang baru diisi di panel terasa
# "langsung jadi", dan cukup jarang untuk tidak menghabiskan jatah penerbitan
# Let's Encrypt saat DNS-nya belum siap. Penyelarasnya sendiri menjeda satu jam
# setelah kegagalan.
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
CONF

systemctl daemon-reload

if [ -n "$TOKEN" ]; then
  systemctl enable --now brand-sync.timer >/dev/null 2>&1
  ok "timer brand-sync aktif (tiap 5 menit)"
  echo "     Jalankan sekarang : systemctl start brand-sync"
  echo "     Lihat hasilnya    : journalctl -u brand-sync -n 50 --no-pager"
else
  systemctl disable --now brand-sync.timer >/dev/null 2>&1 || true
  skip "timer brand-sync (menunggu SCHEDULER_TOKEN)"
fi

echo ""
echo "     Domain baru cukup diisi di panel owner; penyelaras yang memasang"
echo "     vhost dan sertifikatnya."
if [ "${SSL_METHOD:-cloudflare}" != "letsencrypt" ]; then
  echo "     Sertifikatnya bisa terbit SEBELUM DNS diarahkan - Origin"
  echo "     Certificate diterbitkan lewat API, bukan lewat validasi HTTP."
fi
