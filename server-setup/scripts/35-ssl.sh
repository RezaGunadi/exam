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

# Pasang hook yang memuat ulang nginx setiap kali certbot memperpanjang.
#
# INI YANG MEMBUAT JALUR LET'S ENCRYPT AMAN DIPAKAI.
#
# nginx membaca berkas sertifikat SEKALI saat start. Tanpa reload, perpanjangan
# certbot berhasil di disk tetapi tidak pernah sampai ke pengunjung — situs
# tetap menyajikan sertifikat lama sampai benar-benar kedaluwarsa, tanpa satu
# pun pesan error di sepanjang jalan.
install_renewal_hook() {
  local hook=/etc/letsencrypt/renewal-hooks/deploy/10-reload-nginx.sh
  [ -f "$hook" ] && { skip "hook perpanjangan certbot"; return 0; }
  mkdir -p "$(dirname "$hook")"
  cat > "$hook" <<'HOOK'
#!/bin/sh
# Dipasang oleh server-setup. Lihat scripts/35-ssl.sh.
nginx -t && systemctl reload nginx
HOOK
  chmod +x "$hook"
  ok "hook perpanjangan certbot dipasang"
}

# Minta sertifikat Let's Encrypt lewat certbot.
#
# `certonly`, bukan `--nginx` penuh: certbot hanya MENGAMBIL sertifikatnya,
# sedangkan server block tetap ditulis oleh skrip ini. Dua pihak yang sama-sama
# menyunting berkas yang sama akan saling menimpa, dan `make nginx` berikutnya
# akan menghapus pekerjaan certbot tanpa memberi tahu siapa pun.
issue_letsencrypt_cert() {
  local domain="$1" reg out
  apt_install certbot python3-certbot-nginx

  if [ -n "${CERTBOT_EMAIL:-}" ]; then
    reg="-m ${CERTBOT_EMAIL}"
  else
    # Tanpa email, Let's Encrypt tidak bisa memperingatkan bila perpanjangan
    # berhenti bekerja. Diizinkan, tapi disebutkan terus terang.
    reg="--register-unsafely-without-email"
    warn "CERTBOT_EMAIL kosong — tidak ada peringatan bila perpanjangan gagal"
  fi

  # Seluruh nama situs masuk ke SATU sertifikat: amhriset.com dan
  # www.amhriset.com harus sama-sama sah, kalau tidak salah satunya menerima
  # peringatan sertifikat di browser.
  local names=""
  local n
  for n in ${domain//|/ }; do
    names="$names -d $n"
  done

  log "meminta sertifikat Let's Encrypt untuk ${domain//|/, }"
  # shellcheck disable=SC2086
  if out="$(certbot certonly --nginx --non-interactive --agree-tos $reg             $names 2>&1)"; then
    install_renewal_hook
    ok "sertifikat Let's Encrypt $domain (berlaku 90 hari, diperpanjang otomatis)"
    return 0
  fi

  warn "certbot gagal untuk $domain:"
  echo "$out" | tail -8 | sed 's/^/       /'
  warn "  Domainnya harus SUDAH mengarah ke server ini dan port 80 terbuka —"
  warn "  Let's Encrypt memverifikasi dengan menghubunginya dari luar."
  return 1
}

# Pastikan sertifikat sebuah domain tersedia, apa pun cara mendapatkannya.
#
# Mengisi CERT_FILE dan KEY_FILE dengan lokasi yang harus dipakai nginx.
ensure_cert() {
  local domain="$1" cert="$2" key="$3" paths

  if paths="$(site_cert_paths "${domain%%|*}")"; then
    read -r CERT_FILE KEY_FILE <<< "$paths"
    # 30 hari, bukan 0: sertifikat yang kedaluwarsa besok pagi sama saja dengan
    # yang sudah kedaluwarsa — keduanya membuat situs tidak bisa dibuka.
    if openssl x509 -in "$CERT_FILE" -noout -checkend 2592000 >/dev/null 2>&1; then
      skip "sertifikat $domain"
      return 0
    fi
    warn "sertifikat $domain habis dalam <30 hari — diambil ulang"
  fi

  # Let's Encrypt lebih dulu bila diminta: ia tidak butuh kredensial API sama
  # sekali, hanya domain yang sudah mengarah ke sini.
  if [ "${SSL_METHOD:-cloudflare}" = "letsencrypt" ]; then
    if issue_letsencrypt_cert "$domain"; then
      CERT_FILE="/etc/letsencrypt/live/${domain%%|*}/fullchain.pem"
      KEY_FILE="/etc/letsencrypt/live/${domain%%|*}/privkey.pem"
      return 0
    fi
    return 1
  fi

  if [ -s "$LOCAL_CERTS/${domain%%|*}.pem" ] && [ -s "$LOCAL_CERTS/${domain%%|*}.key" ]; then
    # Konsol web/VNC kerap menelan karakter saat menempel teks panjang, dan PEM
    # yang terpotong lolos sampai `nginx -t` — yang lalu mengeluh tentang
    # konfigurasi, bukan tentang tempelan yang rusak. Dicocokkan di sini selagi
    # penyebabnya masih bisa disebut dengan tepat.
    local cmod kmod
    cmod="$(openssl x509 -noout -modulus -in "$LOCAL_CERTS/${domain}.pem" 2>/dev/null || true)"
    kmod="$(openssl rsa  -noout -modulus -in "$LOCAL_CERTS/${domain}.key" 2>/dev/null || true)"
    if [ -z "$cmod" ] || [ "$cmod" != "$kmod" ]; then
      warn "certs/${domain}.pem dan .key rusak atau tidak berpasangan"
      warn "  Tempelan lewat konsol web sering terpotong — ulangi KEDUANYA,"
      warn "  termasuk baris BEGIN/END-nya."
      return 1
    fi
    install -m 600 "$LOCAL_CERTS/${domain}.key" "$key"
    install -m 644 "$LOCAL_CERTS/${domain}.pem" "$cert"
    CERT_FILE="$cert"; KEY_FILE="$key"
    ok "sertifikat $domain dipasang dari certs/"
    return 0
  fi

  if [ -n "${CF_ORIGIN_CA_KEY:-}" ]; then
    log "meminta Origin Certificate untuk $domain"
    if issue_origin_cert "$domain" "$cert" "$key"; then
      CERT_FILE="$cert"; KEY_FILE="$key"
      return 0
    fi
    return 1
  fi

  warn "belum ada sertifikat untuk $domain — situsnya tetap HTTP saja"
  echo "       Pilih salah satu:"
  echo "       a) isi CF_ORIGIN_CA_KEY di .env, lalu: sudo make ssl"
  echo "       b) SSL_METHOD=letsencrypt di .env — tanpa kredensial API sama"
  echo "          sekali, cukup domain yang sudah mengarah ke server ini"
  echo "       c) buat manual di dashboard Cloudflare (SSL/TLS → Origin Server),"
  echo "          simpan sebagai certs/${domain}.pem dan certs/${domain}.key"
  return 1
}

ISSUED_VIA_API=0
INSTALLED=0

log "HTTPS per situs"
while read -r site; do
  [ -n "$site" ] || continue
  domain="$(kv_lookup "$site" "${SITE_DOMAINS:-}")"
  [ -n "$domain" ] || continue

  # certbot dan Origin CA sama-sama menyimpan di bawah nama pertama.
  primary="${domain%%|*}"
  cert="${CERT_DIR}/${primary}.pem"
  key="${CERT_DIR}/${primary}.key"

  # Satu situs yang gagal TIDAK boleh menjatuhkan sisanya: server yang separuh
  # situsnya HTTPS jauh lebih baik daripada yang setupnya berhenti di tengah.
  CERT_FILE=""; KEY_FILE=""
  if ensure_cert "$domain" "$cert" "$key"; then
    write_site_conf "$site" "$domain" "$PHP_SOCK" "$CERT_FILE" "$KEY_FILE"
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
