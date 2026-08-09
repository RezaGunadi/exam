#!/usr/bin/env bash
# Pasang HTTPS untuk setiap situs yang punya domain di SITE_DOMAINS.
#
# SERTIFIKATNYA CLOUDFLARE ORIGIN CERTIFICATE, BUKAN LET'S ENCRYPT.
#
# certbot memvalidasi lewat port 80 — yang di sini sudah diproksikan Cloudflare.
# Pemasangan pertama biasanya berhasil, lalu perpanjangan otomatisnya gagal diam
# -diam berbulan-bulan kemudian, tepat saat tidak ada yang memperhatikan. Origin
# Certificate berlaku 15 tahun dan tidak punya jadwal perpanjangan yang bisa
# gagal sama sekali.
#
# Sertifikatnya didapat dengan salah satu dari dua cara, dicoba berurutan:
#
#   1. Berkas yang Anda salin sendiri ke certs/<domain>.pem dan .key
#      (SSL/TLS → Origin Server → Create Certificate di dashboard).
#   2. Otomatis lewat API Origin CA, bila CF_ORIGIN_CA_KEY diisi di .env.
#      Kuncinya diambil dari dashboard: My Profile → API Tokens → Origin CA Key.
#
# Yang TIDAK diurus skrip ini: record DNS. Domainnya harus sudah mengarah ke
# server ini (proxied/awan oranye) sebelum HTTPS-nya bisa dipakai pengunjung.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
load_env "$ROOT_DIR"

require_root
require_apt

CERT_DIR=/etc/ssl/cloudflare
LOCAL_CERTS="$ROOT_DIR/certs"

if [ -z "${SITE_DOMAINS:-}" ]; then
  # Ditulis mencolok, bukan satu baris yang hanyut di antara ratusan baris
  # keluaran lain. Situs yang tetap HTTP-only sementara mode SSL Cloudflare
  # sudah dinaikkan menghasilkan error 521 — dan penyebabnya persis di sini,
  # beberapa menit sebelumnya, tanpa ada yang sempat menyadarinya.
  echo ""
  warn "═══════════════════════════════════════════════════════════"
  warn "  HTTPS TIDAK DIPASANG — SITE_DOMAINS kosong di .env"
  warn ""
  warn "  Tidak ada satu pun situs yang akan mendengarkan di port 443."
  warn "  Bila mode SSL Cloudflare sudah Full/Full (strict), pengunjung"
  warn "  menerima error 521 sampai baris ini diisi."
  warn ""
  warn "  Tambahkan ke .env lalu: sudo make ssl"
  warn "    SITE_DOMAINS=exam_v2=exam.kelasprivat.id"
  warn "    CF_ORIGIN_CA_KEY=v1.0-..."
  warn "═══════════════════════════════════════════════════════════"
  echo ""
  exit 0
fi

apt_install openssl jq curl ca-certificates

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

PHP_SOCK="$(find_php_sock || true)"
[ -n "$PHP_SOCK" ] || die "PHP-FPM belum berjalan — jalankan dulu: sudo make nginx"

# Kirim CSR ke Origin CA dengan satu header autentikasi tertentu.
cf_post_certificate() {
  curl -sS --max-time 30 -X POST \
    'https://api.cloudflare.com/client/v4/certificates' \
    -H "$2" \
    -H 'Content-Type: application/json' \
    --data "$1" 2>/dev/null || true
}

# Minta Origin Certificate baru ke Cloudflare.
#
# CSR-nya dibuat di sini dan kunci privatnya TIDAK PERNAH meninggalkan server —
# Cloudflare hanya menerima permintaan penandatanganan, bukan kuncinya.
issue_origin_cert() {
  local domain="$1" cert="$2" key="$3"
  local tmpdir body resp
  tmpdir="$(mktemp -d)"
  chmod 700 "$tmpdir"

  if ! openssl req -new -newkey rsa:2048 -nodes \
        -keyout "$tmpdir/key" -out "$tmpdir/csr" \
        -subj "/CN=${domain}" >/dev/null 2>&1; then
    warn "gagal membuat CSR untuk $domain"
    rm -rf "$tmpdir"
    return 1
  fi

  # requested_validity 5475 hari = 15 tahun, nilai terpanjang yang diterima.
  body="$(jq -n --arg csr "$(cat "$tmpdir/csr")" --arg host "$domain" \
    '{hostnames: [$host], requested_validity: 5475,
      request_type: "origin-rsa", csr: $csr}')"

  # Endpoint ini menerima DUA bentuk kredensial, dan keduanya memakai header
  # yang sama sekali berbeda:
  #
  #   Origin CA Key (diawali v1.0-)          → X-Auth-User-Service-Key
  #   API Token dengan izin SSL & Certificates → Authorization: Bearer
  #
  # Dashboard Cloudflare sekarang lebih sering mengarahkan orang ke API Token,
  # sementara dokumentasi lama menyebut Origin CA Key. Menebak dari bentuk
  # nilainya tidak cukup andal — keduanya dicoba, karena jawaban Cloudflare
  # untuk header yang salah hanyalah "Authentication failed", yang sama sekali
  # tidak menyinggung bahwa masalahnya ada di JENIS kunci.
  local h1="X-Auth-User-Service-Key: ${CF_ORIGIN_CA_KEY}"
  local h2="Authorization: Bearer ${CF_ORIGIN_CA_KEY}"
  case "$CF_ORIGIN_CA_KEY" in
    v1.0-*) : ;;                      # bentuk Origin CA Key — urutan sudah pas
    *) h1="Authorization: Bearer ${CF_ORIGIN_CA_KEY}"
       h2="X-Auth-User-Service-Key: ${CF_ORIGIN_CA_KEY}" ;;
  esac

  resp="$(cf_post_certificate "$body" "$h1")"
  if [ "$(echo "$resp" | jq -r '.success // false' 2>/dev/null)" != "true" ]; then
    local alt
    alt="$(cf_post_certificate "$body" "$h2")"
    if [ "$(echo "$alt" | jq -r '.success // false' 2>/dev/null)" = "true" ]; then
      resp="$alt"
    else
      warn "Cloudflare menolak permintaan sertifikat untuk $domain:"
      echo "$resp" | jq -r '.errors[]?.message' 2>/dev/null | sed 's/^/       /' \
        || echo "       (jawaban tidak terbaca)"
      warn "  Kedua bentuk kredensial ditolak. CF_ORIGIN_CA_KEY harus salah satu:"
      warn "    a) Origin CA Key — My Profile > API Tokens > Origin CA Key (v1.0-...)"
      warn "    b) API Token dengan izin User > Origin CA Keys, atau"
      warn "       Zone > SSL and Certificates > Edit"
      rm -rf "$tmpdir"
      return 1
    fi
  fi

  # Kunci dipasang lebih dulu dengan mode 600. Sertifikat tanpa kunci tidak
  # berguna, tapi kunci yang sempat terbaca siapa pun sudah tidak bisa ditarik.
  install -m 600 "$tmpdir/key" "$key"
  echo "$resp" | jq -r '.result.certificate' > "$cert"
  chmod 644 "$cert"
  rm -rf "$tmpdir"
  ok "Origin Certificate $domain diterbitkan (berlaku 15 tahun)"
  ISSUED_VIA_API=1
}

# Pastikan sertifikat sebuah domain tersedia di $CERT_DIR.
ensure_cert() {
  local domain="$1" cert="$2" key="$3"

  if [ -s "$cert" ] && [ -s "$key" ]; then
    # 30 hari, bukan 0: sertifikat yang kedaluwarsa besok pagi sama saja dengan
    # yang sudah kedaluwarsa — keduanya membuat situs tidak bisa dibuka.
    if openssl x509 -in "$cert" -noout -checkend 2592000 >/dev/null 2>&1; then
      skip "sertifikat $domain"
      return 0
    fi
    warn "sertifikat $domain habis dalam <30 hari — diambil ulang"
  fi

  if [ -s "$LOCAL_CERTS/${domain}.pem" ] && [ -s "$LOCAL_CERTS/${domain}.key" ]; then
    install -m 600 "$LOCAL_CERTS/${domain}.key" "$key"
    install -m 644 "$LOCAL_CERTS/${domain}.pem" "$cert"
    ok "sertifikat $domain dipasang dari certs/"
    return 0
  fi

  if [ -n "${CF_ORIGIN_CA_KEY:-}" ]; then
    log "meminta Origin Certificate untuk $domain"
    issue_origin_cert "$domain" "$cert" "$key" && return 0
    return 1
  fi

  warn "belum ada sertifikat untuk $domain — situsnya tetap HTTP saja"
  echo "       Pilih salah satu:"
  echo "       a) isi CF_ORIGIN_CA_KEY di .env, lalu: sudo make ssl"
  echo "       b) buat manual di dashboard Cloudflare (SSL/TLS → Origin Server),"
  echo "          simpan sebagai certs/${domain}.pem dan certs/${domain}.key,"
  echo "          lalu: sudo make ssl"
  return 1
}

ISSUED_VIA_API=0
INSTALLED=0

log "HTTPS per situs"
while read -r site; do
  [ -n "$site" ] || continue
  domain="$(kv_lookup "$site" "${SITE_DOMAINS:-}")"
  [ -n "$domain" ] || continue

  cert="${CERT_DIR}/${domain}.pem"
  key="${CERT_DIR}/${domain}.key"

  # Satu situs yang gagal TIDAK boleh menjatuhkan sisanya: server yang separuh
  # situsnya HTTPS jauh lebih baik daripada yang setupnya berhenti di tengah.
  if ensure_cert "$domain" "$cert" "$key"; then
    write_site_conf "$site" "$domain" "$PHP_SOCK" "$cert" "$key"
    INSTALLED=$((INSTALLED + 1))
  fi
done < <(split_csv "${SITES:-}")

if [ "$INSTALLED" -eq 0 ]; then
  warn "tidak ada situs yang dipasangi HTTPS"
  exit 0
fi

# Sertifikat dari Origin CA membuktikan situsnya MEMANG di belakang Cloudflare,
# jadi real_ip dipasang sekalian. Tanpa itu setiap permintaan terlihat berasal
# dari alamat edge Cloudflare dan pembatas "3 kali salah login" mengunci semua
# pengunjung sekaligus — kegagalan yang tidak menimbulkan pesan error apa pun.
if [ "$ISSUED_VIA_API" -eq 1 ] && [ ! -f /etc/nginx/conf.d/cloudflare-realip.conf ]; then
  log "memasang real_ip Cloudflare (menyusul penerbitan Origin Certificate)"
  bash "$SCRIPT_DIR/25-cloudflare-realip.sh"
fi

log "menguji konfigurasi nginx"
nginx -t || die "konfigurasi nginx tidak valid — tidak ada yang di-reload"
systemctl reload nginx
ok "nginx dimuat ulang — $INSTALLED situs melayani HTTPS"

echo ""
echo "Dua hal terakhir yang HANYA bisa dilakukan di dashboard Cloudflare:"
echo "  1. Record DNS tiap domain mengarah ke IP server ini (proxied)."
echo "  2. SSL/TLS → Overview → mode Full (strict)."
echo ""
echo "Naikkan ke Full (strict) SETELAH langkah di atas selesai. Dinaikkan lebih"
echo "awal, pengunjung akan menerima error 525 alih-alih halaman situs."
