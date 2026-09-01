# Rencana Penyamaan UI/UX v1 → v2

Tujuan: v2 **sama persis** dengan v1 dalam hal yang bisa dilakukan orang di
tiap layar, dengan kode yang lebih rapi, terstruktur, dan ringan.

Disusun 2 September 2026, dari inventaris menyeluruh kedua repo.

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

### 1. `admin/students` — rasio 0.43, selisih terbesar
Blade v1: `admin/students/index` (49 kendali). Periksa: kolom tabel, saringan,
tindakan massal, impor/ekspor, pratinjau pembaruan massal.

### 2. `admin/reports` — 0.61
Blade v1: `admin/reports/index` + `export` + `student`.

### 3. `admin/payment` — 0.62
Blade v1: `admin/payment/index`. Sebagian sudah dikerjakan (DP, kuitansi DP,
bukti pelunasan) — periksa sisanya.

### 4. `admin/promotions` — 0.78

### 5. `owner/users` — 0.80

### 6. `admin/attempt-management` — 0.82
Baru saja diperbaiki (nama siswa/ujian, kolom email). Periksa ulang.

### 7. `admin/subjects` — KKM hilang dari daftar (di luar urutan rasio)

### 8. `admin/exam-results` — 0.96

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
