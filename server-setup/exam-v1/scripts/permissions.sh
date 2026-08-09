#!/usr/bin/env bash
# Izin berkas Laravel untuk Exam v1.
#
# Menerapkan resep izin Laravel yang lazim dipakai:
#
#   chown -R $USER:www-data .
#   find . -type f -exec chmod 664 {} \;
#   find . -type d -exec chmod 775 {} \;
#   chgrp -R www-data storage bootstrap/cache
#   chmod -R ug+rwx storage bootstrap/cache
#
# APA YANG DIBELI DAN APA YANG DIBAYAR — supaya keputusannya sadar, bukan
# diwarisi dari potongan perintah yang beredar di internet.
#
# Yang dibeli: pemilik bisa menyunting kode langsung di server, dan tidak ada
# lagi kegagalan "Permission denied" dari perintah artisan mana pun.
#
# Yang dibayar: direktori 775 dengan grup www-data berarti PHP boleh MEMBUAT
# BERKAS BARU di seluruh pohon aplikasi — termasuk public/, yang disajikan
# nginx dan menjalankan .php. Satu celah pada unggahan berubah dari "penyerang
# menaruh berkas" menjadi "penyerang menaruh .php lalu menjalankannya".
#
# Alternatif yang lebih rapat: kode dimiliki root dan hanya DIBACA www-data,
# sementara hanya storage/ dan bootstrap/cache yang boleh ditulisnya. Itu model
# yang dipakai skrip ini sebelumnya; diganti atas permintaan.
#
# .env DIKECUALIKAN dan tetap 640. `find -type f -exec chmod 664` akan
# membuatnya terbaca SELURUH pengguna di server, sedangkan isinya password
# database, APP_KEY, dan kredensial SMTP. Tidak ada langkah deploy yang menjadi
# lebih mudah karena berkas itu bisa dibaca orang lain.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
[ -d "$APP_ROOT" ] || die "$APP_ROOT tidak ada — jalankan dulu: sudo make app"

# Pemilik berkas.
#
# $USER tidak bisa dipakai di sini. Skrip ini berjalan di dalam `sudo make`,
# jadi $USER-nya sudah root — dan `chown -R root:www-data` bukan yang dimaksud
# resep aslinya. SUDO_USER menyimpan siapa yang sebenarnya mengetik sudo.
OWNER="${DEPLOY_USER:-${SUDO_USER:-root}}"
id "$OWNER" >/dev/null 2>&1 || die "pengguna '$OWNER' tidak ada — setel sendiri: sudo make permissions DEPLOY_USER=nama"

log "izin Laravel — pemilik ${OWNER}, grup www-data"

chown -R "${OWNER}:www-data" "$APP_ROOT"
ok "kepemilikan ${OWNER}:www-data"

# `-exec ... +` menggabungkan banyak berkas ke satu pemanggilan chmod, bukan
# `\;` yang memanggilnya SEKALI PER BERKAS. Hasilnya identik; bedanya vendor/
# sendirian berisi puluhan ribu berkas, dan versi `\;` mengubah langkah ini
# menjadi tunggu beberapa menit tiap deploy.
find "$APP_ROOT" -type f -exec chmod 664 {} +
find "$APP_ROOT" -type d -exec chmod 775 {} +
ok "berkas 664, direktori 775"

chgrp -R www-data "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"
chmod -R ug+rwx "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"
ok "storage & bootstrap/cache bisa ditulis"

# ── Yang harus dikembalikan setelah sapuan chmod ───────────────────────────

# 664 mencabut bit executable dari SEMUA berkas, termasuk binari di vendor/bin
# (pint, phpunit, dan apa pun yang dipanggil composer sebagai skrip). Kegagalan
# yang muncul kemudian berbunyi "Permission denied" pada nama paket, tanpa
# menyinggung bahwa penyebabnya adalah perintah chmod di langkah deploy.
if [ -d "$APP_ROOT/vendor/bin" ]; then
  find "$APP_ROOT/vendor/bin" -type f -exec chmod 775 {} +
  ok "vendor/bin bisa dieksekusi lagi"
fi
[ -f "$APP_ROOT/artisan" ] && chmod 775 "$APP_ROOT/artisan"

# .env dikecualikan — lihat alasannya di kepala berkas ini.
if [ -f "$APP_ENV_FILE" ]; then
  chown "${OWNER}:www-data" "$APP_ENV_FILE"
  chmod 640 "$APP_ENV_FILE"
  ok ".env tetap 640 (password database & SMTP ada di dalamnya)"
fi

# Repo tidak lagi dimiliki root, sedangkan `sudo make update` menjalankan git
# sebagai root. git menolaknya dengan "detected dubious ownership" dan
# membatalkan seluruh pembaruan — pesan yang tidak menyinggung chown sama
# sekali, meski itulah yang baru saja mengubah pemiliknya.
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx "$APP_ROOT"; then
  git config --global --add safe.directory "$APP_ROOT"
  ok "git safe.directory $APP_ROOT (agar 'sudo make update' tidak tertolak)"
else
  skip "git safe.directory $APP_ROOT"
fi

echo ""
warn "Direktori 775 + grup www-data berarti PHP boleh membuat berkas baru"
warn "  di seluruh pohon aplikasi, TERMASUK public/ yang menjalankan .php."
warn "  Jaga agar unggahan tidak pernah mendarat di public/ — aplikasi ini"
warn "  memakai FILESYSTEM_DISK=r2, jadi seharusnya memang tidak."
