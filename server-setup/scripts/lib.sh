#!/usr/bin/env bash
# Fungsi bersama untuk seluruh skrip setup.
#
# Prinsip yang dipegang semua skrip di sini:
#   1. IDEMPOTEN — dijalankan berulang kali harus aman. Yang sudah ada dilewati.
#   2. TIDAK MERUSAK — tidak pernah menimpa konfigurasi yang sudah disunting
#      manusia tanpa memberi tahu; berkas lama dicadangkan lebih dulu.
#   3. BERHENTI SAAT RAGU — lebih baik gagal terang-terangan daripada
#      melanjutkan dan meninggalkan server setengah jadi.

set -euo pipefail

C_RESET='\033[0m'; C_INFO='\033[0;36m'; C_OK='\033[0;32m'
C_WARN='\033[0;33m'; C_ERR='\033[0;31m'; C_SKIP='\033[0;90m'

log()  { printf "${C_INFO}==>${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_OK}  ok${C_RESET} %s\n" "$*"; }
skip() { printf "${C_SKIP}  -- %s (sudah ada, dilewati)${C_RESET}\n" "$*"; }
warn() { printf "${C_WARN}  !! %s${C_RESET}\n" "$*"; }
die()  { printf "${C_ERR}GAGAL:${C_RESET} %s\n" "$*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "jalankan sebagai root (sudo make server)"
}

require_apt() {
  command -v apt-get >/dev/null 2>&1 \
    || die "skrip ini untuk Debian/Ubuntu (apt tidak ditemukan)"
}

# Pasang paket hanya bila belum terpasang.
apt_install() {
  local missing=()
  for pkg in "$@"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    skip "paket: $*"
    return
  fi
  log "memasang: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${missing[@]}" >/dev/null
  ok "terpasang: ${missing[*]}"
}

# Cadangkan berkas sebelum ditimpa, sekali saja per berkas.
backup_once() {
  local file="$1"
  [ -f "$file" ] || return 0
  [ -f "${file}.orig" ] && return 0
  cp -a "$file" "${file}.orig"
  ok "cadangan: ${file}.orig"
}

# Muat .env; buat dari contoh bila belum ada.
load_env() {
  local dir="$1"
  if [ ! -f "$dir/.env" ]; then
    cp "$dir/.env.example" "$dir/.env"
    chmod 600 "$dir/.env"
    warn ".env dibuat dari .env.example — GANTI password bawaannya."
  fi
  set -a
  # shellcheck disable=SC1090
  . "$dir/.env"
  set +a
  check_env_vars "$dir"
}

# Peringatkan bila .env ketinggalan variabel yang sudah ada di .env.example.
#
# .env dibuat SEKALI lalu tidak pernah disentuh lagi — `git pull` memperbarui
# .env.example, tetapi variabel barunya tidak muncul di .env yang sudah ada.
# Skrip lalu membaca nilai kosong dan melewati pekerjaannya tanpa keluhan.
#
# Ini bukan kemungkinan teoretis: SITE_DOMAINS yang tidak ada membuat SELURUH
# tahap HTTPS dilewati, sementara `make server` tetap mencetak "Setup selesai"
# — dan situsnya baru ketahuan mati dari halaman error Cloudflare.
check_env_vars() {
  local dir="$1" missing=() name
  [ -f "$dir/.env.example" ] || return 0
  while read -r name; do
    grep -qE "^[[:space:]]*${name}=" "$dir/.env" || missing+=("$name")
  done < <(grep -oE '^[A-Z_][A-Z0-9_]*=' "$dir/.env.example" | tr -d '=')
  [ ${#missing[@]} -eq 0 ] && return 0
  warn ".env ketinggalan ${#missing[@]} variabel yang sudah ada di .env.example:"
  printf '       %s\n' "${missing[@]}"
  warn "  Bagian yang memakainya akan DILEWATI. Tambahkan ke $dir/.env"
}

# Tambahkan variabel yang belum ada ke .env, lengkap dengan nilai bawaannya.
#
#   ensure_env_var <dir> <NAMA> <nilai> [komentar]
#
# check_env_vars hanya MEMPERINGATKAN — dan peringatan itu tidak menolong pada
# server yang sudah berjalan: .env dibuat sekali dari .env.example lalu tidak
# pernah disentuh lagi, sehingga variabel baru hasil `git pull` tidak pernah
# sampai ke sana. Skrip lalu membaca nilai kosong dan diam-diam mengambil jalur
# bawaan yang salah.
#
# Hanya untuk variabel yang AMAN diberi nilai bawaan. Password dan kredensial
# tidak pernah lewat sini — nilai bawaan yang bisa ditebak lebih berbahaya
# daripada variabel yang hilang.
ensure_env_var() {
  local dir="$1" name="$2" value="$3" comment="${4:-}"
  local file="$dir/.env"

  [ -f "$file" ] || return 0
  if grep -qE "^[[:space:]]*${name}=" "$file"; then
    return 0
  fi

  {
    echo ""
    if [ -n "$comment" ]; then
      echo "# $comment"
    fi
    echo "${name}=${value}"
  } >> "$file"

  # Diekspor juga, bukan hanya ditulis: .env sudah dibaca sebelum ini dipanggil,
  # jadi tanpa export pemanggilnya masih melihat nilai kosong pada eksekusi yang
  # sama — dan baru berperilaku benar saat dijalankan untuk kedua kalinya.
  export "${name}=${value}"
  ok "${name}=${value} ditambahkan ke .env"
}

# Ubah "a,b,c" menjadi baris-baris.
split_csv() {
  echo "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
}

# Cari nilai sebuah nama di daftar berformat "nama=nilai" dipisah koma.
#   kv_lookup exam_v2 "$SITE_DOMAINS"
#
# Nama tanpa entri menghasilkan string kosong dan status 0 — pemanggilnya
# memutuskan sendiri apakah itu masalah. Sebagian besar situs memang belum
# punya domain, dan itu keadaan yang sah, bukan kegagalan.
kv_lookup() {
  local target="$1" list="${2:-}" pair name value
  while read -r pair; do
    [ -n "$pair" ] || continue
    name="${pair%%=*}"
    value="${pair#*=}"
    if [ "$name" = "$target" ] && [ "$value" != "$pair" ]; then
      echo "$value"
      return 0
    fi
  done < <(split_csv "$list")
  return 0
}

# Socket PHP-FPM baru ADA setelah layanannya berjalan. Pencariannya memakai glob
# shell, bukan `grep -oP`: PCRE tidak selalu tersedia dan gagal pada sebagian
# locale, dengan pesan yang sama sekali tidak menjelaskan hubungannya dengan PHP.
#
# PHP_VERSION di .env didahulukan. Glob-nya mengambil hasil PERTAMA menurut
# abjad — php8.1 sebelum php8.2 — jadi selama dua versi masih terpasang
# berdampingan, `make nginx` yang dijalankan ulang setelah `make php` akan
# diam-diam mengembalikan seluruh situs ke PHP lama. Kegagalannya tidak
# menimbulkan error apa pun: situsnya tetap terbuka, hanya dengan versi yang
# salah, dan itu baru ketahuan dari aplikasi yang menolak jalan.
#
# Kalau socket versi itu belum ada (mis. `make nginx` dijalankan sebelum
# `make php`), pencarian jatuh kembali ke glob supaya situs tetap terkonfigurasi
# dengan PHP yang memang ada, bukan berhenti sama sekali.
find_php_sock() {
  local candidate
  if [ -n "${PHP_VERSION:-}" ]; then
    candidate="/run/php/php${PHP_VERSION}-fpm.sock"
    [ -S "$candidate" ] && { echo "$candidate"; return 0; }
  fi
  for candidate in /run/php/php*-fpm.sock; do
    [ -S "$candidate" ] && { echo "$candidate"; return 0; }
  done
  return 1
}

# Apakah paket php<versi>-fpm bisa dipasang dari repo yang aktif?
#
# Dipakai untuk memutuskan antara paket berversi dan paket meta bawaan distro.
# `apt-get install` pada paket yang tidak punya kandidat akan menghentikan
# seluruh skrip — padahal jawabannya cuma "repo-nya belum ditambahkan".
#
# Diputuskan lewat SIMULASI pemasangan, bukan dengan membaca keluaran
# `apt-cache policy`. Keluaran apt diterjemahkan mengikuti locale server —
# "Candidate:" menjadi "Kandidat:" pada pemasangan berbahasa Indonesia — dan
# pencarian teks itu lalu menjawab "tidak tersedia" untuk paket yang sebenarnya
# ADA. Kegagalannya menuduh repo yang baru saja berhasil ditambahkan, sehingga
# yang diperiksa orang justru bagian yang tidak rusak.
#
# `-s` hanya mensimulasikan: tidak ada yang dipasang, tidak ada kunci apt yang
# diambil, dan status keluarnya sudah menjawab pertanyaannya tanpa penguraian
# teks sama sekali.
php_pkg_available() {
  apt-get install -s -y "php${1}-fpm" >/dev/null 2>&1
}

# Cari pasangan sertifikat yang sudah terpasang untuk sebuah domain.
# Mencetak "berkas_cert berkas_kunci", atau mengembalikan 1 bila belum ada.
#
# Let's Encrypt diperiksa lebih dulu dan nginx menunjuk LANGSUNG ke sana.
# Berkasnya diperbarui di tempat oleh certbot; kalau disalin ke direktori lain,
# nginx akan tetap menyajikan salinan lama setelah perpanjangan — persis jenis
# kegagalan yang tidak menimbulkan error sampai sertifikatnya benar-benar mati.
site_cert_paths() {
  # Dipisah per baris dengan sengaja. `local a="$1" b="${a}"` TIDAK bekerja:
  # bash mengembangkan seluruh argumen `local` lebih dulu, sehingga ${a} masih
  # bernilai lama (atau kosong, dan `set -u` menghentikan skrip).
  local domain="$1"
  local le="/etc/letsencrypt/live/${domain}"
  local cf="/etc/ssl/cloudflare"
  if [ -s "$le/fullchain.pem" ] && [ -s "$le/privkey.pem" ]; then
    echo "$le/fullchain.pem $le/privkey.pem"
    return 0
  fi
  if [ -s "${cf}/${domain}.pem" ] && [ -s "${cf}/${domain}.key" ]; then
    echo "${cf}/${domain}.pem ${cf}/${domain}.key"
    return 0
  fi
  return 1
}

# Baris listen untuk blok 443, lengkap dengan cara menyalakan HTTP/2.
#
# `http2 on;` baru dikenal nginx 1.25.1. Ubuntu 24.04 masih membawa 1.24, dan di
# sana direktif itu bukan sekadar diabaikan — `nginx -t` GAGAL, sehingga seluruh
# konfigurasi (termasuk situs lain yang tadinya sehat) tidak jadi dimuat. Karena
# itu versinya diperiksa, bukan diasumsikan.
#
# Bentuk lama `listen 443 ssl http2` masih diterima versi baru, hanya memberi
# peringatan — jadi ia yang dipakai saat versinya tidak terbaca sama sekali.
# Apakah nginx yang terpasang minimal versi <arg>?
nginx_at_least() {
  local want="$1" ver
  # grep + cut, bukan sed: pola sed penuh backslash mudah rusak saat berkas
  # ini disunting lewat perkakas lain, dan rusaknya diam-diam.
  ver="$(nginx -v 2>&1 | grep -o "nginx/[0-9.]*" | cut -d/ -f2)"
  [ -n "$ver" ] || return 1
  # Dua echo, bukan printf berformat: pola berisi backslash berulang kali rusak
  # saat berkas ini disunting lewat perkakas lain — dan rusaknya diam-diam,
  # menghasilkan perbandingan versi yang selalu menjawab "tidak".
  [ "$( { echo "$want"; echo "$ver"; } | sort -V | head -1 )" = "$want" ]
}

listen_ssl_lines() {
  if nginx_at_least 1.25.1; then
    echo "    listen 443 ssl;"
    echo "    listen [::]:443 ssl;"
    echo "    http2 on;"
  else
    echo "    listen 443 ssl http2;"
    echo "    listen [::]:443 ssl http2;"
  fi
}

# Situs yang dilayani container (Next.js 3000, API Go 8080), bukan berkas di
# /var/www — server block-nya meneruskan ke 127.0.0.1, bukan menyajikan berkas.
#
# Ini TIDAK berarti direktorinya tidak berguna: di situlah docker-compose.yml
# berada, jadi situs container yang punya entri SITE_REPOS tetap diklon seperti
# yang lain. Yang dilewati hanya pembuatan direktori kosong berisi halaman
# sambutan bagi yang tidak punya repo.
#
# Daftarnya eksplisit lewat PROXY_SITES di .env. Menebak dari isi direktori akan
# salah tepat pada saat paling merepotkan, yaitu ketika klon git belum sempat
# berjalan dan direktorinya masih kosong.
is_proxy_site() {
  local target="$1" name
  while read -r name; do
    [ "$name" = "$target" ] && return 0
  done < <(split_csv "${PROXY_SITES:-exam_v2}")
  return 1
}

# Port lokal tujuan proxy sebuah situs container, dari PROXY_PORTS di .env.
#
# Tanpa entri, situs container memakai bentuk DUA upstream milik Exam v2
# (/api/ ke 8080, sisanya ke 3000). Bentuk itu dulunya satu-satunya, dan tetap
# jadi bawaan supaya server yang sudah berjalan tidak berubah diam-diam saat
# repo ini di-pull — tetapi ia salah untuk aplikasi mana pun yang mendengar di
# SATU port, seperti backend FastAPI Kelas Junior di 8000.
#
# Kegagalannya kalau ditebak: permintaan ke /api/... diteruskan ke 8080 yang
# tidak ada isinya, dan nginx menjawab 502 hanya untuk sebagian alamat. Situsnya
# terbuka, halaman depannya normal, dan yang rusak cuma bagian yang paling
# jarang dibuka lebih dulu.
proxy_port() {
  kv_lookup "$1" "${PROXY_PORTS:-}"
}

# Direktori yang HARUS disajikan nginx untuk sebuah situs.
#
# Menunjuk root ke akar repo adalah kesalahan yang menghasilkan dua akibat
# sekaligus, dan keduanya tidak saling menjelaskan:
#
#   1. Laravel tidak punya index.php di akar repo — try_files gagal, jatuh ke
#      indeks direktori, dan nginx menjawab 403. Di log ia terbaca seperti
#      masalah izin, padahal soal alamat.
#   2. app/, storage/, composer.json, dan seluruh kode sumber jadi bisa diunduh
#      siapa saja. Aturan deny hanya menutup berkas berawalan titik.
#
# Urutannya: SITE_ROOTS di .env menang; sisanya dideteksi dari isi direktori.
site_docroot() {
  local site="$1"
  local base="/var/www/${site}"
  local sub

  sub="$(kv_lookup "$site" "${SITE_ROOTS:-}")"
  if [ -n "$sub" ]; then
    echo "${base}/${sub#/}"
    return 0
  fi

  # Laravel, Symfony, dan hampir semua kerangka PHP modern.
  [ -f "${base}/public/index.php" ] && { echo "${base}/public"; return 0; }
  # Next.js `output: "export"` dan sejenisnya.
  [ -f "${base}/out/index.html" ] && { echo "${base}/out"; return 0; }
  # Hasil build Vite/Rollup.
  [ -f "${base}/dist/index.html" ] && { echo "${base}/dist"; return 0; }

  echo "$base"
}

# Isi server block sebuah situs — bagian yang sama untuk HTTP maupun HTTPS.
site_body() {
  local site="$1" php_sock="$2"
  local docroot port
  docroot="$(site_docroot "$site")"

  # Unggahan jawaban bergambar dan impor soal lewat di sini.
  echo "    client_max_body_size 32M;"
  echo ""

  port="$(proxy_port "$site")"
  # Divalidasi di sini, bukan dibiarkan masuk ke berkas konfigurasi. Nilai yang
  # bukan angka membuat `nginx -t` gagal untuk SELURUH server — situs lain yang
  # tadinya sehat ikut tidak dimuat — dan pesan nginx menyebut baris proxy_pass,
  # bukan .env yang sebenarnya salah.
  if [ -n "$port" ]; then
    case "$port" in
      *[!0-9]*) die "PROXY_PORTS: port '$port' untuk situs '$site' bukan angka" ;;
    esac
  fi

  if is_proxy_site "$site" && [ -n "$port" ]; then
    # Aplikasi container yang mendengar di SATU port — seluruh permintaan
    # diteruskan ke sana, tanpa memisahkan /api/. Backend Kelas Junior (FastAPI)
    # menyajikan API, /docs, /admin, dan /media dari satu proses yang sama.
    cat <<CONF
    # ── Aplikasi container (127.0.0.1:${port}) ────────────────────────────
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        "upgrade";
        proxy_set_header Host              \$host;
        # \$remote_addr, BUKAN \$proxy_add_x_forwarded_for — lihat alasannya
        # pada blok dua-upstream di bawah.
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout      300s;
        proxy_send_timeout      300s;
        proxy_request_buffering off;
    }
CONF
  elif is_proxy_site "$site"; then
    cat <<CONF
    # ── API Go ────────────────────────────────────────────────────────────
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        # \$remote_addr, BUKAN \$proxy_add_x_forwarded_for.
        #
        # Yang kedua menyambungkan header X-Forwarded-For yang dikirim
        # pengunjung dengan alamat aslinya. Aplikasi membaca entri pertama —
        # yaitu bagian yang dikarang pengunjung. Cukup mengganti isinya tiap
        # percobaan, dan pembatas login 3-kali-salah hilang sama sekali.
        #
        # Di belakang Cloudflare, 25-cloudflare-realip.sh yang memulihkan
        # \$remote_addr dari CF-Connecting-IP.
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Pengumpulan jawaban dan koreksi otomatis bisa memakan waktu. Timeout
        # pendek di sini berarti jawaban siswa ditolak di detik-detik terakhir
        # ujian — kegagalan yang paling mahal dari semuanya.
        proxy_read_timeout      300s;
        proxy_send_timeout      300s;
        proxy_request_buffering off;
    }

    # ── Next.js ───────────────────────────────────────────────────────────
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        "upgrade";
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }
CONF
  else
    cat <<CONF
    root  ${docroot};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${php_sock};
    }

    location ~ /\.(?!well-known) { deny all; }
CONF
  fi
}

# Tulis server block sebuah situs ke /etc/nginx/sites-available/<situs>.
#
#   write_site_conf <situs> <domain> <socket_php> [berkas_cert] [berkas_kunci]
#
# Bila cert & kunci diisi, blok 443 ikut ditulis dan port 80 hanya mengalihkan.
# Berkas yang isinya sudah sama persis dilewati, sehingga menjalankan ulang
# tidak menghasilkan cadangan palsu maupun reload yang tidak perlu.
write_site_conf() {
  local site="$1" domain="$2" php_sock="$3" cert="${4:-}" key="${5:-}"
  # SITE_DOMAINS boleh memuat beberapa nama untuk satu situs, dipisah "|":
  #   amh=amhriset.com|www.amhriset.com
  #
  # Tanpa ini, www.amhriset.com tidak cocok dengan blok mana pun dan nginx
  # menyajikannya dari blok PERTAMA menurut abjad — lengkap dengan sertifikat
  # milik situs lain. Pengunjung menerima peringatan sertifikat, lalu isi yang
  # sama sekali bukan miliknya.
  local server_names="${domain//|/ }"
  # NGINX_SITES_DIR hanya untuk menguji keluaran fungsi ini tanpa root.
  local avail="${NGINX_SITES_DIR:-/etc/nginx/sites-available}/${site}"
  local tmp
  tmp="$(mktemp)"

  {
    echo "# ${site} — dibuat oleh server-setup (sudo make nginx / make ssl)."
    echo "# Suntingan manual akan tertimpa saat skrip dijalankan ulang;"
    echo "# salinan berkas lama disimpan sebagai ${avail}.orig."
    echo ""

    if [ -n "$cert" ] && [ -n "$key" ]; then
      cat <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${server_names};

    # Cloudflare tetap boleh menyambung lewat 80; sisanya diarahkan ke HTTPS.
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
CONF
      listen_ssl_lines
      cat <<CONF
    server_name ${server_names};

    ssl_certificate     ${cert};
    ssl_certificate_key ${key};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

CONF
      site_body "$site" "$php_sock"
      echo "}"
    else
      cat <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${server_names};

CONF
      site_body "$site" "$php_sock"
      echo "}"
    fi
  } > "$tmp"

  if [ -f "$avail" ] && cmp -s "$tmp" "$avail"; then
    rm -f "$tmp"
    skip "server block $site"
    return 0
  fi

  backup_once "$avail"
  mv "$tmp" "$avail"
  chmod 644 "$avail"
  ok "server block $site → ${server_names}${cert:+ (HTTPS)}"
}

# Pasang Node.js versi mayor tertentu dari NodeSource.
#
#   install_node 22
#
# Dipakai 40-node.sh (build situs di NODE_SITES) dan skrip deploy aplikasi yang
# punya langkah build sendiri (repost-app/15-assets.sh). Ditaruh di sini, bukan
# disalin, karena tiga jebakannya sama di mana pun dan mahal untuk ditemukan
# dua kali:
#
#   1. Paket `npm` bawaan Ubuntu 22.04 menarik Node 12.22 — di bawah syarat
#      minimum hampir semua kerangka yang masih dirawat. Kegagalannya bukan
#      "versi terlalu lama" yang jelas, melainkan galat sintaks di dalam
#      node_modules, yang terbaca seperti paketnya yang rusak.
#   2. Paket nodejs NodeSource sudah memuat npm sendiri dan BENTROK dengan
#      paket `npm` Ubuntu. Yang lama dicabut lebih dulu, bukan ditumpuk.
#   3. "nodistro" bukan salah ketik: NodeSource memakai satu suite untuk semua
#      rilis Debian/Ubuntu, bukan per-codename seperti repo lain.
#
# Mengembalikan 1 bila gagal; pemanggilnya memutuskan apakah itu fatal.
install_node() {
  local want="$1" current keyring repo_log

  case "$want" in
    [0-9]|[0-9][0-9]) ;;
    *) warn "NODE_VERSION='${want}' harus nomor mayor saja (contoh: 22)"; return 1 ;;
  esac

  current=""
  if command -v node >/dev/null 2>&1; then
    current="$(node -v 2>/dev/null | sed -n 's/^v\([0-9]\{1,\}\).*/\1/p')"
  fi

  if [ "${current:-0}" = "$want" ]; then
    skip "Node.js $(node -v) & npm $(npm -v 2>/dev/null)"
    return 0
  fi

  [ -n "$current" ] && log "Node terpasang v${current} — diganti ${want}"

  # Hanya paket dari apt yang dicabut. Node yang dipasang lewat nvm atau tarball
  # tidak tersentuh dpkg, dan mencabut apa pun di /usr/local dari skrip setup
  # bukan wewenangnya.
  if dpkg -s npm >/dev/null 2>&1 || dpkg -s nodejs >/dev/null 2>&1; then
    log "mencabut nodejs/npm bawaan distro"
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -q npm nodejs >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q >/dev/null 2>&1 || true
  fi

  apt_install curl ca-certificates gnupg

  keyring=/usr/share/keyrings/nodesource.gpg
  if [ ! -s "$keyring" ]; then
    log "menambahkan repo NodeSource"
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o "$keyring" \
      || { warn "gagal mengambil kunci NodeSource"; return 1; }
    chmod 644 "$keyring"
  fi

  echo "deb [signed-by=${keyring}] https://deb.nodesource.com/node_${want}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list

  repo_log="$(mktemp)"
  if ! apt-get update >"$repo_log" 2>&1; then
    sed 's/^/       /' "$repo_log"
    rm -f "$repo_log"
    warn "apt-get update gagal setelah menambahkan NodeSource"
    return 1
  fi
  rm -f "$repo_log"

  DEBIAN_FRONTEND=noninteractive apt-get install -y -q nodejs >/dev/null \
    || { warn "gagal memasang nodejs ${want}"; return 1; }
  ok "Node.js $(node -v) & npm $(npm -v)"
}

# Build Next.js/Vite rutin memakan lebih dari 1GB. Di VPS kecil tanpa swap,
# kernel mematikan prosesnya begitu saja — npm melaporkan "Killed" atau kode
# keluar 137, tanpa menyinggung memori sama sekali.
warn_low_memory() {
  local total swap
  total="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  swap="$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  [ "$total" -lt 2048 ] && [ "$swap" -lt 1024 ] || return 0
  warn "RAM ${total}MB, swap ${swap}MB — build bisa dimatikan kernel (exit 137)."
  warn "  Tambahkan swap bila itu terjadi:"
  warn "    sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile"
  warn "    sudo mkswap /swapfile && sudo swapon /swapfile"
}

# Nama database yang aman dipakai MySQL.
sanitize_db_name() {
  echo "$1" | tr '[:upper:]-' '[:lower:]_' | sed 's/[^a-z0-9_]//g'
}

# Blok penangkap untuk Host yang tidak cocok dengan server_name mana pun.
#
# TANPA INI NGINX MENYAJIKAN BLOK PERTAMA MENURUT ABJAD.
#
# Akibatnya bukan sekadar salah halaman: pengunjung yang mengetik domain yang
# belum dikonfigurasi — atau pemindai yang menembak IP server langsung —
# menerima sertifikat milik situs LAIN beserta isinya. Di log, `server:` dan
# `host:` tampak tidak nyambung, dan penyebabnya hampir mustahil ditebak dari
# sana.
#
# 444 menutup koneksi tanpa menjawab apa pun. Untuk permintaan yang memang
# salah alamat, itu jawaban yang paling jujur sekaligus paling murah.
write_default_server() {
  local avail="${NGINX_SITES_DIR:-/etc/nginx/sites-available}/000-default"
  local tmp
  tmp="$(mktemp)"

  cat > "$tmp" <<'CONF'
# Dibuat oleh server-setup — JANGAN disunting manual.
#
# Menangkap Host yang tidak cocok dengan server_name mana pun, supaya nginx
# tidak menyajikan situs pertama menurut abjad berikut sertifikatnya.
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
CONF

  # Kebocoran sertifikat terjadi di 443, bukan 80: nginx memilih blok pertama
  # menurut abjad untuk SNI yang tidak dikenal, lalu menyajikan sertifikat
  # SITUS LAIN. ssl_reject_handshake menolak jabat tangannya sejak awal,
  # sehingga tidak ada sertifikat yang pernah dikirim.
  #
  # Butuh nginx 1.19.4. Pada versi lebih tua tidak ada padanan yang aman:
  # satu-satunya cara adalah sertifikat khusus untuk blok penangkap, dan
  # sertifikat asal-asalan di pintu depan lebih berisiko daripada masalah
  # yang hendak diperbaikinya.
  if nginx_at_least 1.19.4; then
    cat >> "$tmp" <<'CONF'

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}
CONF
  fi

  if [ -f "$avail" ] && cmp -s "$tmp" "$avail"; then
    rm -f "$tmp"
    skip "blok penangkap default"
  else
    mv "$tmp" "$avail"
    chmod 644 "$avail"
    ok "blok penangkap default (Host tak dikenal ditutup)"
  fi
}
