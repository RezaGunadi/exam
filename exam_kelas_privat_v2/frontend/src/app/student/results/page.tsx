"use client";

import { useEffect, useMemo, useState } from "react";
import { FileText, Printer, Search } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch, downloadApiFile } from "@/lib/api";

type ResultItem = {
  id: number;
  exam_id: number;
  status: string;
  score: number;
  pg_score: number;
  essay_score: number;
  completed_at?: string | null;
};

type AnswerItem = {
  question_id: number;
  question_type: string;
  student_answer: string;
  correct_answer: string;
  points_earned: number;
  max_points: number;
};

export default function StudentResultsPage() {
  const [items, setItems] = useState<ResultItem[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [answers, setAnswers] = useState<AnswerItem[]>([]);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [minScore, setMinScore] = useState("");
  const [maxScore, setMaxScore] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<{ items: ResultItem[] }>("/api/student/results")
      .then((data) => {
        setItems(data.items);
        setSelectedId(data.items[0]?.id ?? null);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat hasil ujian"));
  }, []);

  useEffect(() => {
    if (!selectedId) {
      return;
    }
    apiFetch<{ answers: AnswerItem[] }>(`/api/student/results/${selectedId}`)
      .then((data) => setAnswers(data.answers))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat detail hasil"));
  }, [selectedId]);

  const filteredItems = useMemo(() => {
    return items.filter((item) => {
      const keyword = search.trim().toLowerCase();
      const matchesSearch = !keyword || `result ${item.id} exam ${item.exam_id}`.includes(keyword);
      const matchesStatus = statusFilter === "all" || item.status === statusFilter;
      const min = minScore === "" ? Number.NEGATIVE_INFINITY : Number(minScore);
      const max = maxScore === "" ? Number.POSITIVE_INFINITY : Number(maxScore);
      return matchesSearch && matchesStatus && item.score >= min && item.score <= max;
    });
  }, [items, maxScore, minScore, search, statusFilter]);

  return (
    <AppShell
      title="Hasil Ujian"
      description="Lihat nilai dan hasil ujian yang sudah dikerjakan."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}

      <div className="panel data-card" style={{ marginBottom: 16 }}>
        <div className="section-heading-inline">
          <div>
            <h3>Filter hasil ujian</h3>
            <p className="muted">Cari dan saring hasil seperti halaman Blade siswa.</p>
          </div>
          <Search size={18} />
        </div>
        <div className="resource-form-grid">
          <label className="field">
            <span>Pencarian</span>
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Result / Exam" />
          </label>
          <label className="field">
            <span>Status</span>
            <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
              <option value="all">Semua</option>
              <option value="completed">Completed</option>
              <option value="timeout">Timeout</option>
              <option value="disconnected">Disconnected</option>
              <option value="in_progress">In progress</option>
            </select>
          </label>
          <label className="field">
            <span>Nilai minimal</span>
            <input type="number" value={minScore} onChange={(event) => setMinScore(event.target.value)} />
          </label>
          <label className="field">
            <span>Nilai maksimal</span>
            <input type="number" value={maxScore} onChange={(event) => setMaxScore(event.target.value)} />
          </label>
        </div>
      </div>

      <div className="attendance-grid">
        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>Daftar hasil ujian</h3>
              <p className="muted">Pilih hasil untuk melihat ringkasan jawaban dan score.</p>
            </div>
          </div>
          <div className="compact-list">
            {filteredItems.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`attendance-class-button ${selectedId === item.id ? "active" : ""}`}
                onClick={() => setSelectedId(item.id)}
              >
                <strong>Result #{item.id}</strong>
                <span className="muted">Exam #{item.exam_id}</span>
                <span className={`status-pill ${item.status === "completed" ? "success" : item.status === "timeout" ? "warning" : "danger"}`}>
                  {item.status}
                </span>
              </button>
            ))}
          </div>
        </div>

        <div className="panel data-card">
          {selectedId ? (
            <div className="detail-stack">
              <div className="section-heading-inline">
                <div>
                  <h3>Ringkasan hasil</h3>
                  <p className="muted">Periksa score total, score PG, score essay, dan jawaban tersimpan.</p>
                </div>
                <button
                  type="button"
                  className="button-secondary"
                  onClick={() =>
                    void downloadApiFile(
                      `/api/student/results/${selectedId}/answer-sheet.pdf`,
                      `answer-sheet-result-${selectedId}.pdf`,
                    )
                  }
                >
                  <FileText size={16} />
                  Unduh lembar jawaban (PDF)
                </button>
                <button className="button-secondary" type="button" onClick={() => window.print()}>
                  <Printer size={16} />
                  Print
                </button>
              </div>
              {items
                .filter((item) => item.id === selectedId)
                .map((item) => (
                  <div key={item.id} className="results-grid">
                    <article className="result-card">
                      <div className="meta-row">
                        <span className="meta-key">Score total</span>
                        <span className="meta-value">{item.score}</span>
                      </div>
                      <div className="meta-row">
                        <span className="meta-key">PG</span>
                        <span className="meta-value">{item.pg_score}</span>
                      </div>
                      <div className="meta-row">
                        <span className="meta-key">Essay</span>
                        <span className="meta-value">{item.essay_score}</span>
                      </div>
                      <div className="meta-row">
                        <span className="meta-key">Selesai</span>
                        <span className="meta-value">
                          {item.completed_at?.slice(0, 19).replace("T", " ") ?? "-"}
                        </span>
                      </div>
                    </article>
                  </div>
                ))}
              <div className="section-heading-inline">
                <div>
                  <h3>Jawaban</h3>
                  <p className="muted">Lihat jawaban yang tersimpan untuk hasil ini.</p>
                </div>
              </div>
              <div className="results-grid">
                {answers.map((answer) => (
                  <article key={`${answer.question_id}-${answer.question_type}`} className="result-card">
                    <div className="meta-row">
                      <span className="meta-key">Question ID</span>
                      <span className="meta-value">{answer.question_id}</span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Tipe</span>
                      <span className="meta-value">{answer.question_type}</span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Jawaban saya</span>
                      <span className="meta-value">{answer.student_answer || "-"}</span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Skor</span>
                      <span className="meta-value">
                        {answer.points_earned} / {answer.max_points}
                      </span>
                    </div>
                  </article>
                ))}
              </div>
            </div>
          ) : (
            <div className="empty-state">Belum ada hasil ujian yang tersedia.</div>
          )}
        </div>
      </div>
    </AppShell>
  );
}
