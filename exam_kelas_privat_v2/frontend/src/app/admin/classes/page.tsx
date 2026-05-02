import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function AdminClassesPage() {
  return (
    <AppShell
      title="Kelas"
      description="Kelola daftar kelas yang digunakan untuk siswa, ujian, absensi, dan tugas."
    >
      <ResourcePage
        endpoint="/api/admin/classes"
        title="Daftar kelas"
        description="Lihat dan kelola kelas yang aktif di sekolah."
        createHint={{ name: "Kelas 9A", is_active: true }}
      />
    </AppShell>
  );
}
