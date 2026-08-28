#!/usr/bin/env bash
# Aset frontend cuandariponsel: Node.js + `npm ci && npm run build` (Vite).
#
# KENAPA INI HARUS ADA. `/public/build` ada di .gitignore repo aplikasi, jadi
# klon git tidak pernah membawa hasil buildnya. Tanpa langkah ini setiap halaman
# tetap terbuka — Blade-nya render, HTML-nya utuh — tetapi @vite() menunjuk ke
# manifest yang tidak ada, dan Laravel melemparkan
# "Vite manifest not found at: /var/www/repost/public/build/manifest.json".
#
# Ini beda dengan company-kelasprivat, yang meng-commit public/build/ sehingga
# tidak butuh Node di server sama sekali.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_apt
assert_not_managed_by_setup

[ -f "$APP_ROOT/package.json" ] || die "$APP_ROOT/package.json tidak ada — jalankan dulu: sudo make app"

log "aset frontend — Node.js ${NODE_VERSION:-22}"

# install_node ada di lib.sh induk dan dipakai bersama 40-node.sh. Di sini
# kegagalannya fatal: tanpa Node tidak ada manifest, dan tanpa manifest situsnya
# melemparkan galat pada permintaan pertama.
install_node "${NODE_VERSION:-22}" || die "gagal memasang Node.js"

warn_low_memory

# npm ci, bukan npm install: ia memasang PERSIS isi package-lock.json. `npm
# install` boleh menaikkan versi transitif sendiri, sehingga hasil build di
# server bisa berbeda dari yang diuji — perbedaan yang tidak muncul di mana pun
# kecuali sebagai bug yang tidak bisa ditirukan.
if [ -f "$APP_ROOT/package-lock.json" ]; then
  NPM_CMD=(npm ci --include=dev)
else
  warn "tidak ada package-lock.json — memakai 'npm install'"
  warn "  Versi transitif bisa berbeda dari yang diuji. Commit lockfile-nya."
  NPM_CMD=(npm install)
fi

# --include=dev eksplisit: vite, tailwind, dan laravel-vite-plugin semuanya ada
# di devDependencies, dan tanpanya perintah build tidak ada sama sekali. npm
# melewatkannya begitu NODE_ENV=production terbaca dari lingkungan — nilai yang
# mudah tertinggal di profil shell server dan tidak disebut di pesan galatnya.
log "npm: memasang dependensi build"
build_log="$(mktemp)"
if ! ( cd "$APP_ROOT" && NODE_ENV=development "${NPM_CMD[@]}" ) >"$build_log" 2>&1; then
  tail -20 "$build_log" | sed 's/^/       /'
  rm -f "$build_log"
  die "pemasangan dependensi npm gagal"
fi

log "npm run build (Vite)"
if ! ( cd "$APP_ROOT" && npm run build ) >"$build_log" 2>&1; then
  tail -25 "$build_log" | sed 's/^/       /'
  rm -f "$build_log"
  warn "Kode keluar 137 atau 'Killed' = kehabisan memori, bukan kode yang salah."
  die "'npm run build' gagal"
fi
rm -f "$build_log"

[ -f "$APP_WEBROOT/build/manifest.json" ] \
  || die "build selesai tetapi $APP_WEBROOT/build/manifest.json tidak ada — periksa vite.config.js"
ok "aset dibangun → public/build/manifest.json"

# node_modules bisa berisi puluhan ribu berkas milik root, dan sapuan izin di
# permissions.sh menyentuh seluruh pohon aplikasi. Dijalankan di sini supaya
# berkas yang baru dibuat npm tidak tertinggal dengan pemilik yang salah.
bash "$SCRIPT_DIR/permissions.sh"
