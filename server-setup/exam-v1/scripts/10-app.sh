#!/usr/bin/env bash
# Kode aplikasi Exam v1: klon, dependensi, .env, database, migrasi, izin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_apt
assert_not_managed_by_setup

log "Exam v1 — ${APP_DOMAIN}"

# ── PHP ────────────────────────────────────────────────────────────────────
# composer.json aplikasi ini meminta php ^8.2. Diperiksa di awal, bukan
# dibiarkan muncul sebagai kegagalan composer di tengah jalan — pesan composer
# menyebut daftar paket yang tidak cocok, bukan penyebabnya.
command -v php >/dev/null 2>&1 || die "PHP belum terpasang — jalankan: sudo make php (di direktori induk)"
if ! php -r 'exit(version_compare(PHP_VERSION, "8.2.0", "<") ? 1 : 0);'; then
  warn "PHP terpasang: $(php -r 'echo PHP_VERSION;')"
  warn "  Exam v1 butuh minimal 8.2 (lihat composer.json)."
  die "naikkan versinya dulu: cd $SETUP_DIR && sudo make php"
fi
ok "PHP $(php -r 'echo PHP_VERSION;')"

apt_install git unzip curl ca-certificates

# ── Composer ───────────────────────────────────────────────────────────────
# Diambil dari getcomposer.org, bukan dari apt: versi apt pada Ubuntu 22.04
# tertinggal cukup jauh, dan sebagian paket Laravel 11 meminta composer-plugin-api
# yang lebih baru — kegagalannya berupa daftar konflik dependensi yang tidak
# menyinggung versi composer sama sekali.
#
# Sidik sha384 installer-nya DIPERIKSA terhadap tanda tangan resmi. Tanpa itu,
# satu unduhan yang dibajak berarti kode pihak lain berjalan sebagai root di
# server ini.
if command -v composer >/dev/null 2>&1; then
  skip "composer ($(composer --version 2>/dev/null | head -1))"
else
  log "memasang composer"
  expected="$(curl -fsSL https://composer.github.io/installer.sig)" \
    || die "gagal mengambil tanda tangan installer composer"
  curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php \
    || die "gagal mengunduh installer composer"
  actual="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"
  if [ "$actual" != "$expected" ]; then
    rm -f /tmp/composer-setup.php
    die "sidik installer composer tidak cocok — unduhan rusak atau dipalsukan"
  fi
  php /tmp/composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer \
    || die "installer composer gagal"
  rm -f /tmp/composer-setup.php
  ok "composer ($(composer --version 2>/dev/null | head -1))"
fi

# ── Kode ───────────────────────────────────────────────────────────────────
# Diklon sebagai root; kepemilikan dan izinnya diatur belakangan oleh
# permissions.sh — pemilik SUDO_USER, grup www-data. Lihat berkas itu untuk apa
# yang dibeli dan apa yang dibayar oleh pilihan tersebut.
if [ -d "$APP_ROOT/.git" ]; then
  skip "klon $APP_SITE (perbarui dengan: sudo make update)"
else
  [ -d "$APP_ROOT" ] && [ -n "$(ls -A "$APP_ROOT" 2>/dev/null || true)" ] \
    && die "$APP_ROOT sudah berisi tetapi bukan klon git — pindahkan dulu, jangan ditimpa"
  log "mengklon $APP_REPO"
  rm -rf "$APP_ROOT"
  clone_log="$(mktemp)"
  if ! git clone "$APP_REPO" "$APP_ROOT" >"$clone_log" 2>&1; then
    sed 's/^/       /' "$clone_log"
    rm -f "$clone_log"
    warn "  Repo privat? Klon lewat HTTPS meminta kredensial dan gagal tanpa TTY."
    warn "  Pakai URL SSH dan kunci milik root:"
    warn "    sudo make app REPO=git@github.com:RezaGunadi/exam_kelas_privat.git"
    die "gagal mengklon $APP_SITE"
  fi
  rm -f "$clone_log"
  ok "klon $APP_SITE dari $APP_REPO"
fi

# ── .env aplikasi ──────────────────────────────────────────────────────────
# TIDAK PERNAH ditulis ulang setelah ada. Berkas ini memuat APP_KEY — mengganti
# kunci itu membuat seluruh sesi tercabut dan setiap nilai terenkripsi di
# database tidak bisa dibaca lagi. Kerusakan permanen dari satu perintah yang
# dijalankan ulang tanpa curiga.
if [ -f "$APP_ENV_FILE" ]; then
  skip ".env aplikasi (sunting sendiri di $APP_ENV_FILE)"
else
  [ -f "$APP_ROOT/.env.example" ] || die ".env.example tidak ada di dalam klon"
  cp "$APP_ROOT/.env.example" "$APP_ENV_FILE"

  set_env_kv "$APP_ENV_FILE" APP_ENV production
  set_env_kv "$APP_ENV_FILE" APP_DEBUG false
  set_env_kv "$APP_ENV_FILE" APP_URL "https://${APP_DOMAIN}"
  set_env_kv "$APP_ENV_FILE" LOG_LEVEL warning
  set_env_kv "$APP_ENV_FILE" DB_CONNECTION mysql
  set_env_kv "$APP_ENV_FILE" DB_HOST 127.0.0.1
  set_env_kv "$APP_ENV_FILE" DB_PORT 3306
  set_env_kv "$APP_ENV_FILE" DB_DATABASE "$APP_DB"
  set_env_kv "$APP_ENV_FILE" DB_USERNAME "${DB_USER:-}"
  set_env_kv "$APP_ENV_FILE" DB_PASSWORD "${DB_PASSWORD:-}"
  # APP_KEY dari .env.example adalah kunci yang sama untuk semua orang yang
  # pernah mengklon repo ini. Dikosongkan agar key:generate membuat yang baru.
  set_env_kv "$APP_ENV_FILE" APP_KEY ""

  ok ".env aplikasi dibuat (APP_ENV=production, APP_DEBUG=false)"
  warn ".env.example repo ini memuat kredensial sungguhan (SMTP)."
  warn "  Periksa $APP_ENV_FILE dan ganti yang tidak seharusnya dipakai di sini."
fi

# Dibaca PHP-FPM sebagai www-data, tidak perlu bisa dibaca siapa pun selain itu.
# permissions.sh mempertahankan mode ini; ia satu-satunya berkas yang
# dikecualikan dari sapuan `chmod 664`.
chgrp www-data "$APP_ENV_FILE"
chmod 640 "$APP_ENV_FILE"

# ── Dependensi ─────────────────────────────────────────────────────────────
# --no-dev: paket pengembangan tidak dipasang di produksi. Beberapa di antaranya
# mendaftarkan service provider yang membuka informasi debug.
log "composer install"
( cd "$APP_ROOT" && COMPOSER_ALLOW_SUPERUSER=1 composer install \
    --no-dev --optimize-autoloader --no-interaction --no-progress ) \
  || die "composer install gagal"
ok "dependensi terpasang"

# ── Database ───────────────────────────────────────────────────────────────
# Dibuat dengan kredensial DB_USER dari .env induk, yang memang diberi seluruh
# hak untuk keperluan ini. Bila gagal, database ditambahkan lewat setup induk —
# bukan dengan menebak password root di sini.
if [ -z "${DB_USER:-}" ]; then
  warn "DB_USER kosong di $SETUP_DIR/.env — pembuatan database dilewati"
elif mysql -u"$DB_USER" -p"${DB_PASSWORD:-}" -e "USE \`${APP_DB}\`" >/dev/null 2>&1; then
  skip "database $APP_DB"
elif mysql -u"$DB_USER" -p"${DB_PASSWORD:-}" \
       -e "CREATE DATABASE \`${APP_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
       >/dev/null 2>&1; then
  ok "database $APP_DB dibuat"
else
  warn "tidak bisa membuat database $APP_DB dengan pengguna $DB_USER"
  warn "  Tambahkan '${APP_DB}' ke DATABASES di $SETUP_DIR/.env lalu:"
  warn "    cd $SETUP_DIR && sudo make mysql"
  die "database belum siap — migrasi tidak dijalankan"
fi

# ── Izin ───────────────────────────────────────────────────────────────────
# Dilakukan SETELAH composer install dan SEBELUM artisan dijalankan. Urutannya
# bukan kebetulan: vendor/ yang baru dipasang ikut disapu, dan perintah artisan
# pertama yang menulis log akan gagal bila storage/ belum bisa ditulis.
bash "$SCRIPT_DIR/permissions.sh"

# ── APP_KEY ────────────────────────────────────────────────────────────────
# Dibuat dengan openssl, BUKAN `php artisan key:generate`.
#
# Dua alasan, dan keduanya nyata di sini:
#
#   1. key:generate bekerja dengan MENULIS BALIK ke .env. Berkas itu sengaja
#      dibiarkan 640 dengan grup www-data — aplikasi boleh membacanya, tidak
#      boleh mengubahnya — sedangkan artisan berjalan sebagai www-data.
#      Perintahnya gagal, dan memberi www-data hak tulis atas .env demi satu
#      langkah setup adalah harga yang salah untuk dibayar.
#
#   2. Ayam-dan-telur: sebagian aplikasi tidak bisa boot sama sekali tanpa
#      APP_KEY ("No application encryption key has been specified"), sehingga
#      artisan tidak bisa dipakai untuk membuat kunci yang dibutuhkannya
#      sendiri.
#
# Hasilnya identik. key:generate memanggil Encrypter::generateKey(), yang untuk
# AES-256-CBC — cipher yang dipakai config/app.php aplikasi ini — mengembalikan
# 32 byte acak lalu di-base64. Persis yang dikerjakan baris di bawah.
apt_install openssl
if [ -z "$(get_env_kv "$APP_ENV_FILE" APP_KEY || true)" ]; then
  set_env_kv "$APP_ENV_FILE" APP_KEY "base64:$(openssl rand -base64 32)"
  chgrp www-data "$APP_ENV_FILE"
  chmod 640 "$APP_ENV_FILE"
  ok "APP_KEY dibuat"
else
  skip "APP_KEY (sudah ada — JANGAN diganti, sesi & data terenkripsi ikut hilang)"
fi

# ── Symlink storage ────────────────────────────────────────────────────────
# Dibuat langsung dengan ln, bukan lewat `artisan storage:link`. Satu perintah,
# tanpa mem-boot seluruh aplikasi, dan tetap bekerja pada urutan mana pun izin
# dipasang — termasuk bila skrip ini dijalankan sebelum permissions.sh.
if [ -L "$APP_WEBROOT/storage" ]; then
  skip "symlink public/storage"
elif [ -e "$APP_WEBROOT/storage" ]; then
  warn "$APP_WEBROOT/storage sudah ada tetapi bukan symlink — dibiarkan apa adanya"
else
  ln -s "$APP_ROOT/storage/app/public" "$APP_WEBROOT/storage"
  ok "symlink public/storage → storage/app/public"
fi

# ── Berkas di public/ yang ditulis aplikasi ────────────────────────────────
# Penjadwal harian menjalankan `sitemap:generate`, yang menulis
# public/sitemap.xml lewat file_put_contents. Berkas itu tidak ikut ke klon
# (.gitignore), jadi perintahnya harus MEMBUATNYA — dan membuat berkas baru
# butuh izin atas direktorinya, bukan cuma atas berkasnya.
#
# Dengan izin 775 dari permissions.sh, www-data memang boleh menulis di public/.
# Berkasnya tetap disiapkan di sini supaya langkah ini tidak diam-diam ikut
# rusak kalau suatu saat public/ dirapatkan lagi — menulis ulang berkas yang
# SUDAH ADA hanya butuh izin atas berkas itu sendiri.
#
# Tanpa ini perintahnya gagal tiap hari, dan satu-satunya jejaknya ada di
# /var/log/exam_v1-schedule.log yang tidak ada yang membaca.
[ -f "$APP_WEBROOT/sitemap.xml" ] || : > "$APP_WEBROOT/sitemap.xml"
chgrp www-data "$APP_WEBROOT/sitemap.xml"
chmod 664 "$APP_WEBROOT/sitemap.xml"
ok "public/sitemap.xml bisa ditulis penjadwal"

# ── Migrasi ────────────────────────────────────────────────────────────────
# --force karena tidak ada TTY untuk menjawab konfirmasi produksi.
log "menjalankan migrasi"
artisan migrate --force || die "migrasi gagal — periksa kredensial database di $APP_ENV_FILE"
ok "migrasi selesai"

# ── Cache konfigurasi: SENGAJA TIDAK DIJALANKAN ────────────────────────────
# `php artisan config:cache` adalah langkah baku deploy Laravel, dan di aplikasi
# ini ia MERUSAK. Ada 38 pemanggilan env() di luar config/ — termasuk
# env('R2_DOMAIN') di app/helpers.php yang menyusun URL berkas. Begitu config
# di-cache, env() mengembalikan null dan URL-nya rusak tanpa satu pun pesan
# error; yang terlihat hanya gambar yang tidak muncul.
#
# `php artisan route:cache` juga tidak dijalankan: routes/web.php memakai closure
# sebagai aksi route, dan closure tidak bisa diserialkan — perintahnya gagal.
#
# view:cache aman, tapi Blade meng-cache sendiri saat permintaan pertama, jadi
# tidak ada yang perlu dikerjakan di sini.
artisan config:clear >/dev/null 2>&1 || true
artisan view:clear   >/dev/null 2>&1 || true

# Berkas cache yang baru dibuat artisan mewarisi umask, bukan izin direktorinya.
# Dikembalikan pada dua direktori itu saja — murah, dan tidak perlu menyapu
# vendor/ untuk kedua kalinya.
chgrp -R www-data "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"
chmod -R ug+rwX "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"

ok "kode Exam v1 siap di $APP_ROOT"

if [ -z "$(get_env_kv "$APP_ENV_FILE" AWS_ACCESS_KEY_ID || true)" ]; then
  warn "AWS_ACCESS_KEY_ID kosong, sementara FILESYSTEM_DISK=r2."
  warn "  Unggahan berkas akan gagal sampai kredensial R2 diisi di $APP_ENV_FILE"
fi
