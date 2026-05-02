import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function TutorExamsPage() {
  return (
    <AppShell title="Ujian" description="Akses baca daftar ujian untuk tutor.">
      <ResourcePage
        endpoint="/api/tutor/exams"
        title="Daftar ujian"
        description="Tutor dapat memantau ujian yang tersedia seperti pada panel Laravel."
      />
    </AppShell>
  );
}
