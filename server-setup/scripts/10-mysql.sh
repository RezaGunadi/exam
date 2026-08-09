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
    # `cut -c1-24`, bukan `head -c 24`: head menutup pipa setelah cukup byte,
    # membuat perintah sebelumnya menerima SIGPIPE. Dengan `pipefail` itu
    # dianggap kegagalan pipeline dan menghentikan seluruh skrip — kegagalan
    # yang muncul acak dan sangat sulit ditelusuri.
    # Password acak lebih baik daripada nilai bawaan yang bisa ditebak.
    MYSQL_ROOT_PASSWORD="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-24)"
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
#
# PENTING: 127.0.0.1 SAJA TIDAK CUKUP bila ada aplikasi dalam container.
# Container menyambung lewat gateway jembatan Docker (biasanya 172.17.0.1),
# dan MySQL yang hanya mendengar di loopback akan MENOLAK koneksi itu — grant
# untuk '172.%' pun tidak menolong, karena permintaannya tidak pernah sampai.
# Jadi alamat gateway Docker ikut didengarkan bila jembatannya ada.
BIND_CONF=/etc/mysql/mysql.conf.d/zz-bind-address.cnf

# CATATAN PENTING: skrip ini berjalan dengan `set -euo pipefail` (lib.sh).
# Artinya SATU perintah gagal di dalam pipeline akan menghentikan SELURUH
# skrip — termasuk saat kegagalan itu wajar dan sudah diantisipasi.
#
# `ip ... docker0` memang gagal bila Docker belum terpasang, dan `grep` memang
# gagal bila berkasnya belum ada. Keduanya keadaan normal pada pemasangan
# pertama. Tanpa `|| true`, MySQL selesai terpasang dengan benar tetapi `make`
# tetap melaporkan gagal — persis gejala yang membingungkan: layanan berjalan,
# tetapi langkah berikutnya tidak pernah dijalankan.
detect_docker_gateway() {
  command -v ip >/dev/null 2>&1 || return 0
  ip -4 -o addr show docker0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true
}

DOCKER_GW="$(detect_docker_gateway || true)"
if [ -n "$DOCKER_GW" ]; then
  BIND_LIST="127.0.0.1,${DOCKER_GW}"
else
  BIND_LIST="127.0.0.1"
fi

# Tulis ulang bila daftar alamatnya berubah — mis. Docker baru dipasang setelah
# MySQL. Tanpa ini, menjalankan ulang setelah memasang Docker tidak berefek.
# sed dipakai, bukan `grep -oP`: PCRE tidak selalu tersedia dan gagal pada
# sebagian locale. `|| true` menjaga agar berkas yang belum ada tidak
# menghentikan skrip.
CURRENT_BIND="$(sed -n 's/^bind-address[[:space:]]*=[[:space:]]*//p' "$BIND_CONF" 2>/dev/null | tr -d ' ' | head -1 || true)"
if [ "$CURRENT_BIND" = "$BIND_LIST" ]; then
  skip "bind-address ${BIND_LIST}"
else
  cat > "$BIND_CONF" <<CONF
# Ditulis oleh server-setup.
#
# MySQL TIDAK boleh terbuka ke internet, tetapi HARUS terjangkau dari container
# aplikasi. Karena itu hanya loopback + gateway jembatan Docker yang
# didengarkan — bukan 0.0.0.0.
[mysqld]
bind-address = ${BIND_LIST}
CONF
  systemctl restart mysql
  ok "MySQL mendengar di ${BIND_LIST}"
  if [ -z "$DOCKER_GW" ]; then
    warn "Docker belum terpasang — container belum bisa menyambung ke MySQL."
    warn "  Jalankan ulang 'sudo make mysql' SETELAH Docker dipasang."
  fi
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

# ── Penyetelan performa ────────────────────────────────────────────────────
# innodb_buffer_pool_size adalah penentu terbesar performa MySQL, DAN pemakan
# RAM terbesar. Nilainya dihitung dari RAM yang benar-benar ada, bukan angka
# tetap: menyetel 3G di mesin 8GB yang juga menjalankan LLM lokal membuat
# keduanya berebut memori, lalu kernel mulai mematikan proses.
TUNING_CONF=/etc/mysql/mysql.conf.d/zz-exam-tuning.cnf
if [ -f "$TUNING_CONF" ]; then
  skip "penyetelan MySQL"
else
  TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  if [ -n "${MYSQL_BUFFER_POOL_MB:-}" ]; then
    # Nilai yang ditentukan sendiri menang. Buffer pool yang lebih besar dari
    # ukuran database tidak menambah kecepatan apa pun — jadi setel setelah
    # mengukur data, bukan menebak.
    POOL_MB="$MYSQL_BUFFER_POOL_MB"
    warn "buffer pool disetel manual: ${POOL_MB}M"
  else
    # Sekitar seperempat RAM. Sisanya untuk aplikasi, LLM lokal, dan sistem.
    POOL_MB=$(( TOTAL_MB / 4 ))
  fi
  [ "$POOL_MB" -lt 256 ] && POOL_MB=256
  [ "$POOL_MB" -gt 8192 ] && POOL_MB=8192

  cat > "$TUNING_CONF" <<CONF
# Ditulis oleh server-setup. RAM terdeteksi: ${TOTAL_MB}MB.
[mysqld]
innodb_buffer_pool_size = ${POOL_MB}M
innodb_buffer_pool_instances = 4
innodb_redo_log_capacity = 512M

# Ujian menulis sangat sering (autosave jawaban tiap beberapa detik).
# Menahan flush ke disk setiap transaksi membuat MySQL menjadi penghambat;
# nilai 2 menukar risiko kehilangan <1 detik transaksi terakhir saat mesin
# mati mendadak dengan lonjakan throughput yang besar.
innodb_flush_log_at_trx_commit = 2
sync_binlog = 0
skip-log-bin
innodb_flush_method = O_DIRECT

max_connections = 300
tmp_table_size = 64M
max_heap_table_size = 64M
# Tanpa ini setiap koneksi menunggu lookup DNS balik yang sering gagal.
skip-name-resolve
CONF
  systemctl restart mysql
  ok "penyetelan MySQL (buffer pool ${POOL_MB}M dari ${TOTAL_MB}MB RAM)"
fi

log "MySQL selesai"
