import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";

export default function TutorAttemptManagementPage() {
  return (
    <AppShell title="Attempt Management" description="Pantau percobaan ujian dari akun tutor.">
      <ResourcePage
        endpoint="/api/tutor/attempt-management"
        title="Attempt siswa"
        description="Akses baca attempt management seperti route tutor Laravel."
      />
    </AppShell>
  );
}
