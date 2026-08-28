#!/usr/bin/env bash
# Kode & konfigurasi backend Kelas Junior: klon, database, .env.
#
# Yang TIDAK dikerjakan di sini: memasang Python. Backend berjalan di dalam
# container (image python:3.12-slim), jadi runtime-nya ikut image — bukan
# dipasang di host. Python host dipasang 20-python.sh, dan itu untuk skrip
# perawatan (seed_all.py, export_bundled_svgs.py), bukan untuk melayani.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_apt
assert_setup_env

log "Kelas Junior — ${APP_DOMAIN}"

apt_install git openssl

# ── Kode ───────────────────────────────────────────────────────────────────
# Setup induk sudah mengklon situs yang punya entri di SITE_REPOS, termasuk
# situs container — di sanalah docker-compose.yml berada. Klon di sini hanya
# untuk keadaan sebaliknya: entri itu belum diisi, atau `make nginx` belum
# pernah dijalankan. Keduanya berakhir sama, dan urutan menjalankannya bebas.
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
    die "gagal mengklon $APP_SITE"
  fi
  rm -f "$clone_log"
  ok "klon $APP_SITE dari $APP_REPO"
fi

# Situs container TIDAK dijadikan milik www-data. nginx tidak pernah membaca
# direktori ini, dan `sudo git -C ... pull` akan ditolak dengan "detected
# dubious ownership" begitu pemiliknya bukan root.
[ -d "$BACKEND_DIR" ] \
  || die "$BACKEND_DIR tidak ada — SUBDIR=${APP_SUBDIR} salah, atau klonnya tidak lengkap"
[ -f "$BACKEND_DIR/docker-compose.yml" ] \
  || die "$BACKEND_DIR/docker-compose.yml tidak ada — periksa isi repo"
ok "backend di $BACKEND_DIR"

# Ikon yang di-bake ke image. Tanpa direktori ini seed berjalan tanpa keluhan
# lalu menghasilkan konten tanpa ikon — kekurangan yang baru terlihat di layar
# anak yang memakainya, bukan di log deploy.
if [ -d "$BACKEND_DIR/seed_media/icons" ]; then
  ICON_COUNT="$(find "$BACKEND_DIR/seed_media/icons" -type f | wc -l)"
  if [ "$ICON_COUNT" -lt 100 ]; then
    warn "seed_media/icons hanya berisi ${ICON_COUNT} berkas (harusnya ~184)"
  else
    ok "seed_media/icons (${ICON_COUNT} berkas)"
  fi
else
  warn "$BACKEND_DIR/seed_media/icons tidak ada — konten akan ter-seed tanpa ikon"
fi

# ── Database ───────────────────────────────────────────────────────────────
# DB `kidlearn` TERPISAH dari database Laravel, di instans MySQL yang sama.
# utf8mb4 wajib: kontennya dwibahasa dan memuat emoji.
[ -n "${DB_USER:-}" ] || die "DB_USER kosong di $SETUP_DIR/.env"
command -v mysql >/dev/null 2>&1 \
  || die "klien MySQL tidak ada — jalankan dulu: cd $SETUP_DIR && sudo make mysql"

if mysql -u"$DB_USER" -p"${DB_PASSWORD:-}" -e "USE \`${APP_DB}\`" >/dev/null 2>&1; then
  TABLES="$(mysql -u"$DB_USER" -p"${DB_PASSWORD:-}" -N -B \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${APP_DB}';" 2>/dev/null || echo 0)"
  ok "database $APP_DB (${TABLES:-0} tabel)"
else
  mysql -u"$DB_USER" -p"${DB_PASSWORD:-}" \
    -e "CREATE DATABASE \`${APP_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
    >/dev/null 2>&1 || {
      warn "tidak bisa membuat database $APP_DB dengan pengguna $DB_USER"
      warn "  Tambahkan '${APP_DB}' ke DATABASES di $SETUP_DIR/.env lalu:"
      warn "    cd $SETUP_DIR && sudo make mysql"
      die "database belum siap"
    }
  ok "database $APP_DB dibuat (utf8mb4)"
fi

# MySQL harus mendengar di gateway jembatan Docker, bukan cuma loopback.
#
# Container menyambung lewat host.docker.internal, yang oleh compose dipetakan
# ke host-gateway (biasanya 172.17.0.1). MySQL yang hanya terikat 127.0.0.1
# MENOLAK koneksi itu — dan grant untuk '172.%' tidak menolong sama sekali,
# karena permintaannya tidak pernah sampai. Setup induk sudah mengurusnya,
# TETAPI hanya bila docker0 sudah ada saat `make mysql` dijalankan. Server yang
# Dockernya dipasang belakangan tetap terikat loopback, dan kegagalannya muncul
# sebagai "Can't connect to MySQL server" di log container, jauh dari sini.
DOCKER_GW="$(ip -4 -o addr show docker0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)"
if [ -z "$DOCKER_GW" ]; then
  warn "jembatan docker0 belum ada — container belum tentu bisa menyambung ke MySQL"
elif ! ss -lnt 2>/dev/null | grep -q "${DOCKER_GW}:3306"; then
  warn "MySQL tidak mendengar di ${DOCKER_GW}:3306 (gateway Docker)."
  warn "  Container akan gagal menyambung. Perbaiki dengan:"
  warn "    cd $SETUP_DIR && sudo make mysql"
else
  ok "MySQL terjangkau container (${DOCKER_GW}:3306)"
fi

# ── .env aplikasi ──────────────────────────────────────────────────────────
# TIDAK PERNAH ditulis ulang setelah ada. Di dalamnya ada JWT_SECRET — mengganti
# nilai itu mencabut seluruh sesi yang sedang berjalan, dan setiap anak yang
# sedang bermain harus login ulang tanpa tahu sebabnya.
#
# Password di-URL-encode sebelum masuk DATABASE_URL. Nilai bawaan di
# .env induk saja sudah memuat "@" (@Reza1234), dan DSN
# `mysql+pymysql://user:@Reza1234@host/db` diurai SQLAlchemy dengan host yang
# salah — bukan sebagai galat kredensial, melainkan "Name or service not known"
# yang menuduh jaringan.
urlencode() {
  local s="$1" i c out=""
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out="${out}${c}" ;;
      *)               out="${out}$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}

if [ -f "$APP_ENV_FILE" ]; then
  skip ".env aplikasi (sunting sendiri di $APP_ENV_FILE)"
else
  [ -f "$BACKEND_DIR/.env.example" ] || die ".env.example tidak ada di dalam klon"
  cp "$BACKEND_DIR/.env.example" "$APP_ENV_FILE"

  DB_USER_ENC="$(urlencode "$DB_USER")"
  DB_PASS_ENC="$(urlencode "${DB_PASSWORD:-}")"
  # host.docker.internal, bukan 127.0.0.1: dari dalam container, loopback adalah
  # container itu sendiri. docker-compose.yml sudah memetakan nama itu ke
  # host-gateway lewat extra_hosts.
  set_env_kv "$APP_ENV_FILE" DATABASE_URL \
    "mysql+pymysql://${DB_USER_ENC}:${DB_PASS_ENC}@host.docker.internal:3306/${APP_DB}?charset=utf8mb4"

  # Nilai bawaan .env.example ("change-this-to-a-long-random-string" dan
  # "admin123") sama untuk semua orang yang pernah mengklon repo ini. JWT yang
  # bisa ditebak berarti siapa pun bisa menandatangani token milik anak mana pun.
  set_env_kv "$APP_ENV_FILE" JWT_SECRET "$(openssl rand -hex 32)"
  set_env_kv "$APP_ENV_FILE" ADMIN_USER "${ADMIN_USER:-admin}"
  set_env_kv "$APP_ENV_FILE" ADMIN_PASSWORD "$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"

  ok ".env aplikasi dibuat — JWT_SECRET & ADMIN_PASSWORD acak"
  warn "Password panel admin ada di $APP_ENV_FILE:"
  warn "  sudo grep ADMIN_ $APP_ENV_FILE"
fi

# Dibaca daemon Docker sebagai root saat compose menguraikan ${...}. Tidak ada
# pengguna lain yang perlu membacanya, dan isinya password MySQL + JWT_SECRET.
chown root:root "$APP_ENV_FILE"
chmod 600 "$APP_ENV_FILE"

# ── Yang masih harus diisi tangan ──────────────────────────────────────────
if [ -z "$(get_env_kv "$APP_ENV_FILE" R2_ENDPOINT || true)" ]; then
  warn "R2_* kosong — 184 ikon SVG disajikan dari /media di dalam container."
  warn "  Itu berfungsi, tetapi asetnya ikut mati bila volume container hilang."
  warn "  Isi R2_ENDPOINT/R2_ACCESS_KEY/R2_SECRET_KEY/R2_BUCKET/R2_PUBLIC_BASE"
  warn "  di $APP_ENV_FILE lalu: sudo make restart"
fi
if [ -z "$(get_env_kv "$APP_ENV_FILE" SMTP_HOST || true)" ]; then
  warn "SMTP_HOST kosong — kode reset password hanya DICETAK KE LOG, tidak dikirim."
  warn "  Orang tua yang lupa password tidak akan pernah menerima kodenya."
fi

ok "kode & konfigurasi Kelas Junior siap di $BACKEND_DIR"
