#!/usr/bin/env bash
# Ringkasan keadaan server — aman dijalankan tanpa root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT_DIR="$(dirname "$SCRIPT_DIR")"
[ -f "$ROOT_DIR/.env" ] && { set -a; . "$ROOT_DIR/.env"; set +a; }

svc() {
  if systemctl is-active --quiet "$1" 2>/dev/null; then
    printf "  %-12s ${C_OK}berjalan${C_RESET}\n" "$1"
  else
    printf "  %-12s ${C_ERR}mati${C_RESET}\n" "$1"
  fi
}

echo "Layanan:"
svc nginx
svc mysql

echo ""
echo "Situs aktif:"
if [ -d /etc/nginx/sites-enabled ]; then
  for link in /etc/nginx/sites-enabled/*; do
    [ -e "$link" ] || continue
    name="$(basename "$link")"
    # sed, bukan `grep -oP`: PCRE tidak selalu tersedia dan gagal pada sebagian
    # locale, dengan pesan yang tidak menyinggung penyebabnya sama sekali.
    domain="$(sed -n 's/^[[:space:]]*server_name[[:space:]]\+\([^;]*\);.*/\1/p' \
      "$link" 2>/dev/null | head -1)"
    [ -n "$domain" ] || domain='?'
    if grep -q 'listen[[:space:]].*443' "$link" 2>/dev/null; then
      scheme="${C_OK}https${C_RESET}"
    else
      scheme="${C_WARN}http saja${C_RESET}"
    fi
    printf "  %-28s %-28s ${scheme}\n" "$name" "$domain"
  done
else
  echo "  (nginx belum terpasang)"
fi

echo ""
echo "Database:"
if command -v mysql >/dev/null 2>&1 && [ -n "${DB_USER:-}" ]; then
  mysql -u "$DB_USER" -p"${DB_PASSWORD:-}" -N -B \
    -e "SELECT schema_name FROM information_schema.schemata
        WHERE schema_name NOT IN ('information_schema','mysql','performance_schema','sys');" \
    2>/dev/null | sed 's/^/  /' || echo "  (tidak bisa menyambung — periksa kredensial di .env)"
else
  echo "  (MySQL belum terpasang)"
fi

echo ""
echo "Kapasitas permintaan bersamaan:"
# Plafon yang paling sering terlewat. Uji beban aplikasi menempuh kode dari
# dalam proses, bukan lewat PHP-FPM, jadi angkanya tetap bagus sementara server
# sungguhan sudah antre di bawah lonjakan.
FPM_POOL="$(ls /etc/php/*/fpm/pool.d/*.conf 2>/dev/null || true)"
if [ -n "$FPM_POOL" ]; then
  MC="$(grep -h '^[[:space:]]*pm.max_children' $FPM_POOL 2>/dev/null | tail -1 | sed 's/.*=[[:space:]]*//' || true)"
  if [ -n "$MC" ]; then
    echo "  PHP-FPM pm.max_children : $MC"
    if [ "$MC" -le 5 ] 2>/dev/null; then
      echo "  -> Masih bawaan distro. Seluruh situs hanya melayani $MC permintaan"
      echo "     PHP bersamaan; satu kelas menekan 'Mulai' berbarengan sudah cukup"
      echo "     membuatnya antre. Jalankan 'sudo make php' untuk menyetelnya."
    fi
  else
    echo "  PHP-FPM pm.max_children : (tidak terbaca)"
  fi
else
  echo "  (PHP-FPM belum terpasang)"
fi
if command -v mysql >/dev/null 2>&1 && [ -n "${DB_USER:-}" ]; then
  MAXC="$(mysql -u "$DB_USER" -p"${DB_PASSWORD:-}" -N -B -e "SELECT @@max_connections;" 2>/dev/null || true)"
  [ -n "$MAXC" ] && echo "  MySQL max_connections   : $MAXC"
fi

echo ""
echo "MySQL terjangkau dari container?"
# Pertanyaan yang paling sering ditanyakan saat "API tidak bisa konek padahal
# .env sudah benar", dan paling susah dijawab dengan menebak.
#
# Yang diperiksa BUKAN apakah MySQL hidup — itu sudah di atas — melainkan
# apakah ia mendengar di alamat yang dituju container. Container compose
# menyambung lewat gateway jembatannya sendiri (br-*), bukan docker0, dan
# MySQL yang hanya mendengar di docker0 menolak sambungan itu tanpa pernah
# sampai ke urusan pengguna atau password.
if command -v docker >/dev/null 2>&1 && command -v ss >/dev/null 2>&1; then
  DENGAR="$(ss -lnt 2>/dev/null | awk '$4 ~ /:3306$/ {sub(/:3306$/, "", $4); print $4}' | sort -u)"
  echo "  MySQL mendengar di: $(echo "$DENGAR" | tr '
' ' ')"
  ADA_MASALAH=0
  for br in $(ip -4 -o addr show 2>/dev/null | awk '$2 == "docker0" || $2 ~ /^br-/ {print $2"="$4}'); do
    nama="${br%%=*}"
    gw="${br#*=}"
    gw="${gw%%/*}"
    if echo "$DENGAR" | grep -qx "$gw"; then
      echo "  OK   $nama ($gw) — container di jaringan ini bisa menyambung"
    else
      echo "  BEDA $nama ($gw) — MySQL TIDAK mendengar di sini"
      ADA_MASALAH=1
    fi
  done
  if [ "$ADA_MASALAH" = "1" ]; then
    echo "  -> Jalankan 'sudo make mysql' untuk menambahkan alamat itu ke bind-address."
  fi
else
  echo "  (docker atau ss tidak tersedia)"
fi

echo ""
echo "Port yang didengarkan:"
ss -lntp 2>/dev/null | awk 'NR>1 {print "  " $4 "  " $NF}' | sort -u | head -20
