#!/usr/bin/env bash
# ============================================================================
# brand-sync.sh — menyelaraskan domain branding premium dengan nginx + SSL.
#
# Dijalankan DI HOST oleh systemd timer, bukan oleh aplikasi.
#
# Aplikasi berjalan di dalam container. Memberinya akses tulis ke
# /etc/nginx/sites-available dan wewenang me-reload nginx berarti satu celah di
# aplikasi web menjadi kendali penuh atas seluruh server — termasuk situs v1
# yang menumpang di mesin yang sama. Karena itu arahnya dibalik: aplikasi hanya
# MENGUMUMKAN domain mana yang seharusnya aktif; skrip ini yang menariknya lalu
# mengerjakan nginx dan sertifikatnya.
#
# CARANYA MENGIKUTI SSL_METHOD, SAMA DENGAN 35-ssl.sh.
#
# Versi pertama skrip ini memaksa Cloudflare Origin Certificate. Di server ini
# itu keliru: SSL_METHOD=letsencrypt, dan kesebelas situs yang sudah jalan
# memakai /etc/letsencrypt. Domain branding akan menjadi satu-satunya yang
# memakai cara berbeda — atau, kalau kunci API-nya kedaluwarsa, satu-satunya
# yang tidak punya TLS sama sekali.
#
# URUTANNYA PENTING DAN TIDAK BOLEH DIBALIK:
#
#   1. tulis vhost HTTP saja, aktifkan, reload
#   2. BARU minta sertifikat
#   3. bila dapat, tulis ulang vhost lengkap dengan 443, reload lagi
#
# Let's Encrypt memverifikasi dengan MENGHUBUNGI domainnya di port 80. Tanpa
# vhost yang sudah menjawab lebih dulu, verifikasinya jatuh ke situs lain yang
# kebetulan menjadi server default — dan gagal terus tanpa sebab yang terlihat.
# Urutan ini juga benar untuk Origin Certificate, yang terbit lewat API dan
# tidak peduli pada urutan sama sekali.
#
# ATURAN YANG TIDAK BOLEH DILANGGAR:
#   - `nginx -t` SELALU dijalankan sebelum reload. Konfigurasi tidak valid
#     membuat nginx menolak memuat SELURUHNYA — v1, v2, dan phpMyAdmin ikut
#     mati. Server tidak boleh pernah mati karena skrip ini.
#   - Hanya berkas berawalan `brand-` yang disentuh. Situs utama tidak pernah
#     ikut terhapus, betapa pun kacaunya daftar yang diterima.
#   - Sertifikat TIDAK dihapus saat domain dilepas. Memasang ulang domain yang
#     sama jadi seketika, dan sertifikat menganggur tidak merugikan siapa pun.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-cert.sh
. "$SCRIPT_DIR/lib-cert.sh"

API_BASE="${API_BASE:-http://127.0.0.1:8080}"
SCHEDULER_TOKEN="${SCHEDULER_TOKEN:-}"
WEB_PORT="${WEB_PORT:-3000}"
API_PORT="${API_PORT:-8080}"
SSL_METHOD="${SSL_METHOD:-cloudflare}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
AVAIL="/etc/nginx/sites-available"
ENABLED="/etc/nginx/sites-enabled"
CERT_DIR="/etc/ssl/cloudflare"
STATE_DIR="/var/lib/brand-sync"
PREFIX="brand-"

log()  { printf '[brand-sync] %s\n' "$*"; }
warn() { printf '[brand-sync] PERINGATAN: %s\n' "$*" >&2; }
die()  { printf '[brand-sync] GALAT: %s\n' "$*" >&2; exit 1; }

[ -n "$SCHEDULER_TOKEN" ] || die "SCHEDULER_TOKEN kosong - tidak bisa memanggil API"
command -v nginx >/dev/null || die "nginx tidak terpasang"
command -v curl  >/dev/null || die "curl tidak terpasang"
mkdir -p "$CERT_DIR"; chmod 700 "$CERT_DIR"
mkdir -p "$STATE_DIR"; chmod 750 "$STATE_DIR"

# Jeda setelah gagal. Timernya berdenyut tiap 5 menit; tanpa jeda, satu domain
# yang DNS-nya belum diarahkan akan meminta sertifikat 288 kali sehari.
#
# Untuk Let's Encrypt itu bukan sekadar berisik: batasnya 5 kegagalan validasi
# per host per jam, dan melewatinya memblokir domain itu berjam-jam — termasuk
# saat DNS-nya akhirnya benar. Jedanya jauh lebih panjang daripada Cloudflare,
# yang penerbitannya lewat API dan tidak punya batas serupa.
if [ "$SSL_METHOD" = "letsencrypt" ]; then
  JEDA_GAGAL=21600   # 6 jam
else
  JEDA_GAGAL=3600    # 1 jam
fi

boleh_coba_lagi() {
  local penanda="${STATE_DIR}/$1.gagal" umur
  [ -f "$penanda" ] || return 0
  umur=$(( $(date +%s) - $(stat -c %Y "$penanda" 2>/dev/null || echo 0) ))
  [ "$umur" -ge "$JEDA_GAGAL" ]
}
tandai_gagal()  { touch "${STATE_DIR}/$1.gagal"; }
hapus_penanda() { rm -f "${STATE_DIR}/$1.gagal"; }

lapor() {
  local domain="$1" status="$2" pesan="${3:-}"
  pesan="$(printf '%s' "$pesan" | tr -d '"\\' | tr '\n' ' ' | cut -c1-400)"
  curl -fsS -m 15 -X POST \
    "${API_BASE}/api/scheduler/brand-status?token=${SCHEDULER_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "{\"domain\":\"${domain}\",\"status\":\"${status}\",\"message\":\"${pesan}\"}" \
    >/dev/null 2>&1 || warn "gagal melaporkan status ${domain}"
}

# Uji SEBELUM reload. Reload dengan konfigurasi rusak membuat nginx menolak
# memuat seluruhnya, dan seluruh situs di server ini ikut mati.
uji_dan_reload() {
  if ! nginx -t >/dev/null 2>&1; then
    warn "nginx -t GAGAL - tidak ada yang di-reload"
    nginx -t 2>&1 | sed 's/^/[brand-sync]   /' >&2 || true
    return 1
  fi
  systemctl reload nginx
}

# Lokasi sertifikat berbeda menurut caranya. Dipusatkan di sini supaya tidak
# ada tempat lain yang menebak-nebak jalurnya.
cert_pem() {
  if [ "$SSL_METHOD" = "letsencrypt" ]; then
    printf '/etc/letsencrypt/live/%s/fullchain.pem' "$1"
  else
    printf '%s/%s.pem' "$CERT_DIR" "$1"
  fi
}
cert_key() {
  if [ "$SSL_METHOD" = "letsencrypt" ]; then
    printf '/etc/letsencrypt/live/%s/privkey.pem' "$1"
  else
    printf '%s/%s.key' "$CERT_DIR" "$1"
  fi
}
punya_sertifikat() { [ -s "$(cert_pem "$1")" ] && [ -s "$(cert_key "$1")" ]; }

# Minta sertifikat Let's Encrypt untuk satu domain branding.
#
# `certonly`, bukan `--nginx` penuh: server block-nya ditulis skrip ini, dan
# dua pihak yang menyunting berkas yang sama akan saling menimpa.
#
# www ikut disertakan dalam SATU sertifikat karena vhost-nya melayani keduanya;
# tanpa itu pengunjung yang mengetik www menerima peringatan sertifikat. Bila
# www-nya belum diarahkan, seluruh permintaan gagal — maka dicoba ulang tanpa
# www, karena domain telanjang yang jalan jauh lebih baik daripada tidak sama
# sekali.
issue_letsencrypt_brand() {
  local domain="$1" reg out
  command -v certbot >/dev/null || { CERT_ERROR="certbot tidak terpasang di server"; return 1; }

  if [ -n "$CERTBOT_EMAIL" ]; then
    reg="-m $CERTBOT_EMAIL"
  else
    reg="--register-unsafely-without-email"
  fi

  # shellcheck disable=SC2086
  if out="$(certbot certonly --nginx --non-interactive --agree-tos $reg \
              -d "$domain" -d "www.$domain" 2>&1)"; then
    return 0
  fi
  # shellcheck disable=SC2086
  if out="$(certbot certonly --nginx --non-interactive --agree-tos $reg \
              -d "$domain" 2>&1)"; then
    warn "$domain: sertifikat terbit tanpa www (www belum diarahkan)"
    return 0
  fi
  CERT_ERROR="$(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
  return 1
}

minta_sertifikat() {
  local domain="$1"
  CERT_ERROR=""
  if [ "$SSL_METHOD" = "letsencrypt" ]; then
    issue_letsencrypt_brand "$domain"
  else
    issue_origin_cert "$domain" "$(cert_pem "$domain")" "$(cert_key "$domain")"
  fi
}

# Vhost ditulis dalam dua bentuk. Blok 443 hanya ditulis bila sertifikatnya
# BENAR-BENAR ada di disk: menunjuk berkas yang belum ada membuat nginx menolak
# memuat seluruh konfigurasinya, dan seluruh situs di server ini ikut mati.
tulis_vhost() {
  local domain="$1" berkas="${AVAIL}/${PREFIX}$1"
  local cert key
  cert="$(cert_pem "$domain")"
  key="$(cert_key "$domain")"
  {
    cat <<CONF
# Dibuat otomatis oleh brand-sync.sh - JANGAN diubah tangan.
# Sumber kebenarannya: branding sekolah di panel owner.
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};
CONF
    if punya_sertifikat "$domain"; then
      cat <<CONF
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${domain} www.${domain};

    ssl_certificate     ${cert};
    ssl_certificate_key ${key};
CONF
    fi
    cat <<CONF

    client_max_body_size 64m;

    location /api/ {
        proxy_pass http://127.0.0.1:${API_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout      300s;
        proxy_send_timeout      300s;
        proxy_request_buffering off;
    }

    location /_next/static/ {
        proxy_pass http://127.0.0.1:${WEB_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }

    location / {
        proxy_pass http://127.0.0.1:${WEB_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        "upgrade";
        # Host DITERUSKAN apa adanya - inilah yang dipakai aplikasi untuk
        # memilih branding. Menggantinya dengan nama tetap akan membuat semua
        # domain menampilkan merek yang sama.
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }
}
CONF
  } > "$berkas"
}

respons="$(curl -fsS -m 20 "${API_BASE}/api/scheduler/brand-domains?token=${SCHEDULER_TOKEN}")" \
  || die "gagal mengambil daftar domain dari API"

# Tanpa jq untuk bagian ini: bentuk JSON-nya dikendalikan handler kita sendiri.
domains="$(printf '%s' "$respons" \
  | grep -oE '"domain"[[:space:]]*:[[:space:]]*"[^"]+"' \
  | sed -E 's/.*"([^"]+)"$/\1/' | sort -u || true)"

log "cara SSL: ${SSL_METHOD}; domain aktif menurut API: $(printf '%s' "$domains" | grep -c . || true)"

berubah=0
while IFS= read -r domain; do
  [ -n "$domain" ] || continue
  case "$domain" in
    *[!a-z0-9.-]*) warn "domain diabaikan (karakter tidak sah): $domain"; continue ;;
  esac

  # LANGKAH 1 — vhost HTTP lebih dulu, supaya tantangan Let's Encrypt punya
  # yang menjawab di port 80. Selalu ditulis ulang: isinya ikut berubah begitu
  # sertifikatnya ada.
  tulis_vhost "$domain"
  if [ ! -L "${ENABLED}/${PREFIX}${domain}" ]; then
    ln -sf "${AVAIL}/${PREFIX}${domain}" "${ENABLED}/${PREFIX}${domain}"
  fi
  berubah=1

  if punya_sertifikat "$domain"; then
    hapus_penanda "$domain"
    lapor "$domain" "aktif" "sertifikat terpasang"
    continue
  fi

  if ! boleh_coba_lagi "$domain"; then
    log "$domain: percobaan terakhir gagal, menunggu jeda"
    continue
  fi

  # LANGKAH 2 — vhost-nya harus sudah hidup sebelum sertifikat diminta.
  if ! uji_dan_reload; then
    die "konfigurasi tidak valid - nginx TIDAK di-reload, perbaiki dulu"
  fi
  berubah=0

  log "$domain: meminta sertifikat"
  if minta_sertifikat "$domain"; then
    hapus_penanda "$domain"
    # LANGKAH 3 — tulis ulang, sekarang lengkap dengan blok 443.
    tulis_vhost "$domain"
    berubah=1
    lapor "$domain" "aktif" "sertifikat terbit"
  else
    tandai_gagal "$domain"
    # Situsnya TETAP bisa dibuka lewat HTTP sementara sertifikatnya menyusul,
    # jadi ini "menunggu", bukan "gagal".
    lapor "$domain" "menunggu" "${CERT_ERROR:-sertifikat belum terbit - periksa apakah DNS sudah mengarah ke server ini}"
    warn "$domain: sertifikat belum terbit, dicoba lagi setelah $((JEDA_GAGAL / 3600)) jam"
  fi
done <<< "$domains"

# Lepas yang sudah tidak terdaftar. HANYA berkas berawalan brand-.
for link in "${ENABLED}/${PREFIX}"*; do
  [ -e "$link" ] || continue
  nama="$(basename "$link")"
  domain="${nama#"$PREFIX"}"
  if printf '%s\n' "$domains" | grep -qx "$domain"; then
    continue
  fi
  log "$domain: tidak lagi terdaftar - dinonaktifkan"
  rm -f "$link"
  berubah=1
done

if [ "$berubah" = "1" ]; then
  if uji_dan_reload; then
    log "nginx di-reload"
  else
    die "konfigurasi tidak valid - nginx TIDAK di-reload, perbaiki dulu"
  fi
fi

log "selesai"
