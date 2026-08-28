#!/usr/bin/env bash
# Rilis berikutnya: tarik perubahan, perbarui dependensi, bangun aset, migrasi.
#
# Dipisahkan dari `make deploy` dengan sengaja. Menarik perubahan ke situs yang
# sedang melayani pengunjung menyalakan versi yang belum tentu diuji — itu
# keputusan sadar, bukan efek samping dari menjalankan ulang setup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root

[ -d "$APP_ROOT/.git" ] || die "$APP_ROOT bukan klon git — jalankan dulu: sudo make app"
[ -f "$APP_ENV_FILE" ] || die "$APP_ENV_FILE tidak ada — jalankan dulu: sudo make app"

log "cuandariponsel — memperbarui $APP_ROOT"

# Perubahan lokal yang belum di-commit membuat `git pull` berhenti di tengah dan
# meninggalkan working tree campur aduk. Diperiksa lebih dulu, bukan ditemukan
# setelah separuh pekerjaan berjalan.
if [ -n "$(git -C "$APP_ROOT" status --porcelain 2>/dev/null || true)" ]; then
  warn "ada perubahan lokal yang belum di-commit di $APP_ROOT:"
  git -C "$APP_ROOT" status --short | sed 's/^/       /'
  die "selesaikan dulu (commit, stash, atau checkout) sebelum menarik perubahan"
fi

BEFORE="$(git -C "$APP_ROOT" rev-parse --short HEAD)"
git -C "$APP_ROOT" pull --ff-only || die "git pull gagal"
AFTER="$(git -C "$APP_ROOT" rev-parse --short HEAD)"

if [ "$BEFORE" = "$AFTER" ]; then
  skip "kode (sudah pada $AFTER)"
else
  ok "kode $BEFORE → $AFTER"
fi

log "composer install"
( cd "$APP_ROOT" && COMPOSER_ALLOW_SUPERUSER=1 composer install \
    --no-dev --optimize-autoloader --no-interaction --no-progress ) \
  || die "composer install gagal"

# Aset dibangun ulang SETIAP kali, bukan hanya saat package.json berubah.
# Berkas Blade dan CSS yang berubah pun menghasilkan manifest baru, dan
# manifest lama menunjuk berkas ber-hash yang sudah tidak ada — halamannya
# tampil tanpa gaya sama sekali, tanpa satu pun galat di sisi server.
bash "$SCRIPT_DIR/15-assets.sh"

# Batas unggahan PHP dipasang ulang: `sudo make php` di direktori induk bisa
# memindahkan server ke versi PHP lain, dan drop-in di conf.d versi lama ikut
# ditinggal tanpa satu pun pesan.
bash "$SCRIPT_DIR/18-uploads.sh"

# Izin dikembalikan SEBELUM artisan dijalankan. Berkas yang baru masuk lewat
# `git pull` dan paket yang baru dipasang composer dimiliki root dan mengikuti
# umask root — bukan izin yang dipasang deploy sebelumnya.
bash "$SCRIPT_DIR/permissions.sh"

case "${MIGRATE:-yes}" in
  [Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|0)
    skip "migrasi (MIGRATE=no)"
    ;;
  *)
    log "migrasi"
    artisan migrate --force || die "migrasi gagal"
    ;;
esac

# Katalog jenis tugas ikut disegarkan: seeder-nya idempoten (updateOrCreate per
# slug) dan hanya memperbarui kolom struktural, jadi harga yang sudah disetel
# owner lewat panel TIDAK ditimpa. Jenis tugas baru yang ikut masuk lewat rilis
# ini akan muncul tanpa langkah manual.
artisan db:seed --class='Database\Seeders\TaskTypeSeeder' --force >/dev/null 2>&1 \
  && ok "katalog jenis tugas disegarkan" \
  || warn "TaskTypeSeeder gagal — jenis tugas baru (bila ada) belum muncul"

# config:cache dibangun ULANG, bukan sekadar dibersihkan. Cache lama memuat
# nilai .env sebelum rilis ini; dibiarkan, satu-satunya yang berubah adalah
# kodenya, sementara konfigurasinya tetap yang kemarin.
artisan config:clear >/dev/null 2>&1 || true
artisan config:cache >/dev/null 2>&1 && ok "konfigurasi di-cache ulang" \
  || warn "config:cache gagal — situs tetap jalan, hanya lebih lambat"
artisan view:clear >/dev/null 2>&1 || true

chgrp -R www-data "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"
chmod -R ug+rwX "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"

# ── Pekerja antrean harus dinyalakan ulang ─────────────────────────────────
# PHP memuat seluruh aplikasi SEKALI saat pekerja start. Pekerja yang sudah
# hidup akan terus menjalankan kode lama sampai ia berhenti sendiri — sampai
# satu jam kemudian dengan --max-time. Sepanjang jam itu, pekerjaan baru
# diproses versi kemarin, dan tidak ada yang terlihat salah.
if systemctl list-unit-files --no-legend "${APP_SITE}-queue.service" 2>/dev/null | grep -q .; then
  systemctl restart "${APP_SITE}-queue.service" \
    && ok "pekerja antrean dinyalakan ulang (kode baru terpakai)" \
    || warn "gagal menyalakan ulang ${APP_SITE}-queue — periksa: systemctl status ${APP_SITE}-queue"
else
  warn "unit ${APP_SITE}-queue.service belum ada — jalankan: sudo make queue"
fi

# OPcache menyimpan bytecode PHP di memori proses FPM. Tanpa reload, kode lama
# tetap dijalankan meski berkasnya sudah berganti — dan yang membingungkan,
# sebagian permintaan memakai kode baru sementara sisanya tidak, tergantung
# proses mana yang melayaninya.
FPM_UNIT="php${PHP_VERSION:-}-fpm.service"
if [ -n "${PHP_VERSION:-}" ] && systemctl is-active --quiet "$FPM_UNIT" 2>/dev/null; then
  systemctl reload "$FPM_UNIT"
  ok "$FPM_UNIT dimuat ulang (OPcache dibersihkan)"
else
  reloaded=0
  while read -r unit; do
    [ -n "$unit" ] || continue
    systemctl is-active --quiet "$unit" 2>/dev/null || continue
    systemctl reload "$unit" && { ok "$unit dimuat ulang"; reloaded=1; }
  done < <(systemctl list-unit-files --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}')
  [ "$reloaded" -eq 1 ] || warn "tidak ada PHP-FPM yang dimuat ulang — OPcache mungkin masih memegang kode lama"
fi

ok "cuandariponsel diperbarui ke $AFTER"
