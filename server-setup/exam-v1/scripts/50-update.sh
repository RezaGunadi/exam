#!/usr/bin/env bash
# Rilis berikutnya: tarik perubahan, perbarui dependensi, migrasi.
#
# Dipisahkan dari `make app` dengan sengaja. Menarik perubahan ke situs yang
# sedang melayani pengunjung menyalakan versi yang belum tentu diuji — itu
# keputusan sadar, bukan efek samping dari menjalankan ulang setup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root

[ -d "$APP_ROOT/.git" ] || die "$APP_ROOT bukan klon git — jalankan dulu: sudo make app"
[ -f "$APP_ENV_FILE" ] || die "$APP_ENV_FILE tidak ada — jalankan dulu: sudo make app"

log "Exam v1 — memperbarui $APP_ROOT"

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

# Izin dikembalikan SEBELUM artisan dijalankan. Berkas yang baru masuk lewat
# `git pull` dan paket yang baru dipasang composer dimiliki root dan mengikuti
# umask root — bukan izin yang dipasang deploy sebelumnya.
bash "$SCRIPT_DIR/permissions.sh"

# Migrasi dimatikan secara bawaan — lihat alasan panjangnya di 10-app.sh.
# Database ini dipakai bersama Exam v2; skema diubah dari sana, bukan dari sini.
case "${MIGRATE:-no}" in
  [Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|1)
    log "migrasi"
    artisan migrate --force || die "migrasi gagal"
    ;;
  *)
    skip "migrasi (MIGRATE=${MIGRATE:-no})"
    ;;
esac

# Lihat komentar panjang di 10-app.sh: config:cache MERUSAK aplikasi ini
# (38 pemanggilan env() di luar config/), dan route:cache gagal karena ada
# closure sebagai aksi route. Yang dilakukan hanya MEMBERSIHKAN cache lama.
artisan config:clear >/dev/null 2>&1 || true
artisan view:clear   >/dev/null 2>&1 || true
chgrp -R www-data "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"
chmod -R ug+rwX "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"

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

ok "Exam v1 diperbarui ke $AFTER"
