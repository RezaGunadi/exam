#!/usr/bin/env bash
# ============================================================================
# lib-cert.sh — penerbitan Cloudflare Origin Certificate.
#
# Dipisahkan supaya DUA pemakai memakai implementasi yang SAMA:
#
#   35-ssl.sh      memasang HTTPS untuk situs yang tercantum di SITE_DOMAINS
#   brand-sync.sh  memasang HTTPS untuk domain branding premium, yang muncul
#                  dan hilang lewat panel dan tidak pernah ada di .env
#
# Dua salinan dari kode yang menerbitkan sertifikat akan berbeda cepat atau
# lambat, dan yang tertinggal biasanya justru yang lebih jarang dijalankan —
# di sini itu berarti sekolah premium mendapat sertifikat dengan cara yang
# sudah tidak dipakai lagi, dan tidak ada yang menyadarinya sampai ia gagal.
#
# KENAPA ORIGIN CERTIFICATE, BUKAN LET'S ENCRYPT:
# certbot memvalidasi lewat port 80 yang di sini diproksikan Cloudflare.
# Pemasangan pertama biasanya berhasil, lalu perpanjangan otomatisnya gagal
# diam-diam berbulan-bulan kemudian — tepat saat tidak ada yang memperhatikan.
# Origin Certificate berlaku 15 tahun dan tidak punya jadwal perpanjangan yang
# bisa gagal sama sekali.
#
# Keuntungan tambahan yang menentukan untuk branding premium: penerbitannya
# lewat API, TIDAK menuntut domainnya sudah bisa dijangkau dari internet. Jadi
# sertifikatnya bisa dipasang lebih dulu, dan sekolah tinggal mengarahkan DNS
# kapan pun mereka siap — bukan sebaliknya.
# ============================================================================

# cf_post_certificate <body> <header-auth>
cf_post_certificate() {
  curl -sS -X POST \
    'https://api.cloudflare.com/client/v4/certificates' \
    -H 'Content-Type: application/json' \
    -H "$2" \
    --data "$1" 2>/dev/null || true
}

# issue_origin_cert <domain> <cert-path> <key-path>
#
# Mengembalikan 0 bila sertifikatnya terpasang. Memakai warn()/ok() dari
# lib.sh bila ada; kalau tidak, jatuh ke echo supaya tetap bisa dipakai skrip
# yang tidak menyertakan lib.sh.
issue_origin_cert() {
  local domain="$1" cert="$2" key="$3"
  local tmpdir body resp

  command -v jq      >/dev/null || { _cert_warn "jq tidak terpasang"; return 1; }
  command -v openssl >/dev/null || { _cert_warn "openssl tidak terpasang"; return 1; }
  [ -n "${CF_ORIGIN_CA_KEY:-}" ] || { _cert_warn "CF_ORIGIN_CA_KEY kosong"; return 1; }

  tmpdir="$(mktemp -d)"
  chmod 700 "$tmpdir"

  if ! openssl req -new -newkey rsa:2048 -nodes \
        -keyout "$tmpdir/key" -out "$tmpdir/csr" \
        -subj "/CN=${domain}" >/dev/null 2>&1; then
    _cert_warn "gagal membuat CSR untuk $domain"
    rm -rf "$tmpdir"
    return 1
  fi

  # Hostname DAN wildcard-nya sekaligus: pengunjung yang mengetik www harus
  # sama-sama sah, kalau tidak salah satunya menerima peringatan sertifikat.
  # requested_validity 5475 hari = 15 tahun, nilai terpanjang yang diterima.
  body="$(jq -n --arg csr "$(cat "$tmpdir/csr")" --arg host "$domain" --arg w "www.$domain" \
    '{hostnames: [$host, $w], requested_validity: 5475,
      request_type: "origin-rsa", csr: $csr}')"

  # Endpoint ini menerima DUA bentuk kredensial dengan header yang berbeda:
  #   Origin CA Key (v1.0-...)                 -> X-Auth-User-Service-Key
  #   API Token dengan izin SSL & Certificates -> Authorization: Bearer
  # Keduanya dicoba, karena jawaban Cloudflare untuk header yang salah hanya
  # "Authentication failed" — yang sama sekali tidak menyinggung JENIS kunci.
  local h1="X-Auth-User-Service-Key: ${CF_ORIGIN_CA_KEY}"
  local h2="Authorization: Bearer ${CF_ORIGIN_CA_KEY}"
  case "$CF_ORIGIN_CA_KEY" in
    v1.0-*) : ;;
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
      CERT_ERROR="$(echo "$resp" | jq -r '[.errors[]?.message] | join("; ")' 2>/dev/null)"
      [ -n "$CERT_ERROR" ] || CERT_ERROR="Cloudflare menolak permintaan sertifikat"
      _cert_warn "$domain: $CERT_ERROR"
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
  _cert_ok "Origin Certificate $domain diterbitkan (berlaku 15 tahun)"
  return 0
}

_cert_warn() { if command -v warn >/dev/null 2>&1; then warn "$*"; else printf '  !! %s\n' "$*" >&2; fi; }
_cert_ok()   { if command -v ok   >/dev/null 2>&1; then ok   "$*"; else printf '  ok %s\n' "$*"; fi; }
