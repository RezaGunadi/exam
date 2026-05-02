import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function AdminReportsPage() {
  return (
    <AppShell title="Laporan" description="Ringkasan laporan siswa berdasarkan hasil ujian dan skor.">
      <ResourcePage
        endpoint="/api/admin/reports"
        title="Daftar laporan siswa"
        description="Lihat agregasi nilai siswa seperti modul laporan Laravel."
      />
    </AppShell>
  );
}
