#!/usr/bin/env bash
# Pemeriksaan awal sebelum apa pun dipasang.
#
# Tujuannya menemukan bentrokan SEBELUM setengah server terkonfigurasi —
# memperbaiki keadaan setengah jadi jauh lebih repot daripada berhenti di awal.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
load_env "$(dirname "$SCRIPT_DIR")"

require_root
require_apt

log "pemeriksaan awal"

# ── Sistem operasi ─────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
  . /etc/os-release
  ok "sistem: ${PRETTY_NAME:-tidak diketahui}"
fi

# ── Bentrokan port ─────────────────────────────────────────────────────────
# nginx host memakai 80/443. Bila ada proses lain memegangnya — termasuk
# container yang mengekspos port publik — nginx akan gagal start.
check_port() {
  local port="$1" label="$2"
  local holder
  holder="$(ss -lntp 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {print $NF}' | head -1)"
  if [ -n "$holder" ]; then
    if echo "$holder" | grep -q 'nginx'; then
      ok "port ${port} dipegang nginx (${label})"
    else
      warn "port ${port} sudah dipakai: ${holder}"
      warn "  ${label} akan gagal. Hentikan proses itu, atau bila itu container,"
      warn "  ubah agar hanya mendengar di 127.0.0.1 — nginx host yang jadi pintu depan."
    fi
  else
    ok "port ${port} bebas (${label})"
  fi
}

apt_install iproute2 >/dev/null 2>&1 || true
check_port 80  "nginx"
check_port 443 "nginx SSL"
check_port 3306 "MySQL"

# ── Docker ─────────────────────────────────────────────────────────────────
if command -v docker >/dev/null 2>&1; then
  ok "docker terpasang"
  # Container yang mengekspos 0.0.0.0:80 akan bentrok dengan nginx host.
  conflicting="$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null \
    | grep -E '0\.0\.0\.0:(80|443|3306)->' || true)"
  if [ -n "$conflicting" ]; then
    warn "container berikut membuka port yang dibutuhkan host:"
    echo "$conflicting" | sed 's/^/      /'
    warn "  ubah port-nya menjadi 127.0.0.1:<port> agar tidak berebut"
  fi
else
  ok "docker belum terpasang (tidak masalah untuk setup ini)"
fi

# ── Ruang disk ─────────────────────────────────────────────────────────────
avail_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
if [ "${avail_mb:-0}" -lt 2048 ]; then
  warn "sisa ruang / hanya ${avail_mb}MB — pemasangan paket bisa gagal"
else
  ok "sisa ruang /: ${avail_mb}MB"
fi

# ── Isi .env ───────────────────────────────────────────────────────────────
[ -n "${DB_USER:-}" ]   || die "DB_USER kosong di .env"
[ -n "${SITES:-}" ]     || die "SITES kosong di .env"
[ -n "${DATABASES:-}" ] || die "DATABASES kosong di .env"

if [ "${DB_PASSWORD:-}" = '@Reza1234' ]; then
  warn "DB_PASSWORD masih memakai nilai bawaan — ganti sebelum server dipakai produksi"
fi

log "pemeriksaan awal selesai"
apt-get update -qq >/dev/null 2>&1 || warn "apt-get update gagal — lanjut dengan indeks paket yang ada"
