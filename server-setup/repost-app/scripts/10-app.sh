#!/usr/bin/env bash
# Kode aplikasi cuandariponsel: klon, dependensi, .env, database, migrasi, izin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_apt
assert_not_managed_by_setup

log "cuandariponsel — ${APP_DOMAIN}"

# ── PHP ────────────────────────────────────────────────────────────────────
# composer.json aplikasi ini meminta php ^8.2 (Laravel 12). Diperiksa di awal,
# bukan dibiarkan muncul sebagai kegagalan composer di tengah jalan — pesan
# composer menyebut daftar paket yang tidak cocok, bukan penyebabnya.
command -v php >/dev/null 2>&1 || die "PHP belum terpasang — jalankan: sudo make php (di direktori induk)"
if ! php -r 'exit(version_compare(PHP_VERSION, "8.2.0", "<") ? 1 : 0);'; then
  warn "PHP terpasang: $(php -r 'echo PHP_VERSION;')"
  warn "  Laravel 12 butuh minimal 8.2 (lihat composer.json)."
  die "naikkan versinya dulu: cd $SETUP_DIR && sudo make php"
fi
ok "PHP $(php -r 'echo PHP_VERSION;')"

apt_install git unzip curl ca-certificates openssl

# ── Composer ───────────────────────────────────────────────────────────────
# Diambil dari getcomposer.org, bukan dari apt: versi apt pada Ubuntu 22.04
# tertinggal cukup jauh, dan sebagian paket Laravel 12 meminta
# composer-plugin-api yang lebih baru — kegagalannya berupa daftar konflik
# dependensi yang tidak menyinggung versi composer sama sekali.
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
    warn "  Klon dijalankan sebagai root, jadi kunci SSH yang dipakai ada di"
    warn "  /root/.ssh — BUKAN milik pengguna yang mengetik sudo. Periksa:"
    warn "    sudo ssh -T git@github.com"
    warn "  Repo publik? Pakai URL HTTPS:"
    warn "    sudo make app REPO=https://github.com/RezaGunadi/cuan_dari_ponsel.git"
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

  # .env.example memakai sqlite untuk pengembangan lokal, dan barisnya ada DUA
  # (satu aktif, satu dikomentari untuk mysql). set_env_kv meringkasnya jadi
  # satu — dibiarkan keduanya, yang menang ditentukan urutan pembacaan dotenv,
  # bukan oleh apa yang tertulis. Situs ini akan diam-diam memakai berkas
  # sqlite yang tidak pernah dibackup.
  set_env_kv "$APP_ENV_FILE" DB_CONNECTION mysql
  set_env_kv "$APP_ENV_FILE" DB_HOST 127.0.0.1
  set_env_kv "$APP_ENV_FILE" DB_PORT 3306
  set_env_kv "$APP_ENV_FILE" DB_DATABASE "$APP_DB"
  set_env_kv "$APP_ENV_FILE" DB_USERNAME "${DB_USER:-}"
  set_env_kv "$APP_ENV_FILE" DB_PASSWORD "${DB_PASSWORD:-}"

  # Ketiganya memakai tabel yang dibuat migrasi — bukan berkas di storage/ —
  # supaya sesi tidak hilang saat cache dibersihkan dan antrean tetap ada
  # setelah restart.
  set_env_kv "$APP_ENV_FILE" SESSION_DRIVER database
  set_env_kv "$APP_ENV_FILE" QUEUE_CONNECTION database
  set_env_kv "$APP_ENV_FILE" CACHE_STORE database

  # retry_after bawaan 90 detik TERLALU PENDEK untuk pekerjaan di antrean ini.
  # CompressPortfolioClip menjalankan FFmpeg atas clip sampai 200MB; begitu
  # lewat 90 detik, Laravel menganggap pekerjanya mati dan MENYERAHKAN ULANG
  # pekerjaan yang sama ke pekerja lain. Dua FFmpeg lalu menulis berkas yang
  # sama, dan yang selesai belakangan menghapus keluaran yang sudah dipakai
  # yang pertama. Nilainya harus di ATAS --timeout pekerja (lihat 35-queue.sh).
  set_env_kv "$APP_ENV_FILE" DB_QUEUE_RETRY_AFTER 1800

  # APP_KEY dari .env.example adalah kunci yang sama untuk semua orang yang
  # pernah mengklon repo ini. Dikosongkan agar dibuatkan yang baru di bawah.
  set_env_kv "$APP_ENV_FILE" APP_KEY ""

  ok ".env aplikasi dibuat (APP_ENV=production, APP_DEBUG=false, MySQL)"
fi

# Dibaca PHP-FPM sebagai www-data, tidak perlu bisa dibaca siapa pun selain itu.
# permissions.sh mempertahankan mode ini; ia satu-satunya berkas yang
# dikecualikan dari sapuan `chmod 664`.
chgrp www-data "$APP_ENV_FILE"
chmod 640 "$APP_ENV_FILE"

# ── Dependensi ─────────────────────────────────────────────────────────────
# --no-dev: paket pengembangan tidak dipasang di produksi. Beberapa di antaranya
# (laravel/pail, nunomaduro/collision) mendaftarkan service provider yang
# membuka informasi debug.
#
# laravel/tinker ada di "require", bukan "require-dev", jadi ia SELAMAT dari
# --no-dev — dan itu penting: pembuatan pengguna sistem platform di bawah
# memakainya.
log "composer install"
( cd "$APP_ROOT" && COMPOSER_ALLOW_SUPERUSER=1 composer install \
    --no-dev --optimize-autoloader --no-interaction --no-progress ) \
  || die "composer install gagal"
ok "dependensi terpasang"

# ── Database ───────────────────────────────────────────────────────────────
# MIGRATE=yes ADALAH BAWAANNYA di sini, kebalikan dari exam-v1.
#
# Databasenya baru dan memang dibangun dari nol, dan riwayat migrasinya rapi:
# 34 berkas dengan penamaan berurut (0001_01_01_*, lalu 2026_07_*), tidak ada
# yang merujuk tabel yang baru dibuat migrasi bertanggal lebih akhir.
case "${MIGRATE:-yes}" in
  [Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|0) DO_MIGRATE=0 ;;
  *)                               DO_MIGRATE=1 ;;
esac

db_query() { mysql -u"$DB_USER" -p"${DB_PASSWORD:-}" -N -B -e "$1" 2>/dev/null; }

[ -n "${DB_USER:-}" ] || die "DB_USER kosong di $SETUP_DIR/.env"
command -v mysql >/dev/null 2>&1 \
  || die "klien MySQL tidak ada — jalankan dulu: cd $SETUP_DIR && sudo make mysql"

if mysql -u"$DB_USER" -p"${DB_PASSWORD:-}" -e "USE \`${APP_DB}\`" >/dev/null 2>&1; then
  TABLES="$(db_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${APP_DB}';" || echo 0)"
  ok "database $APP_DB (${TABLES:-0} tabel)"
elif [ "$DO_MIGRATE" -eq 1 ]; then
  mysql -u"$DB_USER" -p"${DB_PASSWORD:-}" \
    -e "CREATE DATABASE \`${APP_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
    >/dev/null 2>&1 || {
      warn "tidak bisa membuat database $APP_DB dengan pengguna $DB_USER"
      warn "  Tambahkan '${APP_DB}' ke DATABASES di $SETUP_DIR/.env lalu:"
      warn "    cd $SETUP_DIR && sudo make mysql"
      die "database belum siap"
    }
  ok "database $APP_DB dibuat (utf8mb4)"
else
  warn "database '$APP_DB' tidak ada, dan migrasi dimatikan."
  warn "  Database yang ada di server ini:"
  db_query "SHOW DATABASES;" | grep -vE '^(information_schema|mysql|performance_schema|sys)$' | sed 's/^/       /'
  warn "  Tunjuk yang benar:  sudo make app DB_NAME=nama_database"
  die "database tidak ditemukan"
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
#   2. Ayam-dan-telur: Laravel menolak boot tanpa APP_KEY ("No application
#      encryption key has been specified"), sehingga artisan tidak bisa dipakai
#      untuk membuat kunci yang dibutuhkannya sendiri.
#
# Hasilnya identik: key:generate memanggil Encrypter::generateKey(), yang untuk
# AES-256-CBC mengembalikan 32 byte acak lalu di-base64.
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
# dipasang.
if [ -L "$APP_WEBROOT/storage" ]; then
  skip "symlink public/storage"
elif [ -e "$APP_WEBROOT/storage" ]; then
  warn "$APP_WEBROOT/storage sudah ada tetapi bukan symlink — dibiarkan apa adanya"
else
  mkdir -p "$APP_ROOT/storage/app/public"
  ln -s "$APP_ROOT/storage/app/public" "$APP_WEBROOT/storage"
  ok "symlink public/storage → storage/app/public"
fi

# ── Migrasi ────────────────────────────────────────────────────────────────
if [ "$DO_MIGRATE" -eq 1 ]; then
  # --force karena tidak ada TTY untuk menjawab konfirmasi produksi.
  log "menjalankan migrasi"
  artisan migrate --force || die "migrasi gagal"
  ok "migrasi selesai"
else
  skip "migrasi (MIGRATE=no)"
fi

# ── Data awal ──────────────────────────────────────────────────────────────
# SEED=minimal ADALAH BAWAANNYA, dan itu bukan sikap hati-hati yang berlebihan.
#
# DatabaseSeeder repo ini membuat DELAPAN akun demo dengan password harfiah
# "password" — termasuk owner@cuandariponsel.local (role owner, akses penuh)
# dan admin@test.com. Dijalankan di produksi, situs ini terbuka dengan
# kredensial yang bisa ditebak siapa pun yang pernah membaca reponya, dan
# tidak ada satu pun pesan yang menyebutkan bahwa akun-akun itu ada.
#
# Yang benar-benar DIBUTUHKAN aplikasi hanya dua:
#
#   1. TaskTypeSeeder — katalog jenis tugas. Idempoten (updateOrCreate per
#      slug) dan hanya memperbarui kolom struktural, jadi harga yang sudah
#      disetel owner lewat panel tidak ditimpa.
#   2. Pengguna sistem platform — pemilik dompet yang menampung komisi.
#      WalletService::platformWallet() melemparkan RuntimeException tanpanya,
#      dan itu terjadi pada kampanye PERTAMA yang disetujui, bukan saat deploy.
case "${SEED:-minimal}" in
  [Nn][Oo]|[Nn][Oo][Nn][Ee]|0)
    skip "data awal (SEED=no)"
    ;;
  [Aa][Ll][Ll]|[Dd][Ee][Mm][Oo])
    warn "SEED=all — DatabaseSeeder membuat 8 akun demo berpassword 'password'."
    warn "  Jangan pernah dipakai di server yang bisa dijangkau publik."
    artisan db:seed --force || die "seeding gagal"
    ok "data awal lengkap (termasuk akun demo)"
    ;;
  *)
    log "katalog jenis tugas (TaskTypeSeeder)"
    artisan db:seed --class='Database\Seeders\TaskTypeSeeder' --force \
      || die "TaskTypeSeeder gagal — aplikasi tidak bisa jalan tanpa katalog ini"
    ok "katalog jenis tugas siap"

    # Pengguna sistem platform, dibuat dengan potongan kode yang SAMA seperti di
    # DatabaseSeeder: password acak 40 karakter dan is_active=false, karena ini
    # bukan akun untuk login — ia hanya memegang buku besar komisi.
    #
    # PHP-nya ditulis memakai kutip GANDA seluruhnya, sehingga seluruh cuplikan
    # muat dalam satu string bash berkutip tunggal. Versi campur kutip di sini
    # adalah cara paling mudah menghasilkan kode PHP yang rusak diam-diam —
    # dan yang rusak baru terlihat sebagai galat sintaks dari tinker, jauh dari
    # baris yang menyusunnya.
    log "pengguna sistem platform (dompet komisi)"
    PLATFORM_PHP='$u = \App\Models\User::firstOrCreate(["email" => config("cdp.platform_email")], ["name" => "Kas Platform", "password" => \Illuminate\Support\Facades\Hash::make(\Illuminate\Support\Str::random(40)), "role" => \App\Models\User::ROLE_OWNER, "is_active" => false]); app(\App\Services\WalletService::class)->walletFor($u); echo "platform_user_id=" . $u->id . PHP_EOL;'

    if out="$(artisan tinker --execute="$PLATFORM_PHP" 2>&1)"; then
      echo "$out" | grep -E '^platform_user_id=' | sed 's/^/  ok /' || true
      ok "pengguna sistem platform siap"
      warn "Isi CDP_PLATFORM_USER_ID di $APP_ENV_FILE dengan id di atas."
      warn "  Tanpa itu setiap komisi dicari lewat lookup email — berfungsi,"
      warn "  tetapi satu kueri tambahan pada tiap kiriman yang disetujui."
    else
      echo "$out" | tail -10 | sed 's/^/       /'
      warn "gagal membuat pengguna sistem platform."
      warn "  Kampanye PERTAMA yang disetujui akan gagal dengan"
      warn "  'Platform system user not found'. Buat manual lalu ulangi:"
      warn "    cd $APP_ROOT && sudo -u www-data php artisan db:seed --force"
    fi
    ;;
esac

# ── Cache konfigurasi ──────────────────────────────────────────────────────
# DIJALANKAN di sini, tidak seperti exam-v1 — dan bedanya bisa diperiksa, bukan
# soal selera: aplikasi ini TIDAK punya satu pun pemanggilan env() di luar
# config/. Itu syarat tunggal yang membuat config:cache aman; begitu ada satu
# saja, nilainya berubah jadi null tanpa pesan error apa pun.
#
# `route:cache` TIDAK dijalankan: routes/web.php memakai closure sebagai aksi
# route (baris `fn () => view('welcome', ...)`), dan closure tidak bisa
# diserialkan — perintahnya gagal, bukan menghasilkan cache yang salah.
#
# KONSEKUENSINYA: menyunting .env tidak lagi berpengaruh sampai cache dibuat
# ulang. Disebutkan lagi di akhir deploy, karena inilah kejutan paling umum
# dari langkah ini.
artisan config:clear >/dev/null 2>&1 || true
artisan config:cache >/dev/null 2>&1 && ok "konfigurasi di-cache" \
  || warn "config:cache gagal — situs tetap jalan, hanya lebih lambat"
artisan view:clear >/dev/null 2>&1 || true

# Berkas cache yang baru dibuat artisan mewarisi umask, bukan izin direktorinya.
chgrp -R www-data "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"
chmod -R ug+rwX "$APP_ROOT/storage" "$APP_ROOT/bootstrap/cache"

ok "kode cuandariponsel siap di $APP_ROOT"

# ── Yang masih harus diisi tangan ──────────────────────────────────────────
if [ "$(get_env_kv "$APP_ENV_FILE" CDP_PORTFOLIO_DISK || echo local)" = "r2" ]; then
  # config/filesystems.php mendefinisikan disk r2 dengan driver s3, tetapi
  # composer.lock repo ini TIDAK memuat league/flysystem-aws-s3-v3 — hanya
  # flysystem dan flysystem-local. Unggahan ke r2 akan gagal dengan "Driver
  # [s3] is not supported", dan perbaikannya ada di repo aplikasi:
  #   composer require league/flysystem-aws-s3-v3
  if [ ! -d "$APP_ROOT/vendor/league/flysystem-aws-s3-v3" ]; then
    warn "CDP_PORTFOLIO_DISK=r2 tetapi league/flysystem-aws-s3-v3 TIDAK terpasang."
    warn "  Unggahan bukti kerja & portofolio akan gagal: 'Driver [s3] is not supported'."
    warn "  Perbaikannya di repo aplikasi, bukan di sini:"
    warn "    composer require league/flysystem-aws-s3-v3"
  fi
fi
if [ -z "$(get_env_kv "$APP_ENV_FILE" MANUAL_BANK_ACCOUNT || true)" ]; then
  warn "MANUAL_BANK_ACCOUNT kosong, sementara XENDIT_SECRET_KEY juga kosong."
  warn "  Top-up manual adalah satu-satunya jalur yang aktif, dan pemberi kerja"
  warn "  tidak akan melihat nomor rekening tujuan transfer."
fi
