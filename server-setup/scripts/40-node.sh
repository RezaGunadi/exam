#!/usr/bin/env bash
# Node.js + build situs yang hasil buildnya TIDAK ikut ke git.
#
# Situs yang hasil buildnya di-commit (mis. company-kelasprivat: public/build/
# ada di dalam repo) TIDAK perlu Node di server sama sekali. Yang perlu hanyalah
# yang direktori keluarannya di-.gitignore — untuk itu, tanpa build di sini,
# /var/www/<situs> tidak punya apa pun untuk disajikan dan nginx menjawab 403.
#
# DAFTARNYA EKSPLISIT lewat NODE_SITES, bukan ditebak dari ada-tidaknya
# package.json. Hampir semua proyek PHP di server ini punya package.json untuk
# perkakas pengembangan, dan menjalankan `npm run build` di sana bukan cuma
# mubazir — ia bisa menimpa aset yang sudah benar dengan hasil build setengah
# jadi. Menebak akan salah tepat pada saat paling merepotkan.
#
# NODE_SITES kosong = skrip ini tidak mengerjakan apa pun, termasuk tidak
# memasang Node. Server yang tidak butuh Node tidak akan pernah kejatuhan repo
# pihak ketiga hanya karena `make server` dijalankan.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
load_env "$(dirname "$SCRIPT_DIR")"

require_root
require_apt

if [ -z "${NODE_SITES:-}" ]; then
  skip "build Node (NODE_SITES kosong)"
  exit 0
fi

NODE_VERSION="${NODE_VERSION:-22}"

log "Node.js ${NODE_VERSION} — situs: $(echo "${NODE_SITES}" | tr ',' ' ')"

# ── Pemasangan Node ────────────────────────────────────────────────────────
# Isinya ada di install_node (lib.sh) karena skrip deploy aplikasi yang punya
# langkah build sendiri memakainya juga — lihat repost-app/15-assets.sh. Di sini
# kegagalannya fatal: tanpa Node tidak ada satu pun situs yang bisa dibangun.
install_node "$NODE_VERSION" || die "gagal memasang Node.js ${NODE_VERSION}"

warn_low_memory

# ── Tulis ulang server block setelah build ─────────────────────────────────
# site_docroot mendeteksi out/ dan dist/ dari ADA-TIDAKNYA index di dalamnya.
# Pada `make server` pertama, direktori itu belum ada saat 20-nginx.sh menulis
# server block, sehingga root-nya jatuh ke akar repo — dan situsnya menyajikan
# kode sumber, bukan hasil build. Setelah build berhasil, blocknya ditulis ulang
# di sini dengan root yang sudah benar.
#
# Cara paling pasti menghindari itu tetap SITE_ROOTS di .env: dengan entri
# eksplisit, deteksi tidak pernah dipakai dan root-nya benar sejak awal.
PHP_SOCK="$(find_php_sock || true)"

refresh_site_conf() {
  local site="$1" domain paths certf keyf
  [ -n "$PHP_SOCK" ] || return 0
  domain="$(kv_lookup "$site" "${SITE_DOMAINS:-}")"
  [ -n "$domain" ] || return 0
  if paths="$(site_cert_paths "${domain%%|*}")"; then
    read -r certf keyf <<< "$paths"
    write_site_conf "$site" "$domain" "$PHP_SOCK" "$certf" "$keyf"
  else
    write_site_conf "$site" "$domain" "$PHP_SOCK"
  fi
}

# ── Build tiap situs ───────────────────────────────────────────────────────
# Kegagalan satu situs TIDAK menghentikan yang lain, dan tidak menghentikan
# `make server`. Sama seperti HTTPS: build bergantung pada hal-hal di luar
# kendali skrip ini (jaringan npm, memori, kode aplikasi yang sedang rusak), dan
# menghentikan seluruh setup karena satu di antaranya bukan pertukaran yang baik.
BUILT=0
FAILED=""

while read -r site; do
  [ -n "$site" ] || continue
  root="/var/www/${site}"

  if [ ! -f "$root/package.json" ]; then
    warn "$site: tidak ada package.json di $root — dilewati"
    warn "  Sudah diklon? Periksa SITE_REPOS di .env, lalu: sudo make nginx"
    FAILED="${FAILED} ${site}"
    continue
  fi

  if ! kv_lookup "$site" "${SITE_ROOTS:-}" | grep -q .; then
    warn "$site tidak punya entri di SITE_ROOTS — root nginx ditentukan deteksi otomatis."
    warn "  Tambahkan (mis. SITE_ROOTS=${site}=out) agar tidak bergantung pada urutan build."
  fi

  log "membangun $site"
  build_log="$(mktemp)"

  # npm ci, bukan npm install: ia memasang PERSIS isi package-lock.json. `npm
  # install` boleh menaikkan versi transitif sendiri, sehingga hasil build di
  # server bisa berbeda dari yang diuji — perbedaan yang tidak muncul di mana
  # pun kecuali sebagai bug yang tidak bisa ditirukan.
  #
  # devDependencies TETAP dipasang: next, vite, dan tailwind ada di sana, dan
  # tanpanya perintah build tidak ada.
  if [ -f "$root/package-lock.json" ]; then
    npm_cmd=(npm ci)
  else
    warn "$site: tidak ada package-lock.json — memakai 'npm install'"
    warn "  Versi transitif bisa berbeda dari yang diuji. Commit lockfile-nya."
    npm_cmd=(npm install)
  fi

  if ! ( cd "$root" && "${npm_cmd[@]}" ) >"$build_log" 2>&1; then
    tail -15 "$build_log" | sed 's/^/       /'
    rm -f "$build_log"
    warn "$site: pemasangan dependensi gagal"
    FAILED="${FAILED} ${site}"
    continue
  fi

  if ! ( cd "$root" && npm run build ) >"$build_log" 2>&1; then
    tail -20 "$build_log" | sed 's/^/       /'
    rm -f "$build_log"
    warn "$site: 'npm run build' gagal"
    # 137 = SIGKILL, hampir selalu kehabisan memori. Disebutkan terang-terangan
    # karena pesan npm-nya sendiri tidak pernah menyinggung itu.
    warn "  Kode keluar 137 atau 'Killed' = kehabisan memori, bukan kode yang salah."
    FAILED="${FAILED} ${site}"
    continue
  fi
  rm -f "$build_log"

  # node_modules bisa berisi puluhan ribu berkas dan tidak pernah dibaca nginx.
  # Kepemilikan dikembalikan ke www-data seperti yang dilakukan 20-nginx.sh,
  # supaya tidak ada berkas milik root yang tertinggal di direktori situs.
  chown -R www-data:www-data "$root"

  docroot="$(site_docroot "$site")"
  if [ -z "$(ls -A "$docroot" 2>/dev/null || true)" ]; then
    warn "$site: build selesai tetapi $docroot masih kosong."
    warn "  Periksa direktori keluaran yang sebenarnya, lalu setel SITE_ROOTS."
    FAILED="${FAILED} ${site}"
    continue
  fi

  refresh_site_conf "$site"
  ok "$site dibangun → $docroot"
  BUILT=1
done < <(split_csv "${NODE_SITES}")

if [ "$BUILT" -eq 1 ] && command -v nginx >/dev/null 2>&1; then
  nginx -t >/dev/null 2>&1 && systemctl reload nginx && ok "nginx dimuat ulang"
fi

if [ -n "$FAILED" ]; then
  echo ""
  warn "Situs yang TIDAK berhasil dibangun:${FAILED}"
  warn "  Situs itu akan menjawab 403 sampai buildnya berhasil."
  warn "  Ulangi setelah diperbaiki: sudo make node"
fi
