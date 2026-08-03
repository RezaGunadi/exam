#!/usr/bin/env bash
# ============================================================================
# Monitoring per-menit -> CSV /var/log/exam-monitor.csv (dipasang ke cron oleh setup).
# Kolom: waktu, cpu%, steal%, ram_used_mb, ram_total_mb, disk_used%,
#        mysql_threads_connected, mysql_threads_running, load1
# steal% penting di VPS Classic (shared CPU): konsisten >5% = tetangga berisik,
# pertimbangkan pindah paket/node. Analisis: buka CSV di Excel / `column -s, -t`.
# ============================================================================
LOG="/var/log/exam-monitor.csv"
# Membaca kredensial MySQL dari .env server-setup (MySQL ada di HOST).
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -f "$LOG" ]] || echo "time,cpu_pct,steal_pct,ram_used_mb,ram_total_mb,disk_used_pct,mysql_conn,mysql_running,load1" > "$LOG"

# CPU & steal dari /proc/stat (delta 1 detik)
read -r _ u1 n1 s1 i1 w1 irq1 sirq1 st1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 w2 irq2 sirq2 st2 _ < /proc/stat
T1=$((u1+n1+s1+i1+w1+irq1+sirq1+st1)); T2=$((u2+n2+s2+i2+w2+irq2+sirq2+st2))
DT=$((T2-T1)); [[ $DT -eq 0 ]] && DT=1
CPU=$(( ( (T2-i2-w2) - (T1-i1-w1) ) * 100 / DT ))
STEAL=$(( (st2-st1) * 100 / DT ))

RAM_USED=$(free -m | awk '/^Mem:/{print $3}')
RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
DISK=$(df --output=pcent / | tail -1 | tr -d ' %')
LOAD1=$(cut -d' ' -f1 /proc/loadavg)

MYSQL_CONN=0; MYSQL_RUN=0
if [[ -f "$APP_DIR/env/api.env" ]]; then
  source <(grep -E '^DB_(USERNAME|PASSWORD)=' "$APP_DIR/env/api.env")
  MYSQL_CONN=$(MYSQL_PWD="$DB_PASSWORD" mysql -u"$DB_USERNAME" -Nse "SHOW STATUS LIKE 'Threads_connected'" 2>/dev/null | awk '{print $2}') || MYSQL_CONN=0
  MYSQL_RUN=$(MYSQL_PWD="$DB_PASSWORD" mysql -u"$DB_USERNAME" -Nse "SHOW STATUS LIKE 'Threads_running'" 2>/dev/null | awk '{print $2}') || MYSQL_RUN=0
fi

echo "$(date '+%F %T'),$CPU,$STEAL,$RAM_USED,$RAM_TOTAL,$DISK,${MYSQL_CONN:-0},${MYSQL_RUN:-0},$LOAD1" >> "$LOG"

# Rotasi sederhana: >50MB -> arsipkan
if [[ $(stat -c%s "$LOG") -gt 52428800 ]]; then
  mv "$LOG" "$LOG.$(date +%F)"; gzip "$LOG.$(date +%F)" &
fi
