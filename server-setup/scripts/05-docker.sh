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

# ── Kebijakan daemon: port container tidak pernah terbuka ke internet ──────
#
# `ports: "8000:8000"` di docker-compose.yml BUKAN berarti localhost. Docker
# mengartikannya sebagai 0.0.0.0:8000 — aplikasi terjangkau langsung dari
# internet, tanpa HTTPS dan tanpa melewati nginx.
#
# Dan ufw TIDAK menghalanginya. Docker menulis aturan DNAT-nya sendiri di
# rantai nftables/iptables yang diproses SEBELUM aturan ufw, sehingga
# `ufw deny 8000` tidak berpengaruh sementara `ufw status` tetap tampak
# meyakinkan. Ini jenis kesalahan yang tidak pernah muncul di log mana pun.
#
# `"ip": "127.0.0.1"` mengubah alamat BAWAAN untuk port yang dipublikasikan
# tanpa menyebut IP. Itu menjadikan arsitektur yang sudah ditulis di README —
# nginx host satu-satunya pintu depan — berlaku secara bawaan, bukan
# bergantung pada setiap compose file mengingatnya sendiri. Container yang
# memang perlu terbuka tetap bisa menyebut "0.0.0.0:port:port" dengan sengaja.
#
# Sekalian rotasi log: driver json-file bawaan tumbuh TANPA BATAS. Container
# yang menulis beberapa baris per detik memenuhi partisi dalam hitungan bulan,
# dan partisi penuh mematikan MySQL beserta seluruh situs di server ini.
DAEMON_JSON=/etc/docker/daemon.json
DOCKER_NEEDS_RESTART=0

if [ ! -f "$DAEMON_JSON" ]; then
  mkdir -p /etc/docker
  cat > "$DAEMON_JSON" <<'JSON'
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  }
}
JSON
  chmod 644 "$DAEMON_JSON"
  ok "daemon.json (port bawaan ke 127.0.0.1, log dirotasi)"
  DOCKER_NEEDS_RESTART=1
elif grep -q '"ip"[[:space:]]*:' "$DAEMON_JSON"; then
  skip "daemon.json (\"ip\" sudah disetel)"
else
  # TIDAK ditimpa. Berkas ini bisa memuat pengaturan yang disunting orang, dan
  # menggabungkan JSON dengan aman butuh jq yang belum tentu ada. Yang bisa
  # dilakukan skrip adalah menyebutkan persis apa yang kurang.
  warn "$DAEMON_JSON sudah ada tetapi tidak menyetel \"ip\"."
  warn "  Port container akan dipublikasikan ke 0.0.0.0 — terbuka ke internet,"
  warn "  dan ufw tidak menghalanginya. Tambahkan sendiri ke berkas itu:"
  warn '    "ip": "127.0.0.1",'
  warn '    "log-driver": "json-file",'
  warn '    "log-opts": { "max-size": "10m", "max-file": "5" }'
  warn "  lalu: sudo systemctl restart docker"
fi

systemctl enable --now docker >/dev/null 2>&1 || true

# Restart HANYA bila daemon.json baru saja ditulis. Daemon membaca berkas itu
# sekali saat start, jadi tanpa restart pengaturannya tidak berlaku sama sekali;
# tetapi restart yang tidak perlu ikut menjatuhkan container yang sedang
# melayani, dan itu harga yang tidak pantas dibayar tiap `make server`.
if [ "$DOCKER_NEEDS_RESTART" -eq 1 ]; then
  systemctl restart docker >/dev/null 2>&1 || true
fi

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

# ── Jaringan proyek dibuat DI SINI, sebelum MySQL menentukan bind-address ──
#
# Urutannya yang penting, bukan sekadar keberadaannya.
#
# Tiap proyek docker-compose punya jembatan sendiri dengan subnet berbeda dari
# docker0, dan `extra_hosts: host-gateway` di container menunjuk gateway
# jembatan ITU. Bila MySQL hanya mendengar di docker0, container compose
# menyambung ke alamat yang tidak didengarkan siapa pun — sambungannya ditolak
# sebelum urusan pengguna atau password dimulai. Itulah "API tidak bisa konek
# padahal .env sudah benar".
#
# MySQL menolak START bila disuruh mendengar di alamat yang belum ada, jadi
# jembatannya harus lahir LEBIH DULU. Membuat jaringannya di sini berarti
# 10-mysql.sh sudah melihatnya, dan `make up` nanti memakai ulang jaringan yang
# sama (namanya cocok dengan yang ditulis di docker-compose.yml proyek).
#
# Idempoten: jaringan yang sudah ada dilewati. Subnet dipatok di dalam 172.x
# supaya tetap tercakup grant '172.%' di MySQL.
buat_jaringan() {
  nama="$1"
  subnet="$2"
  gateway="$3"
  if docker network inspect "$nama" >/dev/null 2>&1; then
    skip "jaringan $nama"
    return 0
  fi
  if docker network create --driver bridge       --subnet "$subnet" --gateway "$gateway" "$nama" >/dev/null 2>&1; then
    ok "jaringan $nama dibuat ($subnet)"
  else
    # Subnet bentrok dengan jaringan lain, atau Docker menolak. Bukan alasan
    # menghentikan pemasangan: compose tetap bisa membuat jaringannya sendiri,
    # hanya saja MySQL perlu 'sudo make mysql' sekali lagi sesudahnya.
    warn "jaringan $nama gagal dibuat (subnet $subnet bentrok?)"
    warn "  Jalankan 'sudo make mysql' SETELAH 'make up' agar MySQL mendengar"
    warn "  di gateway jaringan yang akhirnya dipakai compose."
  fi
}

buat_jaringan exam-v2 172.28.0.0/24 172.28.0.1

log "Docker selesai ($(docker --version 2>/dev/null || echo 'versi tidak terbaca'))"
