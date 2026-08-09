#!/usr/bin/env bash
# Pindahkan seluruh server ke versi PHP yang ditulis di .env (PHP_VERSION).
#
# MENGGANTI VERSI PHP ADA TIGA BAGIAN, dan yang terlupa selalu bagian ketiga:
#   1. paketnya dipasang;
#   2. `php` di terminal menunjuk ke sana;
#   3. SERVER BLOCK NGINX menunjuk ke socket FPM-nya.
#
# Bagian 3 yang menentukan versi mana yang benar-benar melayani pengunjung.
# Tanpa itu `php -v` menjawab 8.2 dengan meyakinkan sementara setiap halaman
# web masih dijalankan 8.1 — selisih yang tidak menimbulkan satu pun pesan
# error, dan baru ketahuan dari aplikasi yang menolak jalan.
#
# Skripnya IDEMPOTEN: dijalankan ulang pada versi yang sudah aktif tidak
# mengubah apa pun dan tidak membuat cadangan palsu.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
load_env "$ROOT_DIR"

require_root
require_apt

# ── Versi yang dituju ──────────────────────────────────────────────────────
# .env yang dibuat sebelum variabel ini ada belum memuatnya. Ditambahkan di
# sini, bukan sekadar diperingatkan, supaya server yang sudah berjalan ikut
# terurus tanpa menyunting berkas dengan tangan.
ensure_env_var "$ROOT_DIR" PHP_VERSION 8.2 \
  "Versi PHP untuk semua situs — ubah lalu jalankan: sudo make php"

PHP_VERSION="${PHP_VERSION:-8.2}"
case "$PHP_VERSION" in
  [0-9].[0-9] | [0-9].[0-9][0-9]) ;;
  *) die "PHP_VERSION='${PHP_VERSION}' tidak berbentuk <mayor>.<minor> (contoh: 8.2)" ;;
esac

log "PHP ${PHP_VERSION}"

# ── Repo ───────────────────────────────────────────────────────────────────
# Paket meta tanpa versi (php-fpm) selalu mengikuti bawaan distro: 8.1 di
# Ubuntu 22.04, 8.3 di 24.04, 8.2 di Debian 12. Versi lain harus datang dari
# repo pihak ketiga — ondrej untuk Ubuntu, sury untuk Debian. Keduanya dikelola
# orang yang sama dan menjadi sumber paket PHP de facto di kedua distro.
add_php_repo() {
  local codename id
  apt_install lsb-release ca-certificates curl
  codename="$(lsb_release -sc 2>/dev/null || true)"
  id="$(. /etc/os-release 2>/dev/null && echo "${ID:-}")"

  # Keluaran perintah repo TIDAK dibuang. Sebelumnya semuanya diarahkan ke
  # /dev/null, sehingga "tidak ada koneksi ke launchpad", "PPA tidak punya paket
  # untuk rilis ini", dan "kunci GPG ditolak" — tiga kegagalan dengan perbaikan
  # yang sama sekali berbeda — terlihat identik dari luar: satu baris GAGAL
  # tanpa sebab.
  local repo_log
  repo_log="$(mktemp)"

  if [ "$id" = "ubuntu" ]; then
    apt_install software-properties-common
    log "menambahkan ppa:ondrej/php"
    if ! add-apt-repository -y ppa:ondrej/php >"$repo_log" 2>&1; then
      sed 's/^/       /' "$repo_log"
      rm -f "$repo_log"
      die "gagal menambahkan ppa:ondrej/php"
    fi
    ok "repo ppa:ondrej/php"
  else
    [ -n "$codename" ] || die "codename distro tidak terbaca — repo PHP tidak bisa ditambahkan"
    apt_install apt-transport-https gnupg
    log "menambahkan packages.sury.org"
    if ! curl -fsSLo /usr/share/keyrings/deb.sury.org-php.gpg \
         https://packages.sury.org/php/apt.gpg 2>"$repo_log"; then
      sed 's/^/       /' "$repo_log"
      rm -f "$repo_log"
      die "gagal mengunduh kunci packages.sury.org"
    fi
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${codename} main" \
      > /etc/apt/sources.list.d/php.list
    ok "repo packages.sury.org (${codename})"
  fi

  log "memperbarui indeks paket"
  if ! apt-get update >"$repo_log" 2>&1; then
    sed 's/^/       /' "$repo_log"
    warn "apt-get update gagal — lanjut dengan indeks paket yang ada"
  fi
  rm -f "$repo_log"
}

if ! php_pkg_available "$PHP_VERSION"; then
  add_php_repo
fi

if ! php_pkg_available "$PHP_VERSION"; then
  # Alasan sebenarnya dicetak, bukan disuruh cari sendiri. LC_ALL=C supaya
  # keluarannya sama di server mana pun — dan supaya bisa disalin ke orang lain
  # tanpa diterjemahkan setengah-setengah.
  #
  # `|| true` di tiap baris BUKAN hiasan: perintahnya memang gagal (itu
  # sebabnya kita di sini), dan dengan `set -o pipefail` kegagalan itu
  # menghentikan skrip di tengah diagnosis — pesan GAGAL yang menjelaskan
  # semuanya tidak pernah sampai tercetak.
  warn "apt-cache policy php${PHP_VERSION}-fpm:"
  { LC_ALL=C apt-cache policy "php${PHP_VERSION}-fpm" 2>&1 || true; } | sed 's/^/       /'
  warn "percobaan pemasangan:"
  { LC_ALL=C apt-get install -s -y "php${PHP_VERSION}-fpm" 2>&1 || true; } \
    | tail -5 | sed 's/^/       /'
  warn "berkas repo yang menyebut php:"
  grep -rls 'ondrej\|sury' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null \
    | sed 's/^/       /' || echo "       (tidak ada)"
  die "php${PHP_VERSION} tetap tidak tersedia"
fi

# ── Paket ──────────────────────────────────────────────────────────────────
# Daftarnya = yang selama ini dipasang 20-nginx.sh, ditambah bcmath dan intl
# yang diminta Laravel. Ekstensi yang hilang hanya terlihat saat fitur yang
# memakainya dipanggil — jauh setelah setup dinyatakan berhasil.
PKGS=()
for ext in fpm cli mysql mbstring zip gd curl xml bcmath intl; do
  PKGS+=("php${PHP_VERSION}-${ext}")
done
apt_install "${PKGS[@]}"

# ── Layanan ────────────────────────────────────────────────────────────────
FPM_UNIT="php${PHP_VERSION}-fpm.service"
SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

systemctl enable --now "$FPM_UNIT" >/dev/null 2>&1 || true

# Socket baru muncul beberapa saat setelah layanannya start. Diperiksa berulang,
# bukan sekali: pemeriksaan tunggal tepat setelah `systemctl start` gagal pada
# server yang lambat, dan pesannya menuduh pemasangan yang sebenarnya berhasil.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -S "$SOCK" ] && break
  sleep 1
done
if [ ! -S "$SOCK" ]; then
  warn "Periksa: systemctl status ${FPM_UNIT}"
  die "socket ${SOCK} tidak muncul — PHP-FPM ${PHP_VERSION} belum berjalan"
fi
ok "PHP-FPM ${PHP_VERSION} ($SOCK)"

# ── php di terminal ────────────────────────────────────────────────────────
# Ini yang dipakai composer, artisan, dan cron — bukan yang dipakai nginx.
if [ -x "/usr/bin/php${PHP_VERSION}" ]; then
  update-alternatives --install /usr/bin/php php "/usr/bin/php${PHP_VERSION}" 100 \
    >/dev/null 2>&1 || true
  if update-alternatives --set php "/usr/bin/php${PHP_VERSION}" >/dev/null 2>&1; then
    ok "php (CLI) → /usr/bin/php${PHP_VERSION}"
  else
    warn "gagal menyetel alternatives untuk php — periksa: update-alternatives --display php"
  fi

  # PATH bisa memuat php lain yang mendahului /usr/bin (XAMPP, kompilasi
  # sendiri, atau symlink sisa pemasangan lama). update-alternatives tidak
  # menyentuhnya, dan `php -v` akan tetap menjawab versi lama meski semua
  # langkah di atas berhasil.
  cli_path="$(command -v php 2>/dev/null || true)"
  if [ -n "$cli_path" ] && [ "$cli_path" != "/usr/bin/php" ]; then
    warn "php di PATH menunjuk ke ${cli_path}, bukan /usr/bin/php"
    warn "  Versi CLI tidak akan berubah selama berkas itu masih ada."
  fi
fi

# ── Server block nginx ─────────────────────────────────────────────────────
# Inilah bagian yang menentukan versi mana yang melayani pengunjung.
#
# sites-enabled ikut disisir: isinya biasanya symlink ke sites-available (dan
# sudah tertangani), tetapi server block yang dibuat dengan tangan kadang
# berupa berkas biasa di sana — dan berkas itulah yang dibaca nginx.
#
# Boleh dijalankan sebelum `make nginx`: tanpa nginx tidak ada yang perlu
# diarahkan, dan berhenti dengan error di sini hanya akan menghalangi orang
# yang memang baru sampai tahap memasang PHP.
if ! command -v nginx >/dev/null 2>&1; then
  skip "server block (nginx belum terpasang — jalankan: sudo make nginx)"
else
  log "mengarahkan server block ke ${SOCK}"
  php_conf_changed=0
  for conf in /etc/nginx/sites-available/* /etc/nginx/sites-enabled/*; do
    [ -f "$conf" ] || continue        # -f mengikuti symlink; symlink ke berkas
    [ -L "$conf" ] && continue        # yang sama tidak perlu disunting dua kali

    # Berkas cadangan DILEWATI. backup_once menaruh <nama>.orig tepat di
    # sebelah aslinya, di direktori yang sedang disisir ini — tanpa penyaringan,
    # jalan kedua akan menyunting cadangannya sendiri dan menerbitkan
    # <nama>.orig.orig. Yang hilang justru satu-satunya salinan yang dibutuhkan
    # untuk kembali ke keadaan semula. nginx sendiri tidak pernah membacanya:
    # yang dimuat hanya symlink di sites-enabled.
    case "$conf" in
      *.orig|*.bak|*~|*.dpkg-*|*.ucf-*) continue ;;
    esac

    grep -q 'fastcgi_pass[[:space:]]\{1,\}unix:' "$conf" 2>/dev/null || continue

    # Hasilnya dibandingkan utuh, bukan diperiksa dengan "apakah socket baru
    # sudah disebut". Berkas yang memuat DUA fastcgi_pass — satu sudah benar,
    # satu masih menunjuk versi lama — lolos dari pemeriksaan semacam itu dan
    # ditinggalkan setengah jadi. Membandingkan seluruh isi juga yang membuat
    # target ini idempoten: tidak ada cadangan palsu dan tidak ada reload yang
    # tidak perlu saat dijalankan ulang.
    tmp="$(mktemp)"
    sed "s|\(fastcgi_pass[[:space:]]\{1,\}unix:\)[^;]*;|\1${SOCK};|g" "$conf" > "$tmp"
    if cmp -s "$tmp" "$conf"; then
      rm -f "$tmp"
      skip "$(basename "$conf")"
      continue
    fi
    backup_once "$conf"
    # Isinya disalin ke berkas yang sudah ada, BUKAN `mv` — memindahkan berkas
    # dari mktemp akan membawa serta mode 600 miliknya, dan nginx (yang membaca
    # sebagai www-data setelah menurunkan hak) tidak lagi bisa membacanya.
    cat "$tmp" > "$conf"
    rm -f "$tmp"
    ok "$(basename "$conf") → php${PHP_VERSION}"
    php_conf_changed=1
  done

  # Diuji SEBELUM reload dan sebelum FPM lama dimatikan. Konfigurasi yang tidak
  # valid membuat nginx menolak MEMUAT SELURUHNYA — termasuk situs lain yang
  # tadinya sehat — jadi lebih baik berhenti di sini dengan socket lama yang
  # masih hidup daripada meneruskan dan mematikan semuanya sekaligus.
  log "menguji konfigurasi nginx"
  nginx -t >/dev/null 2>&1 || {
    nginx -t || true
    die "konfigurasi nginx tidak valid — tidak ada yang di-reload"
  }

  if [ "$php_conf_changed" -eq 1 ]; then
    systemctl reload nginx
    ok "nginx dimuat ulang"
  else
    skip "reload nginx (tidak ada server block yang berubah)"
  fi
fi

# ── Versi lama ─────────────────────────────────────────────────────────────
# Dimatikan SETELAH nginx menunjuk ke socket baru, bukan sebelumnya — urutan
# terbalik berarti situs mati di sela-sela kedua langkah.
#
# Dimatikan, bukan di-purge. `apt purge php8.1-*` bisa ikut mencabut paket meta
# php-fpm beserta apa pun yang bergantung padanya, dan itu keputusan yang
# terlalu besar untuk diambil diam-diam oleh skrip setup.
log "menonaktifkan PHP-FPM versi lain"
found_old=0
while read -r unit; do
  [ -n "$unit" ] || continue
  [ "$unit" = "$FPM_UNIT" ] && continue
  systemctl is-enabled --quiet "$unit" 2>/dev/null \
    || systemctl is-active --quiet "$unit" 2>/dev/null \
    || continue
  systemctl disable --now "$unit" >/dev/null 2>&1 || true
  ok "$unit dimatikan"
  found_old=1

  # Socket yatim menipu find_php_sock: `[ -S ]` tetap benar untuk berkas socket
  # yang layanannya sudah mati, dan glob-nya mengambil hasil pertama menurut
  # abjad — php8.1 sebelum php8.2. Server block berikutnya akan diarahkan ke
  # socket yang tidak ada yang mendengarkan, dan situsnya menjawab 502.
  old_ver="${unit#php}"; old_ver="${old_ver%-fpm.service}"
  old_sock="/run/php/php${old_ver}-fpm.sock"
  if [ -S "$old_sock" ] && ! systemctl is-active --quiet "$unit" 2>/dev/null; then
    rm -f "$old_sock"
    ok "socket usang $old_sock dihapus"
  fi
done < <(systemctl list-unit-files --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}')
[ "$found_old" -eq 1 ] || skip "versi PHP lain (tidak ada yang aktif)"

echo ""
ok "PHP aktif: $(php -v 2>/dev/null | head -1 || echo 'tidak terbaca')"
ok "nginx memakai: ${SOCK}"
echo ""
warn "Paket PHP versi lama TIDAK dihapus — hanya dimatikan."
warn "  Setelah yakin semua situs sehat, buang sendiri bila mau:"
warn "    sudo apt purge 'php8.1-*' && sudo apt autoremove"
