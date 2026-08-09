#!/usr/bin/env bash
# phpMyAdmin untuk memantau seluruh database.
#
# DUA LAPIS PENGAMAN, karena panel ini memberi akses penuh ke SELURUH database
# di server — termasuk data pribadi siswa:
#   1. Berjalan di port tersendiri, bukan di domain publik mana pun.
#   2. Dilindungi basic-auth nginx SEBELUM permintaan sampai ke PHP.
#
# Alamat yang tidak dipublikasikan bukan pengaman: pemindai otomatis rutin
# mencoba /phpmyadmin di setiap IP.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
load_env "$(dirname "$SCRIPT_DIR")"

require_root
require_apt

if [ "${PMA_ENABLE:-true}" != "true" ]; then
  skip "phpMyAdmin (PMA_ENABLE bukan true)"
  exit 0
fi

log "phpMyAdmin"
apt_install apache2-utils   # menyediakan htpasswd

PMA_DIR=/usr/share/phpmyadmin
if [ -d "$PMA_DIR" ]; then
  skip "phpMyAdmin sudah terpasang"
else
  # Paket distro sering tertinggal versi; ambil rilis resmi terbaru.
  apt_install wget unzip
  TMP="$(mktemp -d)"
  log "mengunduh phpMyAdmin"
  wget -q -O "$TMP/pma.zip" \
    https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip \
    || die "gagal mengunduh phpMyAdmin"
  unzip -q "$TMP/pma.zip" -d "$TMP"
  mkdir -p "$PMA_DIR"
  cp -r "$TMP"/phpMyAdmin-*/. "$PMA_DIR/"
  rm -rf "$TMP"

  mkdir -p "$PMA_DIR/tmp"
  chown -R www-data:www-data "$PMA_DIR"
  chmod 700 "$PMA_DIR/tmp"
  ok "phpMyAdmin terpasang"
fi

# blowfish_secret wajib diisi; tanpa itu phpMyAdmin menolak menyimpan sesi.
PMA_CONF="$PMA_DIR/config.inc.php"
if [ -f "$PMA_CONF" ]; then
  skip "config.inc.php"
else
  SECRET="$(openssl rand -base64 48 | tr -d '/+=' | cut -c1-32)"
  cat > "$PMA_CONF" <<CONF
<?php
declare(strict_types=1);
\$cfg['blowfish_secret'] = '${SECRET}';
\$i = 1;
\$cfg['Servers'][\$i]['auth_type']  = 'cookie';
\$cfg['Servers'][\$i]['host']       = '127.0.0.1';
\$cfg['Servers'][\$i]['compress']   = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
\$cfg['TempDir'] = '${PMA_DIR}/tmp';
CONF
  chown www-data:www-data "$PMA_CONF"
  chmod 640 "$PMA_CONF"
  ok "config.inc.php dibuat"
fi

# ── Basic auth ─────────────────────────────────────────────────────────────
HTPASSWD=/etc/nginx/.htpasswd-pma
if [ -f "$HTPASSWD" ]; then
  skip "basic-auth phpMyAdmin"
else
  [ -n "${PMA_AUTH_USER:-}" ]     || die "PMA_AUTH_USER kosong di .env"
  [ -n "${PMA_AUTH_PASSWORD:-}" ] || die "PMA_AUTH_PASSWORD kosong di .env"
  htpasswd -bc "$HTPASSWD" "$PMA_AUTH_USER" "$PMA_AUTH_PASSWORD" >/dev/null
  chown root:www-data "$HTPASSWD"
  chmod 640 "$HTPASSWD"
  ok "basic-auth dibuat untuk $PMA_AUTH_USER"
fi

# Socket dicari lewat glob, bukan `grep -oP`. Versi lama menyusun path dari
# nomor versi hasil regex; bila regex itu gagal, path-nya menjadi
# "/run/php/php-fpm.sock" yang tidak ada — dan skrip TETAP LANJUT, sehingga
# phpMyAdmin baru ketahuan rusak saat dibuka (502, tanpa petunjuk apa pun).
PHP_SOCK=""
for candidate in /run/php/php*-fpm.sock; do
  [ -S "$candidate" ] && { PHP_SOCK="$candidate"; break; }
done
[ -n "$PHP_SOCK" ] || die "socket PHP-FPM tidak ditemukan — jalankan 'sudo make nginx' lebih dulu"
PMA_PORT="${PMA_PORT:-8081}"

AVAIL=/etc/nginx/sites-available/phpmyadmin
if [ -f "$AVAIL" ]; then
  skip "server block phpMyAdmin"
else
  cat > "$AVAIL" <<CONF
# phpMyAdmin — port terpisah + basic auth.
# Disarankan membatasi lebih lanjut ke IP Anda dengan allow/deny di bawah.
server {
    listen ${PMA_PORT};
    listen [::]:${PMA_PORT};
    server_name _;

    root ${PMA_DIR};
    index index.php;

    # Batasi ke alamat tertentu bila perlu:
    # allow 203.0.113.10;
    # deny all;

    auth_basic           "Area Terbatas";
    auth_basic_user_file /etc/nginx/.htpasswd-pma;

    client_max_body_size 256M;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_read_timeout 300;
    }

    location ~ /(libraries|setup|templates)/ { deny all; }
    location ~ /\. { deny all; }
}
CONF
  ok "server block phpMyAdmin (port $PMA_PORT)"
fi

[ -L /etc/nginx/sites-enabled/phpmyadmin ] || ln -s "$AVAIL" /etc/nginx/sites-enabled/phpmyadmin

nginx -t || die "konfigurasi nginx tidak valid"
systemctl reload nginx
ok "phpMyAdmin siap di port ${PMA_PORT}"
warn "buka lewat http://<ip-server>:${PMA_PORT} — pastikan firewall hanya mengizinkan IP Anda"
