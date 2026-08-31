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
cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib.sh

need_root
load_env

judul "Penyelaras domain branding premium"

TOKEN="${SCHEDULER_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  # Tanpa token, penyelarasnya tidak bisa memanggil API sama sekali. Dipasang
  # tetapi tidak dijadwalkan — memasang timer yang pasti gagal setiap lima
  # menit hanya memenuhi journal dengan galat yang sama.
  warn "SCHEDULER_TOKEN belum diisi di .env — timer TIDAK diaktifkan"
  warn "  Isi SCHEDULER_TOKEN (sama dengan yang dipakai API), lalu jalankan ulang."
fi

install -m 0750 -o root -g root scripts/brand-sync.sh /usr/local/sbin/brand-sync.sh
ok "/usr/local/sbin/brand-sync.sh"

install -d -m 0750 /var/lib/brand-sync

cat > /etc/default/brand-sync <<CONF
# Dibaca systemd sebelum menjalankan brand-sync.
# Berkas ini memuat token — izinnya sengaja 0640.
API_BASE=${BRAND_SYNC_API_BASE:-http://127.0.0.1:8080}
SCHEDULER_TOKEN=${TOKEN}
CERTBOT_EMAIL=${CERTBOT_EMAIL:-${SSL_EMAIL:-}}
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
  info "Jalankan sekarang : systemctl start brand-sync"
  info "Lihat hasilnya    : journalctl -u brand-sync -n 50 --no-pager"
else
  systemctl disable --now brand-sync.timer >/dev/null 2>&1 || true
  skip "timer brand-sync (menunggu SCHEDULER_TOKEN)"
fi

info "Domain baru cukup diisi di panel owner; penyelaras yang memasang"
info "vhost dan sertifikatnya. DNS domain itu harus sudah mengarah ke server"
info "ini lebih dulu — certbot tidak bisa membuktikan kepemilikan tanpa itu."
