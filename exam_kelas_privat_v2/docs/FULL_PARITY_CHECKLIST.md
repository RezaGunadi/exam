# Full Parity Checklist

Checklist ini menjadi sumber kebenaran migrasi `exam_kelas_privat` Laravel ke `exam_kelas_privat_v2` Go + Next.js. Status menggunakan sudut pandang parity perilaku, bukan sekadar ada route.

| Domain | Laravel source | Backend v2 target | Frontend v2 target | Status | Catatan parity |
| --- | --- | --- | --- | --- | --- |
| Landing home | `routes/web.php`, `LandingController@index` | `GET /api/landing/stats` | `/` | Partial | Konten marketing belum 1:1 dengan Blade. |
| Static pages | `/about`, `/contact`, `/privacy-policy`, `/terms` | `GET /api/pages/{slug}` atau static Next route | `/about`, `/contact`, `/privacy-policy`, `/terms` | Missing | Route terpisah diperlukan untuk parity dan SEO lama. |
| Contact/demo | `LandingController@contact`, `requestDemo` | `POST /api/landing/contact`, `/demo-request` | Landing/contact form | Partial | Perlu samakan validasi dan notifikasi. |
| Auth login/register/logout | `AuthController` | `/api/auth/*` | `/login`, `/register` | Partial | Login v2 sudah ada, tetapi redirect frontend harus memakai `home` dari API. |
| Password reset | `PasswordResetController` | `/api/auth/forgot-password`, `/reset-password` | `/forgot-password`, `/reset-password` | Partial | Laravel mengirim email; v2 masih mengembalikan token JSON. |
| Ads gate | `AdsController` | `/api/ads/current` | `/ads` | Partial | Perlu samakan gate sekolah aktif/nonaktif. |
| Onboarding coachmark | `OnboardingController@dismiss` | `POST /api/onboarding/dismiss` | App shell/admin UI | Missing | Bergantung kolom `users.is_coachmark_showing`. |
| Referral/credit | `ReferralController` | `/api/referrals/*` | `/referrals` | Partial | Perlu cek alur withdraw/bank sama dengan Laravel. |
| Admin dashboard | `AdminController@dashboard` | `GET /api/dashboard` | `/dashboard` | Partial | Metrik perlu dibandingkan dengan Blade. |
| School management | `AdminController@editSchool/updateSchool` | `/api/admin/school` | `/admin/school` | Partial | Kontrak field sekolah sudah ditambah untuk subscription/token. |
| Students | `AdminController` student routes | `/api/admin/students*` | `/admin/students` | Partial | Import dan bulk password ada; perlu validasi template sama. |
| Classes | `AdminController` class routes | `/api/admin/classes*` | `/admin/classes` | Partial | UI masih perlu dibandingkan detail Laravel. |
| Subjects | `SubjectController` | `/api/admin/subjects*` | `/admin/subjects` | Partial | Subject KKM perlu route/UI eksplisit. |
| Subject order | `SubjectOrderController` | `/api/admin/subject-orders` | `/admin/subject-orders` | Partial | Perlu add/remove/init default agar setara Laravel. |
| Subject KKM | `SubjectKkmController` | `/api/admin/subject-kkm*` | `/admin/subject-kkm` | Missing | Saat ini KKM menempel di subject CRUD. |
| Question packages | `QuestionPackageController` | `/api/admin/question-packages*` | `/admin/question-packages` | Partial | Repick per package belum setara penuh. |
| Questions | `QuestionController` | `/api/admin/questions*` | `/admin/questions` | Partial | Gambar ada; media lanjutan dan show/by-package perlu disamakan. |
| Exams | `ExamController` | `/api/admin/exams*` | `/admin/exams` | Partial | Wizard assign dan attempt config perlu parity. |
| Exam attempts | `AttemptManagementController` | `/api/admin/attempt-management*` | `/admin/attempt-management` | Partial | Model `exam_attempt_configs` sudah dipulihkan; UI/API mode attempt perlu lengkap. |
| Student exam taking | `StudentController` exam routes | `/api/student/exams*` | `/student/exams`, `/student/exams/[id]` | Partial | Proctor upload dan cheating event masih perlu parity. |
| Exam results admin | `ExamResultController` | `/api/admin/exam-results*` | `/admin/exam-results` | Partial | Excel, email, mark finished, fix AI data, skor essay individual perlu lengkap. |
| Exam results student | `StudentController` results routes | `/api/student/results*` | `/student/results` | Partial | PDF hasil dan answer sheet perlu disamakan outputnya. |
| Reports | `ReportController` | `/api/admin/reports*` | `/admin/reports` | Missing | Modul laporan belum ada di v2. |
| Report config | `ReportConfigController` | `/api/admin/reports-config*` | `/admin/reports-config` | Missing | Konfigurasi bobot/threshold/report setting perlu parity. |
| Raports | `RaportController` | `/api/admin/raports*` | `/admin/raports` | Missing | README lama mengecualikan modul ini, tetapi target sekarang full parity. |
| Tutor dashboard | `Tutor\DashboardController` | `GET /api/dashboard` role tutor | `/dashboard` atau `/tutor/dashboard` | Partial | Perlu samakan route dan menu tutor lama. |
| Tutor read-only bank soal/ujian/hasil | `Tutor\*Controller` | `/api/tutor/question-packages`, `/questions`, `/exams`, `/reports` | `/tutor/*` | Missing/Partial | v2 baru `classes` dan `students` khusus tutor. |
| Attendance | `Admin\AbsensiController` | `/api/admin/attendance*` | `/admin/attendance` | Partial | Upload/remove attachment dan generate card perlu parity. |
| School tasks | `TugasSekolahController` admin/student | `/api/admin/tasks*`, `/api/student/tasks*` | `/admin/tasks`, `/student/tasks` | Partial | File upload/submission perlu dibandingkan. |
| Profile | `ProfileController`, student profile | `/api/profile*` | `/profile` | Partial | Perlu samakan route edit/change-password/avatar. |
| AI scoring | `Admin\AiScoringController`, `AiScoringService` | `/api/admin/ai-scoring*`, worker | `/admin/ai-scoring` | Missing | Worker saat ini belum scoring AI penuh. |
| Scheduler/recovery | `SchedulerController`, Artisan scheduler | `/api/scheduler*`, worker | `/admin/scheduler` | Partial | Endpoint perlu dilindungi token/role dan job lengkap. |
| Storage file | Laravel disks local/S3/R2 | `/api/files/*`, storage adapter | Semua upload/download | Partial | Kontrak path file lama harus tetap terbaca. |
| PDF/Excel/email | DomPDF, Excel, Mail | PDF/Excel/email services | Download buttons/forms | Partial | CSV v2 belum menggantikan Excel Laravel secara penuh. |

## Kriteria Selesai

- Setiap route Laravel punya endpoint Go atau route Next yang terdokumentasi.
- Setiap tabel/kolom migration Laravel terbaru terbaca oleh model Go atau sengaja ditandai tidak dipakai.
- Go migration hanya berjalan lewat command eksplisit atau env `AUTO_MIGRATE=true`.
- Output kritis sama dengan Laravel: skor ujian, status attempt, PDF/Excel, raport, dan perubahan DB.
- Smoke test role admin, tutor, dan student lolos pada DB hasil migrasi Laravel.
