#!/usr/bin/env bash
# Pasang & amankan MySQL, buat pengguna aplikasi, siapkan database per proyek.
#
# SATU INSTANS MYSQL untuk semua proyek, database TERPISAH per proyek. Lebih
# mudah dikelola (satu backup, satu phpMyAdmin, satu tuning) tanpa mencampur
# data antar aplikasi.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
load_env "$(dirname "$SCRIPT_DIR")"

require_root
require_apt

log "MySQL"
apt_install mysql-server mysql-client

systemctl enable --now mysql >/dev/null 2>&1 || true
systemctl is-active --quiet mysql || die "MySQL tidak berjalan"

# ── Password root ──────────────────────────────────────────────────────────
ROOT_PW_FILE="$(dirname "$SCRIPT_DIR")/.mysql-root-password"
if [ -z "${MYSQL_ROOT_PASSWORD:-}" ]; then
  if [ -f "$ROOT_PW_FILE" ]; then
    MYSQL_ROOT_PASSWORD="$(cat "$ROOT_PW_FILE")"
  else
    # Password acak lebih baik daripada nilai bawaan yang bisa ditebak.
    MYSQL_ROOT_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
    umask 077
    printf '%s' "$MYSQL_ROOT_PASSWORD" > "$ROOT_PW_FILE"
    chmod 600 "$ROOT_PW_FILE"
    warn "password root MySQL dibuat acak → $ROOT_PW_FILE (mode 600)"
  fi
fi

# Di Ubuntu, root MySQL memakai auth_socket sehingga root sistem bisa masuk
# tanpa password. Itu dipakai untuk penyiapan awal.
mysql_root() {
  if mysql --protocol=socket -u root -e 'SELECT 1' >/dev/null 2>&1; then
    mysql --protocol=socket -u root "$@"
  else
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$@"
  fi
}

mysql_root -e 'SELECT VERSION()' >/dev/null 2>&1 \
  || die "tidak bisa masuk MySQL sebagai root — periksa $ROOT_PW_FILE"

# ── Pengerasan dasar ───────────────────────────────────────────────────────
log "mengamankan MySQL"
mysql_root <<SQL
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
ok "pengguna anonim & database test dibersihkan"

# MySQL HANYA mendengar di localhost. Aplikasi mengaksesnya dari host yang sama
# (termasuk container lewat host-gateway), jadi tidak ada alasan membuka port
# 3306 ke internet — itu sasaran empuk pemindaian otomatis.
BIND_CONF=/etc/mysql/mysql.conf.d/zz-local-only.cnf
if [ ! -f "$BIND_CONF" ]; then
  cat > "$BIND_CONF" <<'CONF'
# Ditulis oleh server-setup. MySQL tidak boleh terbuka ke internet.
[mysqld]
bind-address = 127.0.0.1
CONF
  systemctl restart mysql
  ok "MySQL dikunci ke 127.0.0.1"
else
  skip "bind-address 127.0.0.1"
fi

# ── Pengguna aplikasi ──────────────────────────────────────────────────────
[ -n "${DB_USER:-}" ]     || die "DB_USER kosong di .env"
[ -n "${DB_PASSWORD:-}" ] || die "DB_PASSWORD kosong di .env"

log "pengguna aplikasi: $DB_USER"
# Dibuat untuk localhost DAN 172.17.0.0/16 (jaringan Docker bawaan) supaya
# container bisa menyambung ke MySQL host tanpa membuka port ke luar.
for host in 'localhost' '127.0.0.1' '172.%'; do
  mysql_root <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'${host}' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'${host}' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'${host}' WITH GRANT OPTION;
SQL
done
mysql_root -e 'FLUSH PRIVILEGES;'
ok "pengguna $DB_USER siap (localhost + jaringan Docker)"

# ── Database per proyek ────────────────────────────────────────────────────
log "database per proyek"
while read -r raw; do
  db="$(sanitize_db_name "$raw")"
  [ -n "$db" ] || continue
  if mysql_root -e "USE \`${db}\`" >/dev/null 2>&1; then
    skip "database $db"
  else
    mysql_root -e "CREATE DATABASE \`${db}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    ok "database $db dibuat"
  fi
done < <(split_csv "${DATABASES:-}")

log "MySQL selesai"
