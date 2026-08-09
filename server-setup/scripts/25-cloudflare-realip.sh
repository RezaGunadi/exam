#!/usr/bin/env bash
# Pulihkan IP klien asli saat situs berada di belakang proxy Cloudflare.
#
# TANPA INI, PEMBATASAN LAJU TIDAK BEKERJA — dan diamnya berbahaya.
#
# Di belakang Cloudflare, setiap permintaan tiba dari alamat edge Cloudflare.
# Bagi nginx dan aplikasi, seluruh dunia terlihat berasal dari segelintir IP.
# Pembatas "3 kali salah login" lalu mengunci semua orang sekaligus, sementara
# penyerang sungguhan tidak pernah terpisahkan dari pengguna biasa.
#
# Cloudflare mengirim IP asli di CF-Connecting-IP. Header itu hanya boleh
# dipercaya bila koneksinya MEMANG datang dari jaringan Cloudflare — kalau tidak,
# siapa pun yang menghubungi IP server secara langsung bisa mengarang isinya dan
# menyamar sebagai alamat mana pun. Karena itu daftar rentangnya penting: ia
# bukan pelengkap, melainkan syarat header itu boleh dipakai sama sekali.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root

CONF=/etc/nginx/conf.d/cloudflare-realip.conf

# Daftar cadangan dipakai bila pengambilan daring gagal. Server tanpa akses
# keluar tetap harus bisa dikonfigurasi — dan konfigurasi yang kosong jauh lebih
# berbahaya daripada daftar yang sedikit tertinggal.
FALLBACK_V4="173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
141.101.64.0/18
108.162.192.0/18
190.93.240.0/20
188.114.96.0/20
197.234.240.0/22
198.41.128.0/17
162.158.0.0/15
104.16.0.0/13
104.24.0.0/14
172.64.0.0/13
131.0.72.0/22"

FALLBACK_V6="2400:cb00::/32
2606:4700::/32
2803:f800::/32
2405:b500::/32
2405:8100::/32
2a06:98c0::/29
2c0f:f248::/32"

fetch_ranges() {
  local url="$1"
  curl -fsSL --max-time 15 "$url" 2>/dev/null | grep -E '^[0-9a-fA-F:.]+/[0-9]+$' || true
}

log "rentang IP Cloudflare"
V4="$(fetch_ranges https://www.cloudflare.com/ips-v4)"
V6="$(fetch_ranges https://www.cloudflare.com/ips-v6)"

if [ -z "$V4" ]; then
  warn "gagal mengambil daftar terbaru — memakai daftar bawaan skrip"
  V4="$FALLBACK_V4"
  V6="$FALLBACK_V6"
else
  ok "$(echo "$V4" | wc -l) rentang IPv4, $(echo "$V6" | wc -l) rentang IPv6"
fi

TMP="$(mktemp)"
{
  echo "# Dibuat oleh server-setup — JANGAN disunting manual."
  echo "# Perbarui dengan: sudo make cloudflare"
  echo "#"
  echo "# real_ip_header hanya berlaku untuk koneksi dari alamat di bawah ini."
  echo "# Permintaan langsung ke IP server tidak bisa memalsukan CF-Connecting-IP."
  echo ""
  while read -r cidr; do
    [ -n "$cidr" ] && echo "set_real_ip_from $cidr;"
  done <<< "$V4"
  while read -r cidr; do
    [ -n "$cidr" ] && echo "set_real_ip_from $cidr;"
  done <<< "$V6"
  echo ""
  echo "real_ip_header CF-Connecting-IP;"
  echo "real_ip_recursive on;"
} > "$TMP"

if [ -f "$CONF" ] && cmp -s "$TMP" "$CONF"; then
  rm -f "$TMP"
  skip "$CONF sudah mutakhir"
else
  mv "$TMP" "$CONF"
  chmod 644 "$CONF"
  ok "$CONF ditulis"
fi

if nginx -t >/dev/null 2>&1; then
  systemctl reload nginx
  ok "nginx dimuat ulang"
else
  nginx -t || true
  die "konfigurasi nginx tidak valid — tidak ada yang di-reload"
fi

echo ""
echo "Setelah ini, \$remote_addr di nginx SUDAH berisi IP asli pengunjung."
echo "Pada server block, kirimkan apa adanya — jangan \$proxy_add_x_forwarded_for,"
echo "karena itu ikut membawa header yang dikarang pengunjung:"
echo ""
echo "    proxy_set_header X-Forwarded-For \$remote_addr;"
echo "    proxy_set_header X-Real-IP       \$remote_addr;"
