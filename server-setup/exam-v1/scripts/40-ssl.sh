#!/usr/bin/env bash
# HTTPS untuk Exam v1 lewat Let's Encrypt.
#
# Domain ini TIDAK boleh diurus 35-ssl.sh milik setup induk: skrip itu menulis
# ulang server block dengan write_site_conf, yang root-nya bukan public/. Jadi
# sertifikatnya diambil di sini, dan server block-nya tetap ditulis 20-site.sh.
#
# TIDAK MENGHENTIKAN DEPLOY BILA GAGAL. Sertifikat bergantung pada DNS yang
# sudah mengarah ke server ini — keadaan di luar kendali skrip. Situsnya tetap
# dilayani lewat HTTP, dan perintah ini dijalankan lagi setelah DNS siap.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
require_apt

# Sudah punya sertifikat? Tidak ada yang perlu diminta. certbot punya batas laju
# mingguan per domain, dan menabraknya berarti menunggu, bukan mencoba lagi.
if paths="$(site_cert_paths "$APP_DOMAIN")"; then
  read -r certf _ <<< "$paths"
  skip "sertifikat $APP_DOMAIN ($certf)"
  bash "$SCRIPT_DIR/20-site.sh"
  exit 0
fi

if [ "${SSL_METHOD:-cloudflare}" != "letsencrypt" ]; then
  warn "SSL_METHOD di $SETUP_DIR/.env bukan 'letsencrypt' (sekarang: ${SSL_METHOD:-cloudflare})."
  warn "  Origin Certificate Cloudflare diterbitkan setup induk untuk domain di"
  warn "  SITE_DOMAINS — dan domain ini sengaja TIDAK terdaftar di sana."
  warn "  Salin sendiri sertifikatnya ke:"
  warn "    /etc/ssl/cloudflare/${APP_DOMAIN}.pem  dan  .key"
  warn "  lalu jalankan: sudo make site"
  exit 0
fi

apt_install certbot python3-certbot-nginx

if [ -n "${CERTBOT_EMAIL:-}" ]; then
  REG=(-m "$CERTBOT_EMAIL")
else
  # Tanpa email, Let's Encrypt tidak bisa memperingatkan bila perpanjangan
  # berhenti bekerja — dan diamnya baru ketahuan saat sertifikat sudah mati.
  REG=(--register-unsafely-without-email)
  warn "CERTBOT_EMAIL kosong — tidak ada peringatan bila perpanjangan gagal"
fi

# Hook yang memuat ulang nginx setiap kali certbot memperpanjang.
#
# INI YANG MEMBUAT JALUR LET'S ENCRYPT AMAN DIPAKAI. nginx membaca berkas
# sertifikat SEKALI saat start; tanpa reload, perpanjangan berhasil di disk
# tetapi tidak pernah sampai ke pengunjung — situs menyajikan sertifikat lama
# sampai benar-benar kedaluwarsa, tanpa satu pun pesan error.
#
# Berkasnya sama persis dengan yang dipasang 35-ssl.sh, jadi aman bila keduanya
# pernah berjalan di server yang sama.
HOOK=/etc/letsencrypt/renewal-hooks/deploy/10-reload-nginx.sh
if [ -f "$HOOK" ]; then
  skip "hook perpanjangan certbot"
else
  mkdir -p "$(dirname "$HOOK")"
  cat > "$HOOK" <<'HOOKEOF'
#!/bin/sh
# Dipasang oleh server-setup. Lihat scripts/35-ssl.sh.
nginx -t && systemctl reload nginx
HOOKEOF
  chmod +x "$HOOK"
  ok "hook perpanjangan certbot dipasang"
fi

log "meminta sertifikat Let's Encrypt untuk $APP_DOMAIN"
# `certonly`, bukan `--nginx` penuh: certbot hanya MENGAMBIL sertifikatnya,
# sedangkan server block tetap ditulis 20-site.sh. Dua pihak yang sama-sama
# menyunting berkas yang sama akan saling menimpa.
if out="$(certbot certonly --nginx --non-interactive --agree-tos "${REG[@]}" \
          -d "$APP_DOMAIN" 2>&1)"; then
  ok "sertifikat $APP_DOMAIN (90 hari, diperpanjang otomatis)"
  # Server block ditulis ulang agar blok 443 ikut terpasang.
  bash "$SCRIPT_DIR/20-site.sh"
  exit 0
fi

warn "certbot gagal untuk $APP_DOMAIN:"
echo "$out" | tail -8 | sed 's/^/       /'
warn "  Domainnya harus SUDAH mengarah ke server ini dan port 80 terbuka —"
warn "  Let's Encrypt memverifikasi dengan menghubunginya dari luar."
warn "  Di belakang Cloudflare, awan harus ABU-ABU saat verifikasi, atau"
warn "  aktifkan mode 'Full (strict)' setelah sertifikatnya terbit."
warn ""
warn "Situs tetap dilayani lewat HTTP. Ulangi setelah DNS siap:"
warn "  sudo make ssl"
exit 0
