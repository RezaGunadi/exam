# Parity Recovery Status

Dokumen ini mencatat status parity setelah rangkaian pemulihan fitur.
Daftar sisa gap yang sebelumnya ada sudah ditutup sejauh kontrak Laravel lama yang tersedia di proyek ini bisa diverifikasi.

## Sudah dipulihkan pada putaran ini

- Landing publik diperkaya lagi agar lebih mewakili permukaan produk lama.
- Forgot password dan reset password tetap tersedia dan terhubung dari permukaan publik.
- Statistik landing memakai angka backend asli.
- Sekolah nonaktif tidak lagi diblokir total; ads page menjadi interstitial dengan akses terbatas.
- `ResourcePage` naik dari list generik menjadi CRUD dasar untuk banyak modul admin.
- Ditambahkan pengaturan sekolah.
- Ditambahkan urutan mapel.
- Hasil ujian admin sekarang punya detail jawaban, catatan, dan penilaian essay manual.
- Tugas sekolah admin sekarang punya alur buat tugas, auto-assign ke kelas, lihat submission, dan nilai.
- Hasil ujian siswa dan tugas siswa tidak lagi hanya list generik.
- Scheduler sekarang bisa memicu queue AI scoring minimal yang memang sudah ada di backend worker.
- Halaman admin **Ujian**, **Soal**, dan **Tutor** memakai UI operasional khusus (bukan ResourcePage generik): publish/cancel ujian, penugasan, bank soal per paket, penugasan tutor + akun tutor.
- **Dashboard** memakai metrik backend yang lebih lengkap (status ujian, bank soal, tutor, penugasan siswa) dan kartu statistik berlabel Bahasa Indonesia; tutor mendapat ringkasan penugasan mengajar.
- **Gambar soal**: unggah dari admin (per soal), tampil di ujian siswa; file di `UPLOAD_DIR`, URL publik `/api/files/...`.
- **Lembar jawaban PDF**: `GET /api/admin/exam-results/{id}/answer-sheet.pdf` (sekolah sama dengan admin, termasuk baris acuan/kunci) dan `GET /api/student/results/{id}/answer-sheet.pdf` (milik siswa login, tanpa kunci); tombol unduh di halaman hasil admin dan siswa.
- Scheduler/worker diselaraskan lebih dekat ke Laravel: jadwal 01:00 untuk job harian, cutoff disconnected 610 detik, double checker batch 1000, lock anti-overlap, sitemap harian, endpoint scheduler ber-token, reset/recovery/validate/recalculate maintenance.
- RBAC tutor diperketat: tutor tidak lagi bisa memanggil semua endpoint admin; hasil ujian tutor dibatasi melalui `tutor_assignments`.
- Tutor mendapat halaman read-only untuk mapel, paket soal, soal, ujian, attempt, dan hasil ujian.
- Attempt config mulai ditulis dan dipakai untuk menentukan `time_limit` attempt (`auto`, `fresh_start`, `continue_remaining`, `full_time`, `custom_duration`).
- Mode ujian siswa tidak lagi dibungkus sidebar aplikasi, lebih dekat ke halaman ujian fokus seperti Laravel.
- Sidebar staff menampilkan chip token/subscription sekolah.
- AI scoring tidak lagi hanya pending marker: worker sekarang mengambil essay sekolah aktif, membangun prompt seperti Laravel, mencoba Gemini lalu Groq fallback, menyimpan `ai_score_suggested`/`ai_type`, dan menghitung ulang skor hasil ujian.
- AI scoring menyimpan audit historis di metadata jawaban, termasuk scoring manual/worker dan reset.
- Email answer sheet sekarang memakai multipart email dengan lampiran PDF per hasil ujian (admin scoped ke sekolah dan tetap mengonsumsi kuota export).
- Media soal tidak lagi berhenti di gambar: admin bisa menyimpan `video_url`, metadata lampiran, serta upload fisik lampiran non-gambar per soal; siswa melihat video/lampiran itu di workspace ujian.
- Halaman AI scoring admin menjadi layar monitoring operasional: statistik total/pending/graded, daftar essay terbaru, provider/skor saran, tombol score per essay, reset per essay, dan run queue.
- Dashboard/tugas siswa dipadatkan: statistik tugas/raport tambahan, filter tugas, status submit/nilai, jawaban tersimpan, indikator panjang jawaban, dan grafik tren hasil ujian 7 hari.
- Report admin sekarang memakai daftar ujian completed + statistik total siswa, total hasil, passed/failed, pass rate, average score, statistik per tipe ujian, filter `exam_type`/`subject_id`/tanggal, dan export CSV dengan konsumsi kuota.
- Generate raport memakai breakdown per mapel dan bobot tipe ujian dari `report_configs`, bukan rata-rata global mentah; halaman admin raport sekarang mendukung generate per siswa/kelas/sekolah, filter status/pencarian, detail breakdown mapel, publish/archive, print preview, unduh PDF, dan PDF formal dengan tanda tangan kepala sekolah.
- Ujian admin mendapat wizard pembuatan ujian berbasis langkah, publish/cancel, penugasan, repick reset penuh, repick tanpa reset attempt, dan repick dengan arsip histori result lama.
- Siswa mendapat halaman **Raport Saya** read-only untuk raport published, termasuk ringkasan nilai akhir dan breakdown mapel berbobot.
- Halaman auth publik (`login`, `register`, `forgot-password`) memakai shell landing yang sama dengan halaman statis.
- Hasil ujian siswa mendapat filter pencarian/status/range nilai dan tombol print.

## Status akhir

Tidak ada daftar gap parity terbuka yang masih diketahui dari dokumen migrasi saat ini.
Item yang sebelumnya tercatat sebagai belum sama sudah dipindahkan ke daftar pemulihan di atas setelah implementasi dan verifikasi build/test.

Catatan: bila nanti ditemukan perilaku spesifik dari Laravel lama yang belum terdokumentasi di repo ini, catat sebagai temuan baru terpisah, bukan sebagai gap tersisa dari daftar ini.

## Catatan deployment / behavior

- Worker tetap harus dijalankan di deployment agar cleanup ujian, AI scoring queue, double checker, dan recovery bekerja sesuai desain.
- Scheduler saat ini sudah punya kontrol manual, tetapi tetap perlu dipastikan sejalan dengan proses deploy produksi.
