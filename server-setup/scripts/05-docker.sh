#!/usr/bin/env bash
# Pasang Docker Engine + plugin Compose.
#
# DIJALANKAN SEBELUM MYSQL, dan urutannya penting.
#
# Skrip MySQL menentukan alamat mana yang didengarkan berdasarkan ada-tidaknya
# jembatan Docker (docker0). Bila Docker dipasang BELAKANGAN, MySQL sudah
# terlanjur terikat ke loopback saja — dan container aplikasi tidak akan pernah
# bisa menyambung, dengan galat "connection refused" yang tidak menyinggung
# urutan pemasangan sama sekali.
#
# Memakai repositori resmi Docker, bukan `curl … | sh`. Skrip sekali-jalan itu
# tidak memberi jalur pembaruan: paketnya tidak ikut `apt upgrade`, sehingga
# perbaikan keamanan Docker tidak pernah sampai ke server ini.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_apt

log "Docker"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  skip "Docker + plugin Compose sudah terpasang"
else
  apt_install ca-certificates curl gnupg

  KEYRING=/etc/apt/keyrings/docker.gpg
  if [ ! -f "$KEYRING" ]; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o "$KEYRING" || die "gagal mengambil kunci GPG Docker"
    chmod a+r "$KEYRING"
    ok "kunci repositori Docker dipasang"
  else
    skip "kunci repositori Docker"
  fi

  SOURCE_LIST=/etc/apt/sources.list.d/docker.list
  ARCH="$(dpkg --print-architecture)"
  CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-jammy}")"
  DESIRED="deb [arch=${ARCH} signed-by=${KEYRING}] https://download.docker.com/linux/ubuntu ${CODENAME} stable"
  if [ "$(cat "$SOURCE_LIST" 2>/dev/null || true)" = "$DESIRED" ]; then
    skip "repositori Docker"
  else
    echo "$DESIRED" > "$SOURCE_LIST"
    ok "repositori Docker (${CODENAME})"
  fi

  log "memasang paket Docker"
  apt-get update -qq >/dev/null 2>&1 || warn "apt-get update gagal — lanjut dengan indeks yang ada"
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker >/dev/null 2>&1 || true
systemctl is-active --quiet docker || die "Docker tidak berjalan — periksa: journalctl -u docker -n 50"

# Pengguna yang memanggil sudo dimasukkan ke grup docker agar tidak perlu sudo
# untuk `make up`. Perubahan grup baru berlaku setelah login ulang.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  if id -nG "$SUDO_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    skip "$SUDO_USER sudah di grup docker"
  else
    usermod -aG docker "$SUDO_USER"
    ok "$SUDO_USER ditambahkan ke grup docker"
    warn "logout & login ulang agar keanggotaan grup itu berlaku"
  fi
fi

# Jembatan docker0 baru muncul setelah daemon berjalan. MySQL membacanya untuk
# menentukan alamat yang didengarkan, jadi keberadaannya dipastikan di sini —
# bukan diserahkan pada nasib urutan.
for _ in $(seq 1 10); do
  if ip -4 -o addr show docker0 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ip -4 -o addr show docker0 >/dev/null 2>&1; then
  ok "jembatan docker0 siap ($(ip -4 -o addr show docker0 | awk '{print $4}' | cut -d/ -f1 || true))"
else
  warn "jembatan docker0 belum muncul — MySQL akan mendengar di loopback saja."
  warn "  Jalankan ulang 'sudo make mysql' setelah docker0 ada."
fi

log "Docker selesai ($(docker --version 2>/dev/null || echo 'versi tidak terbaca'))"
