import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function TutorQuestionsPage() {
  return (
    <AppShell title="Soal" description="Akses baca bank soal untuk tutor.">
      <ResourcePage
        endpoint="/api/tutor/questions"
        title="Bank soal"
        description="Tutor dapat meninjau soal tanpa aksi tulis."
      />
    </AppShell>
  );
}
