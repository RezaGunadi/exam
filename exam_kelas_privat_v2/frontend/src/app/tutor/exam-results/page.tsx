import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function TutorExamResultsPage() {
  return (
    <AppShell title="Hasil Ujian" description="Akses baca hasil ujian untuk tutor.">
      <ResourcePage
        endpoint="/api/tutor/exam-results"
        title="Hasil ujian"
        description="Tutor dapat melihat hasil ujian seperti route tutor Laravel."
      />
    </AppShell>
  );
}
