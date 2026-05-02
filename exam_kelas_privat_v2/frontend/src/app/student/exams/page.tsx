"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type ExamsData = {
  assignments: Array<{
    id: number;
    exam_id: number;
    attempt: number;
    total_attempt: number;
  }>;
  exams: Array<{
    id: number;
    title: string;
    status: string;
    duration: number;
  }>;
};

export default function StudentExamsPage() {
  const [data, setData] = useState<ExamsData | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<ExamsData>("/api/student/exams")
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat ujian"));
  }, []);

  return (
    <AppShell
      title="Ujian Saya"
      description="Lihat ujian yang tersedia dan mulai ujian sesuai jadwal."
    >
      {error ? <div className="panel data-card">{error}</div> : null}
      <div className="panel data-card">
        <div className="list">
          {(data?.exams ?? []).map((exam) => {
            const assignment = data?.assignments.find((item) => item.exam_id === exam.id);
            return (
              <div key={exam.id} className="list-item">
                <h3>{exam.title}</h3>
                <p className="muted">
                  Status: {exam.status} • Durasi: {exam.duration} menit • Attempt:{" "}
                  {assignment?.attempt ?? 0}/{assignment?.total_attempt ?? 0}
                </p>
                <Link className="button" href={`/student/exams/${exam.id}`}>
                  Mulai Ujian
                </Link>
              </div>
            );
          })}
        </div>
      </div>
    </AppShell>
  );
}
