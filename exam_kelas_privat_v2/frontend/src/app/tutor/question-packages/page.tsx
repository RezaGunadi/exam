import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function TutorQuestionPackagesPage() {
  return (
    <AppShell title="Paket Soal" description="Akses baca paket soal yang tersedia untuk tutor.">
      <ResourcePage
        endpoint="/api/tutor/question-packages"
        title="Paket soal"
        description="Tutor dapat melihat paket soal seperti pada panel tutor Laravel."
      />
    </AppShell>
  );
}
