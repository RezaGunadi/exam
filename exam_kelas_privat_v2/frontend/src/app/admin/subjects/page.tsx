import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function AdminSubjectsPage() {
  return (
    <AppShell
      title="Mata Pelajaran"
      description="Kelola mata pelajaran, kode mapel, dan KKM yang dipakai untuk soal, paket soal, dan ujian."
    >
      <ResourcePage
        endpoint="/api/admin/subjects"
        title="Daftar mapel"
        description="Lihat, tambah, edit, dan rapikan mata pelajaran aktif beserta KKM sekolah."
        createHint={{ name: "Matematika", code: "MTK", kkm: 75, is_active: true }}
      />
    </AppShell>
  );
}
