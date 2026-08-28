#!/usr/bin/env bash
# Server block nginx untuk cuandariponsel (Laravel).
#
# Ditulis di sini, bukan lewat write_site_conf milik setup induk: fungsi itu
# menyetel `root /var/www/<situs>` kecuali public/index.php sudah ada saat
# server block ditulis — dan pada `make nginx` yang dijalankan sebelum klon,
# ia belum ada. Selisih satu direktori, tetapi akibatnya seluruh kode sumber,
# termasuk .env, berada di dalam jangkauan web.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
assert_not_managed_by_setup

command -v nginx >/dev/null 2>&1 \
  || die "nginx belum terpasang — jalankan dulu: cd $SETUP_DIR && sudo make nginx"

[ -d "$APP_WEBROOT" ] \
  || die "$APP_WEBROOT tidak ada — jalankan dulu: sudo make app"

PHP_SOCK="$(find_php_sock || true)"
[ -n "$PHP_SOCK" ] || die "socket PHP-FPM tidak ditemukan — jalankan: cd $SETUP_DIR && sudo make nginx"
ok "PHP-FPM ($PHP_SOCK)"

# Manifest Vite tidak ikut ke git. Tanpa build, setiap halaman melemparkan
# "Vite manifest not found" — bukan halaman kosong, melainkan galat 500 penuh.
[ -f "$APP_WEBROOT/build/manifest.json" ] \
  || warn "public/build/manifest.json belum ada — jalankan: sudo make assets"

AVAIL="/etc/nginx/sites-available/${APP_SITE}"
ENABLED="/etc/nginx/sites-enabled/${APP_SITE}"

# Sertifikat dicari lewat site_cert_paths (lib.sh) supaya blok 443 ikut ditulis
# bila `make ssl` sudah pernah berjalan. Tanpa ini, menjalankan ulang `make site`
# setelah HTTPS aktif akan diam-diam menurunkan situsnya kembali ke port 80.
CERT=""; KEY=""
if paths="$(site_cert_paths "$APP_DOMAIN")"; then
  read -r CERT KEY <<< "$paths"
  ok "sertifikat ditemukan untuk $APP_DOMAIN"
else
  warn "belum ada sertifikat untuk $APP_DOMAIN — situs dilayani lewat HTTP dulu"
fi

# ── Isi server block ───────────────────────────────────────────────────────
laravel_body() {
  cat <<CONF
    root  ${APP_WEBROOT};
    index index.php;

    # Unggahan clip portofolio divalidasi sampai 200MB oleh aplikasi
    # (PortfolioController: max:204800). Angka di sini harus di ATAS itu, dan
    # di atas post_max_size PHP juga — nginx memeriksa lebih dulu, dan
    # penolakannya berupa 413 yang tidak pernah sampai ke Laravel.
    client_max_body_size 220M;

    # Badan permintaan sebesar itu tidak muat di memori. Tanpa baris ini nginx
    # menulisnya ke berkas sementara lebih dulu, menggandakan I/O tiap unggahan.
    client_body_buffer_size 1m;
    client_body_timeout 300s;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    # Aset hasil build Vite diberi nama ber-hash, jadi isinya tidak pernah
    # berubah untuk nama yang sama. Aman di-cache selamanya, dan tanpa ini tiap
    # kunjungan menanyakan ulang berkas yang dijamin identik.
    location /build/ {
        access_log off;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};

        # Unggahan video, transcode, dan pembuatan laporan bisa memakan waktu.
        # Timeout bawaan 60 detik memutusnya di tengah jalan, dan yang terlihat
        # pengunjung hanya 504 tanpa keterangan.
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
    }

    # .env, .git, dan berkas titik lain tidak pernah disajikan. Ini lapisan
    # kedua: root sudah menunjuk ke public/, jadi seharusnya tidak terjangkau —
    # "seharusnya" bukan alasan untuk membiarkannya terbuka.
    location ~ /\.(?!well-known) { deny all; }
CONF
}

TMP="$(mktemp)"
{
  echo "# ${APP_SITE} — dibuat oleh server-setup/repost-app (sudo make site / make ssl)."
  echo "# Suntingan manual akan tertimpa saat skrip dijalankan ulang;"
  echo "# salinan berkas lama disimpan sebagai ${AVAIL}.orig."
  echo ""

  if [ -n "$CERT" ] && [ -n "$KEY" ]; then
    cat <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${APP_DOMAIN};

    # Jalur verifikasi certbot tetap dilayani lewat 80; sisanya dialihkan.
    location /.well-known/acme-challenge/ {
        root ${APP_WEBROOT};
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
CONF
    listen_ssl_lines
    cat <<CONF
    server_name ${APP_DOMAIN};

    ssl_certificate     ${CERT};
    ssl_certificate_key ${KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

CONF
    laravel_body
    echo "}"
  else
    cat <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${APP_DOMAIN};

CONF
    laravel_body
    echo "}"
  fi
} > "$TMP"

if [ -f "$AVAIL" ] && cmp -s "$TMP" "$AVAIL"; then
  rm -f "$TMP"
  skip "server block $APP_SITE"
else
  backup_once "$AVAIL"
  mv "$TMP" "$AVAIL"
  chmod 644 "$AVAIL"
  ok "server block $APP_SITE → ${APP_DOMAIN}${CERT:+ (HTTPS)}"
fi

if [ -L "$ENABLED" ]; then
  skip "symlink $APP_SITE"
else
  [ -e "$ENABLED" ] && die "$ENABLED sudah ada tetapi bukan symlink — periksa sendiri"
  ln -s "$AVAIL" "$ENABLED"
  ok "symlink $APP_SITE"
fi

log "menguji konfigurasi nginx"
nginx -t >/dev/null 2>&1 || {
  nginx -t || true
  die "konfigurasi nginx tidak valid — tidak ada yang di-reload"
}
systemctl reload nginx
ok "nginx dimuat ulang"
