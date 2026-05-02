import { ExamWorkspace } from "@/components/exam/exam-workspace";

export default async function StudentExamDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return (
    <main className="exam-fullscreen-page">
      <div className="exam-fullscreen-header">
        <div>
          <span className="badge">Mode Ujian</span>
          <h1>Halaman Ujian</h1>
        </div>
        <p className="muted">Kerjakan soal dengan fokus. Jawaban tersimpan otomatis selama ujian berlangsung.</p>
      </div>
      <ExamWorkspace examId={Number(id)} />
    </main>
  );
}
