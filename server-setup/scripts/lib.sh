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
  check_env_vars "$dir"
}

# Peringatkan bila .env ketinggalan variabel yang sudah ada di .env.example.
#
# .env dibuat SEKALI lalu tidak pernah disentuh lagi — `git pull` memperbarui
# .env.example, tetapi variabel barunya tidak muncul di .env yang sudah ada.
# Skrip lalu membaca nilai kosong dan melewati pekerjaannya tanpa keluhan.
#
# Ini bukan kemungkinan teoretis: SITE_DOMAINS yang tidak ada membuat SELURUH
# tahap HTTPS dilewati, sementara `make server` tetap mencetak "Setup selesai"
# — dan situsnya baru ketahuan mati dari halaman error Cloudflare.
check_env_vars() {
  local dir="$1" missing=() name
  [ -f "$dir/.env.example" ] || return 0
  while read -r name; do
    grep -qE "^[[:space:]]*${name}=" "$dir/.env" || missing+=("$name")
  done < <(grep -oE '^[A-Z_][A-Z0-9_]*=' "$dir/.env.example" | tr -d '=')
  [ ${#missing[@]} -eq 0 ] && return 0
  warn ".env ketinggalan ${#missing[@]} variabel yang sudah ada di .env.example:"
  printf '       %s\n' "${missing[@]}"
  warn "  Bagian yang memakainya akan DILEWATI. Tambahkan ke $dir/.env"
}

# Ubah "a,b,c" menjadi baris-baris.
split_csv() {
  echo "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
}

# Cari nilai sebuah nama di daftar berformat "nama=nilai" dipisah koma.
#   kv_lookup exam_v2 "$SITE_DOMAINS"
#
# Nama tanpa entri menghasilkan string kosong dan status 0 — pemanggilnya
# memutuskan sendiri apakah itu masalah. Sebagian besar situs memang belum
# punya domain, dan itu keadaan yang sah, bukan kegagalan.
kv_lookup() {
  local target="$1" list="${2:-}" pair name value
  while read -r pair; do
    [ -n "$pair" ] || continue
    name="${pair%%=*}"
    value="${pair#*=}"
    if [ "$name" = "$target" ] && [ "$value" != "$pair" ]; then
      echo "$value"
      return 0
    fi
  done < <(split_csv "$list")
  return 0
}

# Socket PHP-FPM baru ADA setelah layanannya berjalan. Pencariannya memakai glob
# shell, bukan `grep -oP`: PCRE tidak selalu tersedia dan gagal pada sebagian
# locale, dengan pesan yang sama sekali tidak menjelaskan hubungannya dengan PHP.
find_php_sock() {
  local candidate
  for candidate in /run/php/php*-fpm.sock; do
    [ -S "$candidate" ] && { echo "$candidate"; return 0; }
  done
  return 1
}

# Cari pasangan sertifikat yang sudah terpasang untuk sebuah domain.
# Mencetak "berkas_cert berkas_kunci", atau mengembalikan 1 bila belum ada.
#
# Let's Encrypt diperiksa lebih dulu dan nginx menunjuk LANGSUNG ke sana.
# Berkasnya diperbarui di tempat oleh certbot; kalau disalin ke direktori lain,
# nginx akan tetap menyajikan salinan lama setelah perpanjangan — persis jenis
# kegagalan yang tidak menimbulkan error sampai sertifikatnya benar-benar mati.
site_cert_paths() {
  # Dipisah per baris dengan sengaja. `local a="$1" b="${a}"` TIDAK bekerja:
  # bash mengembangkan seluruh argumen `local` lebih dulu, sehingga ${a} masih
  # bernilai lama (atau kosong, dan `set -u` menghentikan skrip).
  local domain="$1"
  local le="/etc/letsencrypt/live/${domain}"
  local cf="/etc/ssl/cloudflare"
  if [ -s "$le/fullchain.pem" ] && [ -s "$le/privkey.pem" ]; then
    echo "$le/fullchain.pem $le/privkey.pem"
    return 0
  fi
  if [ -s "${cf}/${domain}.pem" ] && [ -s "${cf}/${domain}.key" ]; then
    echo "${cf}/${domain}.pem ${cf}/${domain}.key"
    return 0
  fi
  return 1
}

# Baris listen untuk blok 443, lengkap dengan cara menyalakan HTTP/2.
#
# `http2 on;` baru dikenal nginx 1.25.1. Ubuntu 24.04 masih membawa 1.24, dan di
# sana direktif itu bukan sekadar diabaikan — `nginx -t` GAGAL, sehingga seluruh
# konfigurasi (termasuk situs lain yang tadinya sehat) tidak jadi dimuat. Karena
# itu versinya diperiksa, bukan diasumsikan.
#
# Bentuk lama `listen 443 ssl http2` masih diterima versi baru, hanya memberi
# peringatan — jadi ia yang dipakai saat versinya tidak terbaca sama sekali.
listen_ssl_lines() {
  local ver
  ver="$(nginx -v 2>&1 | sed -n 's#.*nginx/\([0-9][0-9.]*\).*#\1#p')"

  if [ -n "$ver" ] && \
     [ "$(printf '1.25.1\n%s\n' "$ver" | sort -V | head -1)" = "1.25.1" ]; then
    echo "    listen 443 ssl;"
    echo "    listen [::]:443 ssl;"
    echo "    http2 on;"
  else
    echo "    listen 443 ssl http2;"
    echo "    listen [::]:443 ssl http2;"
  fi
}

# Situs yang dilayani container (Next.js 3000, API Go 8080), bukan berkas di
# /var/www — server block-nya meneruskan ke 127.0.0.1, bukan menyajikan berkas.
#
# Ini TIDAK berarti direktorinya tidak berguna: di situlah docker-compose.yml
# berada, jadi situs container yang punya entri SITE_REPOS tetap diklon seperti
# yang lain. Yang dilewati hanya pembuatan direktori kosong berisi halaman
# sambutan bagi yang tidak punya repo.
#
# Daftarnya eksplisit lewat PROXY_SITES di .env. Menebak dari isi direktori akan
# salah tepat pada saat paling merepotkan, yaitu ketika klon git belum sempat
# berjalan dan direktorinya masih kosong.
is_proxy_site() {
  local target="$1" name
  while read -r name; do
    [ "$name" = "$target" ] && return 0
  done < <(split_csv "${PROXY_SITES:-exam_v2}")
  return 1
}

# Isi server block sebuah situs — bagian yang sama untuk HTTP maupun HTTPS.
site_body() {
  local site="$1" php_sock="$2"

  # Unggahan jawaban bergambar dan impor soal lewat di sini.
  echo "    client_max_body_size 32M;"
  echo ""

  if is_proxy_site "$site"; then
    cat <<CONF
    # ── API Go ────────────────────────────────────────────────────────────
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        # \$remote_addr, BUKAN \$proxy_add_x_forwarded_for.
        #
        # Yang kedua menyambungkan header X-Forwarded-For yang dikirim
        # pengunjung dengan alamat aslinya. Aplikasi membaca entri pertama —
        # yaitu bagian yang dikarang pengunjung. Cukup mengganti isinya tiap
        # percobaan, dan pembatas login 3-kali-salah hilang sama sekali.
        #
        # Di belakang Cloudflare, 25-cloudflare-realip.sh yang memulihkan
        # \$remote_addr dari CF-Connecting-IP.
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Pengumpulan jawaban dan koreksi otomatis bisa memakan waktu. Timeout
        # pendek di sini berarti jawaban siswa ditolak di detik-detik terakhir
        # ujian — kegagalan yang paling mahal dari semuanya.
        proxy_read_timeout      300s;
        proxy_send_timeout      300s;
        proxy_request_buffering off;
    }

    # ── Next.js ───────────────────────────────────────────────────────────
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        "upgrade";
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }
CONF
  else
    cat <<CONF
    root  /var/www/${site};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${php_sock};
    }

    location ~ /\.(?!well-known) { deny all; }
CONF
  fi
}

# Tulis server block sebuah situs ke /etc/nginx/sites-available/<situs>.
#
#   write_site_conf <situs> <domain> <socket_php> [berkas_cert] [berkas_kunci]
#
# Bila cert & kunci diisi, blok 443 ikut ditulis dan port 80 hanya mengalihkan.
# Berkas yang isinya sudah sama persis dilewati, sehingga menjalankan ulang
# tidak menghasilkan cadangan palsu maupun reload yang tidak perlu.
write_site_conf() {
  local site="$1" domain="$2" php_sock="$3" cert="${4:-}" key="${5:-}"
  # NGINX_SITES_DIR hanya untuk menguji keluaran fungsi ini tanpa root.
  local avail="${NGINX_SITES_DIR:-/etc/nginx/sites-available}/${site}"
  local tmp
  tmp="$(mktemp)"

  {
    echo "# ${site} — dibuat oleh server-setup (sudo make nginx / make ssl)."
    echo "# Suntingan manual akan tertimpa saat skrip dijalankan ulang;"
    echo "# salinan berkas lama disimpan sebagai ${avail}.orig."
    echo ""

    if [ -n "$cert" ] && [ -n "$key" ]; then
      cat <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    # Cloudflare tetap boleh menyambung lewat 80; sisanya diarahkan ke HTTPS.
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
CONF
      listen_ssl_lines
      cat <<CONF
    server_name ${domain};

    ssl_certificate     ${cert};
    ssl_certificate_key ${key};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

CONF
      site_body "$site" "$php_sock"
      echo "}"
    else
      cat <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

CONF
      site_body "$site" "$php_sock"
      echo "}"
    fi
  } > "$tmp"

  if [ -f "$avail" ] && cmp -s "$tmp" "$avail"; then
    rm -f "$tmp"
    skip "server block $site"
    return 0
  fi

  backup_once "$avail"
  mv "$tmp" "$avail"
  chmod 644 "$avail"
  ok "server block $site → ${domain}${cert:+ (HTTPS)}"
}

# Nama database yang aman dipakai MySQL.
sanitize_db_name() {
  echo "$1" | tr '[:upper:]-' '[:lower:]_' | sed 's/[^a-z0-9_]//g'
}
