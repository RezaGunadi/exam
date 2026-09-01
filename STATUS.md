# Status Exam v2 — Apa yang Sudah, Apa yang Belum

Satu daftar untuk seluruh pekerjaan. Menggantikan tiga berkas terpisah
(`PERMINTAAN_v2.md`, `PLAN_UI_V1_V2.md`, `PLAN_EXAM_V1_V2.md`) sebagai tempat
melihat keadaan; ketiganya tetap ada sebagai catatan rinci.

Diperiksa langsung ke kode dan produksi pada **2 September 2026** — bukan dari
ingatan. Yang tidak dicentang berarti benar-benar belum, bukan belum sempat
dicek.

---

## BELUM — disusun dari yang paling saya dahulukan

### 1. `lms.kelasprivat.id` menyajikan situs orang lain
- [ ] Blok server 443 untuk `lms.kelasprivat.id`
- [ ] Halaman depan bervarian LMS

Hari ini domain itu membuka **"STN Smart System"** — aplikasi milik orang lain.
Sebabnya sama persis seperti yang sudah dua kali terjadi (`db.kelasprivat.id`
dan domain brand): tidak ada blok 443 untuk namanya, jadi nginx menyajikan blok
443 pertama yang ada.

**Didahulukan karena ini satu-satunya butir yang sedang salah menampilkan
sesuatu kepada publik.** DNS Anda sudah mengarah, dan resepnya sudah terbukti
dua kali — tinggal dijalankan. Pustaka variannya (`src/lib/varian-situs.ts`)
sudah dibuat; halaman depannya belum.

### 2. Tanda tangan kepala sekolah tidak punya isian
- [ ] Isian unggah tanda tangan di `/admin/school`

Kolom `schools.signature_image` **sudah ada**, dan **4 sekolah sudah
mengisinya** — lewat v1. Di v2 tidak ada satu pun isian untuk itu, jadi sekolah
yang pindah ke v2 tidak bisa mengganti atau memasangnya.

Didahulukan karena datanya sudah ada dan yang kurang hanya satu isian:
pekerjaan kecil dengan akibat yang sudah nyata.

### 3. Rich text untuk isi cerita/stimulus
- [ ] Penyunting rich text di `/admin/question-stories`

Isinya tersimpan sebagai HTML tetapi disunting di textarea polos, sehingga guru
melihat `<div>`, `&nbsp;`, dan `</div>` bercampur teks soal. Setiap
penyuntingan berisiko merusak markup yang sudah ada.

### 4. Tambah/hapus kategori buku pindah ke owner
- [ ] `POST` dan `DELETE` kategori dibatasi owner
- [ ] Layar pengelolaan kategori di panel owner
- [ ] Layar admin menjadi baca-saja

Kategori **per sekolah** (669 baris di produksi), dan jalur "Lainnya" saat input
buku memakai kode yang **terpisah** (`resolveBookCategory`) — jadi membatasi
endpoint kategori tidak akan mematahkannya. Sudah diverifikasi.

### 5. Sisa select yang belum bisa dicari
- [ ] 22 select tersisa

Turun dari 37. Yang tersisa berisi daftar pendek — tahun ajaran, semester, jenis
pembayaran perpustakaan, daftar kamera. `PilihCari` sudah menyesuaikan diri (di
bawah sembilan pilihan ia tidak menampilkan kotak ketik), jadi mengubahnya aman
kapan saja dan hanya soal keseragaman tampilan, bukan fungsi.

**Ditaruh terakhir karena tidak ada yang rusak** — hanya belum seragam.

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
- [ ] Aksesibilitas layar ujian — layar yang paling lama dipakai siswa, belum pernah diperiksa
