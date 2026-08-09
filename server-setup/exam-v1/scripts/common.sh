#!/usr/bin/env bash
# Konfigurasi & fungsi bersama untuk deploy Exam v1.
# Di-source oleh skrip lain di direktori ini; tidak untuk dijalankan sendiri.

EXAM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAM_APP_DIR="$(dirname "$EXAM_SCRIPT_DIR")"
SETUP_DIR="$(dirname "$EXAM_APP_DIR")"

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
APP_SITE="${SITE:-exam_v1}"
APP_DOMAIN="${DOMAIN:-ujian.kelasprivat.id}"
APP_REPO="${REPO:-https://github.com/RezaGunadi/exam_kelas_privat.git}"
APP_DB="${DB_NAME:-exam_admin_system}"

load_env "$SETUP_DIR"

APP_ROOT="/var/www/${APP_SITE}"
APP_WEBROOT="${APP_ROOT}/public"
APP_ENV_FILE="${APP_ROOT}/.env"

# Situs ini TIDAK boleh ikut dikelola setup induk.
#
# 20-nginx.sh menulis ulang server block setiap situs yang terdaftar di SITES,
# dan 35-ssl.sh melakukan hal yang sama untuk yang terdaftar di SITE_DOMAINS.
# Keduanya memakai write_site_conf, yang menyetel `root /var/www/<situs>` —
# satu direktori di atas public/. Untuk Laravel itu berarti index.php tidak
# ditemukan DAN seluruh kode sumber berpindah ke dalam jangkauan web.
#
# Kegagalannya tidak terjadi saat deploy, melainkan pada `sudo make nginx`
# berikutnya — mungkin berminggu-minggu kemudian, oleh orang yang sedang
# mengurus situs lain dan tidak tahu ia baru saja mematikan yang ini.
assert_not_managed_by_setup() {
  local name
  while read -r name; do
    if [ "$name" = "$APP_SITE" ]; then
      warn "'$APP_SITE' terdaftar di SITES pada $SETUP_DIR/.env"
      warn "  'sudo make nginx' di direktori induk akan MENIMPA server block"
      warn "  Laravel di sini dengan versi yang root-nya bukan public/."
      die "hapus '$APP_SITE' dari SITES lebih dulu"
    fi
  done < <(split_csv "${SITES:-}")

  while read -r name; do
    if [ "${name%%=*}" = "$APP_SITE" ] || [ "${name#*=}" = "$APP_DOMAIN" ]; then
      warn "'$APP_SITE'/'$APP_DOMAIN' terdaftar di SITE_DOMAINS pada $SETUP_DIR/.env"
      warn "  'sudo make ssl' di direktori induk akan MENIMPA server block ini."
      die "hapus entri itu dari SITE_DOMAINS lebih dulu"
    fi
  done < <(split_csv "${SITE_DOMAINS:-}")
}

# Jalankan artisan sebagai www-data, bukan root.
#
# artisan menulis ke storage/ dan bootstrap/cache. Dijalankan sebagai root, log
# dan berkas cache yang dibuatnya jadi milik root — lalu PHP-FPM (yang berjalan
# sebagai www-data) tidak bisa menimpanya, dan situsnya mati dengan "failed to
# open stream: Permission denied" pada permintaan berikutnya. Berjam-jam setelah
# deploy yang terlihat berhasil.
#
# runuser, bukan sudo: sudo belum tentu terpasang di Debian minimal, sedangkan
# runuser ada di util-linux yang selalu ada.
artisan() {
  ( cd "$APP_ROOT" && runuser -u www-data -- php artisan "$@" )
}

# Setel satu pasangan KEY=value di berkas .env.
#
#   set_env_kv <berkas> <KEY> <nilai>
#
# Nilainya lewat ENVIRON milik awk, BUKAN disisipkan ke pola sed. Password dan
# kunci API rutin memuat karakter yang berarti khusus bagi sed (& | \ /), dan
# hasilnya bukan error melainkan nilai yang tersimpan salah — kegagalan yang
# baru terlihat saat layanan yang memakainya menolak kredensial.
#
# Baris yang dikomentari ikut dihitung sebagai definisi, dan definisi ganda
# DIRINGKAS jadi satu. .env.example repo ini memuat DB_DATABASE dua kali (satu
# dikomentari, satu tidak); membiarkan keduanya berarti yang menang ditentukan
# oleh urutan pembacaan dotenv, bukan oleh apa yang tertulis di sini.
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
