# Parity Matrix V2

Matriks ini merangkum perbandingan fitur antara `exam_kelas_privat` lama dan `exam_kelas_privat_v2`.
`Generate rapot` sengaja dikecualikan karena akan dibangun ulang terpisah.

| Area | Laravel lama | Backend v2 | Frontend v2 | Status parity |
| --- | --- | --- | --- | --- |
| Landing publik | Lengkap dan informatif | Stats + contact + demo | Ada, tetapi belum penuh | UI belum setara |
| Login / register | Ada | Ada | Ada | Perlu penyelarasan behavior/copy |
| Forgot / reset password | Ada | Ada | Ada | Sudah ada, perlu dipoles |
| Gate sekolah nonaktif / ads | Ada | Ada | Ada | Behavior sudah pulih, masih perlu pemolesan |
| Dashboard | Ada | Ada | Ada | Perlu diperkaya |
| Profil | Ada | Ada | Ada | Cukup |
| Siswa | CRUD + import + bulk password | Ada | Ada | Cukup kuat |
| Kelas | CRUD | Ada | Tipis | Backend ada, UI belum setara |
| Mapel | CRUD + KKM | Ada | Tipis | Backend ada, UI belum setara |
| Tutor user | CRUD | Ada | Tipis | Backend ada, UI belum setara |
| Assignment tutor | Ada | Ada | Belum jelas | Backend ada, UI belum setara |
| Paket soal | Ada + import | Ada | Ada | Cukup kuat |
| Soal | Ada + upload media + repick | CRUD dasar ada | Tipis | Gap besar |
| Ujian | Ada + publish + assignment | Ada | Tipis | Gap besar |
| Hasil ujian | Ada + detail + essay + export + answer sheet/PDF/email | Detail + essay + export CSV ada | Ada, masih dangkal | Gap besar |
| Attempt management | Ada | Ada | Ada | Cukup |
| Absensi | Ada | Ada | Ada | Cukup |
| Tugas sekolah | Ada | Ada | Tipis | Backend ada, UI belum setara |
| Referral / credit | Ada | Ada | Ada | Cukup |
| Tutor my classes / students | Ada | Ada | Ada | Cukup |
| SEB siswa | Ada | Ada sebagian | Ada | Cukup |
| Scheduler / recovery | Ada | Ada | Ada | Perlu audit deployment |
| Subject order | Ada | Belum ada route | Belum ada | Belum ada |
| Subject KKM | Ada | Menempel di `subjects` | Belum eksplisit | UI belum setara |
| AI scoring | Ada | Belum ada route parity | Belum ada | Belum ada |
| Answer sheet / PDF / email hasil | Ada | Belum ada route parity | Belum ada | Belum ada |
| Upload media soal | Ada | Belum ada route parity | Belum ada | Belum ada |
| Repick soal | Ada | Belum ada route parity | Belum ada | Belum ada |

## Prioritas implementasi

1. Lengkapi permukaan publik dan auth agar user lama tidak merasa ada alur yang hilang.
2. Naikkan modul admin yang masih memakai list generik menjadi halaman operasional sungguhan.
3. Tutup fitur operasional bernilai tinggi yang dulu ada dan sekarang belum punya padanan jelas.
4. Audit worker dan deployment supaya behavior runtime setara dengan ekspektasi sistem lama.
