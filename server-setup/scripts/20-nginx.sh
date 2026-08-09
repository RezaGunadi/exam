#!/usr/bin/env bash
# Pasang nginx + PHP-FPM, siapkan direktori situs, server block, dan symlink.
#
# NGINX HOST ADALAH PINTU DEPAN TUNGGAL (port 80/443) untuk semua proyek.
# Aplikasi berbasis container TIDAK membuka port publik sendiri — mereka hanya
# mendengar di 127.0.0.1 dan diteruskan dari sini. Dengan begitu tidak ada
# rebutan port, dan sertifikat SSL cukup diurus di satu tempat.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
load_env "$(dirname "$SCRIPT_DIR")"

require_root
require_apt

log "nginx + PHP-FPM"
apt_install nginx php-fpm php-mysql php-mbstring php-zip php-gd php-curl php-xml

# Socket PHP-FPM baru ADA setelah layanannya berjalan, jadi layanannya
# dinyalakan lebih dulu. Sebelumnya skrip langsung berhenti bila socket belum
# muncul — padahal penyebabnya cuma layanan yang belum start, bukan pemasangan
# yang gagal.
#
# Pencariannya memakai glob shell, bukan `grep -oP`: PCRE tidak selalu tersedia
# dan gagal pada sebagian locale, dengan pesan yang sama sekali tidak
# menjelaskan hubungannya dengan PHP.
find_php_sock() {
  local candidate
  for candidate in /run/php/php*-fpm.sock; do
    [ -S "$candidate" ] && { echo "$candidate"; return 0; }
  done
  return 1
}

PHP_SOCK="$(find_php_sock || true)"
if [ -z "$PHP_SOCK" ]; then
  log "menyalakan PHP-FPM"
  for unit in $(systemctl list-unit-files --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}'); do
    systemctl enable --now "$unit" >/dev/null 2>&1 || true
  done
  sleep 2
  PHP_SOCK="$(find_php_sock || true)"
fi

if [ -z "$PHP_SOCK" ]; then
  warn "socket PHP-FPM tidak ditemukan di /run/php/."
  warn "  Periksa: systemctl status 'php*-fpm'"
  die "PHP-FPM belum berjalan — situs PHP tidak bisa dikonfigurasi"
fi
ok "PHP-FPM ($PHP_SOCK)"

systemctl enable --now nginx >/dev/null 2>&1 || true

# ── Direktori situs + server block ─────────────────────────────────────────
# repo_for mencari URL repositori sebuah situs di SITE_REPOS.
#
# Format: "nama=url" dipisah koma, mis.
#   SITE_REPOS=STN=https://github.com/user/stn.git,ragh=git@github.com:user/ragh.git
#
# Situs tanpa entri tetap dibuatkan direktori kosong — tidak semua proyek sudah
# punya repo, dan exam_kelas_privat_v2 memang tidak butuh isi apa pun karena
# nginx hanya meneruskannya ke container.
repo_for() {
  local target="$1" pair name url
  while read -r pair; do
    [ -n "$pair" ] || continue
    name="${pair%%=*}"
    url="${pair#*=}"
    if [ "$name" = "$target" ] && [ "$url" != "$pair" ]; then
      echo "$url"
      return 0
    fi
  done < <(split_csv "${SITE_REPOS:-}")
  return 0
}

log "menyiapkan situs"
while read -r site; do
  [ -n "$site" ] || continue
  root="/var/www/${site}"
  repo="$(repo_for "$site" || true)"

  if [ -d "$root/.git" ]; then
    # Sudah berupa klon. TIDAK di-pull otomatis: menarik perubahan diam-diam
    # ke situs yang sedang melayani pengunjung bisa menyalakan versi yang belum
    # diuji. Pembaruan adalah keputusan sadar, bukan efek samping setup.
    skip "klon $site (perbarui manual: git -C $root pull)"
  elif [ -d "$root" ] && [ -n "$(ls -A "$root" 2>/dev/null || true)" ]; then
    skip "direktori $root sudah berisi"
  elif [ -n "$repo" ]; then
    apt_install git >/dev/null 2>&1 || true
    log "mengklon $site"
    rm -rf "$root"
    if git clone --depth 1 "$repo" "$root" >/dev/null 2>&1; then
      chown -R www-data:www-data "$root"
      ok "klon $site dari $repo"
    else
      # Repo privat butuh kunci deploy. Gagal klon TIDAK boleh menghentikan
      # penyiapan situs lain — direktorinya tetap dibuat agar nginx bisa
      # dikonfigurasi, dan isinya menyusul manual.
      mkdir -p "$root"
      chown -R www-data:www-data "$root"
      warn "gagal mengklon $site dari $repo"
      warn "  Bila repo privat, siapkan kunci deploy lalu: git clone $repo $root"
    fi
  else
    mkdir -p "$root"
    cat > "${root}/index.html" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>${site}</title>
<h1>${site}</h1>
<p>Direktori situs sudah disiapkan. Ganti berkas ini dengan aplikasi Anda.</p>
HTML
    chown -R www-data:www-data "$root"
    ok "direktori $root (tanpa repo di SITE_REPOS)"
  fi

  avail="/etc/nginx/sites-available/${site}"
  if [ -f "$avail" ]; then
    skip "server block $site"
  else
    # exam_kelas_privat_v2 diteruskan ke container (Next.js 3000, API Go 8080).
    # Sisanya disiapkan sebagai situs statis/PHP — silakan sesuaikan.
    if [ "$site" = "exam_kelas_privat_v2" ]; then
      cat > "$avail" <<CONF
# ${site} — aplikasi container di belakang nginx host.
# GANTI server_name dengan domain Anda, lalu jalankan: certbot --nginx -d <domain>
server {
    listen 80;
    listen [::]:80;
    server_name ${site}.local;

    client_max_body_size 32M;

    # API Go
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
        # nginx di sini adalah pintu terluar, jadi \$remote_addr sudah alamat
        # sebenarnya. Di belakang Cloudflare, 25-cloudflare-realip.sh yang
        # memulihkannya dari CF-Connecting-IP.
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }

    # Next.js
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        "upgrade";
        proxy_set_header Host              \$host;
        # \$remote_addr, BUKAN \$proxy_add_x_forwarded_for.
        #
        # Yang kedua menyambungkan header X-Forwarded-For yang dikirim
        # pengunjung dengan alamat aslinya. Aplikasi membaca entri pertama —
        # yaitu bagian yang dikarang pengunjung. Cukup mengganti isinya tiap
        # percobaan, dan pembatas login 3-kali-salah hilang sama sekali.
        #
        # nginx di sini adalah pintu terluar, jadi \$remote_addr sudah alamat
        # sebenarnya. Di belakang Cloudflare, 25-cloudflare-realip.sh yang
        # memulihkannya dari CF-Connecting-IP.
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
CONF
    else
      cat > "$avail" <<CONF
# ${site}
# GANTI server_name dengan domain Anda, lalu jalankan: certbot --nginx -d <domain>
server {
    listen 80;
    listen [::]:80;
    server_name ${site}.local;

    root /var/www/${site};
    index index.php index.html;

    client_max_body_size 32M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location ~ /\.(?!well-known) { deny all; }
}
CONF
    fi
    ok "server block $site"
  fi

  enabled="/etc/nginx/sites-enabled/${site}"
  if [ -L "$enabled" ]; then
    skip "symlink $site"
  else
    ln -s "$avail" "$enabled"
    ok "symlink $site"
  fi
done < <(split_csv "${SITES:-}")

# Situs bawaan nginx sering menyerobot permintaan tanpa domain cocok.
if [ -L /etc/nginx/sites-enabled/default ]; then
  rm -f /etc/nginx/sites-enabled/default
  ok "situs bawaan nginx dinonaktifkan"
fi

log "menguji konfigurasi nginx"
nginx -t || die "konfigurasi nginx tidak valid — tidak ada yang di-reload"
systemctl reload nginx
ok "nginx dimuat ulang"
