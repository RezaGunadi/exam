#!/usr/bin/env bash
# Batas unggahan PHP untuk cuandariponsel.
#
# KENAPA HARUS DIUBAH. PortfolioController memvalidasi berkas video dengan
# `max:204800` — 200 MB. Batas bawaan PHP adalah upload_max_filesize=2M dan
# post_max_size=8M, jadi setiap unggahan clip ditolak jauh sebelum aturan
# validasi itu sempat dibaca.
#
# DAN KEGAGALANNYA TIDAK BERBUNYI SEPERTI BATAS UKURAN. Begitu post_max_size
# terlampaui, PHP MENGOSONGKAN $_POST seluruhnya — termasuk token CSRF. Yang
# diterima pengunjung adalah "419 Page Expired", yang membaca seperti masalah
# sesi; orang lalu menghabiskan waktu memeriksa SESSION_DRIVER dan cookie,
# padahal yang salah adalah satu angka di php.ini.
#
# Ditulis sebagai drop-in untuk SETIAP versi PHP yang terpasang, bukan untuk
# satu versi saja: `sudo make php` di direktori induk memindahkan seluruh server
# ke versi lain, dan berkas yang hanya ada di conf.d versi lama ikut ditinggal
# tanpa satu pun pesan. Jalankan ulang skrip ini setelah menaikkan versi PHP —
# `make deploy` dan `make update` sudah melakukannya.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root

# 210M/220M, bukan pas 200M: post_max_size harus LEBIH BESAR daripada
# upload_max_filesize, karena badan permintaan memuat berkasnya plus seluruh
# field lain plus overhead multipart. Disetel sama persis, unggahan tepat pada
# batas maksimum gagal — dan hanya yang tepat pada batas, sehingga terbaca
# seperti gangguan acak.
UPLOAD_MAX="${UPLOAD_MAX:-210M}"
POST_MAX="${POST_MAX:-220M}"

log "batas unggahan PHP (${UPLOAD_MAX} / ${POST_MAX})"

TMP="$(mktemp)"
cat > "$TMP" <<INI
; Ditulis oleh server-setup/repost-app — JANGAN disunting manual.
;
; Unggahan portofolio cuandariponsel divalidasi sampai 200MB
; (PortfolioController: max:204800). Batas bawaan PHP 2M/8M menolaknya lebih
; dulu, dan yang terlihat pengunjung adalah "419 Page Expired", bukan pesan
; tentang ukuran berkas.
upload_max_filesize = ${UPLOAD_MAX}
post_max_size = ${POST_MAX}

; Unggahan 200MB lewat koneksi rumahan bisa memakan menit, bukan detik. Batas
; bawaan 30 detik memutusnya di tengah jalan.
max_execution_time = 300
max_input_time = 300

; Laravel memvalidasi & memindahkan berkasnya; 128M bawaan cukup ketat begitu
; ada antrean yang ikut jalan di proses yang sama.
memory_limit = 256M
INI

FOUND=0
CHANGED=0
for dir in /etc/php/*/fpm/conf.d; do
  [ -d "$dir" ] || continue
  FOUND=1
  target="${dir}/99-repost-uploads.ini"
  if [ -f "$target" ] && cmp -s "$TMP" "$target"; then
    skip "$target"
    continue
  fi
  cp "$TMP" "$target"
  chmod 644 "$target"
  ok "$target"
  CHANGED=1
done
rm -f "$TMP"

if [ "$FOUND" -eq 0 ]; then
  warn "tidak ada /etc/php/*/fpm/conf.d — PHP-FPM belum terpasang?"
  warn "  Jalankan dulu: cd $SETUP_DIR && sudo make nginx"
  exit 0
fi

# FPM membaca conf.d hanya saat start. `reload` cukup — ia memuat ulang
# konfigurasi tanpa memutus permintaan yang sedang berjalan.
if [ "$CHANGED" -eq 1 ]; then
  reloaded=0
  while read -r unit; do
    [ -n "$unit" ] || continue
    systemctl is-active --quiet "$unit" 2>/dev/null || continue
    systemctl reload "$unit" && { ok "$unit dimuat ulang"; reloaded=1; }
  done < <(systemctl list-unit-files --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}')
  [ "$reloaded" -eq 1 ] \
    || warn "tidak ada PHP-FPM yang dimuat ulang — batas baru belum berlaku"
fi

warn "Batas ini berlaku untuk SELURUH situs PHP di server, bukan hanya yang ini."
warn "  Yang dinaikkan cuma langit-langitnya; tiap situs tetap dibatasi"
warn "  client_max_body_size di server block-nya masing-masing (32M untuk situs"
warn "  yang dikelola setup induk)."
