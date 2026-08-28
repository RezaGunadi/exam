#!/usr/bin/env bash
# Rilis berikutnya: tarik perubahan, bangun ulang image, nyalakan ulang stack.
#
# Dipisahkan dari `make deploy` dengan sengaja. Menarik perubahan ke aplikasi
# yang sedang dipakai anak-anak menyalakan versi yang belum tentu diuji — itu
# keputusan sadar, bukan efek samping menjalankan ulang setup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_docker

[ -d "$APP_ROOT/.git" ] || die "$APP_ROOT bukan klon git — jalankan dulu: sudo make app"
[ -f "$APP_ENV_FILE" ] || die "$APP_ENV_FILE tidak ada — jalankan dulu: sudo make app"

log "Kelas Junior — memperbarui $APP_ROOT"

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

# Virtualenv host ikut disegarkan bila memang ada. Dilewati diam-diam kalau
# tidak — ia perkakas perawatan, bukan syarat layanan.
if [ -x "$VENV_DIR/bin/pip" ]; then
  log "menyegarkan dependensi virtualenv host"
  if "$VENV_DIR/bin/pip" install --quiet -r "$BACKEND_DIR/requirements.txt" >/dev/null 2>&1; then
    ok "virtualenv host diperbarui"
  else
    warn "pip install di $VENV_DIR gagal — layanan tidak terpengaruh"
  fi
fi

# Skema & seed berjalan sendiri saat `api` start (RUN_MIGRATIONS/SEED_ON_START),
# keduanya idempoten. Tidak ada langkah migrasi terpisah di sini.
bash "$SCRIPT_DIR/30-stack.sh"

ok "Kelas Junior diperbarui ke $AFTER"
echo ""
warn "Mengubah art ikon berarti modul lama masih menyimpan path ikon lama."
warn "  Seed otomatis TIDAK menyentuhnya (ia hanya mengisi yang kosong). Paksa:"
warn "    sudo make reseed"
