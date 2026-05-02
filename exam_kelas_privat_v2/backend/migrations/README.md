# Migrasi Go

Folder ini menjadi rumah toolchain migrasi untuk `exam_kelas_privat_v2`.

- `cmd/migrate` menjalankan `gorm.AutoMigrate(...)` untuk seluruh model yang sudah dipetakan dari Laravel.
- `manifest.generated.json` dihasilkan otomatis dan mencatat sumber 71 migration Laravel agar jejak translasi tetap terdokumentasi.

Pendekatan ini aman untuk:

- memakai DB existing sebagai sumber data utama,
- membuat environment baru dengan skema yang sama secara bertahap,
- memindahkan ownership migrasi ke codebase Go tanpa mengubah file migration Laravel lama.
