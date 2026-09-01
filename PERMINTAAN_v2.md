# Daftar Permintaan — Exam v2

Catatan seluruh permintaan yang pernah disampaikan, beserta keadaannya.
Disusun agar tidak ada yang terlewat; diperbarui setiap kali ada yang selesai
atau ada permintaan baru.

Terakhir diperbarui: **1 September 2026** (putaran ke-7)

Berkas ini TERPISAH dari `PLAN_EXAM_V1_V2.md`, yang berisi rencana teknis 12
item hasil pembacaan kode. Yang di sini adalah permintaan sebagaimana
disampaikan — bahasanya dipertahankan supaya mudah dicocokkan kembali.

**Legenda:** ✅ selesai & terpasang · 🔨 sebagian · ⬜ belum · ⏸️ menunggu Anda

---

## 1. Branding premium

| # | Permintaan | Keadaan |
|---|---|---|
| 1.1 | Domain khusus per sekolah, landing page & isi dalam ikut merek sendiri | ✅ |
| 1.2 | Warna primary/secondary/accent bisa diatur tiap sekolah | ✅ |
| 1.3 | Mesin tetap satu, tampilan berbeda hanya bila domainnya terdaftar | ✅ |
| 1.4 | Update di panel otomatis pasang site-available + SSL | ✅ kode · ⏸️ timer belum dipasang di server |
| 1.5 | Upload logo navbar | ✅ |
| 1.6 | Upload logo untuk favicon | ✅ |
| 1.7 | Daftar sekolah ber-branding + tautannya di halaman depan | ✅ (tersembunyi selama belum ada brand aktif) |
| 1.8 | Add-on "Premium branding page" di tagihan | ✅ |

**Menunggu Anda:** belum ada satu domain pun terdaftar, jadi jalur ini belum
pernah diuji di produksi. Diuji lokal terhadap API tiruan: nama, warna, favicon,
dan judul tab semuanya benar, tanpa kebocoran merek induk.

---

## 2. Pembayaran & tagihan

| # | Permintaan | Keadaan |
|---|---|---|
| 2.1 | Set DP, diskon, dan add-on dari panel | ✅ |
| 2.2 | Add-on: Exclusive page, Lain-lain, free text | ✅ |
| 2.3 | Menu langganan dihitung dari kapasitas ujian serentak | ✅ |
| 2.4 | Langganan bisa digeser ke token | ✅ |
| 2.5 | Invoice manual untuk pembayaran tunai | ✅ |
| 2.6 | Invoice DP menampilkan total dan sisa tagihan | ✅ |
| 2.7 | Tombol pelunasan dari sekolah, disahkan owner | ✅ |
| 2.8 | Invoice bisa disesuaikan add-on dan diskonnya | ✅ |

**Koreksi:** saya sempat menaikkan `max_concurent_exam` sebagai hal yang perlu
Anda putuskan. Itu keliru. Dari 111 sekolah yang masih di angka bawaan, 85 tidak
punya siswa sama sekali, 24 punya 1–5 siswa, dan nol berlangganan aktif — angka
"110 dari 113" benar secara hitungan tetapi menyesatkan sebagai tanda bahaya.

---

## 3. WhatsApp

| # | Permintaan | Keadaan |
|---|---|---|
| 3.1 | Empat alamat webhook Fonnte siap salin di panel | ✅ |
| 3.2 | Panel chat: baca dan balas percakapan | ✅ |
| 3.3 | Follow-up lead langsung dari halaman Leads | ✅ |
| 3.4 | FU lead membuka chat dengan pesan SIAP KIRIM tapi belum terkirim | ✅ |
| 3.5 | Chatbot balas otomatis yang mengerti konteks | ✅ berbasis niat, bawaan MATI |
| 3.6 | Pesan terkirim & daftar chat tidak muncul di panel | ✅ AKAR: kolom salah nama |
| 3.7 | Percakapan disimpan di basis data sendiri + migrasi | ✅ tabel `wa_chat_messages` |

**Menunggu Anda:** WA Gateway Token masih kosong dan keempat webhook belum
ditempel di dashboard Fonnte. Selama itu, panel chat hanya bisa menampilkan
riwayat kirim — dan sekarang riwayatnya pun masih nol.

**Akar 3.6 — dan ini yang paling perlu diketahui:** model `WaSendLog` memetakan
field `Message` ke kolom `message`, padahal namanya `message_body`. MySQL
menolak **setiap** kueri dengan Error 1054, jadi panel tidak menampilkan apa pun
DAN tidak menyimpan apa pun — sementara HTTP tetap 200 dan layarnya hanya tampak
"belum ada percakapan". Guard kolom yang sudah ada melewatkannya karena ia hanya
menyapu model yang ikut AutoMigrate, sedangkan `WaSendLog` justru dikecualikan.
Guard-nya kini menyapu keduanya.

Ternyata `wa_send_logs` juga **bukan** tempat yang benar: enum `message_type`-nya
hanya mengenal jenis kampanye (`offer`, `follow_up_1..4`, `reminder_*`) — tidak
ada nilai yang berarti "balasan chat". Percakapan kini punya tabel sendiri.

---

## 4. Tampilan

| # | Permintaan | Keadaan |
|---|---|---|
| 4.1 | Halaman depan seprofesional v1 | ✅ hero gelap, skala, irama gelap-terang |
| 4.2 | Navbar sama di semua halaman publik | ✅ |
| 4.3 | Footer setara v1 | ✅ empat kolom |
| 4.4 | Banyak yang tidak center | ✅ akar: `.section-heading` tanpa margin auto |
| 4.5 | Ikon terlihat tidak profesional | ✅ 17 ikon pindah ke Lucide |
| 4.6 | Perpustakaan & LMS masuk halaman depan | ✅ |
| 4.7 | Konten SEO kurang | ✅ dari ~40 jadi 555–715 kata per halaman |
| 4.8 | Cek nilai tanpa login | ✅ (sudah ada, tapi tidak tertaut dari mana pun) |
| 4.9 | Gaya lebih mewah, elegan, profesional | 🔨 tipografi, kedalaman, kekangan — masih berlanjut |
| 4.10 | Kartu pelajar sedekat mungkin dengan v1 | ✅ |
| 4.11 | Judul ujian jelas (kelas, mapel) | ✅ |
| 4.12 | Filter rekap lengkap (siswa, mapel) | ✅ |
| 4.13 | Tombol edit & detail di daftar siswa | ✅ |
| 4.14 | Layar admin diperiksa satu per satu | 🔨 baru `/admin/students` |

| 4.15 | Dashboard owner tidak menampilkan identitas/token sekolah | ✅ |
| 4.16 | Halaman depan selengkap v1 | ✅ 1.899 → 2.350 kata; v1 2.569 |
| 4.17 | Simulasi biaya: siswa × mapel × ujian per semester × 2 | ✅ |

---

## 7. Iklan

| # | Permintaan | Keadaan |
|---|---|---|
| 7.1 | Iklan tidak tampil ke siswa, admin, dan guru | ✅ `ads_enabled`, bawaan MATI |

**Yang ditemukan saat memeriksanya:** iklan bukan sekadar tampil — halaman
`/ads` adalah tujuan **paksa setiap login** dari sekolah tanpa langganan aktif,
lengkap dengan hitung mundur 20 detik. Pada 1 September 2026 itu berarti 110
dari 113 sekolah dan **227 orang**: 108 admin, 100 siswa, 19 guru. Iklan kursus
pihak ketiga di sana sudah tayang **72 kali**, padahal jendela tayangnya berakhir
10 Januari 2026 — sebuah fallback "ambil iklan id 1" membuat jendela itu tidak
berarti apa-apa. Fallback tersebut dibuang; halaman `/ads` tetap ada dengan
informasi aktivasinya saja.

---

## 8. Owner: kendali tenant

| # | Permintaan | Keadaan |
|---|---|---|
| 8.1 | Filter sekolah per jenis langganan | 🔨 |
| 8.2 | Filter sekolah per tanggal aktif terakhir | 🔨 |
| 8.3 | Owner mengatur aktif sampai kapan | 🔨 backend sudah ada, layar menyusul |
| 8.4 | Owner mengatur jumlah user DAN ujian serentak (harus bisa beda) | 🔨 backend ✅, layar menyusul |
| 8.5 | Owner bisa mengunggahkan logo sekolah | 🔨 backend ✅, layar menyusul |
| 8.6 | Branding premium: navbar & favicon memakai logo yang diunggah | ✅ terpasang, belum diuji di domain sungguhan |
| 8.7 | Semua sekolah bisa dicari, tidak dibatasi | ✅ AKAR: per_page dipatok 100, 13 sekolah tak pernah termuat |
| 8.8 | Semua filter select yang mengambil data bisa dicari | 🔨 12 layar; sisanya menyusul |
| 8.9 | Tombol lihat sandi | ✅ 11 isian |
| 8.10 | QR & referral token dibuat saat data dibuat, bukan backfill harian | ✅ kait model |

---

## 10. Domain

| # | Permintaan | Keadaan |
|---|---|---|
| 10.1 | Tukar domain: v2 ke ujian.kelasprivat.id, v1 tetap bisa dipakai | ✅ **sudah aktif** |

v2 kini di **ujian.kelasprivat.id** — alamat yang selama ini dikenal pemakai.
v1 pindah ke **exam.kelasprivat.id** dan tetap hidup. Sertifikat untuk kedua
nama sudah ada sebelumnya, jadi tidak perlu menerbitkan yang baru. `APP_URL`
kedua aplikasi ikut ditukar — tanpa itu tautan reset sandi v1 akan mendarat di
v2, membawa token yang tidak dikenali aplikasi itu.

Cadangan vhost tersimpan di server: `/root/cadangan-exam_v{1,2}.20260901-213155`.

---

## 11. Tagihan manual & invoice

| # | Permintaan | Keadaan |
|---|---|---|
| 11.1 | Invoice manual untuk yang sudah bayar tunai | ✅ |
| 11.2 | Bisa set diskon saat membuat | ✅ |
| 11.3 | Bisa invoice DP dulu | ✅ |
| 11.4 | Tagihan DP menampilkan sisa dan tenggat | ✅ |
| 11.5 | Di admin sekolah: tombol melunasi, bukan invoice | ✅ kuitansi hanya bila lunas |
| 11.6 | Tagihan manual bisa menambah add-on | ✅ |
| 11.7 | Rincian: dasar, add-on, diskon, total | ✅ |
| 11.8 | Centang lunas ambigu — pakai toggle | ✅ tiga keadaan eksplisit |

---

## 12. Cacat yang Anda temukan, dan akarnya

| # | Laporan | Akar sebenarnya | Keadaan |
|---|---|---|---|
| 12.1 | Tampilan ponsel meluber ke kanan | `.button{width:100%}` di bawah 720px mengenai sepasang tombol navbar: wadahnya menyusut ke 163px, dua tombol jadi 163px masing-masing → luap 60px | ✅ 0px di 320/360/390/414, delapan halaman |
| 12.2 | Register "terlalu banyak pendaftaran" | Jatah 3/jam dihitung SEBELUM validasi, jadi 4 kali salah ketik memakannya habis | ✅ dipisah: 30 percobaan, 3 pendaftaran berhasil |
| 12.3 | Panel error tidak menjelaskan apa pun | `recentError` tidak pernah menyimpan pesannya | ✅ sebabnya ikut tampil |
| 12.4 | Balas otomatis belum lengkap | Mengundang "sebutkan jumlahnya" lalu mengabaikan jawabannya | ✅ menghitung perkiraan biaya |
| 12.5 | Pesan masuk tercatat dua kali | Fonnte tidak selalu mengirim id, dedup lewat `external_id` melewatkannya | ✅ kembar dalam 2 menit ditolak |
| 12.6 | Beda Exclusive page vs Premium branding | Exclusive page tidak punya kode apa pun — hanya baris tagihan | ✅ dibuang (keputusan Anda) |

---

## 13. Belum dikerjakan dari putaran ini

| # | Permintaan | Keadaan |
|---|---|---|
| 13.1 | Hasil stress test belum jelas hasilnya apa | ✅ vonis + sebab, dihitung server |
| 13.2 | Stress test: last result belum ada | ✅ disimpan di `app_settings`, bertahan |
| 13.3 | Stress test: optimum & max concurrent belum ada | ✅ kapasitas puncak & aman, berikut dasarnya |
| 13.4 | Sisa select yang belum bisa dicari | 🔨 37 → 13, dan sisanya daftar pendek |

---

## 14. Putaran ketujuh

| # | Laporan | Akar sebenarnya | Keadaan |
|---|---|---|---|
| 14.1 | Upload logo: "Tidak bisa menghubungi server" | `apiFetchForm` tak pernah menyetel method → fetch memakai GET, peramban menolak GET berbadan isi **sebelum** dikirim; tanpa jejak di log mana pun | ✅ |
| 14.2 | Navbar ponsel jelek, tidak melipat seperti v1 | Isinya ditumpuk, bukan dilipat | ✅ 71px (8% layar), diukur |
| 14.3 | Token tetap tampil padahal langganan | Hanya chip sidebar yang disembunyikan; kartu di halaman pembayaran belum | ✅ keduanya, dan muncul lagi saat langganan berakhir |
| 14.4 | Belum bisa unduh invoice DP | Hanya ada dua dokumen; setoran DP tidak punya dokumen yang mengakuinya | ✅ kuitansi DP |
| 14.5 | Lunasi sisa langsung lunas tanpa bukti | Klaim kosong tanpa lampiran | ✅ wajib bukti, tetap menunggu, notif WA menyebut **sisa** |
| 14.6 | Pemilih berkas terbuka tanpa penjelasan | Jendela sistem tidak bisa diberi keterangan | ✅ dialog penjelas sebelum terbuka |
| 14.7 | Pemindai tidak ada di perpustakaan | Endpoint `resolve-copy` sudah ada, pemindainya tidak pernah dipasang | ✅ kamera di 2 layar |
| 14.8 | "Aktif sampai" tidak terisi otomatis | Diisi `tanggal()` format manusia; `<input type=date>` menuntut YYYY-MM-DD dan menolaknya diam-diam | ✅ |
| 14.9 | Tahun ajaran default 2027/2028 | Dihitung dari tahun berikutnya, bukan bulan Juli | ✅ pilihan ±2 tahun, bawaan yang berjalan |
| 14.10 | Panel galat tidak bisa dicari | — | ✅ cari alamat/status/sebab/jam |
| 14.11 | Paket soal terlalu sempit | Dipatok 320px | ✅ rasio 40/60 |
| 14.12 | "Siswa #156", "Ujian #288" di 7.436 baris | `ExamAssignment` **tidak punya field relasi**; `Preload` menunjuk field yang tidak ada dan gagal diam-diam | ✅ + kolom email |
| 14.13 | Banyak aset rusak | Basis data menyimpan **kunci objek** tanpa host; disusun jadi alamat situs ini → 404 | ✅ 18 logo & 4 tanda tangan terbukti terbuka |
| 14.14 | Dua jadwal QR/referral masih ada | Sudah digantikan kait model + backfill boot | ✅ dibuang, fungsinya juga |

---

## 15. Belum dikerjakan

| # | Permintaan | Keadaan |
|---|---|---|
| 15.1 | `lms.kelasprivat.id` | ⬜ pustaka varian dibuat, halaman & DNS belum |
| 15.2 | `db.kelasprivat.id` + SSL untuk panel basis data | ⏸️ **DNS belum diarahkan** — vhost sudah bernama itu, sertifikat tidak bisa terbit tanpa DNS. Sekarang panelnya di `http://IP:8081`, sandi lewat **tanpa enkripsi** |
| 15.3 | Tambah/hapus kategori buku pindah ke owner | ⬜ kategori per sekolah (669 baris); jalur "Lainnya" saat input buku terpisah dan tidak akan terpengaruh |
| 15.4 | Rich text untuk isi cerita/stimulus | ⬜ isian masih textarea polos, HTML tampil mentah |
| 15.5 | Tanda tangan kepala sekolah di profil sekolah | 🔨 kolom `schools.signature_image` **sudah ada** dan 4 sekolah sudah mengisinya — yang kurang isian di layar |
| 15.6 | Penyelaras brand (vhost + SSL) di server | ⏸️ menunggu izin Anda |

**Yang sudah bisa dicari** — daftar terpanjang yang paling sering dicari orang:
paket soal (174 di produksi), siswa, kelas, mata pelajaran, tutor, peminjam
perpustakaan, soal cerita, kategori buku, ruang kelas siswa, dan sekolah.

**Yang sengaja dibiarkan:** 13 sisanya berisi daftar pendek — tahun ajaran,
semester, jenis pembayaran perpustakaan, daftar kamera. Mengubahnya menjadi
kotak pencarian menambah langkah tanpa menambah apa pun: pilihannya sudah
terlihat seluruhnya begitu daftarnya terbuka. `PilihCari` kini menyesuaikan
diri — di bawah sembilan pilihan ia menampilkan daftar biasa tanpa kotak
ketik — jadi mengubah sisanya kapan pun aman dan hanya soal keseragaman
tampilan, bukan fungsi.
| 13.5 | Owner: "Approve" ambigu, detail tagihan tidak bisa dibuka | ✅ "Sahkan lunas/pelunasan" + tombol Detail |
| 13.6 | Balas otomatis tidak menjawab jumlah siswa | ✅ akar: jeda 30 menit membungkam undangannya sendiri |
| 13.7 | Pesan masuk masih tersimpan ganda | ✅ akar: dedup baca-lalu-tulis kalah balapan; kini indeks unik |

**Cara angka kapasitas dihitung** — ditulis di sini supaya bisa dibantah, bukan
dipercaya: throughput terukur ÷ 0,05 permintaan per siswa per detik. Angka 0,05
diturunkan dari layar ujian yang sebenarnya (autosave debounce 700 ms, heartbeat
60 detik, revalidate 60 detik ≈ 3 permintaan/menit). "Aman" = 70% dari itu,
menyisakan ruang untuk lonjakan saat semua siswa menekan mulai bersamaan. Bila
ada satu saja permintaan yang gagal, angkanya **tidak ditampilkan**: yang
terukur saat itu bukan kecepatan melayani, melainkan kecepatan menolak.

---

## 9. LMS sebagai situs terpisah

| # | Permintaan | Keadaan |
|---|---|---|
| 9.1 | `lms.kelasprivat.id` — mesin sama, landing page sendiri, branding LMS lengkap, terpisah dari branding premium | ⬜ belum dimulai |

Belum disentuh sama sekali. Berbeda dari branding premium: yang ini domain
milik sendiri dengan halaman depan yang menonjolkan sisi LMS-nya (kelas,
materi, tugas, perpustakaan), bukan sisi ujiannya.

---

## 5. Perbaikan yang diminta langsung

| # | Permintaan | Keadaan |
|---|---|---|
| 5.1 | Menu SEB disembunyikan | ✅ |
| 5.2 | Scheduler & AI Scoring otomatis, kendalinya di owner | ✅ (AI Scoring dikembalikan ke admin — layarnya per sekolah) |
| 5.3 | Toast bila unduh lembar jawaban tidak diizinkan | ✅ |
| 5.4 | Lampiran esai jelas di semua layar | ✅ |
| 5.5 | Tombol unduh disembunyikan bila tidak diizinkan | ✅ |
| 5.6 | Kolom kode kartu siswa dihapus | ✅ (pemindai USB tetap jalan lewat tangkapan ketikan) |
| 5.7 | Tombol tumpang tindih di kolom Aksi | ✅ |
| 5.8 | Teks tidak kontras di kartu | ✅ |
| 5.9 | Chrome jangan ditutup saat kerja | ✅ |

---

## 6. Setelan panel

| # | Permintaan | Keadaan |
|---|---|---|
| 6.1 | R2 public URL bisa diisi | ✅ |
| 6.2 | URL Gemini/Groq tidak perlu ada isiannya | ✅ dibuang, bawaannya sudah sama dengan v1 |
| 6.3 | Model Gemini/Groq disamakan dengan v1 | ✅ sudah sama sejak awal |
| 6.4 | Penjelasan Scheduler Token & Stress Token | ✅ ditulis di labelnya |

---

## Menunggu Anda — tidak bisa dilanjutkan tanpa ini

1. **WA Gateway Token** (Fonnte) — tanpa ini panel chat tidak bisa mengirim.
2. **Tempel 4 URL webhook** di dashboard Fonnte — tanpa ini tidak ada pesan masuk.
3. ~~Daftarkan satu domain brand~~ — **sudah**: `ibssmpitalikhlas.kelasprivat.id`.
4. **Izin memasang penyelaras brand di server** — dan ini mendesak: layar
   menjanjikan "vhost dan sertifikatnya terpasang dalam 5 menit berikutnya",
   padahal di server **tidak ada timer, unit, maupun cron** yang mengerjakannya.
   Tidak ada vhost dan tidak ada sertifikat untuk domain itu. Janji di layar
   harus dicabut atau penyelarasnya dipasang; sekarang layarnya berbohong.
5. ~~`max_concurent_exam` per sekolah~~ — **DICORET, saya keliru menaikkannya.**
   Rumusnya memang `max_concurent_exam × Rp 3.500 × 12`, tetapi dari 111 sekolah
   yang masih di angka bawaan: 85 **tidak punya siswa sama sekali**, 24 punya
   1–5 siswa, dan **nol** berlangganan aktif. Yang benar-benar berlangganan
   sudah menyetelnya sendiri. Tidak ada yang perlu diputuskan.
6. **`r2_public_url`** — agar logo disajikan dari CDN, bukan lewat server.

---

## Belum pernah disapu sama sekali

Bukan permintaan, tetapi celah yang saya ketahui dan belum dikerjakan:

- **Pembatasan laju** — baru login QR dan cek nilai yang punya.
- **Validasi unggahan selain logo brand** — logo brand memeriksa isi berkas;
  unggahan lain masih percaya ekstensinya.
- **Aksesibilitas layar ujian** — layar yang paling lama dipakai siswa, dan
  belum pernah diperiksa sekali pun.
