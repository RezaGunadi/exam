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

## UI/UX

### ✅ Blok ajakan v1 di halaman statis — SELESAI 3 September
- [x] Terpasang di `/about`, `/contact`, `/privacy-policy`, dan `/terms`
- [x] Dijadikan **satu komponen**, dipakai halaman depan dan halaman statis
- [x] Kata-kata halaman depan tidak berubah sama sekali

v1 menempelkan blok promosi yang sama di bawah **setiap** halaman statis lewat
satu partial (`partials/free-offer.blade.php`): "100% Gratis Dipakai / 500 Token
Saat Daftar / Bonus Kode Referral". Itu satu-satunya perbedaan isi yang tersisa
antara halaman statis kedua versi.

**Bukan disalin, melainkan dipindahkan ke satu tempat.** v2 sudah punya blok itu
di halaman depan, tetapi tertulis langsung di dalam halamannya. Menyalinnya ke
halaman statis berarti dua salinan yang akan berbeda isinya suatu saat tanpa ada
yang menyadari — angka token, kata-katanya, dan tautan daftarnya kini hanya ada
di `penawaran-gratis.tsx`.

**Judulnya berbeda dengan sengaja.** Halaman depan tetap "Mulai ujian online
tanpa biaya."; halaman statis memakai "Belum memakai Kelas Privat?". Orang yang
sampai ke kebijakan privasi datang untuk membaca kebijakan — kalimat pembuka
yang sama akan terbaca seperti iklan yang menyela. Bloknya juga ditempatkan
**di luar** kartu prosa: dokumen yang menjadi pegangan hukum tidak boleh
terlihat memuat ajakan mendaftar di dalam badannya.

Diukur setelah terpasang: delapan halaman publik, **nol** pelanggaran axe-core,
nol luapan mendatar.

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

### ✅ Blok ajakan v1 di halaman statis — SELESAI 3 September

Lihat uraiannya di bagian UI/UX di atas. Setelah blok itu terpasang, isi keempat
halaman statis v2 tidak lagi kurang dari v1 dalam hal apa pun.

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

## Fitur

### ✅ 4. Tanda tangan kepala sekolah — SELESAI 2 September
- [x] Isian unggah + pratinjau + hapus di `/admin/school`
- [x] Endpoint sendiri (`POST`/`DELETE /api/admin/school/signature`), bukan lewat PUT
- [x] Jenis gambar dikenali dari **isi berkas**, bukan dari ekstensinya
- [x] Guru ditolak; berkasnya hanya bisa dibaca admin sekolah itu sendiri
- [x] Tanda tangannya **muncul di raport** yang dicetak

Kolom `schools.signature_image` sudah ada dan 4 sekolah sudah mengisinya lewat
v1; di v2 tidak ada satu pun isian untuk itu.

**Satu lubang ikut ditutup di sepanjang jalan.** Kolom itu terdaftar sebagai
boleh-diubah lewat `PUT /api/admin/school`, yang menyalin nilai kiriman klien
apa adanya — artinya admin mana pun bisa menunjuk kolom itu ke jalur berkas
yang ia karang sendiri. Kini jalur berkas hanya bisa dibentuk server.

**Isiannya tidak berhenti di penyimpanan.** Nilai yang tersimpan tetapi tidak
pernah tampil di mana pun bukan fitur; raport yang dicetak kini menggambar
tanda tangannya di ruang kosong yang selama ini disediakan untuk tanda tangan
tangan. Sekolah yang belum mengunggah tidak kehilangan apa pun — ruangnya tetap
kosong.

Nilai warisan v1 berupa **kunci objek R2** (`schools/signatures/…`), bukan jalur
`/api/files/…`. Keduanya ditangani: yang lama tetap tampil di layar lewat
pengalih `/api/aset/*`, dan tidak pernah diperlakukan sebagai jalur disk saat
berkas lama dihapus.

**Cacat lama yang ikut ketemu:** gofpdf tidak menggagalkan `ImageOptions` di
tempat — ia menyimpan galat internal, dan `Output` yang kemudian gagal. Satu
watermark raport yang hilang karena itu sudah cukup membuat **seluruh** raport
sekolah gagal diunduh dengan 500. Kini keberadaan berkas diperiksa lebih dulu,
dan berkas rusak dilewati tanpa menggagalkan dokumennya.

### ✅ 5. Kategori buku pindah ke owner — SELESAI 2 September
- [x] Tambah, ubah nama, gabung, dan hapus **dibatasi owner**
- [x] Layar `/owner/library-categories` dengan pemilih sekolah
- [x] Layar admin menjadi **baca-saja**

Rutenya **dicabut** dari `/api/admin`, bukan sekadar tombolnya disembunyikan:
alamat endpoint bisa ditebak dari daftar yang masih boleh dibaca. Diuji dengan
memanggil keempat alamat admin itu langsung — tidak ada satu pun yang berhasil,
dan keadaan datanya utuh sesudahnya.

Jalur **"Lainnya"** saat memasukkan buku sengaja tetap terbuka: menutupnya
berarti pendataan buku berhenti di tengah hanya karena kategorinya belum
terdaftar. Yang pindah ke owner adalah **membereskan daftarnya**, bukan
mencatat bukunya.

Sekolah diambil dari **jalur** (`{schoolID}`), bukan dari sesi — owner tidak
punya sekolah sendiri, dan memakai sesinya akan menempelkan kategori ke sekolah
yang kebetulan tertaut ke akunnya. Sekolah yang tidak ada ditolak 404, supaya
tidak ada kategori yatim yang tersimpan tanpa bisa dibuka dari layar mana pun.

---

## UI/UX

### ✅ Aksesibilitas layar SETELAH LOGIN — diukur di peramban, bukan dibaca dari kode
- [x] 33 layar setelah login diukur axe-core (admin, siswa, owner)
- [x] **36 simpul bermasalah → nol**, diukur ulang halaman per halaman
- [x] Alat ukurnya disimpan: `frontend/scripts/ukur-a11y-login.mjs`

**Sapuan pertama berbohong, dan sebabnya perlu ditulis.** Ia dijalankan lewat
server dev yang sedang hidup — dan server itu ternyata menyajikan halaman yang
TIDAK PERNAH terhidrasi: React termuat, tetapi tidak satu pun panggilan API
keluar dari peramban. Yang terukur karena itu hanya kerangka server: tanpa menu
(35 tautan bilah samping tidak ada satu pun), tanpa isi tabel, tanpa dialog.
Hasilnya "24 simpul", dan angka itu terlihat meyakinkan.

Diulang di atas **build produksi** yang berjalan sendiri, muncul 12 simpul lagi
yang selama ini tersembunyi — termasuk satu yang **critical**:

| dampak | masalah | tempat |
|---|---|---|
| critical | tombol **hapus** tanpa nama sama sekali | 2 tombol, daftar soal |
| moderate | dua landmark `<nav>` tanpa nama pembeda | 7 layar siswa |
| moderate | judul kartu `<h4>` di bawah `<h2>` | daftar soal & mapel |
| minor | header kolom tabel kosong | daftar kelas |

Tombol hapus itu hanya berisi ikon tong sampah. Pembaca layar mengumumkannya
sebagai "button" — tanpa kata lain — dan itu tombol yang paling mahal bila
salah tekan.

Sebelumnya yang menjaga layar setelah login hanya aturan jsx-a11y di eslint —
dan lint membaca **kode**, bukan halaman yang sudah tergambar. Yang tidak bisa
dilihatnya justru yang paling merugikan di sini.

| dampak | masalah | tempat |
|---|---|---|
| serious | kontras `.stat-label` **1,07:1** | 4 simpul, halaman Laporan |
| moderate | `heading-order`: judul panel `<h3>` di bawah `<h1>` | 19 halaman |
| minor | header kolom tabel kosong | perpustakaan |

**Kontras 1,07:1 — penyebabnya aturan CSS tanpa lingkup.** `refresh.css` memuat
`.stat-label { color: rgba(255,255,255,0.78) }` tanpa pembatas apa pun, dan
berkas itu dimuat untuk **seluruh** aplikasi lewat `layout.tsx`. Warnanya benar
di tempat asalnya — kartu statistik halaman depan berlatar gelap — tetapi di
halaman Laporan admin ia menjadi putih di atas `#f4f7fb`. Angkanya ada di sana,
tersimpan benar, dan tidak terbaca oleh siapa pun.

Aturannya **dipindahkan** ke `landing.css` (tempat seluruh gaya halaman depan
harus tinggal, dijaga `uji-kelas-landing.mjs`), dan halaman Laporan memakai pola
kartu yang sama dengan layar lain: `panel stat-card stat-card-soft` + `muted`.

**heading-order.** Tiap halaman punya satu `<h1>` (judul halaman di AppShell),
lalu judul panelnya `<h3>` — melompati satu tingkat, sehingga pembaca layar yang
menelusuri daftar judul kehilangan susunannya. Sebagian layar **sudah** memakai
`<h2>` untuk hal yang sama (absensi, profil, dashboard, mapel, pembayaran) — dan
justru layar itulah yang bersih saat diukur. Jadi ini bukan aturan baru:
225 judul di 69 berkas disamakan dengan yang sudah benar.

Ukurannya **dijaga tetap**: `<h2>` bawaan 1,35rem, sedangkan judul panel selama
ini 1,05rem di sebagian besar layar. Satu aturan CSS mengembalikan ukurannya,
supaya yang berubah hanya **tingkatannya**, bukan tampilannya. Akibat yang
disengaja: layar yang sudah memakai `<h2>` kini ikut 1,05rem — setelah ini
seluruh judul panel berukuran sama, yang sebelumnya tidak.

**Halaman publik sengaja tidak ikut disapu.** Susunan judulnya sendiri, sudah
diukur bersih, dan gayanya diatur `landing.css` yang mengunci pada `h3`.

**Cacat pada alat ukurnya sendiri, ditemukan saat memakainya.** `Page.navigate`
kembali SEBELUM dokumen baru menggantikan yang lama, jadi pemeriksaan "dokumen
siap" lolos pada halaman **sebelumnya**. Hasil "bersih"-nya terlihat meyakinkan
dan tidak menandakan apa pun. Kini alamatnya diperiksa lebih dulu — dan
catatannya ditulis di berkas skripnya, karena kesalahan seperti ini tidak
meninggalkan gejala.

---

## Banding tampilan v1 vs v2 — dikerjakan, dan inilah hasilnya

Butir terakhir dari `PLAN_EXAM_V1_V2.md` (Item 4) yang selama ini tertulis
"banding visual belum". Sekarang sudah: **v1 dan v2 dijalankan berdampingan di
BASIS DATA YANG SAMA** (`exam_banding`, dibangun dari migrasi v1), 16 layar
dipotret pada viewport 1440×900, dan angkanya diukur — bukan dikira.

**Yang v2 lebih baik**, dan selisihnya besar:

| layar | v1 | v2 |
|---|---|---|
| dashboard | 7 angka | **12 angka + grafik 7 hari** |
| saringan daftar ujian | 6 isian | **10 isian** |
| daftar soal | 5.755px untuk 2 soal | **1.063px**, opsi & kunci ikut terlihat |
| data sekolah | 1.819px | **1.190px** |

**Satu perbedaan yang merugikan, dan sumbernya satu tempat.** Layar yang memakai
komponen bersama `ResourcePage` menampilkan daftar sebagai **kartu**, sedangkan
v1 memakai **tabel**:

| layar | v1 | v2 |
|---|---|---|
| daftar siswa | 915px, 5 baris tabel muat sekaligus | **1.476px**, 3 kartu, baris ketiga terpotong |
| mata pelajaran | tabel | kartu |
| paket soal | tabel | kartu |

Pada sekolah dengan 800 siswa, bedanya bukan selera: tabel bisa dipindai dengan
mata dari atas ke bawah, kartu harus digulir. Dan orang yang memakainya sekarang
adalah orang yang terbiasa dengan tabel v1.

**Diputuskan 3 September: tabel — dan sudah dikerjakan.** Enam layar berpindah
dari kartu ke tabel: ResourcePage (Mata Pelajaran, Semester, Konfigurasi
raport, Mapel tutor) ditambah Daftar Siswa admin dan tutor. Tiga puluh dua
layar v2 lain sudah bertabel sejak awal — enam ini yang menyimpang.

Keenam tindakan baris siswa tetap ada dan memanggil penangan yang sama:
riwayat ujian, ubah, unduh kartu, cabut kartu, kartu baru, hapus. Ikon
bertooltip, seperti v1 di tabel yang sama — enam tombol berlabel membuat satu
sel selebar 430px. "Hapus" pindah ke ujung, menjauh dari tindakan harian.

Tiga hal ikut terbetulkan saat mengerjakannya:

- Tombol "cabut kartu" pada siswa tanpa kartu aktif kini tetap **menempati
  ruangnya**. Dilepas dari alirannya, tombol sesudahnya bergeser, dan "Hapus"
  satu baris berdiri tepat di bawah "Kartu baru" baris di atasnya.
- Gender ditampilkan lewat kamus label: **"Laki-laki"/"Perempuan"**, bukan
  `male`/`female`. Kamusnya sudah lama ada; dua halaman ini saja yang belum
  memakainya, jadi selama ini kartu siswa memang menampilkan istilah basis
  data.
- Di bawah 720px setiap tombol dibuat selebar wadahnya — benar di dalam kartu,
  salah di sel tabel: enam tombol menumpuk dan satu baris menjadi setinggi
  300px. Diperbaiki lewat kelas tersendiri, bukan aturan umum, supaya puluhan
  tabel lain tidak ikut berubah tanpa diperiksa.

Diukur pada 390px dengan alat ukur repo sendiri: **luapan mendatar 0px, dan 38
sasaran sentuh semuanya >= 44px.**

**Satu cacat paritas kecil, sudah diperbaiki:** daftar ujian v2 hanya
menampilkan waktu **mulai**; v1 menampilkan mulai DAN selesai. Pertanyaan yang
dibawa ke layar itu menjelang hari ujian justru "kapan ditutup". Ditumpuk dalam
satu sel, bukan ditambah satu kolom.

**Luapan mendatar: nol di kedua versi**, di seluruh 16 layar.

Alat pemotretnya ada di `scratchpad/banding-visual.mjs`, dan
`frontend/next.config.ts` kini menerima `NEXT_DIST_DIR` supaya build pengukuran
tidak menimpa `.next` milik server dev yang sedang berjalan.

---

## Celah yang sebelumnya belum pernah disapu

### ✅ Pembatasan laju di luar login — SELESAI 2 September
- [x] `POST /auth/reset-password` — 10 percobaan / 15 menit per alamat
- [x] `POST /landing/contact` & `/landing/demo-request` — 5 kiriman / jam, penjaga yang sama
- [x] Token scheduler — 10 **kegagalan** / 10 menit; panggilan yang sah tidak memakan jatah

Reset password adalah **satu-satunya tempat** tebakan atas token reset bisa
diuji, dan sebelumnya tidak ada apa pun yang menghitung berapa kali seseorang
mencoba. Yang menjaganya hanya panjang tokennya sendiri — pertahanan tanpa
lapisan kedua.

Kontak/demo menulis satu baris lead **dan** mengirim notifikasi keluar tiap
kiriman. Kuota pengiriman yang habis di sana juga memadamkan notifikasi tagihan
yang memakai jalur yang sama.

Penjaga token scheduler hanya menghitung yang **gagal**. Menghitung seluruh
panggilan akan mengunci scheduler-nya sendiri setelah sepuluh panggilan yang
benar — pembatas yang menutup pintu bagi pemiliknya, dengan gejala "pekerjaan
terjadwal berhenti tanpa alasan". Ada ujinya, dan uji itu memanggil 30 kali
berturut-turut dengan token yang benar.

**Yang sengaja TIDAK dibatasi:** pembacaan halaman depan (`/pages/{slug}`,
`/landing/stats`, `/brand`, `/brand/direktori`). Semuanya baca-saja dan justru
dipanggil beruntun oleh satu pengunjung yang wajar; pembatas di sana lebih
mungkin memutus halaman depan sekolah daripada menahan siapa pun.

### ✅ Validasi unggahan — SELESAI 2 September
- [x] Lampiran absensi: jenis dari **isi berkas**, ekstensi ikut hasil pengenalan
- [x] Lampiran absensi **bisa dibuka kembali** oleh sekolahnya sendiri
- [x] Jalur unggahan lain disurvei dan dinyatakan aman, dengan alasannya

**Satu-satunya jalur tanpa daftar-putih sama sekali** ternyata lampiran absensi:
ekstensi apa pun diterima apa adanya, dan yang tanpa ekstensi disimpan sebagai
`.bin`. Penyaji berkas menentukan `Content-Type` dari ekstensi itu, jadi
`surat-izin.html` disajikan sebagai **text/html dari asal yang sama dengan
aplikasinya**. `X-Content-Type-Options` tidak menolong di sana — yang
dicegahnya adalah tebakan peramban, sedangkan tipe ini memang dinyatakan.

v1 hanya menerima gambar dan memeriksa isinya. Jadi ini **kemunduran dari v1**,
bukan pengetatan baru.

**Cacat kedua di layar yang sama:** prefix `attendance` tidak pernah terdaftar
di aturan akses berkas, dan yang tidak terdaftar ditolak. Lampiran absensi bisa
diunggah tetapi **tidak bisa dibuka siapa pun kecuali owner** — admin yang baru
saja mengunggahnya menerima 403 atas berkasnya sendiri, dan di layar itu
terbaca sebagai gambar rusak. Kini admin dan guru sekolah itu bisa membukanya,
dan siswa hanya miliknya sendiri: isinya alasan seseorang tidak masuk sekolah.

Jalur unggahan lain **sudah** punya daftar-putih yang menutup tipe eksekutabel
(`.html`, `.svg`, `.js`, `.xml`), dan berkas ber-ekstensi gambar yang isinya
bukan gambar disajikan sebagai `image/*` dengan `nosniff` — tidak dieksekusi.
Impor Excel diurai excelize, tidak pernah disimpan, tidak pernah disajikan.

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
- [x] **Logo sekolah menyembul keluar dari lingkarannya** di sidebar siswa — wadahnya elips 56x42 karena ukurannya mengikuti logo, kini persegi dan memotong isinya

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

- [x] ~~Pembatasan laju di luar login, pendaftaran, dan cek nilai~~ — selesai, lihat di atas
- [x] ~~Validasi unggahan di luar logo brand~~ — selesai, lihat di atas

Daftar ini kosong sekarang.

---

## Di luar lingkup v1/v2 — dan tetap dikerjakan

Muncul saat memeriksa galat produksi atas pertanyaan Anda. **Bukan v1, bukan
v2** — situs Laravel terpisah di `/var/www/company-kelasprivat` — tetapi
keduanya berdiri di server yang sama dengan v1 dan v2, dan yang kedua (disk)
bisa mematikan ketiganya sekaligus. Diperbaiki 3 September di repo
`company-kelasprivat`; sisanya di tangan Anda karena hanya bisa dilakukan di
server:

- [x] `kelasprivat.id` — halaman `/les-<mapel>-<kota>` membalas **HTTP 500**,
      23 kali dalam 4 jam, termasuk kepada perayap Meta dan pengunjung yang
      datang dari halaman depan situs itu sendiri.
      Sebabnya: baris `seo_pages` dibuat saat halaman pertama kali dibuka,
      tetapi `INSERT`-nya tidak mengisi kolom `content` yang tidak punya nilai
      bawaan — MySQL 1364. Situs Laravel terpisah di
      `/var/www/company-kelasprivat`.
      **Diperbaiki 3 September** (`511bb4d`): kolomnya ikut diisi saat
      menyisipkan, jadi benar pada skema mana pun — repo menyatakan kolom itu
      nullable, produksi menyimpang darinya. `firstOrCreate`, bukan
      `updateOrCreate`, supaya konten suntingan tangan tidak tertimpa tiap
      kunjungan. Ujinya memeriksa pernyataan INSERT-nya sendiri dan
      diverifikasi GAGAL pada kode lama. **Menunggu deploy.**
- [x] Log situs itu **127 MB** dan tidak dirotasi. Disk server 79% terpakai
      (14 GB sisa) — server yang sama menjalankan v1 dan v2.
      **Diperbaiki 3 September** (`cb7b4b0`): saluran log bawaan menjadi
      `daily` dengan simpanan 14 hari. Diubah pada bawaannya di
      `config/logging.php`, bukan hanya di `.env.example` — `.env` produksi
      tidak menyebut `LOG_STACK` sama sekali, jadi contoh yang diperbarui saja
      tidak akan berpengaruh di sana.

      **Dua hal masih di tangan Anda, keduanya di server:**
      berkas `laravel.log` yang 127 MB itu tetap ada (saluran baru menulis ke
      berkas bertanggal dan tidak menyentuh yang lama) sehingga perlu dihapus
      sekali dengan tangan; dan `LOG_LEVEL=debug` di `.env` produksi — sebab
      utama lognya sebesar itu — hanya bisa diubah di sana.
