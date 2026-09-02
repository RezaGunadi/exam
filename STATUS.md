# Status Exam v2 — Apa yang Sudah, Apa yang Belum

Satu daftar untuk seluruh pekerjaan. Menggantikan tiga berkas terpisah
(`PERMINTAAN_v2.md`, `PLAN_UI_V1_V2.md`, `PLAN_EXAM_V1_V2.md`) sebagai tempat
melihat keadaan; ketiganya tetap ada sebagai catatan rinci.

Diperiksa langsung ke kode dan produksi pada **2 September 2026** — bukan dari
ingatan. Yang tidak dicentang berarti benar-benar belum, bukan belum sempat
dicek.

---

## BELUM — disusun dari yang paling saya dahulukan

**Urutan baru mengikuti permintaan Anda (2 September): UI/UX lebih dulu,
fitur belakangan** — supaya fitur tidak dibangun di atas tampilan yang masih
akan berubah, lalu dikerjakan dua kali.

**Di dalam UI, halaman TANPA LOGIN tetap lebih dulu.**
Halaman itu dilihat orang yang belum tentu jadi pelanggan, dan kesan
pertamanya tidak bisa diulang — sementara layar setelah login dilihat orang
yang sudah memakai sistemnya setiap hari dan sudah terbiasa.

### ✅ 1. Template halaman tanpa login — SELESAI
- [x] Halaman depan — bagian **testimoni** yang ada di v1 (isinya dari panel, bukan karangan v1)
- [x] Masuk & Daftar — isian **"tahu dari mana"** yang v1 kumpulkan dan v2 hilangkan
- [x] Harga — tidak ada di v1 (di sana bagian halaman depan); milik v2, tetap
- [x] Cek nilai — saringan **mata pelajaran**
- [x] Halaman statis — **kebijakan privasi v2 hanya SATU KALIMAT**; v1 543 kata. Kini 624 kata, dirender server, berstruktur
- [x] Halaman SEO — sudah sebanding (652–821 kata vs v1 683–961)

Yang disamakan **susunan dan tampilannya**, bukan hanya fiturnya: urutan
bagian, pengelompokan, penamaan tombol, dan letak tindakan. Layar yang punya
fitur sama tetapi tersusun berbeda tetap terasa asing.

Yang **tidak** ikut disamakan: kerangka teknisnya. v1 memakai Bootstrap dan
jQuery; menyalin markup-nya berarti membawa serta yang justru ingin
ditinggalkan.

### ✅ 2. Template halaman setelah login — SELESAI
- [x] Kerangka & laci ponsel — sudah setara v1 sejak awal (z-index pun sudah disamakan)
- [x] **Luapan 126px di SETIAP layar setelah login** — nol di 320px, sepuluh layar diukur

Dua akar, keduanya terukur: `.inline-alert` adalah flex baris yang memuat
tombol berlebar 100% (kali **ketiga** aturan itu menyebabkan luapan), dan
`.shell` memakai `1fr` alih-alih `minmax(0, 1fr)`.

### ✅ 3. `lms.kelasprivat.id` — SELESAI 2 September
- [x] Blok server 443 + sertifikat sendiri
- [x] Halaman depan bervarian LMS
- [x] Warna varian berlaku **setelah login** juga (admin, guru, siswa)

Domain itu sebelumnya membuka **"STN Smart System"** — aplikasi milik orang
lain — karena tidak ada blok 443 untuk namanya, jadi nginx menyajikan blok 443
pertama yang ada. Sebab yang sama sudah dua kali terjadi (`db.kelasprivat.id`
dan domain brand).

Wajah LMS membuka dengan **modul** (kelas, materi, tugas, absensi,
perpustakaan, raport); wajah ujian tetap membuka dengan fitur ujian. Bagiannya
satu, ditempatkan di dua posisi — bukan digandakan.

Paletnya berbeda sampai ke dalam: `#12403a` hijau-teal untuk LMS, `#0c2947`
biru tua untuk ujian, dipasang di layout akar sehingga mengenai semua layar.
Urutan yang menang: **warna sekolah > palet varian > palet induk**.

Dijaga `uji-varian-situs.mjs` dan `uji-warna-brand.mjs` (110 pemeriksaan, 2
varian). Keduanya sudah dibuktikan **gagal** ketika variannya dilepas dan
ketika paletnya disamakan — dua kegagalan yang sebelumnya tidak bersuara.

### ✅ 4. Siswa tidak melihat gambar soal — SELESAI 2 September
- [x] Teks soal dirender sebagai HTML, bukan teks polos
- [x] Opsi jawaban ikut (479 set ber-HTML)
- [x] Pembersih HTML dengan daftar-putih dari sensus isi produksi
- [x] `student_text` (jawaban esai siswa) tidak lagi dirender mentah
- [x] JSON-LD lewat `jsonUntukScript()`

**Ditemukan saat menyurvei butir rich text, bukan dilaporkan.** Layar ujian
merender `question_text` sebagai teks polos, jadi yang dibaca siswa adalah

    Look at the picture below!<div><br></div><div><img src="https://asset...

tanpa gambarnya. Di produksi **4.797 dari 5.417 soal berisi HTML** dan **3.184
memuat `<img>`**. v1 merendernya sebagai HTML, jadi soal yang sama tampil benar
di v1 dan rusak di v2 — dengan basis data yang sama.

Sekalian: `review.student_text` — jawaban esai yang diketik **siswa** —
dirender mentah di layar guru. Satu siswa bisa menjalankan kode di peramban
gurunya saat dinilai. Empat titik semacam ini nyaris terlewat, jadi ada
penjaga yang menolak `dangerouslySetInnerHTML` di luar `<IsiKaya>`.

Daftar-putihnya dari sensus, bukan tebakan: div 2.238, br 2.070, img 3.184,
b 417, i 248, li 105, ol 99, audio 3, dan satu `iframe` yang ternyata sematan
YouTube yang sah. Delapan contoh isi produksi diuji — semuanya selamat utuh.
38 vektor serangan, 12 isi sah, stabil dibersihkan dua kali.

---

## BELUM — UI/UX (dikerjakan lebih dulu)

### ✅ Rich text — SELESAI 2 September
- [x] Penyunting berformat di `/admin/question-stories`
- [x] Penyunting yang sama di teks soal `/admin/questions`
- [x] Tiap opsi jawaban (bilah ringkas, sisip gambar tetap ada)
- [x] Pemeriksaan "wajib diisi" memakai `kosongVisual()`, bukan `.trim()`

Cakupannya melebar setelah survei: cerita hanya **2 baris** di produksi,
sedangkan **soal 4.797 baris ber-HTML** dan **479 set opsi**, semuanya juga
disunting di kotak polos. v1 memasang penyuntingnya di ketiga tempat itu, jadi
v2 pun begitu — satu komponen, tiga pemasangan.

Yang dipakai v1 ternyata **bukan CKEditor sungguhan**, hanya 25 KB
`contenteditable` buatan sendiri. Jadi menyamakannya tidak menambah satu pun
pustaka.

Bagian tersulitnya kursor: komponen React yang menulis ulang `innerHTML` tiap
render membuat "abcde" menjadi "edcba". Diuji di Chrome sungguhan lewat CDP —
mengetik lima huruf, menekan tombol tebal, menempel HTML kotor — **11
pemeriksaan lulus**, termasuk urutan hurufnya. Halaman ujinya sementara dan
sudah dihapus (`/uji-penyunting` membalas 404 di produksi).

### ✅ Select yang bisa dicari — SELESAI 2 September
- [x] 15 daftar pilihan berisi data basis data dikonversi
- [x] Enum tetap sengaja DIBIARKAN `<select>` bawaan, dengan alasan tertulis

Dikonversi: mapel (kelas siswa, materi siswa, detail kelas), semester/mapel/
kelas di rekap tugas, semester dan mapel di cek nilai publik, ruang obrolan,
kelas tujuan kenaikan, tahun ajaran, soal esai yang dilampiri berkas, katalog
add-on, dan kategori buku.

**Tidak semua `<select>` dikonversi, dan itu keputusan.** Tipe soal, huruf
pilihan A–E, jenis pembayaran perpustakaan (peta tetap 3 entri di Go), status
per baris tabel, jenis ujian, dan daftar kamera tetap memakai `<select>`
bawaan: panjangnya tidak pernah berubah, dan di ponsel `<select>` membuka
pemilih sistem yang sudah dikenal semua orang — komponen sendiri hanya
menirunya dan selalu kalah.

Dua sentinel perlu penanganan khusus karena `PilihCari` mengosongkan ke `""`
sedangkan halamannya memakai nilai sungguhan: `"all"` (rekap tugas, materi)
dan `"__other__"` (kategori buku) tetap menjadi opsi biasa.

`uji-select-dicari.mjs` menuntut setiap `<select>` yang membangun pilihannya
dengan `.map()` punya alasan tertulis — bukan melarang `<select>`.

### ✅ Aksesibilitas halaman TANPA LOGIN — SELESAI 2 September
- [x] 14 halaman publik diukur axe-core di peramban sungguhan
- [x] 25 simpul bermasalah → **nol**
- [x] Paritas isi dengan v1 diperiksa, dan satu cacat isi ditemukan + diperbaiki

Diukur dengan axe-core (WCAG 2.0/2.1 A+AA + best-practice) pada halaman yang
sudah tergambar — bukan dibaca dari kode. Yang ditemukan:

| dampak | masalah | tempat |
|---|---|---|
| serious | kontras `.eyebrow` **2.16:1** (butuh 4.5) | 18 simpul, 6 halaman |
| serious | `--muted` **4.24:1** di latar kartu abu | halaman harga |
| moderate | judul footer `h3` melompati `h2` | 4 halaman |
| moderate | tombol WA mengambang di luar semua landmark | 2 halaman |
| moderate | `/reset-password` tanpa `<main>` | 1 halaman |

Kontrasnya diperbaiki dengan token baru `--aksen-teks`, TERPISAH dari
`--secondary-dark` — yang itu dipakai gradien hero di atas biru tua, tempat
amber terang justru benar. Satu nilai tidak bisa melayani keduanya.

**Warna v1 diperiksa:** `#0c2947`, `#163b68`, `#f5b23c`, `#64748b` — sama
persis. `#e09a1f` dan chip `.eyebrow` **tidak ada di v1**, jadi perbaikan ini
tidak menjauhkan v2 dari v1.

### ✅ Cacat isi halaman kontak — SELESAI 2 September
- [x] Surel, telepon, dan kota dipulihkan
- [x] Dua formulir WhatsApp v1 dipulihkan
- [x] `/about` mendapat kembali nama merek dan blok "Informasi situs"

`/contact` hanya **50%** panjang v1, dan sebabnya buruk: halaman kontak tidak
punya satu pun cara menghubungi siapa pun. Yang tampil hanya "Kontak langsung"
lalu "`, Indonesia`" dengan koma menggantung. Nilainya di v1 ditulis
`{{ $supportEmail }}`, dan ikut terbuang ketika markupnya dibuang saat
pemindahan. Tidak ada galat; halamannya tetap rapi.

Dua formulir WhatsApp juga hilang — yang terbawa hanya judulnya, sehingga
halaman menampilkan "Kirim pesan" dan "Minta demo" berturut-turut tanpa apa pun
di bawahnya. Sekarang 85% panjang v1, dan setelah blok ajakan bersama v1
dikeluarkan dari hitungan justru **+70 kata**.

Setelah blok itu dikeluarkan, isi keempat halaman berimbang: `/about` +9 kata,
`/contact` +70, `/privacy-policy` −22, `/terms` −24.

---

## BELUM — UI/UX

### 1. Blok ajakan v1 di halaman statis — MENUNGGU KEPUTUSAN ANDA
- [ ] Ditambahkan, atau diputuskan tidak perlu

v1 menempelkan blok promosi yang sama di bawah **setiap** halaman statis:
"Mulai Ujian Online Tanpa Biaya / 100% Gratis Dipakai / 500 Token Saat Daftar /
Bonus Kode Referral" — sekitar 100 kata. v2 tidak punya itu di `/about`,
`/contact`, `/privacy-policy`, dan `/terms`.

**Itu satu-satunya perbedaan isi yang tersisa** antara halaman statis v1 dan
v2. Tidak saya tambahkan sendiri karena ini keputusan produk, bukan cacat:
menaruh ajakan mendaftar di bawah kebijakan privasi adalah pilihan, dan
halaman depan v2 sudah punya bagian ajakannya sendiri.

### ✅ Aksesibilitas layar SETELAH login — SELESAI 2 September
- [x] Aturan jsx-a11y dinyalakan penuh di `eslint.config.mjs`
- [x] 21 temuan → **nol**; `npm run lint` bersih

Bawaan Next hanya menyalakan enam aturan, semuanya soal ARIA salah tulis. Yang
tidak diperiksanya justru yang paling sering terjadi di sini.

Yang paling berarti: **gambar soal di layar ujian hanya bisa diperbesar dengan
tetikus.** Siswa yang memakai keyboard — karena tangannya terbatas, atau
karena tetikusnya rusak di tengah ujian — tidak punya cara apa pun melihatnya
lebih besar, di layar yang tidak boleh ia tinggalkan. Kini `<button>`
sungguhan.

Empat dialog memasang `role="dialog"` di **latarnya**, bukan di panelnya, dan
menahan rambatan lewat `onClick` di kotaknya. Diperbaiki dengan membandingkan
target di latar.

Tujuh dari 21 temuan ternyata **positif palsu**: saklar di aplikasi ini
menyarangkan teksnya tiga tingkat, dan batas bawaan aturannya hanya dua.
Diperbaiki lewat `depth: 3`, bukan dengan mematikan aturannya.

### ✅ Gaya halaman statis mengikuti v1 — SELESAI 2 September
- [x] Skala judul disamakan (h1 24px, h2 18,4px)
- [x] Judul & baris tanggal keluar dari kartu, seperti v1
- [x] Lima sisa interpolasi Blade yang hilang dipulihkan

Diukur di peramban: judul bagian v2 **28px**, v1 **18,4px** — 52% lebih besar.
Sebabnya `.landing-section h2` ikut mengenai halaman statis dan **menang** atas
`.static-prose h2`.

Ditemukan pula kerusakan porting yang lebih banyak dari kemarin: remah roti v1
terbawa sebagai butir daftar, tanggal dan nama merek hilang di lima kalimat.

---

## BELUM — UI/UX

### ✅ Halaman depan: dua bagian hilang + irama gelap–terang — SELESAI 2 September
- [x] "Mulai Ujian Online Tanpa Biaya" (kartu gelap, seperti v1)
- [x] "Unlimited Attempt — Full Customized Per Percobaan"
- [x] Bagian pengawasan & komitmen berlatar gelap seperti v1
- [x] Logo & favicon branding pulih (cacat terpisah, lihat di bawah)

Dibandingkan satu per satu: v1 punya 14 bagian, v2 kehilangan **dua**.

**"Unlimited Attempt"** yang paling merugikan: fiturnya **ADA** di v2 dan
dipakai lewat panel manajemen attempt — empat mode `fresh_start`,
`continue_remaining`, `full_time`, `custom_duration` — tetapi tidak diceritakan
sama sekali di halaman depan. Fitur yang tidak diceritakan sama saja dengan
tidak ada bagi sekolah yang sedang membandingkan pilihan.

Yang **tidak** ditambahkan karena ternyata sudah ada padanannya: `#komitmen`,
`#kontak`, `#demo`, dan kolom "Khusus / Hubungi kami" di bagian harga.

Warna gelapnya memakai token brand, bukan angka tetap — sekolah dengan branding
premium melihat warnanya sendiri di sana.

### ✅ Logo & favicon branding rusak — SELESAI 2 September
- [x] Penyaji logo mendahulukan disk, bukan CDN

Unggahan menulis ke **disk** dan tidak pernah mengunggah ke R2, tetapi
penyajinya **selalu** mengalihkan ke CDN begitu `r2_public_url` terisi. Logo
setiap sekolah berbranding karena itu selalu 404: tersimpan benar, tercatat
benar, tidak pernah bisa tampil.

Senyap dari sisi server — pengalihannya sendiri berhasil, yang 404 adalah
tujuannya di host lain. Log tetap bersih.

### 1. Blok ajakan v1 di halaman statis — MENUNGGU KEPUTUSAN ANDA
- [ ] Ditambahkan, atau diputuskan tidak perlu

v1 menempelkan blok promosi yang sama di bawah **setiap** halaman statis
(~100 kata). Setelah blok itu dikeluarkan dari hitungan, isi keempat halaman
berimbang: `/about` +9 kata, `/contact` +70, `/privacy-policy` −22,
`/terms` −24.

---

### ✅ Fitur "Lulus" di Naik Kelas — SELESAI 2 September
- [x] Pilihan tiga-arah: naik / tinggal / **lulus**
- [x] Kelulusan tercatat di enrollment (`status="graduated"` + `end_date`)
- [x] Akun di-soft-delete; seluruh nilai, jawaban, dan raport tetap terbaca
- [x] Layar `/admin/alumni`
- [x] Naik kelas GABUNGAN (`/admin/promotions/susun`) juga punya pilihan lulus

Di layar gabungan bentuknya berbeda karena modelnya berbeda: centang di sana
berarti "pindah ke kelas tujuan", jadi lulus menjadi kolom tersendiri yang
saling meniadakan. Menandai lulus **melepas** pilihan pindahnya dan mematikan
kotaknya — bukan dibiarkan bisa dicentang lalu ditolak server setelah semuanya
terlanjur disusun.

Aturan "satu siswa tidak boleh ada di dua daftar" diangkat menjadi satu fungsi
yang dipakai kedua alur. Aturan keselamatan yang ditulis dua kali akan berbeda
suatu saat, dan yang berbeda biasanya yang jarang dibaca.

**Kenapa bukan sekadar soft delete.** Menandai siswa lulus dan menghapus siswa
karena salah input menghasilkan baris yang **sama persis** bila keduanya hanya
mengisi `deleted_at` — tidak bisa dibedakan, tidak ada daftar alumni, dan
memulihkan yang keliru menjadi tebak-tebakan.

**Tidak ada perubahan skema.** Kolomnya sudah ada di `student_enrollments`, dan
`status` bertipe varchar — bukan enum yang menolak nilai baru.

**Bagian yang paling mudah dilanggar tanpa terlihat:** JOIN SQL biasa tidak
menyaring `deleted_at`, jadi hasil ujian alumni tetap muncul. Yang **menyaring**
justru `Preload` dan kueri `Model(&User{})` — laporan tetap terbuka, jumlah
barisnya benar, hanya namanya yang kosong. Empat tempat semacam itu diperbaiki.

`class_id` sengaja tidak dikosongkan: itu kelas terakhir siswa, dan tidak ada
tempat lain yang menyimpannya untuk tahun sebelum enrollment dipakai.

---

## BELUM — fitur (setelah UI beres)

### 4. Tanda tangan kepala sekolah tidak punya isian
- [ ] Isian unggah tanda tangan di `/admin/school`

Kolom `schools.signature_image` **sudah ada**, dan **4 sekolah sudah
mengisinya** — lewat v1. Di v2 tidak ada satu pun isian untuk itu, jadi sekolah
yang pindah ke v2 tidak bisa mengganti atau memasangnya.

Pekerjaan kecil dengan akibat yang sudah nyata, tetapi ditaruh setelah UI
sesuai permintaan Anda.

### 5. Tambah/hapus kategori buku pindah ke owner
- [ ] `POST` dan `DELETE` kategori dibatasi owner
- [ ] Layar pengelolaan kategori di panel owner
- [ ] Layar admin menjadi baca-saja

Kategori **per sekolah** (669 baris di produksi), dan jalur "Lainnya" saat input
buku memakai kode yang **terpisah** (`resolveBookCategory`) — jadi membatasi
endpoint kategori tidak akan mematahkannya. Sudah diverifikasi.

---

## SUDAH

### Domain & infrastruktur
- [x] Domain ditukar: v2 di `ujian.kelasprivat.id`, v1 tetap hidup di `exam.kelasprivat.id`
- [x] `db.kelasprivat.id` + SSL — sebelumnya sandi basis data lewat **tanpa enkripsi** di `http://IP:8081`
- [x] Domain branding premium `ibssmpitalikhlas.kelasprivat.id` + SSL
- [x] `APP_URL` produksi diperbaiki (sebelumnya `http://localhost` — tautan reset sandi menunjuk komputer penerimanya sendiri)
- [x] Aset R2 disajikan lewat pengalih server (`/api/aset/*`)

### Branding premium
- [x] Domain per sekolah, nama, warna, favicon, logo navbar
- [x] Warna berlaku di **seluruh** layar termasuk setelah login
- [x] Judul tab memakai nama sekolah, bukan merek induk
- [x] Owner bisa mengunggahkan logo mewakili sekolah
- [x] Direktori sekolah ber-branding di halaman depan

### WhatsApp
- [x] Panel percakapan — sebelumnya **diam-diam kosong** (kolom `message` vs `message_body`, Error 1054)
- [x] Percakapan punya tabel sendiri (`wa_chat_messages`)
- [x] Balas otomatis berbasis niat, bawaan mati
- [x] Menjawab jumlah siswa dengan perkiraan biaya
- [x] Pesan masuk ganda ditolak lewat indeks unik
- [x] Empat alamat webhook Fonnte siap salin
- [x] Follow-up lead membuka chat dengan draf **belum terkirim**

### Pembayaran & tagihan
- [x] Rekening tujuan transfer — sebelumnya sekolah diberi nominal **tanpa diberi tahu ke mana**
- [x] Invoice manual, DP, diskon, add-on, tenggat pelunasan
- [x] Kuitansi DP sebagai dokumen tersendiri
- [x] "Lunasi sisa" wajib melampirkan bukti, tetap menunggu 1×24 jam
- [x] "Approve" owner menyebut apa yang disahkan
- [x] Notifikasi WA menyebut **sisa**, bukan total

### Paritas UI/UX dengan v1 (delapan butir, seluruhnya)
- [x] `admin/students` — saringan gender & pengurutan
- [x] `admin/reports` — **mengembalikan nol baris sejak awal, di v1 juga**; kini 271 ujian
- [x] `admin/payment` — rekening tujuan
- [x] `admin/promotions` — tahun ajaran jadi pilihan
- [x] `owner/users` — konfirmasi sandi yang **dilumpuhkan dari klien**
- [x] `admin/attempt-management` — nama siswa/ujian (7.436 baris berisi nomor), kolom email, mode attempt
- [x] `admin/subjects` — KKM tampil
- [x] `admin/exam-results` — saringan ujian

### Tampilan
- [x] Navbar ponsel melipat seperti v1 — 71px dari 844px layar, diukur
- [x] Luapan horizontal 60px di ponsel — nol di 320/360/390/414, delapan halaman
- [x] Halaman depan 1.899 → 2.350 kata; simulasi biaya per mapel/semester
- [x] Token disembunyikan pada langganan aktif, muncul lagi saat berakhir
- [x] Tombol lihat sandi di 11 isian
- [x] Dialog penjelas sebelum pemilih berkas terbuka

### Perbaikan yang ditemukan sendiri
- [x] **Kebijakan privasi & syarat layanan hanya satu kalimat** — dokumen yang jadi pegangan sekolah saat menyerahkan data siswanya
- [x] **Halaman /ads** yang menunda setiap login belasan detik — dihapus
- [x] **Pendaftaran sekolah baru gagal total** — token 36 karakter di kolom `varchar(16)`, Error 1406. Tidak ada jalan lain masuk ke sistem selain lewat sana
- [x] Unggah berkas terkirim sebagai **GET** — peramban menolaknya sebelum berangkat, tanpa jejak di log
- [x] Foto proktoring rusak di **2.337** hasil ujian
- [x] 18 logo & 4 tanda tangan sekolah gagal dimuat
- [x] Iklan pihak ketiga di halaman yang **wajib dilewati setiap login** — 227 orang, sudah tayang 72 kali
- [x] Pendaftaran terkunci karena percobaan **gagal** ikut memakan jatah
- [x] Panel galat menampilkan sebab, dan bisa dicari
- [x] QR & referral token dibuat saat pengguna dibuat, bukan sapuan harian
- [x] Pemindai kamera di dua layar perpustakaan

---

## Keputusan Anda — tidak ada yang menunggu

- [x] Foto proktoring di bucket R2 publik → **dibiarkan** (keputusan Anda)
- [x] `max_concurent_exam` → **dicoret**; saya keliru menaikkannya sebagai hal mendesak. Dari 111 sekolah di angka bawaan, 85 tidak punya siswa sama sekali dan **nol** berlangganan aktif
- [x] Add-on "Exclusive page" dibuang (keputusan Anda)
- [x] Izin memasang penyelaras brand → diberikan, sudah dipasang

---

## Yang belum pernah disapu sama sekali

Bukan permintaan, tetapi celah yang saya ketahui:

- [ ] Pembatasan laju di luar login, pendaftaran, dan cek nilai
- [ ] Validasi unggahan di luar logo brand — yang lain masih percaya ekstensi berkas

(Aksesibilitas layar ujian dipindahkan ke daftar UI di atas.)

---

## Di luar lingkup v1/v2 — ditemukan, tidak saya sentuh

Muncul saat memeriksa galat produksi atas pertanyaan Anda. **Bukan v1, bukan
v2**, jadi saya laporkan tanpa mengubah apa pun:

- [ ] `kelasprivat.id` — halaman `/les-<mapel>-<kota>` membalas **HTTP 500**,
      23 kali dalam 4 jam, termasuk kepada perayap Meta dan pengunjung yang
      datang dari halaman depan situs itu sendiri.
      Sebabnya: baris `seo_pages` dibuat saat halaman pertama kali dibuka,
      tetapi `INSERT`-nya tidak mengisi kolom `content` yang tidak punya nilai
      bawaan — MySQL 1364. Situs Laravel terpisah di
      `/var/www/company-kelasprivat`.
- [ ] Log situs itu **127 MB** dan tidak dirotasi. Disk server 79% terpakai
      (14 GB sisa) — server yang sama menjalankan v1 dan v2.
