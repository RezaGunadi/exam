#!/usr/bin/env bash
# Pasang nginx + PHP-FPM, siapkan direktori situs, server block, dan symlink.
#
# NGINX HOST ADALAH PINTU DEPAN TUNGGAL (port 80/443) untuk semua proyek.
# Aplikasi berbasis container TIDAK membuka port publik sendiri — mereka hanya
# mendengar di 127.0.0.1 dan diteruskan dari sini. Dengan begitu tidak ada
# rebutan port, dan sertifikat SSL cukup diurus di satu tempat.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
load_env "$(dirname "$SCRIPT_DIR")"

require_root
require_apt

log "nginx + PHP-FPM"
apt_install nginx php-fpm php-mysql php-mbstring php-zip php-gd php-curl php-xml

# Socket PHP-FPM baru ADA setelah layanannya berjalan, jadi layanannya
# dinyalakan lebih dulu. Sebelumnya skrip langsung berhenti bila socket belum
# muncul — padahal penyebabnya cuma layanan yang belum start, bukan pemasangan
# yang gagal. (find_php_sock ada di lib.sh; 35-ssl.sh memakainya juga.)
PHP_SOCK="$(find_php_sock || true)"
if [ -z "$PHP_SOCK" ]; then
  log "menyalakan PHP-FPM"
  for unit in $(systemctl list-unit-files --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}'); do
    systemctl enable --now "$unit" >/dev/null 2>&1 || true
  done
  sleep 2
  PHP_SOCK="$(find_php_sock || true)"
fi

if [ -z "$PHP_SOCK" ]; then
  warn "socket PHP-FPM tidak ditemukan di /run/php/."
  warn "  Periksa: systemctl status 'php*-fpm'"
  die "PHP-FPM belum berjalan — situs PHP tidak bisa dikonfigurasi"
fi
ok "PHP-FPM ($PHP_SOCK)"

systemctl enable --now nginx >/dev/null 2>&1 || true

# ── Direktori situs + server block ─────────────────────────────────────────
# Repositori diambil dari SITE_REPOS, domain dari SITE_DOMAINS — keduanya
# berformat "nama=nilai" dipisah koma dan dibaca lewat kv_lookup di lib.sh.
#
# Situs tanpa entri repo tetap dibuatkan direktori kosong — tidak semua proyek
# sudah punya repo, dan exam_kelas_privat_v2 memang tidak butuh isi apa pun
# karena nginx hanya meneruskannya ke container.

log "menyiapkan situs"
while read -r site; do
  [ -n "$site" ] || continue
  root="/var/www/${site}"
  repo="$(kv_lookup "$site" "${SITE_REPOS:-}")"
  domain="$(kv_lookup "$site" "${SITE_DOMAINS:-}")"

  if [ -d "$root/.git" ]; then
    # Sudah berupa klon. TIDAK di-pull otomatis: menarik perubahan diam-diam
    # ke situs yang sedang melayani pengunjung bisa menyalakan versi yang belum
    # diuji. Pembaruan adalah keputusan sadar, bukan efek samping setup.
    skip "klon $site (perbarui manual: git -C $root pull)"
  elif [ -d "$root" ] && [ -n "$(ls -A "$root" 2>/dev/null || true)" ]; then
    skip "direktori $root sudah berisi"
  elif [ -n "$repo" ]; then
    # Berlaku juga untuk situs container. nginx memang tidak pernah membaca
    # /var/www/<situs>, tetapi DI SANALAH docker-compose.yml berada — tanpa klon
    # ini, pindah server berarti menyalin aplikasinya dengan tangan lagi.
    apt_install git >/dev/null 2>&1 || true
    log "mengklon $site"
    rm -rf "$root"
    clone_log="$(mktemp)"
    # Klon dijalankan sebagai root (lewat sudo), jadi kunci SSH yang dipakai ada
    # di /root/.ssh — BUKAN milik user yang mengetik sudo. Selisih itu adalah
    # penyebab paling sering "gagal klon" yang tidak jelas sebabnya.
    if git clone --depth 1 "$repo" "$root" >"$clone_log" 2>&1; then
      # Situs container tidak disajikan nginx, jadi tidak perlu milik www-data —
      # dan JANGAN dijadikan miliknya. `sudo git -C ... pull` akan ditolak
      # dengan "detected dubious ownership": git membandingkan pemilik repo
      # dengan SUDO_UID, dan www-data tidak akan pernah cocok.
      is_proxy_site "$site" || chown -R www-data:www-data "$root"
      ok "klon $site dari $repo"
    else
      # Repo privat butuh kunci SSH. Gagal klon TIDAK boleh menghentikan
      # penyiapan situs lain — direktorinya tetap dibuat agar nginx bisa
      # dikonfigurasi, dan isinya menyusul manual.
      mkdir -p "$root"
      is_proxy_site "$site" || chown -R www-data:www-data "$root"
      warn "gagal mengklon $site dari $repo"
      # Pesan git-nya ditampilkan apa adanya. Sebelumnya dibuang ke /dev/null,
      # sehingga "Permission denied (publickey)" dan "Repository not found" —
      # dua kegagalan dengan perbaikan yang sama sekali berbeda — terlihat
      # identik dari luar.
      sed 's/^/       /' "$clone_log"
      warn "  Repo privat? Periksa: sudo ssh -T git@github.com"
      warn "  Catatan kunci SSH ada di .env.example, bagian SITE_REPOS."
    fi
    rm -f "$clone_log"
  elif is_proxy_site "$site"; then
    # Situs container tanpa entri di SITE_REPOS. Tidak dibuatkan direktori:
    # nginx tidak pernah membacanya, dan direktori kosong berisi halaman
    # sambutan hanya menyesatkan orang yang mencari kode aplikasinya di sana.
    skip "direktori $root (situs container tanpa repo)"
  else
    mkdir -p "$root"
    cat > "${root}/index.html" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>${site}</title>
<h1>${site}</h1>
<p>Direktori situs sudah disiapkan. Ganti berkas ini dengan aplikasi Anda.</p>
HTML
    chown -R www-data:www-data "$root"
    ok "direktori $root (tanpa repo di SITE_REPOS)"
  fi

  avail="/etc/nginx/sites-available/${site}"
  if [ -n "$domain" ]; then
    # Situs berdomain dikelola sepenuhnya dari .env. Bila sertifikatnya sudah
    # ada, blok 443 ikut ditulis di sini juga — supaya `make nginx` yang
    # dijalankan ulang setelah `make ssl` tidak diam-diam mematikan HTTPS.
    if paths="$(site_cert_paths "$domain")"; then
      read -r certf keyf <<< "$paths"
      write_site_conf "$site" "$domain" "$PHP_SOCK" "$certf" "$keyf"
    else
      write_site_conf "$site" "$domain" "$PHP_SOCK"
    fi
  elif [ -f "$avail" ]; then
    # Tanpa domain di .env, skrip tidak tahu nilai yang benar — dan menimpanya
    # dengan <situs>.local akan mematikan situs yang sudah jalan.
    skip "server block $site (isi SITE_DOMAINS untuk mengelolanya dari .env)"
  else
    # Belum ada domain dan belum ada server block: dibuatkan dengan nama
    # sementara agar konfigurasi nginx tetap valid, tapi situsnya belum bisa
    # dibuka dari internet sampai SITE_DOMAINS diisi.
    write_site_conf "$site" "${site}.local" "$PHP_SOCK"
    warn "$site belum punya domain — tambahkan ke SITE_DOMAINS di .env"
  fi

  enabled="/etc/nginx/sites-enabled/${site}"
  if [ -L "$enabled" ]; then
    skip "symlink $site"
  else
    ln -s "$avail" "$enabled"
    ok "symlink $site"
  fi
done < <(split_csv "${SITES:-}")

# Situs bawaan nginx sering menyerobot permintaan tanpa domain cocok.
if [ -L /etc/nginx/sites-enabled/default ]; then
  rm -f /etc/nginx/sites-enabled/default
  ok "situs bawaan nginx dinonaktifkan"
fi

log "menguji konfigurasi nginx"
nginx -t || die "konfigurasi nginx tidak valid — tidak ada yang di-reload"
systemctl reload nginx
ok "nginx dimuat ulang"
