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
    domain="$(grep -m1 -oP 'server_name\s+\K[^;]+' "$link" 2>/dev/null || echo '?')"
    printf "  %-28s %s\n" "$name" "$domain"
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
echo "Port yang didengarkan:"
ss -lntp 2>/dev/null | awk 'NR>1 {print "  " $4 "  " $NF}' | sort -u | head -20
