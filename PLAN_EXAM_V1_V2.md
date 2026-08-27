# Rencana Kerja Exam v1 & v2 — 12 Item

Disusun 2026-08-27. Setiap item punya **temuan** (hasil pembacaan kode, dengan
lokasi), **rencana v1** (Laravel), **rencana v2** (Go + Next.js), dan **skema**
bila ada perubahan database.

Prinsip yang dipegang:

1. **v1 dan v2 harus berakhir sama.** Skema keduanya sudah kembar (v2 port dari
   v1), jadi tiap perubahan kolom ditulis dua kali dengan nama yang sama persis.
   Nama yang berbeda antar versi berarti backup/restore lintas versi rusak.
2. **Kolom baru selalu punya default yang mempertahankan perilaku lama**, kecuali
   memang diminta berubah (item 8 & 12). Data lama tidak boleh berubah arti hanya
   karena migrasi dijalankan.
3. **Tidak ada penghapusan data.** Item 3 (buku hilang/diganti) khususnya:
   riwayat yang hilang harus TETAP ada, hanya diberi catatan.

---

## Ringkasan status temuan

| # | Item | v1 | v2 |
|---|---|---|---|
| 1 | Route uji beban ujian serentak | ✅ selesai | ✅ selesai |
| 2 | Download QR buku error | ✅ selesai | ✅ selesai |
| 3 | Harga buku, denda, hilang/ganti, kas masuk | belum ada | belum ada |
| 4 | Tampilan v2 turun kelas dari v1 | — | perlu audit halaman per halaman |
| 5 | Preview soal: jawaban tak ter-highlight | ✅ selesai | ✅ selesai |
| 6 | Tanda "ragu-ragu" per soal | belum ada | belum ada |
| 7 | Waktu ujian berkoma | ✅ selesai | ✅ selesai |
| 8 | Kamera default non-wajib | selalu wajib | selalu wajib |
| 9 | Login scan kartu siswa (QR) | ✅ selesai | ✅ selesai |
| 10 | Kategori buku | `books.category` string bebas | sama |
| 11 | Dua eligibilitas berdiri sendiri (nilai / lembar jawaban) | satu flag `show_results` | sama + `includeAnswerKey` di-hardcode false |
| 12 | Auto-submit kecurangan bisa dimatikan | selalu aktif | selalu aktif |

---

## Item 1 — Route uji beban: berapa siswa bisa ujian serentak  ✅ SELESAI (v1 + v2)

### Temuan

**v2 sudah punya**: `backend/internal/platform/stress.go` (277 baris) —
`POST /api/stress/run?token=<stress_token>`. Ia membuat sekolah SANDBOX
terisolasi, mensimulasikan N siswa (start → K× autosave → submit) langsung ke
handler + MySQL produksi, mengukur latensi per-endpoint, lalu menghapus seluruh
data sandbox. Batas: 2000 siswa, 50 loop, 10 soal.

**v1 belum punya apa pun.**

### Rencana v1

Port `stress.go` ke Laravel sebagai `app/Console/Commands/StressExam.php` +
route admin-only. Alasan memilih **command + route**, bukan route saja: uji beban
2000 siswa lewat HTTP request akan kena `max_execution_time` PHP-FPM jauh sebelum
selesai.

- `php artisan exam:stress --students=500 --loops=10` — jalur utama, tanpa batas
  waktu web.
- `GET /admin/stress` — halaman pemicu yang men-dispatch job + polling hasil,
  supaya bisa dijalankan tanpa SSH.
- Isolasi sandbox sama seperti v2: sekolah bertanda sandbox, dibersihkan di
  blok `finally` — termasuk saat command dibatalkan.
- Yang diukur harus sama dengan v2 agar angkanya bisa dibandingkan: p50/p95/p99
  per endpoint (start, autosave, submit), error rate, throughput.

### Keadaan sekarang di v2 (hasil pembacaan `stress.go`)

**Sekolah & siswa dummy + pembersihan: SUDAH ADA.** Tiap jalan membuat
sekolah bertanda `STRESS-<timestamp>`, siswa virtual, mapel, paket, 10 soal,
dan satu ujian. Seluruhnya dihapus KERAS (`Unscoped()`) di blok `defer` —
jawaban siswa, hasil, penugasan, ujian, soal, paket, enrollment, user,
kelas, lalu sekolahnya. Jadi ia memang tidak menumpuk di database.

**Simpan soal BELUM diukur.** Soal dibuat langsung lewat `s.DB.Create(&q)`
sebagai persiapan, bukan lewat endpoint simpan-soal. Artinya jalur yang
dipakai guru saat mengetik soal — validasi, tipe soal, unggah gambar —
sama sekali tidak ikut terukur, padahal itu yang berat saat banyak guru
menyiapkan ujian berbarengan menjelang musim ujian.

### Yang perlu ditambahkan

- **Fase simpan soal**: N guru virtual membuat soal lewat endpoint
  sungguhnya (POST soal), diukur terpisah dari fase siswa. Ikut dibersihkan
  oleh `defer` yang sudah ada karena semuanya bertanda school_id sandbox.
- **Sapuan sandbox yatim saat start.** `defer` berjalan saat return normal
  dan saat panic, tetapi TIDAK saat prosesnya dimatikan (OOM, restart
  deploy). Sekali itu terjadi, sekolah `STRESS-%` tertinggal selamanya dan
  tidak ada yang tahu. Perlu pembersih yang menyapu sisa saat server start.

### Sisanya di v2:
- **Halaman owner** `/owner/stress` untuk menjalankannya tanpa curl + token
  manual. Sekarang tokennya harus diambil dari `app_settings` dengan tangan.
- **Verifikasi pembersihan sandbox** — baca ulang jalur `defer` di `stress.go`;
  sandbox yang tertinggal berarti data sampah di database produksi.
- Tampilkan **angka kesimpulan**, bukan cuma latensi mentah: "pada beban X siswa
  serentak, p95 submit = Y ms" dan batas aman yang disarankan.

### Catatan penting

Angka dari kedua alat ini **konservatif untuk CPU dan optimistis untuk jaringan**:
generator beban berjalan di mesin yang sama, jadi latensi jaringan siswa tidak
terhitung. Ini harus ditulis di layar hasil, bukan di dokumentasi saja — angka
tanpa konteks akan dibaca sebagai janji kapasitas.

### Status — SELESAI

**v2** — `stress_teacher.go` (fase guru + penyapu), fase guru disambung ke
`runStressScenario`, `clampStressPayload` dipusatkan (jalur token dan jalur
owner tidak boleh punya batas berbeda — batas yang lebih longgar di salah satu
pintu adalah cara sebuah "uji" beban menjatuhkan produksi), dan
`SweepOrphanStressSandboxes` dipanggil saat server start.

**v1 — dibangun dari nol.** `StressTestService` (aturan + pengukuran +
pembersihan), command `exam:stress`, halaman owner `/owner/stress`, dan sapuan
terjadwal tiap jam.

**Fase simpan soal** menempuh controller/endpoint sungguhan, bukan
`Question::create`. Alasannya: jalur itulah yang dipakai guru — validasi tipe
soal, pembangunan payload, pembaruan `total_questions` paket — dan justru itu
yang berat menjelang musim ujian. Guru virtual dibuat berperan **tutor**, bukan
admin: itulah peran yang sebenarnya dipakai, dan otorisasinya berbeda.

**Hasil nyata** (v1, mesin pengembangan, 30 siswa × 5 autosave + 5 guru × 10
soal, 410 permintaan, 0 galat, 3,66 detik):

| Endpoint | N | p50 | p95 | p99 |
|---|---|---|---|---|
| save_question | 50 | 7,73 | 9,26 | 10,47 |
| start | 30 | 12,73 | 20,81 | 32,04 |
| autosave | 150 | 5,05 | 7,21 | 10,79 |
| heartbeat | 150 | 1,93 | 4,25 | 9,95 |
| submit | 30 | 29,07 | 34,98 | 36,17 |

**Perbedaan yang WAJIB disebut saat membandingkan v1 dan v2**, dan karenanya
dicetak di layar hasil, bukan hanya di dokumen ini: v1 menjalankan siswa
**berurutan** (PHP tidak punya goroutine), jadi angkanya adalah **biaya per
operasi**. Angka v2 berasal dari 64 goroutine serentak — itu perilaku di bawah
kontensi. Menyandingkan keduanya tanpa keterangan ini akan terbaca seolah salah
satunya jauh lebih cepat.

### Tiga masalah nyata ditemukan saat menjalankannya

1. **Sandbox tertinggal saat setup gagal.** Percobaan pertama gagal di
   `subjects.code` (NOT NULL tanpa default) — dan sekolah sandbox-nya
   **tertinggal di database**, karena `$school = $this->buildSandbox(...)` tidak
   pernah ter-assign saat exception dilempar dari dalamnya, sehingga blok
   `finally` melewatkannya. Sekolahnya kini dibuat di luar, sebelum apa pun yang
   bisa gagal.
2. **Pembersihan tidak menghapus apa pun.** Sembilan dari sepuluh model yang
   disentuh memakai `SoftDeletes`, jadi `delete()` hanya mengisi `deleted_at`.
   Data uji beban justru yang paling tidak boleh begitu — inilah yang diminta
   dihindari sejak awal ("biar ga menuh-menuhin db"). Kini `forceDelete()` +
   `withTrashed()`; `withTrashed` wajib karena baris yang terlanjur soft-delete
   tidak terlihat kueri biasa dan akan luput selamanya.
3. **`--sweep` tidak bisa membersihkan sisa yang baru saja terbentuk.** Batas
   usia 60 menit melindungi uji yang sedang berjalan, tetapi juga memblokir
   pembersihan sisa dari crash yang baru terjadi. Ditambahkan
   `--sweep-older-than`, dengan bawaan yang tetap melindungi.

Batas web (50 siswa) jauh di bawah batas command (2000), dan alasannya ditulis
di halamannya: uji lewat browser yang terpotong `max_execution_time` bukan hanya
kehilangan hasil — `finally` PHP tidak berjalan saat proses dibunuh timeout, dan
sandbox-nya tertinggal.

**Diuji:** `clampStressPayload` (5 kasus, termasuk "guru=0 → soal-per-guru tetap
0"), fase guru menyimpan soal lewat router sungguhan dan terverifikasi ada di
database, penyapu menghapus sandbox tua berikut anaknya tetapi **melewatkan**
sandbox yang masih baru dan sekolah bernama mirip ("STRESSFUL SCHOOL"). Di v1:
seluruh alur lewat controller owner, dan jumlah baris database sebelum/sesudah
dibandingkan — sama persis.

---

## Item 2 — Download QR buku error  ✅ SELESAI (v1 + v2)

### Temuan v1 — satu sebab, dan ia senyap

**Paketnya tidak pernah terpasang.**
`composer.json:13` meminta `chillerlan/php-qrcode: ^5.0.5`, tetapi
`composer.lock` **tidak memuatnya sama sekali** (0 kecocokan). `composer install`
mengikuti lock, jadi paket itu tidak pernah ada di server.

**KOREKSI atas dugaan awal.** Rencana ini sempat menyebut sebab kedua: bahwa
`QRCode::OUTPUT_IMAGE_PNG` dihapus di v5 sehingga kodenya melempar exception.
**Itu salah.** Paket 5.0.5 dipasang di direktori uji dan kode lama dijalankan apa
adanya — `QRCode.php:96` masih mendefinisikan `OUTPUT_IMAGE_PNG` sebagai alias
`QROutputInterface::GDIMAGE_PNG`, dan render berhasil menghasilkan data URI PNG
1058 byte. Jadi memperbaiki lock saja sudah cukup untuk menghidupkan QR-nya.

**Akibatnya berlipat**: `qrDataUri()` (`LibraryController.php:340`) menangkap
kegagalan lalu **mengembalikan null tanpa memberi tahu siapa pun** — halaman
label tampil normal, hanya kotak QR-nya kosong. Tidak ada pesan error di layar.

Hal yang sama ada di `AbsensiController.php:702` (kartu siswa), tetapi di sana
ada fallback ke API eksternal — `api.qrserver.com` dan `chart.googleapis.com`.
**Yang kedua sudah mati sejak 2019.** Kartu siswa masih jalan hanya karena
fallback pertama, artinya QR kartu siswa saat ini bergantung pada layanan pihak
ketiga tanpa SLA. Ini penting untuk item 9.

### Yang dikerjakan di v1

1. ✅ `composer update chillerlan/php-qrcode --no-install` — lock kini memuat
   `chillerlan/php-qrcode 5.0.5` + `chillerlan/php-settings-container 3.3.0`.
2. ✅ `app/Helpers/QrRenderer.php` — satu-satunya tempat QR dibuat. Melempar
   exception saat gagal, tidak lagi mengembalikan null diam-diam. Punya
   `dataUri`/`png` (melempar) dan `dataUriOrNull`/`pngOrNull` (toleran).
   Payload tidak pernah masuk log utuh — isinya kredensial.
3. ✅ **Dua fallback API eksternal dicabut** dari kartu siswa
   (`api.qrserver.com` dan `chart.googleapis.com` yang sudah mati sejak 2019).
   Fallback pertama itulah yang selama ini menutupi bug lock-nya.
4. ✅ Label buku menolak dicetak bila QR kembar / QR kosong / `copy_code` kosong.
5. ✅ `addCopies` dibungkus transaksi — dulu tidak ada, padahal tiap eksemplar
   butuh insert (mengisi `qr`) lalu update (mengisi `copy_code` dari id).
6. ✅ Route baru `admin.library.labels.pdf` + tombol "Unduh PDF" di toolbar.

### Kenapa "10 buku QR-nya harus beda" aman

Terverifikasi, bukan diasumsikan:

- **v1** — `BookCopy::boot()` mengisi `qr = 'BC-' . Str::lower(Str::random(40))`
  di dalam `creating`, jadi tiap eksemplar dapat nilai baru; kolomnya `unique()`
  di migrasi. Diuji: 10 payload → 10 PNG dengan sha1 berbeda semua.
- **v2** — `createBookCopies` memanggil `uuid.NewString()` **di dalam loop**;
  kolomnya `uniqueIndex`.
- **Risiko sebenarnya bukan QR-nya, melainkan `copy_code`.** Ia diisi SETELAH
  insert, dan di v1 jalur `addCopies` dulu tanpa transaksi. Gagal di antara dua
  operasi meninggalkan eksemplar ber-QR tanpa kode inventaris — dan kode itulah
  satu-satunya bagian label yang terbaca mata. Sepuluh stiker tanpa kode tidak
  bisa dibedakan manusia; **itulah cara buku benar-benar tertukar saat
  ditempel**, bukan lewat QR-nya. Sudah ditutup di kedua versi.

### Yang dikerjakan di v2

Pembuatan QR-nya memang sudah sehat (`skip2/go-qrcode`). Yang ditambahkan:

1. ✅ `library_labels_pdf.go` — `GET /api/admin/library/labels.pdf`, 4 label per
   baris, 46×54 mm, memakai `newPDF()` (gofpdf + font DejaVu) yang sudah dipakai
   lembar jawaban. Nama registrasi gambar dibuat unik per label; dipakai ulang,
   gofpdf akan memakai gambar yang sudah terdaftar dan **seluruh label memakai QR
   yang sama** — persis kegagalan "tertukar" yang paling mahal.
2. ✅ `validateLabelCopies()` — penjaga QR kembar / kosong / `copy_code` kosong,
   dipakai jalur JSON **dan** PDF. Dua jalur keluaran tidak boleh punya standar
   berbeda; yang longgar akan selalu jadi yang dipakai.
3. ✅ `qrcode.Encode` yang gagal kini mengembalikan 500 dengan pesan, bukan
   `qr_image: ""` yang dirender frontend sebagai kotak kosong.
4. ✅ Batas 500 eksemplar diberitahukan (`truncated` + `truncated_message`),
   tidak lagi memotong diam-diam.
5. ✅ Tombol "Unduh PDF" + keterangan pencocokan kode di halaman label.

**Tes**: `library_labels_pdf_test.go` — 10 eksemplar → 10 PNG berbeda (dicek
sampai byte-nya), penolakan QR kembar menyebut kedua eksemplar yang bentrok,
penolakan QR kosong, dan `copy_code` kosong dalam tiga bentuk (nil / "" / spasi).

---

## Item 3 — Harga buku, denda, buku hilang, ganti buku, kas masuk  ✅ SELESAI (v1 + v2)

Ini item terbesar. Dipecah jadi lima bagian. **SELESAI di v1 dan v2.**

### 3a. Harga buku

**Temuan**: `books` (`2026_06_14_100002_create_books_table.php`) tidak punya
kolom harga. `library_settings` hanya punya `loan_days` + `fine_per_day`.

**Skema (v1 & v2, nama identik):**

```
books.price            DECIMAL(12,2) NULL   -- harga satuan buku
books.replacement_cost DECIMAL(12,2) NULL   -- biaya ganti bila hilang; NULL = pakai price
```

Dua kolom, bukan satu: harga beli dan biaya ganti sering berbeda (buku lama
harganya sudah naik). `replacement_cost` NULL jatuh ke `price` supaya sekolah
yang tidak peduli bedanya cukup mengisi satu.

### 3b. Opsi "buku hilang" di daftar pinjaman

**Temuan**: `book_copies` sudah punya `STATUS_LOST`, dan `book_loans` sudah punya
`fine_amount`. Yang belum ada: **alur** menandai pinjaman sebagai hilang berikut
konsekuensinya.

**Skema:**

```
book_loans.status              -- tambah nilai: 'lost', 'replaced'
book_loans.lost_at             TIMESTAMP NULL
book_loans.lost_note           TEXT NULL
book_loans.replacement_copy_id BIGINT NULL       -- eksemplar pengganti (item 3d)
book_loans.settlement_type     VARCHAR(16) NULL  -- 'replace_book' | 'pay_money' | NULL
```

Alur di halaman daftar pinjaman: tombol **"Tandai hilang"** membuka dialog berisi
biaya ganti (terisi otomatis dari `replacement_cost`/`price`, boleh disunting),
catatan, dan pilihan penyelesaian.

### 3c. Input denda

**Temuan**: `fine_per_day` sudah dipakai untuk keterlambatan, tetapi denda tidak
pernah bisa disunting manual saat pengembalian.

**Rencana**: kolom denda pada dialog pengembalian **terisi otomatis dari hitungan
hari telat, tetapi bisa ditimpa** — dengan alasan wajib diisi bila nilainya
berubah. Denda yang diubah tanpa alasan tercatat adalah cara paling umum uang kas
jadi tidak bisa direkonsiliasi.

```
book_loans.fine_auto_amount     DECIMAL(12,2) NULL  -- hasil hitungan sistem
book_loans.fine_override_reason TEXT NULL           -- wajib bila fine_amount != fine_auto_amount
```

### 3d. Ganti buku → QR baru, listing lama tetap ada

**Ini permintaan paling spesifik dan paling mudah salah.** Yang diminta:

> kalau ganti buku bukunya perlu download ulang qr berbeda biar listing yang
> hilang tetep ada tapi ada catatan sudah di ganti

Artinya: eksemplar yang hilang **TIDAK dihapus dan TIDAK dipakai ulang**. Ia
tetap ada dengan status `lost`, dan eksemplar pengganti adalah **baris baru**
dengan `copy_code` dan QR baru.

Alasannya bukan sekadar administratif: QR lama bisa saja ada di buku yang
ditemukan kembali setahun kemudian. Kalau QR itu dipakai ulang untuk buku
pengganti, dua buku fisik punya identitas yang sama dan riwayat peminjaman
keduanya bercampur — tanpa cara memisahkannya lagi.

**Skema:**

```
book_copies.replaced_by_copy_id BIGINT NULL     -- eksemplar lama -> penggantinya
book_copies.replaces_copy_id    BIGINT NULL     -- eksemplar baru -> yang digantikannya
book_copies.replacement_note    TEXT NULL
book_copies.replaced_at         TIMESTAMP NULL
```

Di daftar eksemplar, baris `lost` tetap tampil dengan label
**"Hilang — sudah diganti oleh BK-000123"**, dan baris pengganti berlabel
**"Pengganti BK-000045"**. Keduanya saling menunjuk.

Setelah eksemplar pengganti dibuat, halaman **langsung menawarkan cetak/download
QR-nya** — itu bagian "perlu download ulang qr berbeda".

### 3e. Pembayaran uang → catatan + daftar kas masuk

**Temuan**: v1 punya `PaymentRequest` dan `UserCreditTransaction`, v2 punya
`owner_payment.go` — tetapi keduanya untuk langganan platform, **bukan** kas
perpustakaan. Tidak ada tempat mencatat uang denda/ganti rugi.

**Skema — tabel baru (v1 & v2):**

```
library_payments
  id, school_id, book_loan_id NULL, book_copy_id NULL,
  borrower_id, amount DECIMAL(12,2),
  kind VARCHAR(16),          -- 'fine' | 'replacement' | 'other'
  paid_at TIMESTAMP,
  received_by BIGINT,        -- petugas yang menerima
  note TEXT NULL,
  created_at, updated_at
```

Halaman baru **"Kas Perpustakaan"**: daftar uang masuk, filter tanggal/jenis,
total per periode, ekspor. Terhubung dua arah ke pinjaman yang menjadi sebabnya,
supaya dari baris pinjaman bisa dilihat pembayarannya dan sebaliknya.

**Yang sengaja tidak dilakukan**: pembayaran tidak boleh dihapus, hanya
dibatalkan dengan baris koreksi bernilai negatif. Buku kas yang barisnya bisa
hilang bukan buku kas.

### Status v1 — SELESAI

Migrasi `2026_08_27_000003_add_library_money_tracking.php` (empat tabel
sekaligus, karena keempatnya satu alur), `LibraryLossService`, `LibraryPayment`,
`LibraryPaymentController`, tiga endpoint di `BookLoanController`, halaman
`admin/library/payments.blade.php`, dan form sunting buku di halaman detail.

**Satu penyimpangan dari rencana, disengaja.** Rencana menyebut menambah nilai
`'replaced'` ke `book_loans.status`. Tidak dilakukan: kalau `'replaced'` jadi
status, pinjaman yang diselesaikan DENGAN BUKU berubah statusnya sedangkan yang
diselesaikan DENGAN UANG tetap `'lost'` — dua penyelesaian sejenis tercatat di
tempat berbeda, dan setiap kueri "kerugian yang belum diselesaikan" harus hafal
keanehan itu. Status tetap `active|returned|lost`; caranya ditaruh di
`settlement_type`, dan `settled_at` jadi satu-satunya penentu selesai atau belum.

**Tambahan di luar rencana, karena tanpanya fiturnya tidak berguna:**
`LibraryController::update()` + form sunting buku. Sebelumnya v1 sama sekali
tidak punya endpoint ubah buku — harga hanya bisa diisi pada detik buku dibuat,
sehingga seluruh buku yang sudah terlanjur ada di rak tidak akan pernah punya
harga dan tagihan kehilangannya selamanya kosong.

**Diuji terhadap `exam_v1`, DB dikembalikan dan diverifikasi setiap kali:**

| Diuji | Hasil |
|---|---|
| `LibraryLossService`, 11 perilaku | `replacement_cost` menang atas `price`; buku tanpa harga → NULL bukan 0; tandai-hilang tidak ikut melunasi; eksemplar pengganti ber-QR & ber-kode BEDA; keduanya saling menunjuk; penyelesaian ganda ditolak |
| Pembatalan pembayaran | baris negatif menunjuk baris asli; baris asli TIDAK hilang; saldo kembali nol; pinjaman kembali "belum selesai"; koreksi atas koreksi ditolak |
| Halaman kas lewat controller, 9 langkah | ringkasan periode, pemasukan lain, ekspor CSV ber-BOM, rentang tanggal terbalik tetap mengembalikan baris |
| Render 6 halaman perpustakaan | 46–54 KB, 1–11 kueri (tanpa N+1); label penggantian, tanda denda "diubah", dan biaya ganti bawaan benar-benar muncul |
| `LibraryController::update()` | harga tersimpan; mengosongkan biaya ganti membuat tagihan jatuh ke harga buku |

**Dua bug ditemukan sambil jalan:**

1. `BookLoanController::index()` memuat `book:id,title` saja, sedangkan form
   tandai-hilang memanggil `replacementCharge()` yang butuh `price` dan
   `replacement_cost`. Tanpa perbaikan, kolom biaya ganti selalu tampil kosong
   **tanpa satu pun galat** — seolah sekolah belum pernah mengisi harga.
2. Pola `$data['key']` tanpa `??` pada field `nullable` terulang di kode baru
   (`paid_at`) setelah saya memperbaikinya di `store()` (`isbn`). `validate()`
   hanya mengembalikan kunci yang benar-benar dikirim.

Satu cacat harness uji juga diperbaiki: pemeriksaan form tandai-hilang mula-mula
melapor "TIDAK" karena seluruh pinjaman di fixture sudah berstatus hilang —
formnya memang hanya untuk pinjaman aktif, jadi yang diuji bukan apa-apa.

### Status v2 — SELESAI

`library_loss.go` (model `LibraryPayment` + seluruh aturan),
`library_payment_admin.go` (8 handler), 8 rute baru,
`handleLibraryUpdateBook`, halaman `admin/library/payments/page.tsx`, kolom
harga di form buku dan di halaman detail, serta tombol tandai-hilang di daftar
pinjaman.

Nama kolom, nilai `settlement_type`, dan nilai `kind` **identik dengan v1** —
beda satu huruf saja membuat backup yang dipulihkan lintas versi menampilkan
penyelesaian sebagai tidak dikenal.

**Diuji lewat router sungguhan** (`library_loss_test.go`, 6 fungsi uji):
`ReplacementCharge`, `fineWasOverridden` (termasuk kasus float `0.1+0.2`),
`calculateLoanFine`, alur hilang→ganti buku, pembayaran→pembatalan, API kas,
dan `handleLibraryUpdateBook` (termasuk penolakan buku sekolah lain).

**Satu jebakan GORM ditemukan dan ditutup — bukan hanya di uji, tetapi di kode
produk.** `First()` **tidak menimpa field pointer yang sudah terisi dengan
NULL**; nilai lamanya bertahan tanpa satu pun galat. Terbukti lewat uji
diagnosis terpisah: nilai di database sudah `NULL`, struct baru membacanya
`nil`, struct bekas tetap menampilkan nilai lama. Akibatnya bila dibiarkan:
pembatalan ganti rugi mengosongkan `settled_at` di database, tetapi kode yang
membaca ulang ke struct yang sama tetap melihat pinjaman itu lunas — dan
tagihannya tidak akan pernah muncul lagi. `markLoanLost` kini membaca ke struct
baru lalu menyalinnya, dan alasannya ditulis di tempatnya.

Alasan kedua memakai `Updates(map[...])` alih-alih struct di
`handleLibraryUpdateBook` juga dari keluarga yang sama: GORM melewati field
`nil` pada struct, sehingga harga yang sekali diisi tidak akan pernah bisa
dikosongkan lagi. Ada ujinya sendiri.

---

## Item 4 — Tampilan v2 di bawah v1  🔄 CACAT TERUKUR SELESAI, banding visual belum

### Yang dikerjakan: audit yang bisa dibuktikan, bukan tebakan

Rencana awal menyebut "ambil tangkapan layar berdampingan". Itu tidak bisa
dilakukan dari sini — tidak ada peramban, Playwright, maupun jsdom di
lingkungan ini. Yang dikerjakan sebagai gantinya adalah audit atas hal-hal yang
**bisa diverifikasi tanpa merender**: inventaris halaman, lint, aturan kaskade
CSS, dan angka patok di tata letak.

Perbandingan rasa/estetika berdampingan **masih tersisa** dan jujur belum
dikerjakan.

### Dugaan awal yang TERBANTAH

Dua dari tiga keluhan di rencana awal ternyata tidak berdasar:

**"Banyak halaman memakai inline style alih-alih kelas, jadi tidak ikut tema."**
Seluruh berkas disisir: hanya **satu** yang memakai warna keras di inline
style, yaitu `admin/library/[id]/page.tsx` — dan di sana itu **benar**. Isinya
label QR untuk DICETAK (ada blok `@media print` dan kelas `.no-print`); label
dicetak di atas kertas putih, dan aplikasi ini tidak punya tema gelap sama
sekali (tidak ada `prefers-color-scheme` maupun `data-theme`). Tidak diubah.

**"Halaman v2 lebih sedikit / lebih miskin daripada v1."** Inventarisnya justru
imbang. Satu-satunya direktori v1 yang tidak punya padanan bernama sama,
`admin/tutor-users`, ternyata sudah digabung ke dalam `admin/tutors` v2 (satu
halaman menangani akun tutor sekaligus penugasannya). Di sisi siswa v2 malah
lebih banyak (`raports`, `tasks/rekap`).

### Tiga cacat NYATA yang ditemukan dan diperbaiki

**1. Kerangka halaman berkedip tiap pindah halaman — keluhan yang dilaporkan.**

Tiap halaman merender `AppShell`-nya sendiri, jadi berpindah halaman
meng-unmount kerangka lama dan me-mount yang baru. `user` selalu mulai dari
`null`, dan selama satu putaran render kelasnya `shell-loading`: topbar siswa
BELUM ada (isi halaman naik 56px) dan sidebar masih memakai gradien gelap
alih-alih permukaan terang. Begitu `/api/auth/me` selesai, semuanya berpindah
tempat sekaligus.

Itulah "kerasa ada yang lompat dan membesar". Diperbaiki dengan singgahan
pengguna di tingkat modul (`getCachedUser`/`setCachedUser` di `lib/api.ts`),
dipakai sebagai nilai awal. Perpindahan kedua dan seterusnya langsung merender
kerangka yang benar.

Singgahannya dikosongkan **di dalam `clearToken()`**, bukan di pemanggilnya —
ada tiga tempat yang menghapus token, dan yang lupa membersihkan singgahan akan
menampilkan kerangka pengguna sebelumnya.

**2. Gangguan jaringan sesaat mengeluarkan pengguna.**

`AppShell` menangkap SEMUA error dari `/api/auth/me`, lalu menghapus token dan
melempar ke `/login` — termasuk saat jaringan putus sekejap atau API sedang
tidak menjawab. Bagi siswa yang sedang mengerjakan ujian, satu kedipan koneksi
cukup untuk membuatnya keluar. Kini hanya 401/403 yang mengeluarkan; error lain
dibiarkan dan permintaan berikutnya mencoba lagi.

**3. Sidebar siswa rusak di HP — dan justru siswa yang memakai HP.**

`@media (max-width: 980px)` mengubah `.sidebar` jadi laci (`position: fixed`,
digeser keluar layar). Tetapi `.shell-student .sidebar` (dua kelas, kekhususan
0,2,0) menang atas `.sidebar` (0,1,0), dan **media query tidak menambah
kekhususan**. Akibatnya di HP sidebar siswa bertahan `position: sticky`: masih
memakan satu baris grid setinggi layar penuh — isi halaman terdorong ke bawah
satu layar kosong — dan lacinya mendorong tata letak alih-alih menutupinya.

Diperbaiki dengan mengulang selektor siswa di dalam media query. Disisir juga
seluruh aturan `.shell-student` lain: sisanya hanya mengatur warna dan latar,
yang tidak disentuh media query — jadi ini satu-satunya.

**4. Tinggi topbar dipatok 56px padahal bisa dua baris.**

`.student-topbar-inner` dan `.student-topbar-links` keduanya `flex-wrap: wrap`,
jadi di lebar menengah tautannya turun ke baris kedua dan topbar tumbuh jauh
melewati 56px. Sidebar yang menempel di `top: 56px` lalu tersembunyi sebagian
di balik topbar, dan tingginya (`100vh - 56px`) melewati bawah layar.

Angka ajaibnya diganti nilai terukur: `AppShell` memasang `--topbar-h` dari
`offsetHeight` topbar lewat `ResizeObserver`, dan CSS memakainya
(`top: var(--topbar-h, 56px)`).

### Empat error lint dibereskan

Dua di antaranya **buatan sendiri** di sesi ini, dan itu disebut apa adanya:

| Berkas | Masalah |
|---|---|
| `student/tasks/rekap` (baru) | `setState` sinkron di dalam `useEffect` |
| `student/materials` (baru) | sama |
| `owner/blast/[id]` | dependensi `useCallback` `[params?.id]` tidak cocok dengan yang disimpulkan React Compiler → **seluruh komponen dilewati optimasinya** |
| `exam-workspace` | `<a>` untuk navigasi internal |

Untuk `exam-workspace`, `<a>` diganti `<Link>` hanya setelah dipastikan aman:
komponen itu melepas seluruh listener proktoringnya saat unmount, dan tidak ada
`fullscreen` maupun `beforeunload` yang perlu dibatalkan.

Dua error buatan sendiri diperbaiki dengan memisahkan `ambil()` (tidak
menyentuh state sebelum await, dipanggil dari effect) dari `muat()` (menyalakan
penanda memuat, dipanggil dari handler pengguna).

### Terverifikasi

`npx eslint src` → **0 baris keluaran**; `npx next build` → "✓ Compiled
successfully"; suite backend hijau tiga kali berturut-turut.

Perbaikan CSS diverifikasi lewat **aturan kaskade dan pembacaan kode**, bukan
dengan merender — tidak ada peramban di lingkungan ini. Ketiga perbaikan tata
letak sebaiknya dilihat sekali di HP sungguhan sebelum dianggap tuntas.

### Lanjutan — akar "v2 terasa lebih miskin" akhirnya ketemu

Banding struktural v1 lawan v2 dijalankan sebagai skrip: kolom tabel dan label
filter diekstrak dari Blade dan TSX, lalu diselisihkan. Hasil mentahnya
menyebut 105 penanda "hanya ada di v1" — dan itu **menyesatkan**, karena
heuristiknya tidak mengenali cara v2 merender. Skripnya sendiri sudah
memperingatkan itu, dan peringatannya benar.

Yang ditemukan setelah diperiksa manual jauh lebih spesifik:

**Tujuh halaman v2 bukan halaman, melainkan pembungkus setebal 14–44 baris.**

| Halaman | Baris |
|---|---|
| `admin/reports`, `tutor/subjects` | 14 |
| `admin/classes`, `admin/subjects` | 18 |
| `admin/semesters` | 24 |
| `owner/ads` | 26 |
| `admin/reports-config` | 44 |

Semuanya merender `ResourcePage` generik, yang menggambar tiap baris dari
`Object.entries` apa adanya: urutan kolom mengikuti urutan kunci JSON, label
memakai nama kolom basis data, dan kolom teknis seperti `slug` ikut terpampang.
Halaman jadi tampak seperti dump tabel, bukan halaman yang dirancang.

Bandingkan `admin/classes`: v1 menampilkan **Nama Kelas, Grade, Kapasitas,
Jumlah Siswa, Status** plus delapan saringan. v2 menampilkan apa pun yang
kebetulan dikirim API — dan API-nya **tidak mengirim jumlah siswa sama sekali**.

### Yang diperbaiki

**1. Jumlah siswa dikirim API kelas.** Itu angka pertama yang dicari admin saat
membuka daftar kelas: mana yang kosong, mana yang kepenuhan. Dihitung dengan
satu kueri agregat, bukan satu kueri per kelas.

**2. `ResourcePage` menerima definisi kolom.** Prop `fields` menyebut kolom
mana yang ditampilkan, berikut labelnya dan urutannya. Opsional, sehingga
halaman yang belum dirapikan tetap berjalan seperti sebelumnya.

Ini sekaligus menutup jebakan yang mudah terlewat: penyaring lama membuang
nilai kosong dengan `value !== null && value !== ""`, sehingga **kelas berisi 0
siswa akan kehilangan kolomnya sama sekali** — justru kelas yang paling ingin
diketahui admin. Diuji khusus: kelas kosong menampilkan `0`, bukan hilang.

**3. Nilai disajikan untuk manusia.** `String(value)` apa adanya menghasilkan
`"true"`/`"false"` untuk kolom seperti "Aktif", dan `"undefined"` untuk kolom
yang tidak dikirim API — keduanya terbaca sebagai data rusak, bukan sebagai
jawaban. Kini "Ya"/"Tidak" dan "—". `slug` juga dibuang dari daftar bawaan.

**4. Tiga halaman diberi kolom bernama**: kelas (Nama kelas, Jumlah siswa,
Aktif), mata pelajaran (Nama, Kode, Aktif), semester (Tahun ajaran, Semester,
Mulai, Selesai, Label).

### Terverifikasi

Lewat API sungguhan dengan backend hidup: dua kelas terkirim, kelas berisi 3
siswa melaporkan 3, kelas kosong melaporkan 0 (bukan hilang). Suite backend
hijau tiga kali berturut-turut; `eslint` 0 keluaran; `next build` sukses.

### Yang MASIH tersisa

**Empat halaman masih generik**: `admin/reports`, `admin/reports-config`,
`tutor/subjects`, `owner/ads`. Bentuk datanya tidak saya ketahui dengan pasti,
dan menebak nama kolom hanya akan memasang label yang salah. Keduanya kini
setidaknya tidak lagi menampilkan `slug` dan `"true"`.

**Grade dan Kapasitas tidak bisa ditampilkan v2** — kolomnya memang tidak ada
di skema v2 (`classes` hanya punya id, school_id, name, slug, is_active).
Menambahkannya adalah perubahan skema tersendiri, bukan perbaikan tampilan.

**Saringan lanjutan v1 belum ada di v2**: rentang nilai, urutkan/arah, saring
per kelas di daftar hasil ujian. `ResourcePage` hanya punya pencarian teks, dan
pencarian itu berjalan **di browser atas data yang sudah dimuat seluruhnya** —
untuk sekolah dengan ribuan baris, keduanya jadi masalah sekaligus.

**Banding rasa berdampingan tetap belum dikerjakan.** Itu butuh melihat kedua
aplikasi, dan tidak ada peramban di lingkungan ini.

---

## Item 5 — Preview soal: jawaban tidak ter-highlight  ✅ SELESAI (v1 + v2)

### Yang dikerjakan di v1

Partial bersama `resources/views/partials/question-answer-review.blade.php`
menangani kelima tipe, dipakai lembar jawaban, detail soal, dan detail paket
soal. Memakai `@include`, bukan komponen `<x-...>`, karena repo ini tidak
memakai satu pun komponen Blade.

`Question::typeLabel()` dan `Question::answerKeyLabel()` ditambahkan ke model
sebagai satu sumber kebenaran; **enam** percabangan badge tipe di lima berkas
diganti dengannya.

**Tiga bug yang ditemukan saat mengerjakannya — dua di luar dugaan awal:**

1. **Lembar jawaban hanya menangani 2 dari 5 tipe** (dugaan awal, terkonfirmasi).
2. **Perbandingan TEKS lawan HURUF.** `admin/questions/show.blade.php` dan
   `student/results/show.blade.php` menulis
   `$option === $question->correct_answer` — membandingkan teks opsi
   ("Jakarta") dengan kunci yang berisi huruf ("A"). Perbandingan itu tidak
   pernah benar, jadi di **tipe soal yang paling sering dipakai** tidak ada satu
   pun baris yang ter-highlight — termasuk di halaman hasil yang dibuka siswa
   sendiri. Jejaknya tertinggal di kode: variabel `$optionValue` sudah dihitung
   persis untuk itu, lalu tidak pernah dipakai.
3. **Opsi F–J hilang dari lembar jawaban.** UI `multiple_select` menyediakan
   sampai 10 opsi (`$msLetters` A–J), tetapi `Question::getOptionsWithImages()`
   hanya memetakan A–E. Halaman siswa memakai `getOptionsArray()` (tanpa batas)
   sehingga siswa tetap melihat semuanya — yang terpotong hanya lembar jawaban
   guru.

**Koreksi rencana**: `admin/exam-results/pdf.blade.php` ternyata **tidak
menampilkan daftar soal sama sekali** (hanya ringkasan + pelanggaran), jadi ia
tidak termasuk yang perlu diperbaiki. Sebaliknya, dua berkas yang tidak ada di
rencana awal ikut terkena dan sudah diperbaiki:
`admin/question-packages/show.blade.php` dan `admin/questions/repick.blade.php`.

**Verifikasi**: seluruh Blade dikompilasi lewat BladeCompiler standalone, lalu
partial-nya DIRENDER dengan data tiruan kelima tipe — 8 kasus (benar, salah,
tidak dijawab, benar sebagian, bercerita) semuanya menghasilkan penanda yang
diharapkan, termasuk opsi ke-10 (J) yang dulu terpotong.

### Rincian temuan awal

### Temuan — terkonfirmasi rusak di v1

`Question.php:98-102` mendefinisikan **lima** tipe soal:
`multiple_choice`, `essay`, `multiple_select`, `multiple_choice_reason`,
`true_false`.

`resources/views/admin/exam-results/answer_sheet.blade.php` hanya menangani
**dua**: `multiple_choice` (baris 346) dan `essay` (baris 397). Tiga tipe lain
jatuh ke luar percabangan — **tanpa highlight kunci jawaban maupun jawaban
siswa**. Bahkan label tipenya salah: baris 330 menulis

```php
{{ $question->type === 'multiple_choice' ? 'Pilihan Ganda' : 'Essay' }}
```

sehingga soal benar-salah **dilabeli "Essay"**.

Soal cerita (`question_stories`) dirender di baris 336 tetapi hanya sebagai blok
teks; tidak ada penanda soal mana saja yang termasuk bacaan itu.

### Rencana v1

Perbaiki `answer_sheet.blade.php`, lalu **telusuri tempat lain yang punya
percabangan tipe soal yang sama** — sudah teridentifikasi:
`admin/exam-results/pdf.blade.php`, `admin/exam-results/show.blade.php`,
`admin/questions/show.blade.php`, `admin/questions/index.blade.php`.

Supaya tidak ada tempat yang tertinggal lagi, buat **satu komponen Blade
bersama** `resources/views/components/question-answer-review.blade.php` yang
menangani kelima tipe, lalu semua halaman memakainya. Percabangan tipe soal yang
disalin ke lima berkas adalah sebab bug ini muncul; memperbaiki kelimanya
satu-satu berarti bug yang sama akan lahir lagi saat tipe soal keenam
ditambahkan.

Aturan highlight per tipe:
- `multiple_select` — kunci bisa lebih dari satu; tandai **benar sebagian**
  (siswa memilih 2 dari 3 kunci) berbeda dari benar penuh dan dari salah.
- `true_false` — setiap pernyataan punya kunci sendiri; highlight per baris.
- `multiple_choice_reason` — dua bagian (pilihan + alasan); keduanya di-highlight
  terpisah karena skornya juga terpisah.
- Soal bercerita — beri penanda "Bacaan #N" pada soal-soal yang berbagi cerita.

### Yang dikerjakan di v2

Aturan per tipe soal diputuskan **sekali di backend** (`question_review.go`),
lalu API dan PDF sama-sama memakainya. Frontend hanya menggambar apa yang sudah
ditandai — supaya bentuk v1 (tujuh berkas view yang masing-masing memutuskan
sendiri) tidak lahir lagi, kali ini terbelah antara dua bahasa.

1. ✅ `question_review.go` — `QuestionReview` + `buildQuestionReviews()`.
   Menormalkan opsi (A–J), kunci, pilihan siswa, alasan, dan ringkasan
   benar-sebagian untuk kelima tipe. `questionTypeLabel()` menyamai
   `Question::typeLabel()` di v1 kata demi kata.
2. ✅ **Lembar jawaban PDF ditulis ulang.** Versi lama hanya mencetak tiga baris
   teks — "Jawaban siswa: A", "Acuan/kunci: A", dan poinnya — **tanpa satu pun
   opsi**. Guru harus membuka bank soal di layar lain untuk tahu apa arti "A".
   Sekarang opsi digambar lengkap dengan penanda TEKS, bukan warna: lembar ini
   rutin dicetak hitam-putih, dan blok berwarna yang jadi abu-abu seragam lebih
   menyesatkan daripada tidak ditandai sama sekali. Nomor soal juga diambil dari
   urutan bank soal, bukan urutan `question_id` — dulu penomorannya tidak cocok
   dengan apa pun yang dilihat siswa.
3. ✅ **Halaman hasil siswa.** Sebelumnya hanya menampilkan
   `Question ID: 42 / Tipe: multiple_choice / Jawaban saya: A` — nomor baris
   database dan satu huruf tanpa konteks. Siswa tidak punya cara tahu soalnya
   apa, padahal itu satu-satunya alasan membuka halaman itu.
4. ✅ **Halaman guru**: teks soal kini muncul di kartu penilaian esai (dulu hanya
   "Question ID", jadi penilaian dilakukan sambil menebak soalnya), plus panel
   "Review jawaban" berisi seluruh soal — yang sebelumnya tidak ada sama sekali;
   satu-satunya cara melihat jawaban objektif adalah mengunduh PDF.
5. ✅ Komponen React `question-answer-review.tsx` + gaya di `globals.css`.
   Penanda selalu berpasangan warna + teks: sebagian pengguna mencetak halaman
   ini hitam-putih, sebagian lagi tidak membedakan merah dari hijau.

**Kebocoran kunci ditutup di sisi data, bukan tampilan.** Saat `show_key` false,
kunci tidak ikut ke JSON sama sekali — bukan sekadar tidak digambar. Nilai yang
ada di respons bisa dibaca siapa pun yang membuka devtools.

**Tes**: `question_review_test.go` — 15 tes menutup kelima tipe, benar/salah/
tidak-dijawab, benar sebagian dengan 10 opsi (A–J), jawaban huruf kecil, kunci
tersembunyi saat `show_key` false, bacaan tanpa judul, dan tipe soal yang belum
dikenal (harus TIDAK dilabeli "Essay").

---

## Item 6 — Tanda "ragu-ragu" per soal  ✅ SELESAI (v1 + v2)

Penanda berdiri SENDIRI, tidak menggantikan status terisi/kosong: soal bisa
sudah dijawab DAN masih diragukan sekaligus, dan itu justru soal yang paling
ingin dikunjungi ulang siswa. Di v1 dibuat sebagai bingkai + bendera ⚑ di
sudut, bukan warna latar, supaya tidak menimpa hijau/merah yang sudah ada.

Disimpan ke `exam_results.flagged_questions`, ikut cadangan perangkat DAN
sinkron ke server — cadangan lokal hilang begitu siswa pindah komputer di
tengah ujian, justru saat penandanya paling dibutuhkan.

Ringkasan muncul SEBELUM mengumpulkan, menyebut nomor soalnya satu per satu.
"5 soal ditandai" saja memaksa siswa menutup dialog lalu mencarinya sendiri
di daftar nomor — tepat pada saat waktunya paling sedikit.

**Jebakan yang tertangkap saat mengerjakan (v1):** penanda sempat dititipkan
ke `pendingChanges`, padahal isi variabel itu menjadi `delta_answers` yang
dikunci per `question_id` — server akan menyimpannya sebagai jawaban untuk
soal ber-id `"flagged_questions"`. Dipindah jadi field tersendiri.

**Ketiadaan field dibedakan dari daftar kosong** (`has()` di v1, `*[]int` di
v2). Klien lama tidak mengirim field ini sama sekali; menafsirkannya sebagai
daftar kosong akan MENGHAPUS penanda siswa pada denyut pertama setelah ia
menutup lalu membuka lagi tabnya.

### Rincian rencana awal

**Temuan**: tidak ada di v1 maupun v2. Navigasi soal di v2
(`exam-workspace.tsx`) hanya membedakan sudah/belum dijawab.

### Rencana (v1 & v2 identik)

- Tombol **"Ragu-ragu"** di tiap soal saat siswa mengerjakan.
- Di daftar nomor soal, soal ragu-ragu diberi warna/ikon ketiga — berbeda dari
  "belum dijawab" dan "sudah dijawab". **Soal bisa sudah dijawab DAN ragu-ragu
  sekaligus**; keduanya harus terlihat bersamaan, bukan saling menimpa.
- Disimpan ikut autosave supaya bertahan saat halaman dimuat ulang atau siswa
  pindah perangkat.
- Ringkasan sebelum submit: "3 soal belum dijawab, 5 ditandai ragu-ragu".

**Skema:**

```
exam_results.flagged_questions JSON NULL   -- [12, 15, 23]
```

Kolom JSON di `exam_results`, bukan tabel baru: datanya hanya berarti selama
attempt itu, ikut terhapus/tersalin bersama attempt-nya, dan tidak pernah
di-query lintas baris.

**Catatan**: tanda ragu-ragu **tidak** ikut ke lembar jawaban guru. Itu catatan
pribadi siswa saat mengerjakan, bukan bagian dari penilaian.

---

## Item 7 — Waktu ujian berkoma, harus dibulatkan  ✅ SELESAI (v1 + v2)

### Temuan — terkonfirmasi, dan sebabnya jelas

`composer.lock` memakai **nesbot/carbon 3.10.2**. Di Carbon 3, `diffInMinutes()`
mengembalikan **float**, bukan integer seperti Carbon 2.

`StudentController.php:878` — `$timeTaken = $startedAt->diffInMinutes($completedAt);`
menghasilkan `12.983333`. Nilai itu dikirim apa adanya ke respons JSON
(`StudentController.php:988`) dan disimpan ke `time_taken`.

Titik lain yang terkena sebab yang sama:
- `StudentController.php:1389`, `:2240`
- `CompleteEndedExamResults.php:51`
- `AttemptManagementController.php:508` — dipakai untuk **menghitung sisa waktu**
  (`$examDurationSeconds - ($lastResult->time_taken * 60)`), jadi pecahannya ikut
  masuk ke perhitungan sisa waktu ujian yang sedang berjalan.

### Rencana v1

Bungkus semuanya: `(int) round($startedAt->diffInMinutes($completedAt))`.
Lalu **cari seluruh `diffIn*` di aplikasi** — bukan hanya `diffInMinutes` —
karena migrasi Carbon 2→3 mengubah semuanya sekaligus, dan yang belum ketahuan
hanya berarti belum ada yang melihat angkanya.

Tambahkan **cast eksplisit** `'time_taken' => 'integer'` di model `ExamResult`
sebagai jaring pengaman lapis kedua.

### Rencana v2

`TimeTaken` bertipe `int` di Go, jadi sumbernya aman. Yang perlu diperiksa adalah
**tampilannya**: cari pembagian yang menghasilkan pecahan di frontend
(mis. `detik / 60` tanpa `Math.floor`). `formatRemaining()` di
`exam-workspace.tsx:70` sudah benar; halaman hasil dan rekap belum diperiksa.

---

## Item 8 — Kamera default tidak wajib, bisa dicentang per ujian  ✅ SELESAI (v1 + v2)

**Temuan**: v2 `use-proctoring.ts:372` memanggil `acquireCamera()` tanpa syarat.
v1 serupa di `take.blade.php`. Tidak ada kolom pengaturan.

**Skema:**

```
exams.require_camera BOOLEAN NOT NULL DEFAULT 0
```

Default `0` — sesuai permintaan. **Untuk ujian yang sudah ada, ini berarti
perubahan perilaku**: ujian yang sebelumnya memaksa kamera akan berhenti
memaksanya setelah migrasi. Itu memang yang diminta, tetapi perlu disebut
terang-terangan supaya tidak jadi kejutan di hari ujian.

**Rencana (v1 & v2):**
- Checkbox "Wajib kamera" di form buat/ubah ujian, default mati.
- Saat mati: kamera **tidak diminta sama sekali** — bukan diminta lalu diabaikan.
  Meminta izin kamera yang tidak dipakai melatih siswa menekan "Allow" tanpa
  membaca, dan itu kebiasaan yang merugikan mereka di tempat lain.
- Saat mati, pelanggaran non-kamera (pindah tab, dll) **tetap** dicatat.

---

## Item 9 — Login dengan scan kartu siswa  ✅ SELESAI (v1 + v2)

**Temuan**: `users.qr` sudah ada (`User.php:44`), diisi saat kartu dicetak
(`AbsensiController.php:555` — `$user->id . Str::random(150)`). Sudah dipakai
untuk absensi (`AbsensiController.php:55`), **belum** untuk login.

### Rencana (v1 & v2)

- Tombol **"Scan kartu"** di halaman login, membuka kamera, membaca QR, lalu
  mengirimnya ke `POST /login/qr`.
- Server mencari `users.qr`, lalu membuat sesi seperti login biasa.

**Yang harus ada, dan alasannya:**

1. **Throttle sama ketatnya dengan login password.** QR ini adalah kredensial
   yang setara password. v2 sudah punya `login_throttle.go`; jalur QR harus
   memakainya juga, bukan jalur pintas tanpa pembatas.
2. **Bandingkan dengan `hash_equals`**, bukan `==`. Perbandingan string biasa
   bocor lewat waktu eksekusi.
3. **Bisa dimatikan per sekolah.** Sekolah yang kartunya mudah difoto orang lain
   perlu cara menolak jalur ini: `schools.allow_qr_login BOOLEAN DEFAULT 0`.
4. **Bisa dicabut.** Kartu hilang harus bisa dibatalkan — cetak ulang sudah
   mengganti `users.qr`, tetapi harus ada tombol "cabut kartu" tanpa harus
   mencetak.
5. QR memuat 150 karakter acak — cukup kuat. **Jangan** diganti jadi NISN;
   NISN bisa ditebak.

### Status — SELESAI

**v1** — migrasi `2026_08_27_000004`, `QrLoginService`,
`AuthController::loginByQr` (`POST /login/qr`, `throttle:10,1`),
`StudentCardController` (cabut / terbitkan ulang), tombol scan kamera di
halaman login, saklar di Data Sekolah, kolom status kartu di Data Siswa.

**v2** — `qr_login.go` (resolusi + login + kelola kartu),
`POST /api/auth/login-qr` memakai `loginGuard` yang SAMA dengan login password,
`allow_qr_login` masuk `schoolEditableColumns`, isian kartu di halaman login,
saklar di halaman Sekolah, tombol kartu di halaman Siswa.

### Keputusan yang membentuk perilakunya

- **`allow_qr_login` bawaannya MATI.** Kartu siswa yang selama ini hanya untuk
  absensi sudah terlanjur difotokopi, difoto, dan ditinggal di meja. Menyalakan
  login QR secara otomatis berarti mengubah seluruh kartu itu menjadi password
  — tanpa satu pun sekolah menyetujuinya. Sekolah yang menginginkannya
  menyalakan sendiri, dan halamannya menjelaskan akibatnya sebelum ia diklik.
- **Hanya peran siswa.** Kartu guru/admin memegang akses jauh lebih luas, dan
  kartu fisik terlalu mudah difoto untuk menjaga akses sebesar itu.
- **Pesan galat seragam** untuk semua sebab kegagalan; sebabnya hanya masuk log.
  Membedakan "kartu tidak dikenal" dari "sekolah mematikan login QR" memberi
  tahu penyerang kapan ia menebak nilai yang benar-benar ada.
- **Cabut dipisah dari cetak ulang.** Sebelumnya satu-satunya cara menonaktifkan
  kartu hilang adalah mencetak kartu baru — sekolah harus punya printer, bahan,
  dan waktu, sebelum kartu itu berhenti berlaku. Untuk absensi masih bisa
  ditunggu; untuk kredensial login tidak. Nilai `qr` sengaja TIDAK dihapus saat
  dicabut: riwayat absensi lama menunjuk ke sana.
- **`qr_last_login_at`** dicatat. Tanpanya, kartu yang dicuri tidak meninggalkan
  jejak apa pun — tidak ada cara tahu ia sedang dipakai orang lain.

### Empat masalah nyata ditemukan dan ditutup

1. **`users.qr` TEXT tanpa index sama sekali.** Untuk absensi masih termaafkan;
   untuk login berarti tiap pemindaian memindai seluruh tabel users lintas
   sekolah — dan siapa pun yang mengirim tebakan berulang mendapat penggilingan
   CPU gratis. Diubah ke `VARCHAR(191)` + index di kedua versi.
2. **"Throttle setara login password" ternyata berarti NOL di v1** — rute
   `POST /login` v1 tidak punya throttle sama sekali. Jalur QR dipasangi
   `throttle:10,1`; celah pada login password **dilaporkan, tidak diam-diam
   diubah** (di luar cakupan item ini). v2 sudah punya `loginGuard` yang benar
   dan jalur QR memakainya kembali, bukan membuat penjaga baru yang lebih
   longgar.
3. **Nilai QR ikut terserialisasi ke klien di v2.** `handleListStudents`
   mengembalikan `User` utuh, jadi satu halaman admin membawa kredensial masuk
   untuk SELURUH sekolah ke cache browser, log proxy, dan jangkauan XSS mana pun
   di halaman itu. Diubah ke `json:"-"` + `has_qr` yang dihitung di `AfterFind`
   (satu tempat, bukan per-handler yang bisa lupa). v1 disamakan lewat
   `$hidden` — terverifikasi: akses properti tetap jalan, `toArray`/`toJson`
   tidak lagi membawanya.
4. **Kartu v2 mencetak token sebagai TEKS TERBACA**, bukan gambar QR. Untuk
   penanda absensi masih lewat; sebagai kredensial, teks bisa disalin dari
   seberang ruangan atau dari foto beresolusi rendah. Diubah jadi gambar QR.

**Temuan sampingan lama ikut ditutup**: `htmlToImage()` di
`AbsensiController` mengirim seluruh HTML kartu ke `hcti.io` dan
`api.htmlcsstoimage.com`. Ternyata **nol call site** — kartu dirender lokal —
sehingga yang tersisa hanyalah jalan keluar data yang menunggu seseorang
menyalakannya kembali. Dihapus, alasannya ditinggalkan sebagai catatan.

### Perbedaan yang disengaja antara v1 dan v2

v1 memakai **kamera** (`html5-qrcode`), v2 memakai **isian teks** yang diisi
pemindai genggam. Bukan kelalaian: v1 sudah memuat pustaka pemindai di halaman
lain, sedangkan seluruh pemindaian v2 (mis. Peminjaman Buku) memang berbentuk
isian teks — menambahkan pustaka kamera ke v2 berarti dependensi baru hanya
untuk satu tombol.

**Diuji:** v1 lewat layanan + controller (11 kasus, DB dikembalikan dan
diverifikasi); v2 lewat router sungguhan (`TestQRLogin` 9 sub-uji +
`TestQRLoginThrottle`), termasuk penolakan kartu guru, keseragaman pesan galat,
kartu lama mati setelah terbit ulang, dan admin tidak bisa mencabut kartu siswa
sekolah lain.

**Satu kesalahan pembacaan saya sendiri diperbaiki di sini.** Uji v1 sempat
mencetak `qr + spasi -> OK` dan saya membacanya sebagai lulus. Ia memang
diterima — dan itu benar: `trim()` di awal membuat spasi dari pemindai tidak
menggagalkan kartu yang sama. Bahaya PAD SPACE yang sesungguhnya berbeda: input
bisa cocok dengan nilai tersimpan **milik siswa lain** yang hanya berbeda spasi.
Uji v2 kini menguji properti itu — dua siswa, nilai berbeda spasi, dan login
harus mendarat di pemilik yang benar.

---

## Item 10 — Kategori buku  ✅ SELESAI (v1 + v2)

**Temuan**: `books.category` adalah `string` bebas
(`2026_06_14_100002_create_books_table.php:24`). Tidak ada daftar pilihan, jadi
"Fiksi", "fiksi", dan "FIKSI" jadi tiga kategori berbeda.

**Skema — tabel baru (v1 & v2):**

```
book_categories
  id, school_id, name, slug, sort_order, created_at, updated_at
  UNIQUE(school_id, slug)

books.book_category_id BIGINT NULL   -- FK, nullable
```

Kolom `books.category` lama **dipertahankan** dan diisi otomatis dari relasi,
supaya laporan/ekspor yang membacanya tidak rusak. Dihapus nanti setelah terbukti
tidak ada yang memakainya.

**Migrasi data**: kategori yang sudah terlanjur diketik dikumpulkan
(`SELECT DISTINCT category`), dinormalkan (trim + samakan huruf besar-kecil),
dijadikan baris `book_categories`, lalu `book_category_id` diisi. Yang tidak
cocok dibiarkan — tidak ditebak.

**Bawaan untuk sekolah baru**: Mata Pelajaran, Fiksi, Non-Fiksi, Ilmiah,
Referensi, Majalah/Jurnal. Bisa ditambah/diubah sekolah.

### "Lainnya" + teks bebas yang MENAMBAH daftarnya

Dropdown kategori punya pilihan terakhir **"Lainnya (tulis sendiri)"**. Saat
dipilih, muncul kolom teks bebas — dan apa yang diketik di sana **disimpan
sebagai kategori baru**, sehingga muncul di dropdown untuk buku berikutnya.

Daftarnya tumbuh sendiri dari pemakaian, bukan dari admin yang harus
membuka halaman pengaturan lebih dulu. Petugas yang sedang memasukkan buku
tidak perlu berhenti, pindah halaman, membuat kategori, lalu kembali.

**Yang menentukan apakah ini berguna atau berantakan: pencocokannya.**
Tanpa normalisasi, "Fiksi", "fiksi", " Fiksi ", dan "FIKSI" jadi EMPAT
kategori — persis masalah yang sedang diperbaiki, hanya berpindah tempat.
Karena itu:

- Pencocokan lewat **slug** (huruf kecil, spasi jadi strip, tanda baca
  dibuang), bukan lewat teks apa adanya.
- `UNIQUE(school_id, slug)` + `firstOrCreate` — dua petugas yang mengetik
  kategori sama pada saat bersamaan tetap menghasilkan satu baris.
- Nama yang **disimpan** adalah yang diketik pertama kali; yang kedua
  dicocokkan ke sana, tidak menimpanya.

**Yang tetap perlu ada**: halaman kelola kategori (ubah nama, gabung,
hapus). Daftar yang tumbuh otomatis pasti mengumpulkan salah ketik, dan
tanpa cara membereskannya, masalahnya cuma tertunda beberapa bulan.
Menghapus kategori TIDAK menghapus bukunya — bukunya kembali tanpa kategori.

### Status — SELESAI kecuali halaman kelola kategori

**v1** — `BookCategory` (model), migrasi `2026_08_27_000002`,
`LibraryController::resolveCategory()`, filter `index()` pindah ke
`book_category_id`, form `scan-add` jadi dropdown + "Lainnya",
`AuthController` menyemai bawaan untuk sekolah baru.

**v2** — `book_category.go` (model + `slugifyCategory` + backfill sekali-jalan
bertanda `app_settings`), `Book.BookCategoryID`, `resolveBookCategory()`,
filter dan daftar kategori pindah ke tabel, form React dapat dropdown +
"Lainnya", `auth_admin.go` menyemai bawaan untuk sekolah baru.

**Yang diuji, bukan sekadar dijalankan:**

| Diuji | Hasil |
|---|---|
| Migrasi v1 atas `exam_v1` | "Fiksi"/"fiksi"/" FIKSI " → 1 baris, 3 buku; "Non Fiksi"/"non-fiksi" → 1 baris, 2 buku |
| Simpan buku v1 lewat controller (6 kasus, lalu dikembalikan) | teks bebas menang atas dropdown; ejaan lain tidak menambah baris dan tidak menimpa nama; id sekolah lain ditolak |
| `filter #1` di `index()` v1 | 3 buku — filter teks lama tidak akan pernah menemukan ketiganya |
| Render `library/index` + `scan-add` v1 | OK; `category_id`, `__other__`, `category_new` ada di HTML |
| `go test` v2 (4 uji, MySQL sungguhan) | slug sama dengan `Str::slug` v1 untuk keenam bawaan; resolusi 8 kasus; backfill + penjaga sekali-jalan |

Dua hal yang ditemukan sambil jalan dan ikut diperbaiki:

1. **Keadaan awal uji backfill v2 tidak realistis.** Saya memaksa
   `book_category_id = 999` ke *semua* buku, termasuk yang tak berkategori —
   padahal sebelum backfill kolomnya baru dibuat dan pasti NULL. Paksaannya
   dipersempit ke baris yang memang harus tersentuh.
2. **Bug lama v1**: `LibraryController::store()` membaca `$data['isbn']` tanpa
   `??`, padahal `validate()` hanya mengembalikan kunci yang dikirim. Form web
   selalu mengirimnya (string kosong) sehingga tak pernah terlihat; klien API
   yang menghilangkan field `nullable` itu kena "Undefined array key".

### Halaman kelola kategori — SELESAI

**v1** — `BookCategoryController` (index/store/update/merge/destroy), view
`admin/library/categories.blade.php`, 5 rute, menu sidebar.
**v2** — `book_category_admin.go` (5 handler), 5 rute, halaman
`admin/library/categories/page.tsx`, menu sidebar.

Keputusan yang membentuk perilakunya:

- **Ubah nama yang menabrak slug kategori lain DITOLAK**, tidak digabung
  diam-diam. Menggabung tidak bisa dibatalkan; itu keputusan yang diambil
  sengaja lewat tombol Gabung, bukan efek samping ketikan.
- **Menghapus tidak menghapus bukunya** — bukunya kembali tanpa kategori.
  Keadaan yang bisa diperbaiki; buku yang hilang tidak. Kolom teks lamanya ikut
  dikosongkan supaya tidak ada buku yang tampil berkategori padahal
  kategorinya sudah tidak ada.
- **Jumlah buku disebut di konfirmasi gabung/hapus dan di pesan hasilnya**,
  bukan hanya nama kategorinya — petugas yang salah pilih tahu seberapa besar
  akibatnya.
- **Ubah nama ikut menyamakan `books.category`**; laporan dan ekspor yang masih
  membaca kolom teks itu harus melihat nama yang sama dengan yang di layar.
- **Pesan "ditambahkan" dibedakan dari "sudah ada nama serupa"** — dua hasil
  yang terlihat sama di layar.

Diuji: v1 lewat controller sungguhan (8 langkah, DB dikembalikan dan
diverifikasi sama persis), v2 lewat router sungguhan (`TestBookCategoryAdminAPI`,
9 sub-uji termasuk penolakan gabung ke kategori sekolah lain).

---

## Item 11 — Dua eligibilitas yang berdiri sendiri  ✅ SELESAI (v1 + v2)

### Yang diminta

Bukan sekadar memisahkan nilai dari lembar jawaban, melainkan membuat keduanya
**dua saklar yang benar-benar terpisah**, sehingga keempat kombinasinya sah:

| | Lembar jawaban & soal boleh dilihat | Tidak boleh |
|---|---|---|
| **Nilai boleh dilihat** | keduanya terbuka *(bawaan)* | nilai saja — cocok untuk ujian yang soalnya dipakai lagi |
| **Nilai tidak boleh** | lembar jawaban saja — pembahasan tanpa membuka peringkat | keduanya tertutup |

Kolom ketiga dan keempat itulah yang tidak mungkin dilakukan sekarang: satu flag
`exams.show_results` mengatur dua hal sekaligus, jadi mematikan salah satu
otomatis mematikan yang lain.

### Temuan

`PublicProgressController.php:173` dan `:217` — nilai hanya ikut dihitung bila
`$exam->show_results` menyala. Halaman `public/progress/exam-detail.blade.php`
juga menggerbangkan **soal dan jawabannya** dengan flag yang sama.

Di v2 gerbangnya ada di `handleStudentResult` (`exam_task_attendance.go`), dan
lembar jawaban PDF siswa malah **mengunci `includeAnswerKey = false` secara
harfiah** — siswa tidak pernah bisa mendapat kunci, apa pun pengaturannya.

### Skema — TIGA saklar, bukan dua

```
exams.show_score        BOOLEAN NOT NULL DEFAULT 1   -- nilai terlihat
exams.show_questions    BOOLEAN NOT NULL DEFAULT 1   -- soal + jawaban terbaca di layar
exams.show_answer_sheet BOOLEAN NOT NULL DEFAULT 1   -- lembar jawaban bisa DIUNDUH (PDF)
```

Membaca pembahasan di layar dan mengunduh berkasnya adalah dua hal yang berbeda.
Berkas PDF keluar dari sistem: ia bisa disebar ke grup, disimpan, dan dipakai
lagi tahun depan. Guru yang mau siswanya membaca pembahasan tetapi tidak mau
soalnya beredar sekarang punya cara mengatakannya.

Ketiganya berdiri sendiri, jadi kombinasinya delapan — dan semuanya sah.

### Migrasi ujian LAMA

Diputuskan: **nilai dan soal dibuka untuk semua**, hanya unduhan PDF yang
mewarisi pengaturan lama.

```sql
show_score        = 1              -- semua ujian lama, nilainya dibuka
show_questions    = 1              -- semua ujian lama, soalnya boleh dibaca
show_answer_sheet = show_results   -- hanya ini yang mewarisi
```

**Konsekuensinya perlu disadari, bukan ditemukan belakangan.** Ujian yang dulu
gurunya matikan "Tampilkan Hasil" akan langsung terbuka nilai dan soalnya —
termasuk lewat cek progress dengan NISN, tanpa login. Kalau ternyata
mengagetkan, mengembalikannya satu perintah:

```sql
UPDATE exams SET show_score = show_results, show_questions = show_results
WHERE created_at < '<tanggal migrasi>';
```

`show_results` **sengaja dipertahankan** sebagai kolom bayangan justru supaya
perintah pembatal di atas masih punya sumber datanya. Jangan dihapus sebelum
beberapa minggu berjalan tanpa keluhan.

### Rencana (v1 & v2)

- Tiga checkbox terpisah di form ujian, dengan keterangan bedanya — bukan satu
  dropdown berisi delapan pilihan. Saklar yang berdiri sendiri harus terlihat
  berdiri sendiri.
- **Nilai** (`show_score`) mengatur: skor di rekap siswa, di daftar hasil, dan di
  cek progress lewat NISN.
- **Lihat soal** (`show_questions`) mengatur: review jawaban di layar (halaman
  hasil siswa) dan halaman detail ujian di cek progress.
- **Unduh lembar jawaban** (`show_answer_sheet`) mengatur tombol unduh PDF saja.
  Ia **tidak menyalakan** `show_questions`: mengunduh berkas tanpa boleh membaca
  layarnya memang aneh, tetapi menebak-nebak hubungan antar saklar justru membuat
  form-nya tidak bisa diprediksi. Kalau kombinasinya janggal, yang memberi tahu
  adalah keterangan di form, bukan perilaku diam-diam.
- Tombol yang tidak eligible **disembunyikan**, bukan ditampilkan lalu ditolak.
  Tombol yang selalu gagal mengajari orang mengabaikan pesan error.
- **Gerbangnya di sisi data, bukan tampilan.** Sama seperti yang sudah dikerjakan
  di item 5: bila tidak eligible, kunci dan soal tidak ikut ke respons sama
  sekali. Menyembunyikannya di komponen berarti siapa pun yang membuka devtools
  tetap bisa membacanya.
- v2: cabut `includeAnswerKey = false` yang di-hardcode di
  `handleStudentExamResultAnswerSheetPDF`, ganti mengikuti `show_answer_sheet`.

---

## Item 12 — Auto-submit saat kecurangan bisa dimatikan  ✅ SELESAI (v1 + v2)

**Temuan v1**: `public/js/exam-security-monitor.js` memanggil `autoSubmitExam()`
pada **enam** pelanggaran berbeda (baris 77, 88, 100, 106, 125, 136) — keluar
fullscreen, pindah tab, ubah ukuran window, ubah resolusi layar, shortcut
terlarang, mouse keluar area. Tidak ada cara mematikannya.

Beberapa di antaranya rawan positif palsu: **ubah resolusi layar** dan **mouse
keluar area** bisa terjadi karena laptop disambungkan ke proyektor atau siswa
menggeser kursor tanpa sadar. Ujian yang tersubmit paksa karena itu tidak bisa
dibatalkan.

**Skema:**

```
exams.auto_submit_on_cheating BOOLEAN NOT NULL DEFAULT 1
```

Default `1` — sesuai permintaan, perilaku sekarang dipertahankan.

**Rencana (v1 & v2):**
- Checkbox "Submit otomatis saat terdeteksi kecurangan", default menyala.
- Saat dimatikan: pelanggaran **tetap dicatat** ke `cheating_note` dan snapshot
  proctor tetap diambil. Yang berubah hanya: ujian tidak diakhiri paksa. Guru
  memutuskan sendiri saat memeriksa.
- Saat dimatikan, siswa tetap diberi peringatan di layar — supaya pelanggaran
  tidak berlanjut tanpa sadar.

---

## Urutan pengerjaan

Disusun agar yang **merusak data atau menyesatkan** selesai lebih dulu, dan agar
perubahan skema dikelompokkan supaya tidak ada migrasi beruntun di hari berbeda.

### Fase 1 — Bug yang salah menampilkan/menghitung (tanpa perubahan skema)

1. **Item 7** — pembulatan waktu (v1). Kecil, dampaknya di banyak layar.
2. **Item 2** — QR buku (v1: lock + API v5 + helper bersama; v2: download PDF).
3. **Item 5** — highlight jawaban untuk 3 tipe soal + komponen bersama (v1 & v2).

Ketiganya adalah hal yang **sekarang menampilkan angka atau jawaban yang salah**.

### Fase 2 — Pengaturan ujian (satu migrasi, enam kolom)  🔄 SKEMA SELESAI

**Sudah:** migrasi v1 (`2026_08_27_000001_add_exam_settings_and_flagged_questions.php`),
struct + AutoMigrate v2, backfill sekali-jalan v2 (`backfill_phase2.go`) berikut
penjaganya, dan kolom di model kedua versi. Nama kolom sudah dicocokkan
satu per satu antara v1 dan v2.

**Terverifikasi terhadap MySQL sungguhan** (bukan hanya kompilasi):
migrasi v1 dijalankan pada salinan `exam_admin_system`, hasilnya persis —
`show_score`/`show_questions` = 1 untuk semua, `show_answer_sheet` mewarisi
`show_results` (ujian tertutup tetap 0). Rollback juga diuji dan bersih.
Backfill v2 diuji terhadap MySQL: 2 ujian diperbarui, jalanan kedua dilewati.

**Sudah disambungkan (v2):** `require_camera` dan `auto_submit_on_cheating`
ke `use-proctoring.ts` + `exam-workspace.tsx`.

**Form ujian SELESAI (v1 + v2)** — 5 checkbox, keduanya terverifikasi
menyimpan dengan benar terhadap MySQL sungguhan.

**Jebakan GORM yang ditemukan saat menguji (v2).** `handleCreateExam`
memakai `DB.Create(&payload)`, dan DUA perilaku GORM bekerja sama merusak:

1. Field bernilai zero (`false`) yang punya tag `default:...` DIHILANGKAN
   dari INSERT — MySQL memakai bawaan kolom, yang TRUE untuk empat dari lima.
2. Sesudah INSERT, GORM MENIMPA struct-nya dengan bawaan itu, sehingga
   membacanya kembali dari payload juga memberi nilai yang salah.

Akibatnya guru yang mematikan auto-submit atau menutup nilai mendapatkan
ujian yang saklarnya tetap menyala — form tersimpan tanpa error, daftar
menampilkannya, dan baru ketahuan saat ujian berjalan.

Diperbaiki dengan overlay `*bool` (`examFlagOverrides`): body diurai dua
kali supaya "tidak dikirim" bisa dibedakan dari "dikirim false". Tanpa
pembedaan itu, klien lama yang tidak tahu kolom baru akan diam-diam
mematikan semuanya, termasuk auto-submit kecurangan.

**Item 8 & 12 SELESAI (v1 + v2).**

Di v1 jalurnya ternyata BUKAN `exam-security-monitor.js` — berkas itu hanya
dimuat di halaman daftar ujian, bukan halaman mengerjakan. Corong yang
sebenarnya adalah `handleCheatingDetection()` di `take.blade.php`.

Saat auto-submit dimatikan, input yang tadi dikunci **dibuka kembali**.
Tanpa itu siswa terjebak: ujian tidak diakhiri, tetapi ia juga tidak bisa
mengetik apa pun — jauh lebih buruk daripada dua-duanya.

**Nilai hilang jatuh ke arah AMAN.** `(bool) null` = false, sehingga ujian
lama atau query dengan `select()` tanpa kolom itu akan MEMATIKAN auto-submit
diam-diam. Karena itu dipakai `?? true` untuk auto-submit dan `?? false`
untuk kamera — arah amannya berlawanan, jadi tidak bisa diseragamkan.

**Gerbang eligibilitas v1 SELESAI** — 15 titik di 8 berkas, tidak ada lagi
yang menggerbangi dengan `show_results`. Diuji terhadap MySQL: kelima
kombinasi + model yang dimuat `select()` tanpa kolomnya + ujian terhapus.

Dua perbaikan yang muncul saat mengerjakannya:

- **Tombol "Lihat Detail" di daftar hasil** dulu hilang total saat flag mati,
  sehingga siswa yang hanya ingin melihat nilainya tidak punya jalan masuk —
  persis keluhan aslinya. Sekarang halaman detail terbuka bila SALAH SATU
  dari nilai/soal boleh dilihat, dan labelnya menyesuaikan ("Lihat Nilai").
- **Dua rute unduh (`/pdf`, `/answer-sheet`) sebelumnya TANPA gerbang sama
  sekali.** Digerbangi di server, bukan cuma menyembunyikan tombol: alamatnya
  bisa ditebak dari id.

**Gerbang eligibilitas v2 SELESAI.** Empat titik:

- `handleStudentResult` — soal TIDAK dimuat sama sekali bila `show_questions`
  mati; nilai DIKOSONGKAN dari baris hasil bila `show_score` mati. Bukan
  disembunyikan di tampilan — siswa yang membuka devtools tidak boleh
  menemukannya di respons.
- `handleStudentExamResultAnswerSheetPDF` — `includeAnswerKey` yang dulu
  HARDCODE `false` dicabut, kini mengikuti `show_answer_sheet`.
- `handleStudentExamResultPDF` — mengikuti `show_score`.
- **`handlePublicProgressLookup` sebelumnya TANPA GERBANG SAMA SEKALI** —
  endpoint terbuka tanpa login (cukup NISN) yang mengirim skor tiap ujian
  apa pun pengaturan gurunya. Lebih longgar daripada v1. Kini nilainya
  dihilangkan dari respons bila tidak dibagikan, dan ujian yang sudah
  terhapus ikut tertutup.

**Belum:** tombol ragu-ragu (item 6).

### Penghalang yang ditemukan saat menguji  ✅ SUDAH DIPERBAIKI

`php artisan migrate` dari database KOSONG **gagal** di
`2025_01_16_000001_add_qr_to_users_table` — ia memakai `after('token')`
padahal kolom `token` baru dibuat migrasi bertanggal Oktober. Ini bug lama
yang sudah didokumentasikan di `server-setup/exam-v1/README.md` sebagai
alasan `MIGRATE=no` jadi bawaan, dan sampai sekarang belum diperbaiki.

Akibatnya: environment BARU mana pun (staging, mesin developer baru) tidak
bisa dibangun dari nol.

**Diperbaiki**: keempat berkas dipindah ke `2025_10_27_00000{1..4}`, setelah
kedua dependensinya (`create_schools_table` Agustus, `add_token_to_users_table`
Oktober). Urutan relatifnya dipertahankan, dan seluruh migrasi yang
bergantung padanya bertanggal 2026 sehingga tidak terganggu.

**Keempatnya juga diberi penjaga keberadaan** (`Schema::hasColumn` /
`hasTable`), dan itu WAJIB, bukan sekadar rapi: nama berkasnya berubah,
sedangkan database yang sudah berjalan mencatat nama LAMA di tabel
`migrations`. Laravel karena itu menganggap keempatnya "pending" dan
menjalankannya lagi — tanpa penjaga, `migrate` berikutnya di server
produksi akan GAGAL dengan "column already exists".

**Terbukti**: `php artisan migrate` pada database `exam_v1` yang benar-benar
kosong → **106 migrasi jalan, 0 tertunda, 51 tabel**.


4. **Item 8** — `require_camera`
5. **Item 12** — `auto_submit_on_cheating`
6. **Item 11** — `show_score` + `show_answer_sheet`, keduanya bawaan 1
7. **Item 6** — `flagged_questions` (ragu-ragu)

Digabung dalam **satu migrasi** untuk `exams` + `exam_results`. Empat migrasi
terpisah di tabel yang sama pada tabel produksi besar berarti empat kali kunci
tabel.

### Fase 3 — Perpustakaan (satu paket, saling bergantung)

8. **Item 10** — kategori buku (tabel + migrasi data)
9. **Item 3** — harga, denda, hilang, ganti+QR baru, kas masuk

Item 3 bergantung pada QR yang sudah diperbaiki di Fase 1 — buku pengganti harus
bisa dicetak QR-nya begitu dibuat.

### Fase 4 — Fitur baru berdiri sendiri

10. **Item 9** — login scan kartu siswa
11. **Item 1** — uji beban (v1 baru, v2 UI + verifikasi)

### Fase 5 — Tampilan

12. **Item 4** — audit v2 vs v1 halaman per halaman, lalu perbaikan bertahap

Terakhir dengan sengaja: memperbaiki tampilan halaman yang isinya masih berubah
di Fase 2-4 berarti mengerjakannya dua kali.

---

## Yang perlu diputuskan sebelum mulai

1. **Item 4** — halaman v2 mana yang paling mengganggu? Itu yang dikerjakan
   duluan di Fase 5.
2. **Item 8** — kamera jadi tidak wajib untuk **ujian yang sudah ada** juga.
   Kalau ada ujian terjadwal yang mengandalkan kamera, sebutkan; migrasinya bisa
   dibuat menyalakan `require_camera` untuk ujian yang belum berjalan.
3. **Item 3e** — kas perpustakaan: perlu terhubung ke pembukuan lain, atau
   berdiri sendiri? Rencana sekarang berdiri sendiri.
4. **Urutan v1 vs v2** — dikerjakan berpasangan per item (v1 lalu v2 langsung),
   atau selesaikan v1 dulu seluruhnya baru v2? Rencana ini menganggap
   **berpasangan**, supaya keduanya tidak pernah berbeda lama.

---

# Permintaan lanjutan (item 13–17)

Ditambahkan 2026-08-27 atas permintaan berikutnya. **Belum dikerjakan.**

## Item 13 — Cek progress non-login: filter semester & lintas semester  ✅ SELESAI (v1 + v2)

**Temuan — asumsi awalnya keliru, dan itu penting.** Cek-progress **sudah**
menampilkan SELURUH semester, bukan satu. `PublicProgressController::report()`
menarik semua penugasan ujian dan tugas tanpa satu pun filter tanggal/semester
(baris 105–140), mengelompokkannya per (tahun ajaran + semester) lewat
`resolvePeriod()`, dan view-nya merender tiap periode menurun
(`report.blade.php:105` — "Riwayat per semester (descending)"). Kelas per tahun
ajaran pun sudah benar: diambil dari `StudentEnrollment`, bukan dari
`users.class_id` yang berjalan saat naik kelas.

**Yang benar-benar belum ada** karena itu bukan "akses semua semester",
melainkan **kendali atas tampilannya**:

- Dropdown pilih semester / tahun ajaran, plus "Semua".
- Halaman yang panjang untuk siswa kelas 6 dengan 6 tahun riwayat — perlu
  ringkasan di atas dan periode lama yang tertutup secara bawaan.
- Filter mapel di dalam periode.

### Hasil pengerjaan (item 13)

**v1** — filter periode + mapel pada `PublicProgressController::report()`,
dengan dropdown di `report.blade.php`. Daftar pilihan dibuat dari periode yang
BENAR-BENAR ADA; filter yang menunjuk periode tak dikenal jatuh ke "semua",
bukan halaman kosong.

**Ringkasan MENGIKUTI filter.** Awalnya `$stats` saya sesuaikan tetapi
`$subjectSummary` tidak — sehingga "2 ujian" di atas berdiri di sebelah
rata-rata yang berasal dari 4 ujian. Itu persis kontradiksi yang membuat orang
berhenti mempercayai angkanya, jadi rata-rata per mapel kini dihitung ulang dari
periode yang tersaring. Diverifikasi: pada kelima kombinasi filter, jumlah ujian
di ringkasan mapel **sama persis** dengan `exam_done`.

**v2 — dibangun, bukan sekadar difilter.** Ternyata cek-progress v2 sama sekali
tidak punya pengelompokan periode: ia mengembalikan daftar DATAR maksimum 200
ujian tanpa penanda waktu. Untuk siswa dengan riwayat panjang, 200 baris teratas
memotong sebagian riwayatnya **tanpa satu pun tanda bahwa ada yang hilang**.
Ditambahkan `public_progress_period.go` (padanan `resolvePeriod` v1), tiap baris
ujian kini membawa periode + kelas pada tahun ajaran itu, dan responsnya memuat
daftar seluruh semester milik siswa.

Semester yang **didefinisikan sekolah menang** atas perhitungan bawaan: sekolah
yang semester genapnya mulai Februari punya alasannya sendiri. Perbandingannya
pada level HARI — tanpa itu ujian di hari terakhir semester terlempar ke periode
berikutnya.

**Diuji:** v1 lima kombinasi filter lewat controller sungguhan + render
(rollback, DB kembali persis); v2 empat uji unit termasuk batas Februari, hari
terakhir semester, urutan periode menurun, dan kelas historis per tahun ajaran.

---

## Item 14 — Rekap tugas siswa + filter semester / mapel / kelas  ✅ SELESAI (v1 + v2)

Di akun siswa: rekapan tugas dengan tiga filter yang bisa digabung —
**semester, mata pelajaran, dan kelas**. Filter kelas ada gunanya justru karena
naik kelas: siswa harus bisa melihat riwayat tugasnya sewaktu di kelas
sebelumnya.

Bergantung pada item 15: tanpa kelas historis yang benar, filter kelas hanya
akan mengelompokkan semuanya ke kelas siswa yang SEKARANG.

### Halaman terpisah, bukan filter yang ditumpuk di daftar tugas

Daftar tugas menjawab "apa yang harus saya kerjakan" dan berorientasi hari ini;
rekap menjawab "apa saja yang sudah saya kerjakan selama ini". Menggabung
keduanya membuat halaman yang dipakai tiap hari jadi berat sekaligus rekap yang
setengah hati. Jadi: halaman **Rekap Tugas** sendiri, dengan tautan dari daftar
tugas dan dari menu samping.

Kelas diambil dari `school_tasks.class_id` — kelas tempat tugas itu DIBERIKAN,
bukan kelas siswa hari ini. Keduanya berbeda begitu siswa naik kelas, dan untuk
rekap yang benar adalah yang pertama.

Semester memakai `AcademicYear::periodFor()` (v1) / `resolveProgressPeriod()`
(v2) — **definisi yang sama persis dengan cek-progress**. Di v1 aturannya masih
tertanam sebagai method privat di `PublicProgressController`; ia dipindah ke
helper lebih dulu, lalu controller-nya mendelegasi. Kalau tidak, sekolah yang
menggeser tanggal semesternya akan melihat dua halaman menyebut semester yang
berbeda untuk tugas yang sama.

Tahun ajaran diambil dari kolom `academic_year` bila terisi, bukan dari
`created_at` — kolom itulah acuan di seluruh sistem, dan `created_at` bisa
meleset jauh untuk data hasil impor.

### Angka ringkasan mengikuti filter

Total/sudah/belum/rata-rata dihitung dari baris yang TERSARING. Kalau tidak,
"10 tugas" di atas dan 3 baris di bawah saling bertentangan, dan yang dipercaya
pengguna adalah angka besarnya. Rata-rata hanya dari tugas yang sudah dinilai,
dengan jumlahnya disebut — 90 dari satu tugas bukan hal yang sama dengan 90
dari dua puluh tugas.

Pilihan filter dibuat dari data yang benar-benar ada. Filter yang menunjuk
sesuatu yang tidak ada diperlakukan sebagai "semua", sehingga tautan lama tidak
berubah jadi halaman kosong tanpa penjelasan.

Tugas lama tidak punya mapel (`subject_id` NULL). Itu ditawarkan sebagai
pilihan tersendiri, **"Tanpa mapel"** — kalau tidak, tugas-tugas itu lenyap
begitu siswa menyentuh filter mapel.

### Dua cacat yang ikut ketemu di daftar tugas v1

Keduanya sudah ada sebelum item ini, dan keduanya terlihat karena ujinya
memakai data yang tidak rapi.

**Filter status dijalankan SETELAH paginasi.** Halaman diambil 15 baris dulu,
baru disaring pada koleksi hasilnya. Siswa dengan 15 tugas terkumpul di halaman
1 dan tugas yang belum dikerjakan di halaman 2 membuka filter "Belum Submit",
melihat halaman kosong, lalu menyimpulkan tidak ada yang perlu dikerjakan.
Penomoran halamannya pun salah karena dihitung sebelum saring. Dipindah ke SQL
(`whereExists` / `whereNotExists`).

**`JOIN` menggandakan tugas.** Satu tugas dengan lebih dari satu baris
penugasan aktif untuk siswa yang sama muncul berkali-kali di daftar dan ikut
menggelembungkan hitungan paginasi. Baris ganda begitu bisa lahir dari dua
admin yang menekan "assign" bersamaan (tidak ada unique index) atau dari data
hasil migrasi. Diganti `whereExists`, yang secara struktur tidak bisa
menggandakan. v2 memakai map id untuk alasan yang sama.

Ujinya yang menemukannya: sub-uji "penugasan ganda" awalnya GAGAL di v1 dengan
"sudah submit = 3, mau 2".

### Satu efek samping di menu v2

Menambahkan `/student/tasks/rekap` membuat "Tugas Sekolah" DAN "Rekap Tugas"
menyala bersamaan, karena penyorotan memakai pencocokan awalan. Diganti: yang
menyala adalah tautan yang paling spesifik cocok. Berlaku umum, jadi rute
bersarang berikutnya tidak mengulang masalah yang sama.

### Terverifikasi

**v1 — 44 pemeriksaan, seluruhnya lulus** (transaksi digulung balik; database
tidak berubah). Termasuk: Blade benar-benar ter-render dan memuat tugas kelas
lama; tugas siswa lain tidak bocor; pengelompokan tiga periode terbaru lebih
dulu; kelas periode lama = kelas SAAT ITU (7A), bukan kelas sekarang (8A);
tiap filter sendiri-sendiri dan digabung; kombinasi mustahil → 0 tugas, bukan
error; filter tak dikenal → kembali ke "semua".

**Regresi delegasi periode — 11 pemeriksaan, lulus.** `AcademicYear::periodFor`
dibandingkan baris demi baris dengan salinan aturan lama untuk 10 tanggal
(termasuk batas 1 Juli dan 30 Juni), dan halaman cek-progress masih ter-render.

**v2 — 10 sub-uji lewat router sungguhan, seluruhnya lulus.** Skenario identik
dengan v1. `npx next build` → "✓ Compiled successfully"; suite backend hijau
tiga kali berturut-turut.

---

## Item 15 — Kelas historis pada hasil ujian & tugas (naik kelas)  ✅ SELESAI (v1 + v2)

**Temuan — sebagian sudah benar, sebagian TIDAK, dan bedanya jelas.**

| Tempat | Kelas historis? |
|---|---|
| `exam_assignments.class_id` | ✅ ada — kelas saat ujian ditugaskan |
| `school_task_assignments.class_id` | ✅ ada — kelas saat tugas diberikan |
| `StudentEnrollment` | ✅ ada — kelas per tahun ajaran |
| Cek-progress (non-login) | ✅ memakai `StudentEnrollment` |
| **`exam_results`** | ❌ **tidak punya kolom kelas sama sekali** |
| **Rekap hasil ujian admin/guru** | ❌ membaca `user.classRoom` dan menyaring `user.class_id` (`ExamResultController:25, 54`) |

Artinya: begitu siswa naik kelas, **rekap hasil ujian admin/guru menampilkan dan
menyaring hasil LAMA memakai kelas BARU**. Ujian yang dikerjakan di kelas 5
muncul sebagai kelas 6, dan menyaring "kelas 5" tidak lagi menemukannya.

`AdminController::promotions()` mengubah `users.class_id` dan menulis
`StudentEnrollment` untuk tahun ajaran tujuan — jadi datanya ADA; yang kurang
adalah rekapnya tidak memakainya.

**Rencana**: alihkan rekap hasil ujian & tugas agar kelasnya berasal dari
`exam_assignments.class_id` / `school_task_assignments.class_id` (paling tepat —
kelas pada saat penugasan), dengan `StudentEnrollment` sebagai cadangan untuk
baris lama yang `class_id`-nya kosong. **Jangan** menambah kolom kelas ke
`exam_results` bila dua sumber itu sudah cukup: satu fakta di tiga tempat akan
berbeda pada akhirnya.

### Hasil pengerjaan (item 15 + 17a)

**Item 15** — `exam_results.class_id` (snapshot), diisi saat hasil dibuat dan
di-backfill berlapis: `exam_assignments.class_id` → `student_enrollments` per
tahun ajaran → NULL. **Tidak** menebak dari kelas sekarang; itu justru jawaban
salah untuk siswa yang sudah naik kelas. Filter dan tampilan rekap dialihkan ke
snapshot, dengan kelas sekarang hanya sebagai cadangan untuk baris NULL.

**Item 17a** — `school_tasks.academic_year`, di-backfill dari `created_at`
(tanggal pembuatan memang menentukan tahun ajarannya). Daftar tugas admin/guru
kini bawaannya **tahun berjalan**; riwayat angkatan sebelumnya tetap ada di
filter tahunnya atau "Semua".

Bulan mulai tahun ajaran dijadikan konstanta di kedua versi
(`AcademicYear::START_MONTH`, `academicYearStartMonth`) supaya backfill SQL
tidak menyalin aturan yang sama untuk keempat kalinya.

### Celah deploy yang ditemukan dan ditutup

`cmd/api/main.go` v2 menyatakan *"satu proses = semuanya … tidak perlu
menjalankan cmd/migrate terpisah lagi"*, **tetapi ia tidak memanggil satu pun
backfill** — hanya `Bootstrap()`, yang isinya cuma enrollment + slug. Deploy
yang mengikuti pernyataan itu akan mendapat kolom baru dari AutoMigrate dengan
isi KOSONG: eligibilitas terbuka semua, kategori buku kosong, kelas hasil ujian
hilang, tahun ajaran tugas kosong. Keempat backfill dipindah ke `Bootstrap()`;
semuanya berpenanda `app_settings` sehingga aman dipanggil dari dua tempat.

### Diuji

| Diuji | Hasil |
|---|---|
| Backfill kelas, v1 & v2 (siswa 8A→9A, ujian per-kelas + individual) | keduanya terisi 8A, bukan 9A; nilai & status utuh |
| Rekap v1 lewat controller | menampilkan 8A; filter "8A" = 2 hasil, filter "9A" = 0 |
| **Alur ujian penuh v1** — mulai → autosave → heartbeat → submit | tanpa galat; `class_id` terisi di ketiga jalur `ExamResult::create`; nilai 20/30 poin benar |
| **Auto-submit saat kecurangan** | `recordCheatingEvent` → submit; status `completed`, nilai 10/30, `class_id` terisi |
| Attempt kedua (jalur create berbeda) | hasil baru dibuat, `class_id` terisi |
| Ruang tahunan v2 (8A dipakai ulang) | ruang tahun berjalan tidak membawa tugas angkatan lama; riwayat lama tetap terbuka lewat filter tahunnya; "Semua" menampilkan keduanya |

Satu ekspektasi keliru di uji saya sendiri diperbaiki: `exam_results.score`
menyimpan **poin**, bukan persen — persentasenya dihitung
`score/total_score*100` di `StudentController:960`. 20 dari 30 poin = 66,67%.
Kodenya benar; label ujinya yang rancu.

---

## Item 16 — Rekap tugas & ujian per kelas/mapel untuk admin & guru  ✅ SELESAI (v1 + v2)

Matriks seperti absensi: **daftar siswa ke bawah, tugas/ujian ke samping**,
tiap sel menunjukkan sudah mengumpulkan / belum / nilainya, dan bisa diklik ke
detailnya.

- Filter kelas, mapel, atau keduanya.
- **Entry point dari halaman Kelas dan dari halaman Mapel**, bukan hanya dari
  satu menu rekap.
- Sel bisa diklik → detail tugas maupun detail hasil ujian.

Bergantung pada item 15 untuk kolom kelasnya benar setelah naik kelas.

### Hasil pengerjaan v1 (item 16)

`Admin\RekapController` + tiga view: pilih kelas/mapel → **daftar tahun ajaran**
→ matriks → riwayat kelas siswa.

**Tahun ajaran adalah LANGKAH, bukan filter sampingan.** "Kelas 8A" bukan satu
kelompok, melainkan satu NAMA yang ditempati angkatan berbeda tiap tahun.
Membukanya tanpa menyebut tahun berarti bertanya sesuatu yang tidak punya
jawaban tunggal — dan menjawabnya dengan menggabungkan semua angkatan
menghasilkan matriks yang barisnya siswa dari beberapa angkatan dan kolomnya
tugas dari beberapa tahun. Daftar tahunnya menampilkan jumlah siswa/tugas/ujian
tiap tahun, dan tahun berjalan ditandai tetapi **tidak dipilihkan diam-diam**.

Baris matriks diambil dari `student_enrollments` (siswa yang menempati kelas itu
PADA tahun itu), bukan dari `users.class_id` yang berpindah saat naik kelas.

**Temuan: `school_tasks` tidak punya kaitan ke mapel sama sekali.** Ujian
mencapainya lewat `question_packages.subject_id`, tugas hanya punya `class_id` —
jadi "rekap tugas per mapel" mustahil, bukan sekadar belum dibuatkan halamannya.
Ditambahkan `school_tasks.subject_id` (nullable). **Tanpa backfill, dan itu
disengaja**: tidak ada sumber untuk menebak mapel tugas lama — judul tidak
menyebutnya dan guru pembuatnya bisa mengajar beberapa mapel. Tugas lama tampil
di kelompok "Tanpa mapel".

Dua keputusan tampilan yang diuji:
- Siswa yang **tidak ditugaskan** ditandai "—", bukan "belum mengumpulkan":
  menuntut sesuatu yang tidak pernah diberikan membuat rekap kehilangan
  kepercayaan.
- Ujian yang nilainya ditutup guru tetap menampilkan **ikon sudah mengerjakan**,
  hanya angkanya yang tidak — supaya "belum ikut" tidak tertukar dengan "nilai
  belum dibagikan".

**Satu kesalahan hitung ditemukan lewat uji dan diperbaiki**: riwayat siswa
mula-mula menghitung tugas dari tanggal PENGUMPULAN, sehingga tugas yang
dikumpulkan terlambat — setelah siswanya naik kelas — jatuh ke tahun berikutnya.
Kini dihitung dari tahun ajaran tugasnya.

**Diuji** dengan skenario 8A dua angkatan (Andi & Budi 2024/2025; Citra
2025/2026, Andi kini di 9A): daftar menawarkan dua tahun; matriks tiap tahun
berisi angkatan yang benar; riwayat Andi menunjukkan 8A→1 ujian 1 tugas dan
9A→kosong; guru tanpa penugasan yang menebak id kelas di URL **dialihkan**.
Seluruhnya dalam transaksi, DB dikembalikan.

### Port v2 — SELESAI

`rekap.go` (3 handler: daftar tahun, matriks, riwayat kelas siswa), 3 rute, dan
halaman `admin/rekap/page.tsx` dengan alur yang sama: pilih kelas/mapel →
**kartu tahun ajaran** → matriks → riwayat kelas siswa.

`SchoolTask.SubjectID` ditambahkan ke model v2 (padanan migrasi v1). Nilainya
NULL untuk tugas lama, dengan alasan yang sama: tidak ada sumber untuk menebak
mapelnya.

**Satu kesalahan hitung yang sama ditemukan lagi, dan diperbaiki di KEDUA
versi.** Riwayat kelas siswa menghitung ujian dari `created_at` — kapan BARIS-nya
dibuat. Untuk ujian yang berjalan normal keduanya berdekatan, tetapi untuk data
hasil impor atau migrasi ia bisa jauh meleset, dan hasil ujian tahun lalu
terhitung di tahun saat datanya dipindahkan. Kini
`COALESCE(completed_at, started_at, created_at)` di v1 dan v2.

**Uji yang goyah ditemukan dengan menjalankannya berulang.** Suite v2 lulus,
lalu gagal, lalu lulus lagi. Sebabnya bukan produk melainkan
`stress_teacher_test.go`: callback `do` dipanggil dari 16 goroutine sekaligus
dan menulis ke map tanpa pengunci, sehingga Go menghentikan seluruh proses
dengan `fatal error: concurrent map writes`. Ditambahkan mutex; lima jalan
berturut-turut hijau.

Satu aturan lint React juga ditegakkan: memuat daftar tahun dipindahkan dari
`useEffect` ke handler pemilihnya — memuatnya adalah respons atas aksi pengguna,
bukan sinkronisasi dengan sistem luar, dan `setState` sinkron di dalam effect
memicu render berantai.

**Diuji lewat router sungguhan** (`TestRekapMatrixPerTahunAjaran`, 7 sub-uji):
daftar menawarkan dua tahun dengan yang terbaru lebih dulu; matriks tiap tahun
berisi angkatan yang benar; sel membedakan "tidak ditugaskan" dari "belum
mengumpulkan"; matriks tanpa tahun ajaran ditolak 400; riwayat siswa menunjukkan
8A→1 ujian 1 tugas dan 9A→kosong; guru tanpa penugasan ditolak 403.

---

## Item 17a — Ruang kelas per tahun ajaran (FONDASI)  ✅ SELESAI (v1 + v2)

### Persoalannya

Nama kelas **dipakai ulang tiap tahun**: 8A tahun ini bukan 8A tahun lalu,
tetapi barisnya sama. Yang harus terjadi:

- Kohort 7A naik ke 8A → ruang 8A mereka **kosong**, tidak membawa satu pun
  tugas/materi kohort 8A tahun lalu.
- Kohort yang tahun lalu di 8A (sekarang 9A) → **tetap bisa membuka riwayat 8A
  mereka**.
- Admin **tetap** hanya mengelola 7A, 7B, 8A, 8B, 9A, 9B. Tidak ada kelas baru
  per tahun, tidak ada pekerjaan tambahan.

### Yang membuatnya bekerja

**Kunci ruang = `(class_id, academic_year)`, bukan `class_id` saja.**
Keanggotaannya diambil dari `student_enrollments`, **bukan** dari
`users.class_id` — kolom itu BERPINDAH saat naik kelas, dan apa pun yang
bersandar padanya akan ikut berpindah bersama siswanya.

Fondasinya **sudah ada**, tidak perlu dibangun:

| Sudah ada | Isinya |
|---|---|
| `student_enrollments` | `(school_id, user_id, class_id, class_name, grade, academic_year, status)` |
| `App\Helpers\AcademicYear` | tahun ajaran mulai Juli, mis. `2025/2026` |
| `AdminController::promotions()` | sudah menulis enrollment tahun tujuan saat naik kelas |

Jadi ruang tidak perlu tabel sendiri untuk keanggotaan: **anggota ruang
(8A, 2025/2026) = baris `student_enrollments` dengan pasangan itu.** Siswa yang
tinggal kelas dapat baris baru untuk tahun berikutnya, jadi ia masuk ruang baru
DAN tetap memegang akses baca ke ruang lamanya — tanpa aturan khusus.

### Aturan akses

| Ruang | Guru | Siswa |
|---|---|---|
| Tahun berjalan | baca + tulis | baca + kumpul tugas |
| Tahun lampau | baca saja | baca saja, **hanya bila ia anggota tahun itu** |

Arsip **read-only**, bukan disembunyikan: nilai dan tugas tahun lalu adalah
catatan, dan catatan yang bisa disunting setahun kemudian bukan catatan.

### MASALAH INI SUDAH AKTIF HARI INI

Bukan hanya urusan LMS nanti. Terverifikasi dengan membaca kodenya:

| Jalur | Keadaan |
|---|---|
| **Siswa melihat tugas** — `Student\TugasSekolahController:24` join ke `school_task_assignments` | ✅ **sudah benar**. Kohort baru tidak punya baris penugasan, jadi tugas tahun lalu tidak muncul. |
| **Admin/guru melihat tugas** — `Admin\TugasSekolahController:25–48` menyaring `school_tasks.class_id` saja | ❌ **BOCOR**. Tidak ada satu pun filter tahun ajaran. Daftar tugas kelas 8A menampilkan **seluruh tugas 8A dari semua angkatan**, tercampur, diurutkan tanggal. |

Artinya guru 8A tahun ini sudah melihat tugas kohort-kohort sebelumnya
bercampur dengan miliknya, dan itu bertambah parah tiap tahun.

**Skema yang kurang:**

```
school_tasks.academic_year   VARCHAR(20) NULL   -- diisi saat dibuat
tutor_assignments.academic_year VARCHAR(20) NULL -- guru 8A tahun mana
```

`school_tasks.academic_year` diisi mundur untuk baris lama dari
`created_at` lewat `AcademicYear::windowFor()` — bukan tebakan, karena tanggal
pembuatannya memang menentukan tahun ajarannya.

`tutor_assignments` tanpa tahun berarti guru yang berhenti mengajar 8A tetap
melihat 8A tahun ini. Untuk sekarang bisa ditunda (sekolah menugaskan ulang
manual), tetapi harus disebut agar tidak terlupa.

### Kenapa ini didahulukan

Item 14, 16, dan 17 semuanya menampilkan "tugas/ujian kelas X". Tanpa kunci
tahun ajaran, ketiganya akan menampilkan campuran angkatan — dan memperbaikinya
belakangan berarti membongkar tiga fitur sekaligus, bukan satu.

---

## Item 18 — Bulk edit siswa: template terisi + pratinjau perbedaan  ✅ SELESAI (v1 + v2)

Diminta menyela di tengah item 16. **Temuan:** bulk upload siswa tidak punya
kolom tanggal lahir sama sekali, dan bulk update hanya menerima nisn/name/gender
dengan template berisi **dua baris contoh fiktif** ("budi@example.com").

Untuk memperbaiki NISN 300 siswa, admin harus mengetik ulang 300 email dari
halaman lain — dan satu salah ketik email berarti barisnya ditolak tanpa ada
yang tahu siswa mana yang terlewat.

**Yang dikerjakan (v1):**

- Template bulk update kini **keluar sudah terisi seluruh siswa sekolah itu**,
  dengan kolom `email, nisn, name, gender, birth_date, class`.
- Template import (siswa baru) mendapat kolom `birth_date`. Wajib ada karena
  tanggal lahir dipakai memverifikasi orang tua di Cek Progres — siswa yang
  diimpor tanpa itu tidak akan pernah bisa dicek, dan baru ketahuan saat
  mereka mencoba.
- **Langkah pratinjau**: unggah → tabel "dari X jadi Y" per siswa per kolom →
  baru diterapkan. Nilai lamanya ditampilkan dicoret, karena perubahan yang
  tidak menunjukkan asalnya tidak bisa diperiksa — dan yang perlu diperiksa
  justru perubahan yang TIDAK disengaja.

**Tiga keputusan yang membentuk perilakunya:**

1. **Sel kosong = "biarkan", bukan "kosongkan".** Template keluar sudah terisi,
   jadi sel yang dikosongkan hampir selalu tidak sengaja — dan mengosongkan NISN
   300 siswa karena satu kolom terhapus adalah kerusakan yang tidak bisa
   dibatalkan dari layar itu.
2. **Email tidak bisa diubah** lewat berkas ini: ia kunci pencocokan, dan
   mengubahnya menghasilkan "siswa tidak ditemukan", bukan "email terganti".
3. **Kelas tidak dibuat otomatis.** Kelas yang lahir dari salah ketik akan
   menampung siswa dan baru ketahuan berbulan kemudian.

Perubahan kelas lewat bulk update **ikut menulis riwayat kelas** — tanpa itu
rekap per tahun ajaran tidak tahu siswa itu pindah, dan matriksnya menampilkan
angkatan yang salah.

**Satu bug saya sendiri, ditemukan uji:** `mapGender` saya mengembalikan `'L'`/
`'P'` padahal `users.gender` adalah `enum('male','female','other')` — MySQL
langsung menolak dengan "Data truncated for column 'gender'". Pemetaan lama di
`AdminController` sudah benar; punya saya yang salah.

**Diuji, enam pemeriksaan:** template terisi 3 siswa nyata; diff mendeteksi 2
berubah / 2 sama / 2 bermasalah dengan sebab yang tepat (email asing, kelas tak
dikenal); penerapan mengubah persis yang ditinjau dan **tidak menyentuh** siswa
yang barisnya apa adanya; perubahan kelas menulis riwayat; unggah ulang berkas
yang sama menghasilkan 0 perubahan; seluruh kolom dikosongkan menghasilkan 0
perubahan.

### Port v2 — SELESAI

`student_bulk_update.go` (diff + apply + `ensureEnrollmentForStudent`), template
`handleDownloadBulkUpdateTemplate` kini terisi data siswa dengan kolom
`birth_date` dan `class`, dan `handleBulkUpdateStudents` menjadi **pratinjau**;
`?apply=1` yang menerapkannya.

**Catatan email diperjelas di tiga tempat** atas permintaan: modal bulk update,
halaman pratinjau, dan pesan galatnya — semuanya menyebut bahwa email harus
diubah **satu per satu lewat halaman Data Siswa**.

**Satu jebakan zona waktu ditemukan lewat uji.** Tanggal lahir yang ditulis
dengan `time.Local` terbaca MUNDUR SEHARI dari kolom DATE: 2010-01-01 00:00 WIB
adalah 2009-12-31 17:00 UTC, dan kolom DATE menyimpan harinya saja. Akibatnya
setiap siswa tampak "berubah" pada pratinjau — persis derau yang seharusnya
dicegah pembanding itu.

Jalur produksi ternyata **aman**: ia memakai `time.Parse` (UTC) dan DSN-nya juga
tidak menyetel `loc`, jadi tulis dan baca konsisten. Yang salah adalah fixture
uji saya. `parseFlexibleDate` tetap disamakan ke UTC supaya jebakannya tidak
tertinggal untuk pemakai berikutnya.

**Satu kerusakan yang saya buat dan kompilator tangkap**: penulisan ulang handler
memotong sampai fungsi berikutnya, ikut menghapus tiga konstanta lampiran esai
(`essayAttachmentExt`, `maxEssayAttachmentBytes`, `maxEssayAttachmentsPerUpload`).
Dikembalikan persis seperti semula, dan `git diff` diperiksa untuk memastikan
tidak ada lagi yang hilang.

### Pertanyaan yang dijawab sambil jalan: riwayat kelas saat naik/edit kelas

Diverifikasi dengan menjalankan kedua jalurnya:

```
naik kelas   : 2024/2025 → 8A tetap utuh, 2025/2026 → 9A ditambahkan  ✅
edit manual  : 2024/2025 → 8A tetap utuh, tahun berjalan → 8B ditambahkan  ✅
```

Keduanya memakai `updateOrCreate` berkunci (siswa + tahun ajaran), sehingga tahun
sebelumnya tidak pernah tersentuh.

**Batasan yang perlu diketahui**: pindah kelas di TENGAH tahun menimpa kelas
tahun berjalan — bagian awal tahun itu hilang dari riwayat enrollment, karena
model itu hanya menyimpan satu kelas per tahun. `exam_results.class_id` menyimpan
snapshotnya sendiri, jadi rekap ujian tetap menunjukkan kelas yang benar saat
ujian dikerjakan.

---

---

## Temuan sampingan — Pembatas login  ✅ SELESAI (v1 + v2)

### v1 tidak punya pembatas sama sekali di login password

Login QR sudah dilindungi `throttle:10,1` di rutenya; login password tidak
punya apa pun. Ditambahkan pembatas yang menghitung **kegagalan**, dengan kunci
memuat **email + IP**.

Kuncinya harus memuat email, bukan IP saja: satu lab sekolah berada di balik
SATU IP publik, dan pembatas per-IP akan mengunci seisi kelas gara-gara satu
siswa yang salah ketik password lima kali — persis pada saat ujian dibuka.

Login berhasil mengosongkan hitungan. Aman KARENA kuncinya memuat email:
penyerang yang membereskan hitungan akunnya sendiri tidak mendapat apa pun
untuk menyerang akun orang lain.

### `throttle:10,1` di login QR v1 justru salah bentuk

Middleware itu menghitung SEMUA percobaan per IP. Satu stasiun pemindai di
gerbang sekolah melayani puluhan siswa dari satu IP — siswa ke-11 dalam semenit
ditolak, dengan pesan yang tidak menjelaskan apa pun.

Diganti pembatas kegagalan di controller. Hasilnya lebih ketat terhadap
penyerang (yang selalu gagal, jadi mencapai batas dalam hitungan detik)
sekaligus tidak pernah mengganggu antrean yang sah.

Untuk QR, hitungan **sengaja tidak dikosongkan** saat berhasil — lihat di bawah.

### Dua cacat di v2 yang ketemu saat memindahkan desainnya

v2 sudah punya pembatas berbasis kegagalan. Tetapi:

**1. Jatah kegagalan QR bisa disetel ulang tanpa batas.** Kuncinya per-IP
(jalur ini tidak punya email), namun keberhasilan memanggil
`recordSuccess`. Penyerang yang memegang SATU kartu sah tinggal berselang-seling:
dua tebakan meleset, satu scan kartunya sendiri, ulangi. Pembatasnya ada, tetapi
tidak membatasi apa pun.

Ditutup, dan diuji dengan cara yang benar: **uji regresinya dijalankan lebih
dulu terhadap perilaku lama dan memang GAGAL**, lalu lulus setelah diperbaiki.
Uji yang tidak pernah dibuktikan gagal tidak membuktikan apa-apa.

**2. Ambang QR terlalu ketat untuk gerbang sekolah.** Ia memakai penjaga yang
sama dengan login password: 3 kegagalan → kunci semenit. Tiga kartu bermasalah
berturut-turut — kartu kotor, kartu siswa yang sudah dinonaktifkan, kartu
tertukar — mengunci SELURUH antrean. Dipisah jadi penjaga tersendiri dengan
ambang 10.

Penjaganya benar-benar terpisah, bukan sekadar ambang berbeda pada map yang
sama: kalau berbagi map, kegagalan scan kartu ikut menghitung terhadap login
password dari IP yang sama.

### Jebakan yang dibuat sendiri, lalu ditutup

Menambahkan `maxFailures` ke struct membuat `loginThrottle` bernilai-nol
mengunci pada kegagalan PERTAMA (`failures >= 0` selalu benar). Dua uji lama
langsung merah — helper ujinya memang membuat struct tanpa mengisi ambang.

Diperbaiki di sumbernya, bukan di ujinya: `newLoginThrottle()` menolak ambang
di bawah 1 dan jatuh ke nilai bawaan. Penjaga yang dibuat tanpa ambang tidak
akan pernah diam-diam menolak semua orang.

### Terverifikasi

**v1 — 14 pemeriksaan, lulus.** Termasuk dua yang jadi alasan seluruh desainnya:
siswa lain di IP yang sama tetap bisa masuk saat satu akun terkunci, dan 30 scan
kartu sah berturut-turut dari satu IP semuanya lolos dengan hitungan kegagalan
tetap nol.

**v2 — suite hijau tiga kali berturut-turut**, termasuk uji regresi baru yang
sudah dibuktikan menangkap cacatnya.

---

---

## Temuan sampingan — Tahun ajaran pada penugasan guru  ✅ SELESAI (v1 + v2)

Tanpa kolom ini penugasan guru tidak punya riwayat: tidak ada cara menjawab
"siapa yang mengajar 8A tahun lalu", dan guru yang berhenti mengajar 8A tetap
tercatat mengajarnya selamanya.

### Indeks unik ikut melebar, dan urutannya menentukan

`(tutor_id, class_id, subject_id)` → `(…, academic_year)`. Tanpa itu, satu guru
tidak bisa ditugaskan ke kelas + mapel yang sama pada dua tahun berbeda —
padahal itu hal yang paling lumrah terjadi.

Backfill dijalankan **selagi indeks lama masih terpasang**: indeks itulah yang
menjamin tidak ada baris kembar. Kalau dibuang lebih dulu lalu ternyata ada
duplikat, mengisi semuanya dengan tahun yang sama akan melanggar indeks baru
dan menggagalkan boot.

### Aturan dua langkah — langkah kedua yang penting

1. Guru punya penugasan tahun BERJALAN → hanya itu yang berlaku. Penugasan
   tahun lampau berhenti memberi akses.
2. Guru BELUM punya untuk tahun berjalan → penugasan tahun terakhirnya tetap
   dipakai.

Langkah 2 bukan kelonggaran; ia mencegah **bencana tanggal 1 Juli**. Tahun
ajaran berganti sendiri menurut kalender, sedangkan penugasan ulang dikerjakan
manusia beberapa hari sesudahnya. Tanpa jaring itu, SETIAP guru kehilangan
akses ke SEMUA kelasnya begitu tanggal berganti — tanpa ada yang mengubah
apa pun.

### Baris tanpa tahun tidak boleh mencabut akses

Ditemukan sebagai regresi: begitu relasi disaring per tahun, baris lama
ber-`academic_year` NULL berhenti memberi akses sama sekali. Enam pemeriksaan
materi v1 dan seluruh suite v2 langsung merah.

Perbaikannya bukan di fixture melainkan di aturannya: baris tanpa tahun
diperlakukan sebagai tahun berjalan. Baris begitu hanya lahir dari jalur yang
melewati controller (skrip impor, penyuntingan langsung), dan mengabaikannya
membuat guru kehilangan akses tanpa jejak — kegagalan yang tidak terbaca
sebagai "data kurang lengkap", melainkan sebagai "sistemnya rusak".

### Skema uji v2 disamakan dengan skema boot

`newTestServer` hanya menjalankan AutoMigrate, sedangkan pembuangan indeks lama
terjadi di backfill saat boot. Akibatnya uji berjalan di atas skema yang lebih
tua daripada produksi — dan sub-uji "kelas+mapel sama di dua tahun" gagal
karena indeks lama masih ada di sana. Kini setup uji ikut memanggil backfill-nya.

### Terverifikasi

**v1 — 16 pemeriksaan, lulus.** Termasuk: guru yang sudah ditugaskan ulang
berhenti melihat kelas lamanya; guru yang belum ditugaskan ulang TIDAK
terkunci; riwayat lintas tahun tetap terbaca; kelas+mapel sama diterima di dua
tahun; baris kembar di tahun yang sama tetap ditolak indeks unik.

**v2 — 6 sub-uji, lulus**, skenario identik; suite hijau tiga kali berturut-turut.

---

## Temuan sampingan — Blok penilaian alasan menampilkan huruf saja  ✅ SELESAI (v1)

`admin/exam-results/show.blade.php` menulis "Pilihan siswa: **B** (kunci: C)"
tanpa pernah menampilkan daftar opsinya. Guru sedang menilai ALASAN siswa, dan
masuk-akalnya alasan itu bergantung pada apa isi pilihan B — jadi guru harus
membuka soalnya di tab lain hanya untuk bisa menilai.

Ditambahkan `Question::optionLabel()` yang mengembalikan huruf DAN teksnya
("B — Surabaya"), memetakan true/false ke "A (Benar)" / "B (Salah)", membuang
tag HTML, dan memotong teks yang kepanjangan. Mengembalikan huruf saja bila
teks opsinya tidak ditemukan — lebih baik daripada kosong.

Tempat lain yang menampilkan huruf sudah diperiksa dan **tidak** bermasalah:
di partial `question-answer-review` huruf muncul tepat di bawah daftar opsi
yang sudah tergelar, jadi pembacanya tetap tahu B itu apa.

---

## Item 17 — LMS: materi, tugas, dan grup chat kelas  ✅ SELESAI (v1 + v2)

| Bagian | Keadaan |
|---|---|
| Ruang per tahun ajaran (17a) | ✅ selesai |
| Tugas (`school_tasks`, bertahun-ajaran, bermapel) | ✅ sudah ada sejak item 16 & 17a |
| Materi | ✅ selesai |
| **Grup chat** | ✅ **selesai** |

### Tiga keputusan yang diambil sebelum baris pertama ditulis

Ini percakapan anak-anak di lingkungan sekolah. Menundanya berarti
memutuskannya setelah datanya terlanjur ada.

**1. Retensi — tidak ada penghapusan otomatis.** Menjadwalkan penghapusan
berarti bukti perundungan ikut hilang tepat saat seseorang membutuhkannya;
menyimpan selamanya tanpa menyebutkannya juga tidak jujur. Jalan tengahnya:
tidak ada penghapus terjadwal, dan pembersihan permanen harus dijalankan
manusia secara sadar.

**2. Moderasi — hapus itu SOFT DELETE, dan pelakunya dicatat.** `deleted_by` +
`deleted_reason` ada supaya "pesan ini dihapus siapa" bisa dijawab enam bulan
kemudian. Guru dan admin boleh menghapus pesan siapa pun di ruangnya; siswa
hanya miliknya sendiri.

**3. Real-time — polling berkursor, bukan WebSocket.** v1 berjalan di PHP-FPM
yang tidak bisa menahan koneksi panjang tanpa layanan tambahan. Memakai
mekanisme yang sama di kedua versi membuat keduanya berperilaku identik.
Indeks `(class_id, subject_id, academic_year, id)` membuat "ambil pesan setelah
id N" jadi satu pencarian indeks.

### Kunci ruang sama dengan materi dan tugas

`(class_id, subject_id, academic_year)`. `subject_id` NULL = ruang kelas umum;
terisi = ruang kelas + mapel — itulah "antar kelas" dan "antar kelas + mapel"
yang diminta.

Siswa **boleh** mengirim. Ruang yang hanya bisa ditulisi guru bukan grup chat,
itu papan pengumuman. Arsip tahun lampau terbaca tetapi tidak bisa ditulisi
oleh siapa pun, admin sekalipun.

Tugas dan ujian dibagikan sebagai **rujukan** `(ref_type, ref_id)`, bukan URL
yang ditempel: URL berubah saat domain atau rute berubah, dan tautan lama jadi
404 tanpa ada yang tahu. Rujukan milik sekolah lain dibuang diam-diam —
kalimat yang ditulis orang tetap terkirim, hanya tautannya yang dilepas.

### Cacat yang ditemukan uji, bukan produksi

**Pesan yang sudah dihapus masih bisa "dihapus" lagi** — dan hapus kedua
MENIMPA `deleted_by`/`deleted_reason` milik yang pertama. Jejak itulah satu-
satunya alasan tombol hapus boleh ada, jadi menimpanya membatalkan seluruh
keputusan nomor 2. Ditutup di kedua versi; tombolnya memang tidak ditampilkan
untuk pesan terhapus, tetapi permintaan yang dirangkai sendiri tidak lewat
tombol.

**`@push('scripts')` diabaikan diam-diam.** Kedua layout v1 memakai
`@yield('scripts')`, bukan `@stack`. Skrip polling tidak akan pernah termuat,
dan tidak ada peringatan apa pun — halamannya tampak normal, hanya tidak
pernah memperbarui diri. Diganti `@section`, dan uji-jalan HTTP memeriksa
string `chat/poll` benar-benar ada di HTML-nya.

**Balapan pindah ruang di v2.** Polling berjalan tiap 5 detik; kalau pengguna
berpindah ruang tepat saat satu permintaan sedang di jalan, respons ruang LAMA
tiba setelah ruang baru terpasang — dan pesan ruang lama tergambar di ruang
baru. Tiap respons kini dibandingkan dengan penanda ruang dan dibuang bila
sudah basi.

### Isi pesan terhapus tidak ikut dikirim

Ditahan di server, bukan disembunyikan di tampilan: siapa pun yang membuka
devtools tetap akan membacanya — dan yang dihapus guru biasanya justru yang
tidak boleh dibaca. Yang dikirim hanya penanda "terhapus" dan nama
penghapusnya.

### Terverifikasi

**v1 — 33 pemeriksaan, lulus.** Termasuk: ruang mapel tidak bocor ke ruang umum
(`subject_id = NULL` tidak pernah benar di SQL — ruang umum akan selalu tampak
kosong bila salah); arsip tidak bisa ditulisi admin sekalipun; isi pesan
terhapus masih ada di basis data sementara jejaknya tercatat; rujukan lintas
sekolah dibuang; pesan kepanjangan dipotong, bukan ditolak.

**v1 — uji-jalan HTTP, 12 pemeriksaan, lulus** dengan server benar-benar hidup:
halaman terbuka untuk siswa dan admin, skrip polling ikut termuat, pesan
terkirim dan muncul, endpoint polling mengembalikan JSON, dan kursor hanya
mengambil pesan yang benar-benar baru.

**v2 — 9 sub-uji lewat router, lulus**, skenario identik. Suite hijau tiga kali
berturut-turut.

**v2 — uji-jalan API, 14 pemeriksaan, lulus** dengan backend Go benar-benar
hidup: kirim, pisah ruang, kursor, moderasi berjejak, hapus kedua ditolak, dan
ruang asing ditolak 403.

`npx eslint src` → 0 keluaran; `npx next build` → "✓ Compiled successfully".
