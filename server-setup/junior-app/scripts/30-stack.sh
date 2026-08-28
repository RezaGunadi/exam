#!/usr/bin/env bash
# Nyalakan stack backend Kelas Junior: api + worker + beat + Redis.
#
# Skema database dan seluruh konten dibuat OTOMATIS saat service `api` start
# (RUN_MIGRATIONS=1 → create_all, SEED_ON_START=1 → seed_all). Keduanya
# idempoten dan ber-guard: mengisi yang kosong, melewati yang sudah ada.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_docker
assert_setup_env

[ -f "$BACKEND_DIR/docker-compose.yml" ] \
  || die "$BACKEND_DIR/docker-compose.yml tidak ada — jalankan dulu: sudo make app"
[ -f "$APP_ENV_FILE" ] \
  || die "$APP_ENV_FILE tidak ada — jalankan dulu: sudo make app"

# ── Override compose: restart policy yang tidak ada di repo aplikasi ───────
#
# docker-compose.yml tidak menyetel `restart:` untuk satu service pun. Setelah
# server di-reboot, tidak satu pun container kembali hidup — situsnya menjawab
# 502 sampai ada yang login dan mengetik `docker compose up -d`, dan tidak ada
# yang memberitahu bahwa itu yang perlu dilakukan.
#
# Ditulis sebagai override, bukan suntingan di docker-compose.yml: berkas itu
# milik repo aplikasi, dan suntingan di sana akan bentrok pada `git pull`
# berikutnya. Override didaftarkan ke .git/info/exclude supaya working tree
# tetap bersih — `make update` menolak menarik perubahan bila ada berkas yang
# belum di-commit, dan berkas yang kita buat sendiri tidak boleh jadi
# penyebabnya.
#
# PORT TIDAK DISEBUT DI SINI, dan itu disengaja. Untuk `ports`, Compose
# MENGGABUNGKAN daftar dari berkas dasar dan override — tidak menggantikannya.
# Menulis "127.0.0.1:8000:8000" di sini menghasilkan DUA pemetaan sekaligus:
# yang lama ke 0.0.0.0 tetap ada, dan yang kedua gagal mengikat port yang sudah
# dipakai. Yang membatasinya ke loopback adalah `"ip": "127.0.0.1"` di
# /etc/docker/daemon.json, dipasang scripts/05-docker.sh induk. Diverifikasi di
# bawah setelah stack menyala.
OVERRIDE="$BACKEND_DIR/docker-compose.override.yml"
TMP="$(mktemp)"
cat > "$TMP" <<'CONF'
# Ditulis oleh server-setup/junior-app — JANGAN disunting manual.
# Lihat scripts/30-stack.sh untuk alasan tiap baris di sini.

x-restart: &restart
  # unless-stopped, bukan always: container yang sengaja dimatikan dengan
  # `docker compose stop` tetap mati setelah reboot. `always` akan
  # menghidupkannya kembali dan membatalkan keputusan yang diambil sadar.
  restart: unless-stopped

services:
  redis:
    <<: *restart
  api:
    <<: *restart
  worker:
    <<: *restart
  beat:
    <<: *restart
CONF

if [ -f "$OVERRIDE" ] && cmp -s "$TMP" "$OVERRIDE"; then
  rm -f "$TMP"
  skip "override compose (restart unless-stopped)"
else
  backup_once "$OVERRIDE"
  mv "$TMP" "$OVERRIDE"
  chmod 644 "$OVERRIDE"
  ok "restart unless-stopped untuk keempat service"
fi

# restart policy tidak berarti apa-apa bila daemonnya sendiri tidak dinyalakan
# saat boot. Dua hal yang berbeda, dan yang kedua diam-diam mematikan yang
# pertama: containernya "akan" dihidupkan ulang oleh Docker yang tidak pernah
# jalan.
if ! systemctl is-enabled --quiet docker 2>/dev/null; then
  warn "layanan docker TIDAK aktif saat boot — restart policy tidak akan bekerja."
  warn "  Perbaiki: sudo systemctl enable docker"
fi

EXCLUDE="$APP_ROOT/.git/info/exclude"
if [ -f "$EXCLUDE" ] && ! grep -qx "${APP_SUBDIR}/docker-compose.override.yml" "$EXCLUDE"; then
  echo "${APP_SUBDIR}/docker-compose.override.yml" >> "$EXCLUDE"
  ok "override diabaikan git (lewat .git/info/exclude)"
fi

# ── Bangun & nyalakan ──────────────────────────────────────────────────────
# Build image bisa memakan lebih dari 1GB memori. Di VPS kecil tanpa swap,
# kernel mematikan prosesnya begitu saja — pesannya "Killed" atau kode keluar
# 137, tanpa menyinggung memori sama sekali.
TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
SWAP_MB="$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
if [ "$TOTAL_MB" -lt 2048 ] && [ "$SWAP_MB" -lt 1024 ]; then
  warn "RAM ${TOTAL_MB}MB, swap ${SWAP_MB}MB — build bisa dimatikan kernel (exit 137)."
  warn "    sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile"
  warn "    sudo mkswap /swapfile && sudo swapon /swapfile"
fi

log "docker compose up -d --build (build pertama makan beberapa menit)"
compose up -d --build || die "docker compose gagal — periksa: sudo make logs"
ok "stack dinyalakan"

# ── Tunggu sampai benar-benar melayani ─────────────────────────────────────
# Bukan basa-basi. Saat start pertama, `api` membuat 17 tabel lalu men-seed 184
# ikon SVG, kamus, kosmetik, dan modul awal — beberapa menit, dan selama itu
# port-nya sudah terbuka tetapi belum menjawab. Deploy yang berhenti di
# "stack dinyalakan" tampak berhasil sementara yang sebenarnya terjadi adalah
# seed yang berhenti di tengah karena kredensial database salah.
apt_install curl >/dev/null 2>&1 || true
log "menunggu $APP_SITE menjawab di 127.0.0.1:${APP_PORT}"
HEALTHY=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 "http://127.0.0.1:${APP_PORT}/api/v1/health" >/dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 5
done

if [ "$HEALTHY" -eq 1 ]; then
  ok "backend sehat — http://127.0.0.1:${APP_PORT}/api/v1/health"

  # Diperiksa, bukan diasumsikan. Yang membatasi port ke loopback adalah
  # "ip": "127.0.0.1" di /etc/docker/daemon.json — dan 05-docker.sh sengaja
  # TIDAK menimpa daemon.json yang sudah ada, jadi pada server yang berkasnya
  # sudah disunting orang, pengaturan itu bisa saja tidak pernah terpasang.
  #
  # Kalau terlewat, akibatnya tidak terlihat dari mana pun: situsnya bekerja
  # normal lewat https, sementara API yang sama juga terbuka di
  # http://IP-SERVER:8000 tanpa TLS. Tidak ada log yang menyebutkannya.
  if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "^(0\.0\.0\.0|\[::\]|\*):${APP_PORT}$"; then
    warn "PORT ${APP_PORT} TERBUKA DI SEMUA ANTARMUKA, bukan hanya 127.0.0.1."
    warn "  API ini terjangkau langsung dari internet tanpa TLS, dan ufw"
    warn "  TIDAK menghalanginya — Docker menulis aturan DNAT sendiri."
    warn "  Perbaiki di /etc/docker/daemon.json:"
    warn '    "ip": "127.0.0.1"'
    warn "  lalu: sudo systemctl restart docker && sudo make stack"
  else
    ok "port ${APP_PORT} hanya di loopback"
  fi
else
  warn "backend belum menjawab setelah 5 menit."
  warn "  Penyebab tersering, berurutan:"
  warn "   1. Container tidak bisa menyambung MySQL — DATABASE_URL salah, atau"
  warn "      MySQL belum mendengar di gateway Docker (cd $SETUP_DIR && sudo make mysql)"
  warn "   2. Seed awal masih berjalan (184 ikon SVG) — tunggu lalu periksa lagi"
  warn "   3. Build dimatikan kernel karena kehabisan memori (exit 137)"
  warn "  Lihat sebabnya: sudo make logs"
  echo ""
  compose ps || true
fi

echo ""
warn "App Flutter menunjuk ke API lewat lib/config/api_config.dart di repo yang"
warn "  sama — ganti baseUrl ke https://${APP_DOMAIN}/api/v1 sebelum rilis APK."
warn "  Server ini tidak membangun app Flutter; lihat game/RELEASE.md."
