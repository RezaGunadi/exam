# Rencana Penyamaan UI/UX v1 → v2

Tujuan: v2 **sama persis** dengan v1 dalam hal yang bisa dilakukan orang di
tiap layar, dengan kode yang lebih rapi, terstruktur, dan ringan.

Disusun 2 September 2026, dari inventaris menyeluruh kedua repo.

**SELURUH ANTREAN SELESAI** — delapan butir, semuanya terpasang dan terverifikasi.

---

## Temuan utama: paritas HALAMAN sudah lengkap

Inventaris lengkap kedua sisi:

| | Jumlah |
|---|---|
| Berkas blade v1 | 182 |
| — di antaranya layout, partial, email, vendor (bukan halaman) | 40 |
| **Halaman v1** | **142** |
| **Halaman v2** (`page.tsx`) | **90** |

Selisih 142 → 90 **bukan** berarti 52 halaman hilang. Setelah dipetakan satu
per satu, dengan memperhitungkan padanan nama (`absensi`↔`attendance`,
`materi`↔`materials`, `tugas-sekolah`↔`tasks`):

| | Jumlah |
|---|---|
| Punya padanan 1:1 di v2 | 85 |
| Sengaja **digabung** ke layar lain di v2 | 27 |
| Bukan halaman (layout, cadangan, template) | 30 |
| **Benar-benar belum ada** | **0** |

Contoh penggabungan yang disengaja dan diverifikasi:

- `admin/absensi/{index,input,detail,detail-class}` → satu layar `admin/attendance`
- `admin/tugas-sekolah/{index,assign,submissions}` → satu layar `admin/tasks`
- `admin/library/{checkout,return}` → `admin/library/loans`
- `admin/library/settings` → menyatu di `admin/library` (`loan_days`, `fine_per_day` terverifikasi ada)
- `public/progress/{form,report,exam-detail,task-detail}` → `cek-progress`
- `admin/dashboard` + `student/dashboard` + `tutor/dashboard` → satu `dashboard`

**Artinya:** yang Anda rasakan sebagai "belum sama seperti v1" bukan halaman
yang hilang, melainkan **kelengkapan di dalam halaman**. Rencana ini karena itu
disusun per layar, bukan per halaman yang harus dibuat.

---

## Cara memilih urutan

Diukur, bukan dikira-kira: jumlah **kendali** tiap layar — isian, tombol, dan
kolom tabel, yaitu hal yang bisa *dilakukan* orang di sana.

Rasio v2/v1 yang rendah menandai layar yang menawarkan lebih sedikit tindakan
daripada v1. Ini **penunjuk arah, bukan vonis**: satu `<select>` di v2 bisa
menggantikan tiga tombol di v1. Yang dihasilkan daftar prioritas untuk
diperiksa mata.

| Urutan | Layar | Kendali v1 | Kendali v2 | Rasio |
|---|---|---|---|---|
| 1 | `admin/students` | 49 | 21 | **0.43** |
| 2 | `admin/reports` | 23 | 14 | 0.61 |
| 3 | `admin/payment` | 29 | 18 | 0.62 |
| 4 | `admin/promotions` | 9 | 7 | 0.78 |
| 5 | `owner/users` | 15 | 12 | 0.80 |
| 6 | `admin/attempt-management` | 34 | 28 | 0.82 |
| 7 | `admin/exam-results` | 25 | 24 | 0.96 |
| 8 | `admin/attendance` | 7 | 7 | 1.00 |
| 9 | `admin/raports` | 23 | 23 | 1.00 |

Layar dengan rasio > 1 (`admin/questions` 2.35, `owner/schools` 2.9,
`admin/rekap` 5.33) sudah **melampaui** v1 dan tidak masuk antrean.

**Tiga layar berbasis komponen bersama** (`ResourcePage`) tidak terukur oleh
cara ini karena kendalinya tidak ditulis di halamannya: `admin/subjects`,
`admin/semesters`, `student/exams`. Diperiksa terpisah — dan pemeriksaan
pertama sudah menemukan satu selisih nyata: `admin/subjects` tidak menampilkan
**KKM**, padahal v1 punya dan `createHint`-nya sendiri menyebutnya.

---

## Aturan kerja

Berlaku untuk setiap butir, tanpa kecuali:

1. **Baca blade v1 lebih dulu**, jangan menebak dari nama layar.
2. **Satu layar per langkah** — diverifikasi (tsc, eslint, guard, ukur) sebelum
   pindah.
3. **Jangan menyalin bentuk v1 mentah-mentah.** Yang disamakan *kemampuannya*,
   bukan markup-nya. v1 memakai Bootstrap + jQuery; v2 tidak, dan menyalin
   strukturnya akan membawa serta yang justru ingin ditinggalkan.
4. **Yang sudah lebih baik di v2 tidak diturunkan** untuk menyamai v1, dan
   **fitur yang hanya ada di v2 tetap ada** — penyamaan ini menambah yang
   kurang, tidak pernah membuang yang lebih.
5. **Yang disamakan bukan hanya fitur, tetapi juga tampilan dan susunannya**:
   urutan bagian, pengelompokan, penamaan tombol, dan letak tindakan. Layar
   yang punya fitur sama tetapi tersusun berbeda tetap terasa asing bagi orang
   yang terbiasa dengan v1 — dan merekalah seluruh penggunanya sekarang.

   Yang TIDAK ikut disamakan: kerangka teknisnya. v1 memakai Bootstrap dan
   jQuery; menyalin markup-nya berarti membawa serta hal yang justru ingin
   ditinggalkan. Yang disamakan susunan dan perilakunya, bukan kelas CSS-nya.
6. **Data produksi tidak disentuh.** Setiap perubahan diperiksa ulang terhadap
   hitungan baris.

---

## Antrean

### ✅ 1. `admin/students` — SELESAI
Ketiga jalur impor v1 (siswa, sandi massal, pembaruan massal) beserta tabel
kegagalannya **sudah ada** di v2. Yang belum terbawa: saringan **jenis
kelamin** dan **pengurutan** (kolom + arah).

Backend ternyata sudah menerima `gender` dan `sort_by` sejak awal — frontend
tidak pernah mengirimnya. Ditambah `sort_order` dan kolom `email`.

Klausa ORDER BY dipisahkan jadi `urutanSiswa()` agar bisa diuji: isinya dari
masukan pemakai dan masuk ke SQL apa adanya. Ujinya memeriksa bahwa
`name; DROP TABLE users`, `users.id`, dan `name)--` semuanya jatuh ke bawaan.

### ✅ 2. `admin/reports` — SELESAI, dan temuannya jauh lebih besar
Yang dicari saringan kelas. Yang ditemukan: **layar Laporan mengembalikan nol
baris sejak awal** — `reportExamQuery` menyaring `exams.status = "completed"`,
dan status itu **tidak pernah ada**. Produksi hanya punya draft (178),
published (99), cancelled (22); tidak ada kode di v1 maupun v2 yang pernah
menyetelnya.

**Berlaku di v1 juga** — kuerinya dipindahkan apa adanya berikut cacatnya.

Diganti definisi dari maksudnya: yang dilaporkan adalah ujian yang **punya
hasil**. Di produksi: **271 ujian, dari 0**. Ditambah saringan kelas lewat
subkueri (EXISTS, bukan JOIN — satu ujian punya puluhan hasil).

### ✅ 7. `admin/subjects` — SELESAI
KKM ditampilkan di daftar. v1 punya, dan `createHint` v2 pun menyebutnya —
hanya daftar kolomnya yang melewatkan.

### ✅ 3. `admin/payment` — SELESAI
v1 menampilkan **tiga rekening tujuan** (Mandiri, BCA, GoPay) berikut tombol
salin. v2 tidak menampilkan satu pun — sekolah menerima kode billing dan
nominal, lalu tidak diberi tahu ke mana mentransfernya.

Disimpan sebagai **setelan**, bukan ditanam di kode seperti v1: nomor rekening
berubah, dan di v1 setiap perubahan menuntut deploy. Formatnya baris-per-
rekening, bukan JSON — satu koma yang terlewat di JSON menghapus seluruh
daftar dari layar tanpa galat.

### ✅ 4. `admin/promotions` — SELESAI
"Pilih semua"/"Kosongkan" sudah ada. Yang kurang: tahun ajaran masih ketikan
bebas — kini pilihan, bawaannya tahun **berikutnya** (di layar naik kelas itu
memang tujuannya).

### ✅ 5. `owner/users` — SELESAI
Tabelnya justru **melampaui** v1: v1 empat kolom, v2 enam (NISN dan telepon
ikut). Yang salah reset sandinya — `window.prompt`, tanpa konfirmasi, dan
pemanggilnya mengirim `password_confirmation` berisi **nilai yang sama**
sehingga pemeriksaan konfirmasi di server dilumpuhkan dari sisi klien. Salah
ketik satu huruf menetapkan sandi yang tidak diketahui siapa pun. Diganti
dialog dengan dua isian yang dibandingkan sungguhan.

### ✅ 6. `admin/attempt-management` — SELESAI
**Mode attempt** tidak pernah dikirim: backend menerima `mode` +
`custom_duration_minutes` sejak awal, v1 menampilkannya, v2 selalu memakai
"auto". Bedanya nyata bagi siswa — ujian yang terputus di menit ke-50 dari 60
bisa dilanjutkan dengan sisa 10 menit atau dimulai ulang dengan 60 menit penuh.

### ✅ 8. `admin/exam-results` — SELESAI
Saringan **ujian** tidak pernah dikirim, padahal backend menerimanya. Itu
pertanyaan yang paling sering dibawa ke layar ini.

---

---

## Temuan di luar antrean, ditemukan saat inventaris

**Foto proktoring rusak di 2.337 hasil ujian.** Jalurnya kunci objek R2
(`proctor-snapshots/208/165/....jpg`), tetapi layar menyusunnya sebagai
`/api/files/...` yang dijawab **401**. Seluruh foto tampil sebagai gambar rusak
— di layar yang justru dipakai memeriksa dugaan kecurangan, yaitu saat buktinya
paling dibutuhkan. Sudah diperbaiki.

**Perlu keputusan Anda:** foto itu tersimpan di bucket R2 yang **publik**. Siapa
pun yang tahu alamatnya bisa membukanya tanpa sesi — dan isinya wajah siswa saat
ujian. Sekarang: `https://asset.kelasprivat.id/proctor-snapshots/…` terbuka
langsung. Bila ini tidak diinginkan, jalur yang benar adalah menyajikannya lewat
server dengan pemeriksaan sesi, bukan pengalihan ke CDN.

---

## Yang TIDAK masuk rencana ini

- Layar ujian siswa (`student/exams/[id]`) — jalur paling mahal bila rusak,
  dan tidak ada laporan masalah di sana.
- Layar dengan rasio > 1.
