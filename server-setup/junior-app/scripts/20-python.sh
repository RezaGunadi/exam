#!/usr/bin/env bash
# Python di host + virtualenv untuk skrip perawatan backend Kelas Junior.
#
# INI BUKAN RUNTIME YANG MELAYANI. Backend berjalan di dalam container dari
# image python:3.12-slim; Python host tidak pernah menjalankan uvicorn maupun
# celery. Yang dipasang di sini dipakai untuk skrip di game_backend/scripts/
# yang memang dijalankan dari host — mengekspor bundel ikon, memeriksa engine,
# dan menyeed ulang saat art ikon berubah:
#
#   sudo -u root /var/www/junior_app/.venv/bin/python scripts/seed_all.py
#
# Kenapa venv, bukan `pip install` langsung ke Python sistem: Debian 12 dan
# Ubuntu 24.04 menandai Python sistemnya "externally managed" dan MENOLAK pip
# sama sekali (PEP 668). Melewati penolakan itu dengan --break-system-packages
# berarti paket apt dan paket pip berebut berkas yang sama, dan yang rusak
# belakangan adalah perkakas sistem yang kebetulan ditulis dengan Python.
#
# Kegagalan di sini TIDAK menghentikan deploy: layanannya tidak bergantung pada
# apa pun yang dipasang skrip ini.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_apt

[ -d "$BACKEND_DIR" ] || die "$BACKEND_DIR tidak ada — jalankan dulu: sudo make app"

log "Python host + virtualenv"

apt_install python3 python3-venv python3-pip

PY_VER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "")"
[ -n "$PY_VER" ] || die "python3 terpasang tetapi tidak bisa dijalankan"

# requirements.txt meminta fastapi, sqlmodel, dan pydantic-settings versi baru;
# semuanya sudah melepas Python 3.9 ke bawah. Diperiksa di awal, bukan
# dibiarkan muncul sebagai daftar konflik resolusi pip yang tidak menyebut
# versi Python sama sekali.
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
  warn "Python host ${PY_VER} — di bawah 3.10 yang diminta requirements.txt"
  warn "  Container tetap jalan (image-nya python:3.12), hanya skrip perawatan"
  warn "  dari host yang tidak bisa dipasang. Lewati langkah ini."
  exit 0
fi
ok "Python ${PY_VER}"

# .venv ada di AKAR repo, bukan di dalam game_backend/. Konteks build image
# adalah game_backend/, dan venv berisi ribuan berkas yang tidak ada gunanya di
# sana — .dockerignore memang sudah menutupnya, tetapi menaruhnya di luar
# konteks membuat itu tidak lagi bergantung pada satu baris yang bisa hilang.
if [ -x "$VENV_DIR/bin/python" ]; then
  skip "virtualenv $VENV_DIR"
else
  python3 -m venv "$VENV_DIR" || {
    warn "gagal membuat virtualenv — paket python3-venv mungkin tidak lengkap"
    warn "  Coba: sudo apt install python${PY_VER}-venv"
    exit 0
  }
  ok "virtualenv $VENV_DIR"
fi

log "memasang dependensi backend ke virtualenv"
pip_log="$(mktemp)"
if ! "$VENV_DIR/bin/pip" install --quiet --upgrade pip >"$pip_log" 2>&1; then
  tail -10 "$pip_log" | sed 's/^/       /'
  warn "gagal memutakhirkan pip — dilanjutkan dengan versi bawaan"
fi

# requirements.txt (runtime), bukan requirements-dev.txt: pytest dan kawan-kawan
# tidak dipakai dari server. Kegagalannya diperingatkan, tidak mematikan deploy —
# roda yang tidak tersedia untuk versi Python host bukan alasan untuk membatalkan
# layanan yang berjalan di container dengan Python yang berbeda.
if "$VENV_DIR/bin/pip" install --quiet -r "$BACKEND_DIR/requirements.txt" >"$pip_log" 2>&1; then
  ok "dependensi terpasang di $VENV_DIR"
  echo ""
  log "Menjalankan skrip perawatan dari host:"
  echo "       cd ${BACKEND_DIR}"
  echo "       sudo ${VENV_DIR}/bin/python scripts/seed_all.py"
  echo ""
  warn "Skrip dari host memakai DATABASE_URL di ${APP_ENV_FILE},"
  warn "  dan di sana hostnya 'host.docker.internal' — nama itu HANYA dikenal"
  warn "  di dalam container. Dari host, timpa saat menjalankannya:"
  echo "       sudo DATABASE_URL='mysql+pymysql://USER:PASS@127.0.0.1:3306/${APP_DB}?charset=utf8mb4' \\"
  echo "            ${VENV_DIR}/bin/python scripts/seed_all.py"
  echo ""
  warn "  Atau jalankan di dalam container saja, tanpa venv sama sekali:"
  echo "       sudo make seed"
else
  tail -15 "$pip_log" | sed 's/^/       /'
  warn "pip install gagal — skrip perawatan dari host belum bisa dipakai."
  warn "  Layanan TIDAK terpengaruh: container memakai Python miliknya sendiri."
  warn "  Sementara itu, jalankan skrip di dalam container: sudo make seed"
fi
rm -f "$pip_log"
