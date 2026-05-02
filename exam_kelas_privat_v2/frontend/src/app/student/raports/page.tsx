"use client";

import { useEffect, useMemo, useState } from "react";
import { BookOpen, FileSpreadsheet, Printer } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch, downloadApiFile } from "@/lib/api";

type RaportSubject = {
  name?: string;
  score?: number;
  grade?: string;
  kkm?: number;
  is_passed?: boolean;
  breakdown?: Record<string, { average?: number; count?: number; weight?: number }>;
};

type Raport = {
  id: number;
  academic_year: string;
  semester: string;
  overall_score: number;
  overall_grade: string;
  overall_passed: boolean;
  status: string;
  generated_at?: string | null;
  published_at?: string | null;
  subjects_data?: RaportSubject[] | null;
};

function formatDate(value?: string | null) {
  return value?.slice(0, 19).replace("T", " ") ?? "-";
}

function formatScore(value?: number) {
  return typeof value === "number" ? value.toFixed(2).replace(/\.00$/, "") : "-";
}

export default function StudentRaportsPage() {
  const [items, setItems] = useState<Raport[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<Raport | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<{ items: Raport[] }>("/api/student/raports")
      .then((data) => {
        setItems(data.items);
        setSelectedId(data.items[0]?.id ?? null);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat raport"));
  }, []);

  useEffect(() => {
    if (!selectedId) {
      return;
    }
    apiFetch<{ item: Raport }>(`/api/student/raports/${selectedId}`)
      .then((data) => setDetail(data.item))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat detail raport"));
  }, [selectedId]);

  const summary = useMemo(() => {
    const published = items.length;
    const passed = items.filter((item) => item.overall_passed).length;
    const average = published
      ? items.reduce((total, item) => total + item.overall_score, 0) / published
      : 0;
    return { published, passed, average };
  }, [items]);

  const subjects = Array.isArray(detail?.subjects_data) ? detail.subjects_data : [];

  return (
    <AppShell
      title="Raport Saya"
      description="Lihat raport yang sudah dipublish sekolah beserta rincian nilai per mapel."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}

      <div className="card-grid" style={{ marginBottom: 16 }}>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <FileSpreadsheet size={18} />
          </div>
          <div className="muted">Raport dipublish</div>
          <div className="stat-value">{summary.published}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon green">
            <BookOpen size={18} />
          </div>
          <div className="muted">Raport tuntas</div>
          <div className="stat-value">{summary.passed}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon purple">
            <FileSpreadsheet size={18} />
          </div>
          <div className="muted">Rata-rata nilai akhir</div>
          <div className="stat-value">{formatScore(summary.average)}</div>
        </div>
      </div>

      <div className="attendance-grid">
        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>Daftar raport</h3>
              <p className="muted">Pilih tahun ajaran dan semester untuk melihat rincian nilai.</p>
            </div>
          </div>
          <div className="compact-list">
            {items.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`attendance-class-button ${selectedId === item.id ? "active" : ""}`}
                onClick={() => setSelectedId(item.id)}
              >
                <strong>
                  {item.academic_year} - {item.semester}
                </strong>
                <span className="muted">Dipublish: {formatDate(item.published_at)}</span>
                <span className={`status-pill ${item.overall_passed ? "success" : "warning"}`}>
                  {item.overall_passed ? "Tuntas" : "Belum tuntas"} - {formatScore(item.overall_score)}
                </span>
              </button>
            ))}
            {items.length === 0 ? (
              <div className="empty-state">Belum ada raport yang dipublish untuk akun ini.</div>
            ) : null}
          </div>
        </div>

        <div className="panel data-card">
          {detail ? (
            <div className="detail-stack">
              <div className="section-heading-inline">
                <div>
                  <h3>
                    Raport {detail.academic_year} - {detail.semester}
                  </h3>
                  <p className="muted">
                    Dibuat {formatDate(detail.generated_at)} • Dipublish {formatDate(detail.published_at)}
                  </p>
                </div>
                <div className="button-row">
                  <button className="button-secondary" type="button" onClick={() => window.print()}>
                    <Printer size={16} />
                    Print
                  </button>
                  <button
                    className="button-secondary"
                    type="button"
                    onClick={() =>
                      void downloadApiFile(`/api/student/raports/${detail.id}/print`, `raport-${detail.id}.pdf`)
                    }
                  >
                    <FileSpreadsheet size={16} />
                    PDF
                  </button>
                </div>
              </div>

              <div className="results-grid">
                <article className="result-card">
                  <div className="meta-row">
                    <span className="meta-key">Nilai akhir</span>
                    <span className="meta-value">{formatScore(detail.overall_score)}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Grade</span>
                    <span className="meta-value">{detail.overall_grade}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Status</span>
                    <span className="meta-value">{detail.overall_passed ? "Tuntas" : "Belum tuntas"}</span>
                  </div>
                </article>
              </div>

              <div className="section-heading-inline">
                <div>
                  <h3>Rincian mapel</h3>
                  <p className="muted">Nilai berasal dari breakdown hasil ujian berbobot per tipe ujian.</p>
                </div>
              </div>
              <div className="results-grid">
                {subjects.map((subject, index) => (
                  <article className="result-card" key={`${subject.name ?? "mapel"}-${index}`}>
                    <div className="result-card-header">
                      <div>
                        <h3>{subject.name ?? "Mapel"}</h3>
                        <p className="muted">KKM {subject.kkm ?? 75}</p>
                      </div>
                      <span className={`status-pill ${subject.is_passed ? "success" : "warning"}`}>
                        {subject.grade ?? "-"}
                      </span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Nilai mapel</span>
                      <span className="meta-value">{formatScore(subject.score)}</span>
                    </div>
                    {Object.entries(subject.breakdown ?? {}).map(([examType, value]) => (
                      <div className="meta-row" key={examType}>
                        <span className="meta-key">{examType.replaceAll("_", " ")}</span>
                        <span className="meta-value">
                          {formatScore(value.average)} ({value.count ?? 0}x, bobot {value.weight ?? 0})
                        </span>
                      </div>
                    ))}
                  </article>
                ))}
                {subjects.length === 0 ? (
                  <div className="empty-state">Belum ada rincian mapel pada raport ini.</div>
                ) : null}
              </div>
            </div>
          ) : (
            <div className="empty-state">Pilih raport untuk melihat detail.</div>
          )}
        </div>
      </div>
    </AppShell>
  );
}
