#!/usr/bin/env bash
# Konfigurasi & fungsi bersama untuk deploy backend Kelas Junior.
# Di-source oleh skrip lain di direktori ini; tidak untuk dijalankan sendiri.

JUNIOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JUNIOR_APP_DIR="$(dirname "$JUNIOR_SCRIPT_DIR")"
SETUP_DIR="$(dirname "$JUNIOR_APP_DIR")"

[ -f "$SETUP_DIR/scripts/lib.sh" ] || {
  echo "GAGAL: $SETUP_DIR/scripts/lib.sh tidak ditemukan." >&2
  echo "       Direktori ini harus berada di dalam repo server-setup." >&2
  exit 1
}
# shellcheck source=../../scripts/lib.sh
. "$SETUP_DIR/scripts/lib.sh"

# Nilai dari Makefile dibaca SEBELUM load_env, dengan sengaja.
#
# load_env memuat .env memakai `set -a`, jadi variabel bernama sama di berkas itu
# akan menimpa apa pun yang dikirim Makefile — dan `sudo make deploy DOMAIN=...`
# diam-diam tidak berpengaruh, tanpa satu pun pesan yang menyinggungnya.
APP_SITE="${SITE:-junior_app}"
APP_DOMAIN="${DOMAIN:-junior-app.ragh.co.id}"
APP_REPO="${REPO:-git@github.com:RezaGunadi/kelas_junior.git}"
APP_DB="${DB_NAME:-kidlearn}"
APP_PORT="${PORT:-8000}"
# Backend FastAPI ada di SUBDIREKTORI repo, bukan di akarnya. Repo yang sama
# juga memuat app Flutter (game/), yang tidak pernah di-deploy ke server.
APP_SUBDIR="${SUBDIR:-game_backend}"

load_env "$SETUP_DIR"

APP_ROOT="/var/www/${APP_SITE}"
BACKEND_DIR="${APP_ROOT}/${APP_SUBDIR}"
APP_ENV_FILE="${BACKEND_DIR}/.env"
# Di LUAR direktori build (`build: .` dengan konteks game_backend/), supaya
# tidak pernah ikut tersalin ke image — meski .dockerignore sudah menutupnya.
VENV_DIR="${APP_ROOT}/.venv"

# ── nginx & HTTPS diurus setup induk, bukan di sini ─────────────────────────
#
# Kebalikan dari exam-v1/: aplikasi ini TIDAK menyajikan berkas, jadi server
# block hasil write_site_conf memang bentuk yang benar — nginx meneruskan
# seluruh permintaan ke 127.0.0.1:${APP_PORT}. Yang harus ada di .env induk:
#
#   SITES        memuat junior_app       (agar server block-nya dibuat)
#   PROXY_SITES  memuat junior_app       (agar diproksikan, bukan disajikan)
#   PROXY_PORTS  junior_app=8000         (agar upstream-nya benar)
#   SITE_DOMAINS junior_app=<domain>     (agar server_name & HTTPS terisi)
#
# Yang paling berbahaya bukan entri yang hilang, melainkan SETENGAH terdaftar:
# ada di SITES tetapi tidak di PROXY_SITES berarti nginx MENYAJIKAN
# /var/www/junior_app apa adanya — termasuk game_backend/.env yang memuat
# password MySQL, JWT_SECRET, dan kredensial R2. Karena itu keadaan itu
# menghentikan skrip, bukan sekadar diperingatkan.
assert_setup_env() {
  local name found_sites=0 found_proxy=0 port domain

  while read -r name; do
    [ "$name" = "$APP_SITE" ] && found_sites=1
  done < <(split_csv "${SITES:-}")

  while read -r name; do
    [ "$name" = "$APP_SITE" ] && found_proxy=1
  done < <(split_csv "${PROXY_SITES:-}")

  if [ "$found_sites" -eq 1 ] && [ "$found_proxy" -eq 0 ]; then
    warn "'$APP_SITE' ada di SITES tetapi TIDAK di PROXY_SITES pada $SETUP_DIR/.env"
    warn "  nginx akan MENYAJIKAN /var/www/${APP_SITE} sebagai berkas biasa —"
    warn "  termasuk ${APP_SUBDIR}/.env berisi password MySQL, JWT_SECRET, dan R2."
    die "tambahkan '$APP_SITE' ke PROXY_SITES lebih dulu, lalu: cd $SETUP_DIR && sudo make nginx"
  fi

  if [ "$found_sites" -eq 0 ]; then
    warn "'$APP_SITE' belum terdaftar di SITES pada $SETUP_DIR/.env"
    warn "  Aplikasinya tetap berjalan di 127.0.0.1:${APP_PORT}, tetapi TIDAK"
    warn "  bisa dibuka dari internet karena nginx belum punya server block-nya."
    warn "  Tambahkan di $SETUP_DIR/.env:"
    warn "    SITES=...,${APP_SITE}"
    warn "    PROXY_SITES=...,${APP_SITE}"
    warn "    PROXY_PORTS=${APP_SITE}=${APP_PORT}"
    warn "    SITE_DOMAINS=...,${APP_SITE}=${APP_DOMAIN}"
    warn "  lalu: cd $SETUP_DIR && sudo make nginx && sudo make ssl"
    return 0
  fi

  port="$(kv_lookup "$APP_SITE" "${PROXY_PORTS:-}")"
  if [ -z "$port" ]; then
    warn "'$APP_SITE' belum punya entri di PROXY_PORTS pada $SETUP_DIR/.env"
    warn "  Tanpa itu nginx memakai bentuk lama Exam v2: /api/ diteruskan ke 8080"
    warn "  (tidak ada isinya) dan sisanya ke 3000. Halaman depan tampak normal,"
    warn "  dan yang menjawab 502 hanya alamat di bawah /api/."
    warn "  Tambahkan: PROXY_PORTS=${APP_SITE}=${APP_PORT} — lalu sudo make nginx"
  elif [ "$port" != "$APP_PORT" ]; then
    warn "PROXY_PORTS menunjuk ${APP_SITE}=${port}, sedangkan container mendengar di ${APP_PORT}"
    warn "  Samakan salah satunya, atau nginx akan menjawab 502."
  fi

  domain="$(kv_lookup "$APP_SITE" "${SITE_DOMAINS:-}")"
  if [ -z "$domain" ]; then
    warn "'$APP_SITE' belum punya entri di SITE_DOMAINS — server_name jatuh ke"
    warn "  ${APP_SITE}.local dan HTTPS dilewati. Tambahkan:"
    warn "    SITE_DOMAINS=...,${APP_SITE}=${APP_DOMAIN}"
  elif [ "${domain%%|*}" != "$APP_DOMAIN" ]; then
    warn "SITE_DOMAINS menunjuk ${APP_SITE}=${domain}, Makefile di sini memakai ${APP_DOMAIN}"
  fi
}

# `docker compose` (plugin v2) atau `docker-compose` (skrip v1 lama).
#
# Dipilih saat dipanggil, bukan diasumsikan: setup induk memasang plugin v2,
# tetapi server yang Dockernya dipasang lebih dulu dengan cara lain bisa hanya
# punya yang v1 — dan "docker: 'compose' is not a docker command" tidak
# menyinggung sama sekali bahwa yang kurang adalah satu paket apt.
compose() {
  ( cd "$BACKEND_DIR" || exit 1
    if docker compose version >/dev/null 2>&1; then
      docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
      docker-compose "$@"
    else
      echo "GAGAL: plugin Docker Compose tidak ada." >&2
      echo "       Pasang lebih dulu: cd $SETUP_DIR && sudo make docker" >&2
      exit 1
    fi
  )
}

require_docker() {
  command -v docker >/dev/null 2>&1 \
    || die "Docker belum terpasang — jalankan dulu: cd $SETUP_DIR && sudo make docker"
  docker info >/dev/null 2>&1 \
    || die "daemon Docker tidak berjalan — periksa: systemctl status docker"
}

# Setel satu pasangan KEY=value di berkas .env.
#
# Nilainya lewat ENVIRON milik awk, BUKAN disisipkan ke pola sed. DATABASE_URL
# memuat "/" dan password rutin memuat karakter yang berarti khusus bagi sed
# (& | \ /); hasilnya bukan error melainkan nilai yang tersimpan salah —
# kegagalan yang baru terlihat saat layanan menolak kredensial.
set_env_kv() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  KEY="$key" VALUE="$value" awk '
    BEGIN { key = ENVIRON["KEY"]; value = ENVIRON["VALUE"]; done = 0 }
    {
      line = $0
      sub(/^[ \t]*#?[ \t]*/, "", line)
      if (index(line, key "=") == 1) {
        if (!done) { print key "=" value; done = 1 }
        next
      }
      print
    }
    END { if (!done) print key "=" value }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# Baca satu nilai dari berkas .env aplikasi.
get_env_kv() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  sed -n "s/^[[:space:]]*${key}=//p" "$file" | head -1 | sed 's/^"//; s/"$//'
}
