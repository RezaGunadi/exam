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
# Kodenya TIDAK dijadikan milik www-data, hanya bisa dibaca olehnya.
#
# Dua alasan. Pertama, aplikasi yang berhasil ditembus lewat unggahan tidak bisa
# menulis ulang kodenya sendiri. Kedua, `sudo git -C ... pull` menolak repo milik
# www-data dengan "detected dubious ownership" — git membandingkan pemilik repo
# dengan SUDO_UID, dan www-data tidak akan pernah cocok. Hanya storage/ dan
# bootstrap/cache yang benar-benar perlu ditulis PHP.
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
chown root:www-data "$APP_ENV_FILE"
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
# Dilakukan SEBELUM artisan dijalankan: perintah pertama yang menulis log akan
# gagal bila storage/ belum bisa ditulis www-data.
chown -R www-data:www-data "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"
chmod -R u+rwX,g+rwX "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"
ok "izin storage/ & bootstrap/cache"

# ── APP_KEY ────────────────────────────────────────────────────────────────
if [ -z "$(get_env_kv "$APP_ENV_FILE" APP_KEY || true)" ]; then
  artisan key:generate --force >/dev/null || die "key:generate gagal"
  ok "APP_KEY dibuat"
else
  skip "APP_KEY (sudah ada — JANGAN diganti, sesi & data terenkripsi ikut hilang)"
fi

# ── Symlink storage ────────────────────────────────────────────────────────
if [ -L "$APP_WEBROOT/storage" ]; then
  skip "symlink public/storage"
else
  artisan storage:link >/dev/null || warn "storage:link gagal — unggahan lama mungkin tidak tampil"
  ok "symlink public/storage"
fi

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

# Cache yang dibuat artisan barusan bisa jadi milik root bila skrip ini
# dijalankan ulang dalam keadaan aneh. Dikembalikan, sekali lagi, dengan murah.
chown -R www-data:www-data "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"

ok "kode Exam v1 siap di $APP_ROOT"

if [ -z "$(get_env_kv "$APP_ENV_FILE" AWS_ACCESS_KEY_ID || true)" ]; then
  warn "AWS_ACCESS_KEY_ID kosong, sementara FILESYSTEM_DISK=r2."
  warn "  Unggahan berkas akan gagal sampai kredensial R2 diisi di $APP_ENV_FILE"
fi
