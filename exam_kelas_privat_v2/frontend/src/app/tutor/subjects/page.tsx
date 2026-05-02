import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function TutorSubjectsPage() {
  return (
    <AppShell title="Mata Pelajaran" description="Akses baca mata pelajaran untuk tutor.">
      <ResourcePage
        endpoint="/api/tutor/subjects"
        title="Daftar mata pelajaran"
        description="Tutor dapat melihat mapel seperti pada sidebar Laravel."
      />
    </AppShell>
  );
}
