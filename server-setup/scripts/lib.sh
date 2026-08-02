#!/usr/bin/env bash
# Fungsi bersama untuk seluruh skrip setup.
#
# Prinsip yang dipegang semua skrip di sini:
#   1. IDEMPOTEN — dijalankan berulang kali harus aman. Yang sudah ada dilewati.
#   2. TIDAK MERUSAK — tidak pernah menimpa konfigurasi yang sudah disunting
#      manusia tanpa memberi tahu; berkas lama dicadangkan lebih dulu.
#   3. BERHENTI SAAT RAGU — lebih baik gagal terang-terangan daripada
#      melanjutkan dan meninggalkan server setengah jadi.

set -euo pipefail

C_RESET='\033[0m'; C_INFO='\033[0;36m'; C_OK='\033[0;32m'
C_WARN='\033[0;33m'; C_ERR='\033[0;31m'; C_SKIP='\033[0;90m'

log()  { printf "${C_INFO}==>${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_OK}  ok${C_RESET} %s\n" "$*"; }
skip() { printf "${C_SKIP}  -- %s (sudah ada, dilewati)${C_RESET}\n" "$*"; }
warn() { printf "${C_WARN}  !! %s${C_RESET}\n" "$*"; }
die()  { printf "${C_ERR}GAGAL:${C_RESET} %s\n" "$*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "jalankan sebagai root (sudo make server)"
}

require_apt() {
  command -v apt-get >/dev/null 2>&1 \
    || die "skrip ini untuk Debian/Ubuntu (apt tidak ditemukan)"
}

# Pasang paket hanya bila belum terpasang.
apt_install() {
  local missing=()
  for pkg in "$@"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    skip "paket: $*"
    return
  fi
  log "memasang: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${missing[@]}" >/dev/null
  ok "terpasang: ${missing[*]}"
}

# Cadangkan berkas sebelum ditimpa, sekali saja per berkas.
backup_once() {
  local file="$1"
  [ -f "$file" ] || return 0
  [ -f "${file}.orig" ] && return 0
  cp -a "$file" "${file}.orig"
  ok "cadangan: ${file}.orig"
}

# Muat .env; buat dari contoh bila belum ada.
load_env() {
  local dir="$1"
  if [ ! -f "$dir/.env" ]; then
    cp "$dir/.env.example" "$dir/.env"
    chmod 600 "$dir/.env"
    warn ".env dibuat dari .env.example — GANTI password bawaannya."
  fi
  set -a
  # shellcheck disable=SC1090
  . "$dir/.env"
  set +a
}

# Ubah "a,b,c" menjadi baris-baris.
split_csv() {
  echo "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
}

# Nama database yang aman dipakai MySQL.
sanitize_db_name() {
  echo "$1" | tr '[:upper:]-' '[:lower:]_' | sed 's/[^a-z0-9_]//g'
}
