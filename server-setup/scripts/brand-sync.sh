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
# Setiap kali jalan:
#   1. ambil daftar domain aktif dari API
#   2. domain baru        -> terbitkan Origin Certificate, tulis vhost, aktifkan
#   3. domain yang hilang -> nonaktifkan vhost (sertifikatnya DIBIARKAN)
#   4. uji konfigurasi, reload, lalu laporkan hasilnya balik ke API
#
# ATURAN YANG TIDAK BOLEH DILANGGAR:
#   - `nginx -t` SELALU dijalankan sebelum reload. Konfigurasi tidak valid
#     membuat nginx menolak memuat SELURUHNYA — v1, v2, dan phpMyAdmin ikut
#     mati. Server tidak boleh pernah mati karena skrip ini.
#   - Hanya berkas berawalan `brand-` yang disentuh. Situs utama tidak pernah
#     ikut terhapus, betapa pun kacaunya daftar yang diterima.
#   - Sertifikat TIDAK dihapus saat domain dilepas. Ia berlaku 15 tahun, tidak
#     merugikan siapa pun bila menganggur, dan memasang ulang domain yang sama
#     jadi seketika.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-cert.sh
. "$SCRIPT_DIR/lib-cert.sh"

API_BASE="${API_BASE:-http://127.0.0.1:8080}"
SCHEDULER_TOKEN="${SCHEDULER_TOKEN:-}"
WEB_PORT="${WEB_PORT:-3000}"
API_PORT="${API_PORT:-8080}"
AVAIL="/etc/nginx/sites-available"
ENABLED="/etc/nginx/sites-enabled"
CERT_DIR="/etc/ssl/cloudflare"
PREFIX="brand-"

log()  { printf '[brand-sync] %s\n' "$*"; }
warn() { printf '[brand-sync] PERINGATAN: %s\n' "$*" >&2; }
die()  { printf '[brand-sync] GALAT: %s\n' "$*" >&2; exit 1; }

[ -n "$SCHEDULER_TOKEN" ] || die "SCHEDULER_TOKEN kosong - tidak bisa memanggil API"
command -v nginx >/dev/null || die "nginx tidak terpasang"
command -v curl  >/dev/null || die "curl tidak terpasang"
mkdir -p "$CERT_DIR"; chmod 700 "$CERT_DIR"

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

punya_sertifikat() { [ -s "${CERT_DIR}/$1.pem" ] && [ -s "${CERT_DIR}/$1.key" ]; }

# Vhost ditulis SETELAH sertifikatnya ada, dan langsung lengkap dengan blok
# 443. Menulis blok 443 yang menunjuk berkas yang belum ada membuat nginx
# menolak memuat seluruh konfigurasi.
tulis_vhost() {
  local domain="$1" berkas="${AVAIL}/${PREFIX}$1"
  local cert="${CERT_DIR}/${domain}.pem" key="${CERT_DIR}/${domain}.key"
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

log "domain aktif menurut API: $(printf '%s' "$domains" | grep -c . || true)"

berubah=0
while IFS= read -r domain; do
  [ -n "$domain" ] || continue
  case "$domain" in
    *[!a-z0-9.-]*) warn "domain diabaikan (karakter tidak sah): $domain"; continue ;;
  esac

  if ! punya_sertifikat "$domain"; then
    log "$domain: menerbitkan Origin Certificate"
    CERT_ERROR=""
    if issue_origin_cert "$domain" "${CERT_DIR}/${domain}.pem" "${CERT_DIR}/${domain}.key"; then
      lapor "$domain" "aktif" "Origin Certificate terbit, berlaku 15 tahun"
    else
      # Vhost HTTP tetap dipasang: situsnya sudah bisa dibuka lewat Cloudflare
      # (mode Flexible) sementara sertifikat origin-nya menyusul.
      lapor "$domain" "menunggu" "${CERT_ERROR:-sertifikat belum terbit - periksa CF_ORIGIN_CA_KEY}"
      warn "$domain: sertifikat belum terbit"
    fi
  fi

  berkas="${AVAIL}/${PREFIX}${domain}"
  tulis_vhost "$domain"

  if [ ! -L "${ENABLED}/${PREFIX}${domain}" ]; then
    ln -sf "$berkas" "${ENABLED}/${PREFIX}${domain}"
  fi
  berubah=1

  if punya_sertifikat "$domain"; then
    lapor "$domain" "aktif" "sertifikat terpasang"
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
