"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Download, FileSpreadsheet, FileText, Mail, PenSquare, Save, Shield, Trophy } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch, downloadApiFile } from "@/lib/api";

type ExamResultItem = {
  id: number;
  exam_id: number;
  user_id: number;
  status: string;
  score: number;
  pg_score: number;
  essay_score: number;
  notes?: string | null;
  cheating_note?: string | null;
  proctor_snapshots?: unknown;
  completed_at?: string | null;
};

type AnswerItem = {
  question_id: number;
  question_type: string;
  student_answer: string;
  correct_answer: string;
  points_earned: number;
  max_points: number;
  is_graded: boolean;
};

export default function AdminExamResultsPage() {
  const [items, setItems] = useState<ExamResultItem[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [selectedResult, setSelectedResult] = useState<ExamResultItem | null>(null);
  const [answers, setAnswers] = useState<AnswerItem[]>([]);
  const [notes, setNotes] = useState("");
  const [essayScores, setEssayScores] = useState<Record<string, number>>({});
  const [emailTarget, setEmailTarget] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const loadResults = useCallback(() => {
    apiFetch<{ items: ExamResultItem[] }>("/api/admin/exam-results")
      .then((data) => {
        const resultItems = Array.isArray(data.items) ? data.items : [];
        setItems(resultItems);
        setSelectedId((current) => current ?? resultItems[0]?.id ?? null);
      })
      .catch((err) => {
        setError(err instanceof Error ? err.message : "Gagal memuat hasil ujian");
      });
  }, []);

  useEffect(() => {
    void loadResults();
  }, [loadResults]);

  useEffect(() => {
    if (!selectedId) {
      return;
    }
    apiFetch<{ item: ExamResultItem; answers: AnswerItem[] }>(`/api/admin/exam-results/${selectedId}`)
      .then((data) => {
        setSelectedResult(data.item);
        setAnswers(data.answers);
        setNotes(data.item.notes ?? "");
        setEssayScores(
          Object.fromEntries(
            data.answers
              .filter((answer) => answer.question_type === "essay")
              .map((answer) => [String(answer.question_id), answer.points_earned]),
          ),
        );
      })
      .catch((err) => {
        setError(err instanceof Error ? err.message : "Gagal memuat detail hasil ujian");
      });
  }, [selectedId]);

  const essayAnswers = useMemo(
    () => answers.filter((answer) => answer.question_type === "essay"),
    [answers],
  );

  async function saveNotes() {
    if (!selectedResult) {
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch(`/api/admin/exam-results/${selectedResult.id}/notes`, {
        method: "PUT",
        body: JSON.stringify({ notes }),
      });
      setMessage("Catatan hasil berhasil diperbarui.");
      await loadResults();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan catatan");
    } finally {
      setSaving(false);
    }
  }

  async function saveEssayScores() {
    if (!selectedResult) {
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch(`/api/admin/exam-results/${selectedResult.id}/essay-scores`, {
        method: "PUT",
        body: JSON.stringify({ essay_scores: essayScores }),
      });
      setMessage("Nilai essay berhasil diperbarui.");
      await loadResults();
      const refreshed = await apiFetch<{ item: ExamResultItem; answers: AnswerItem[] }>(
        `/api/admin/exam-results/${selectedResult.id}`,
      );
      setSelectedResult(refreshed.item);
      setAnswers(refreshed.answers);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan nilai essay");
    } finally {
      setSaving(false);
    }
  }

  async function sendAnswerSheetEmail() {
    if (!selectedResult || !emailTarget.trim()) {
      setError("Email tujuan wajib diisi.");
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/admin/exam-results/send-answer-sheets-email", {
        method: "POST",
        body: JSON.stringify({ email: emailTarget.trim(), ids: [selectedResult.id] }),
      });
      setMessage("Permintaan kirim lembar jawaban ke email sudah diproses.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal mengirim email lembar jawaban");
    } finally {
      setSaving(false);
    }
  }

  return (
    <AppShell
      title="Hasil Ujian"
      description="Lihat hasil ujian siswa, periksa nilai, dan unduh data hasil ujian."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon green">
            <Trophy size={18} />
          </div>
          <div className="muted">Total hasil</div>
          <div className="stat-value">{items.length}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <FileSpreadsheet size={18} />
          </div>
          <div className="muted">Ekspor</div>
          <div className="button-row" style={{ marginTop: 8 }}>
            <button
              className="button-secondary"
              onClick={() => void downloadApiFile("/api/admin/exam-results/export.csv", "exam-results.csv")}
            >
              <Download size={16} />
              Export CSV
            </button>
            <button
              className="button-secondary"
              onClick={() => void downloadApiFile("/api/admin/exam-results/export.xlsx", "exam-results.xlsx")}
            >
              <Download size={16} />
              Export Excel
            </button>
          </div>
        </div>
      </div>

      <div className="attendance-grid">
        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>Daftar hasil</h3>
              <p className="muted">Pilih hasil ujian untuk melihat detail jawaban, catatan, dan nilai essay.</p>
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
                <strong>Result #{item.id}</strong>
                <span className="muted">Exam #{item.exam_id} • User #{item.user_id}</span>
                <span className={`status-pill ${item.status === "completed" ? "success" : item.status === "timeout" ? "warning" : "danger"}`}>
                  {item.status}
                </span>
              </button>
            ))}
          </div>
        </div>

        <div className="panel data-card">
          {selectedResult ? (
            <div className="detail-stack">
              <div className="section-heading-inline">
                <div>
                  <h3>Detail hasil ujian</h3>
                  <p className="muted">Periksa score, koreksi essay, dan simpan catatan admin.</p>
                </div>
              </div>
              <div className="results-grid">
                <article className="result-card">
                  <div className="result-card-header">
                    <div className="button-row">
                      <div className="stat-icon purple">
                        <PenSquare size={18} />
                      </div>
                      <div>
                        <h3>Ringkasan result #{selectedResult.id}</h3>
                        <p className="muted">Exam #{selectedResult.exam_id} • User #{selectedResult.user_id}</p>
                      </div>
                    </div>
                    <span className={`status-pill ${selectedResult.status === "completed" ? "success" : selectedResult.status === "timeout" ? "warning" : "danger"}`}>
                      {selectedResult.status}
                    </span>
                  </div>
                  <div className="button-row" style={{ marginTop: 8 }}>
                    <button
                      type="button"
                      className="button-secondary"
                      onClick={() =>
                        void downloadApiFile(
                          `/api/admin/exam-results/${selectedResult.id}/answer-sheet.pdf`,
                          `answer-sheet-result-${selectedResult.id}.pdf`,
                        )
                      }
                    >
                      <FileText size={16} />
                      Unduh lembar jawaban (PDF)
                    </button>
                    <button
                      type="button"
                      className="button"
                      onClick={async () => {
                        await apiFetch(`/api/admin/exam-results/${selectedResult.id}/mark-as-finished`, {
                          method: "POST",
                          body: JSON.stringify({}),
                        });
                        setMessage("Hasil ujian ditandai selesai.");
                        await loadResults();
                      }}
                    >
                      Tandai selesai
                    </button>
                  </div>
                  <div className="button-row" style={{ marginTop: 10 }}>
                    <label className="field" style={{ minWidth: 260 }}>
                      <span>Email tujuan lembar jawaban</span>
                      <input
                        value={emailTarget}
                        onChange={(event) => setEmailTarget(event.target.value)}
                        placeholder="admin@sekolah.com"
                      />
                    </label>
                    <button
                      type="button"
                      className="button-secondary"
                      disabled={saving}
                      onClick={() => void sendAnswerSheetEmail()}
                    >
                      <Mail size={16} />
                      Kirim via email
                    </button>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Score total</span>
                    <span className="meta-value">{selectedResult.score}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">PG</span>
                    <span className="meta-value">{selectedResult.pg_score}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Essay</span>
                    <span className="meta-value">{selectedResult.essay_score}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Selesai</span>
                    <span className="meta-value">
                      {selectedResult.completed_at?.slice(0, 19).replace("T", " ") ?? "-"}
                    </span>
                  </div>
                </article>
              </div>

              <div className="panel data-card">
                <div className="section-heading-inline">
                  <div>
                    <h3>Proctoring dan catatan kecurangan</h3>
                    <p className="muted">Tinjau snapshot dan event yang terekam selama siswa mengerjakan ujian.</p>
                  </div>
                  <Shield size={18} />
                </div>
                <div className="meta-row">
                  <span className="meta-key">Catatan curang</span>
                  <span className="meta-value">{selectedResult.cheating_note?.trim() || "-"}</span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Snapshot proctor</span>
                  <span className="meta-value">
                    {selectedResult.proctor_snapshots
                      ? JSON.stringify(selectedResult.proctor_snapshots).slice(0, 900)
                      : "-"}
                  </span>
                </div>
              </div>

              <div className="panel data-card">
                <div className="section-heading-inline">
                  <div>
                    <h3>Catatan admin</h3>
                    <p className="muted">Tambahkan catatan pemeriksaan untuk hasil ujian ini.</p>
                  </div>
                </div>
                <label className="field">
                  <span>Catatan</span>
                  <textarea rows={4} value={notes} onChange={(event) => setNotes(event.target.value)} />
                </label>
                <div className="button-row">
                  <button className="button" type="button" disabled={saving} onClick={() => void saveNotes()}>
                    <Save size={16} />
                    Simpan catatan
                  </button>
                </div>
              </div>

              <div className="panel data-card">
                <div className="section-heading-inline">
                  <div>
                    <h3>Jawaban essay</h3>
                    <p className="muted">Nilai ulang jawaban essay dan simpan skor per soal.</p>
                  </div>
                </div>
                {essayAnswers.length === 0 ? (
                  <div className="empty-state">Tidak ada jawaban essay pada hasil ini.</div>
                ) : (
                  <div className="results-grid">
                    {essayAnswers.map((answer) => (
                      <article key={answer.question_id} className="result-card">
                        <div className="meta-row">
                          <span className="meta-key">Question ID</span>
                          <span className="meta-value">{answer.question_id}</span>
                        </div>
                        <div className="meta-row">
                          <span className="meta-key">Jawaban siswa</span>
                          <span className="meta-value">{answer.student_answer || "-"}</span>
                        </div>
                        <div className="meta-row">
                          <span className="meta-key">Jawaban acuan</span>
                          <span className="meta-value">{answer.correct_answer || "-"}</span>
                        </div>
                        <label className="field">
                          <span>Nilai essay</span>
                          <input
                            type="number"
                            min={0}
                            max={answer.max_points}
                            value={essayScores[String(answer.question_id)] ?? 0}
                            onChange={(event) =>
                              setEssayScores((prev) => ({
                                ...prev,
                                [String(answer.question_id)]: Number(event.target.value),
                              }))
                            }
                          />
                        </label>
                      </article>
                    ))}
                  </div>
                )}
                {essayAnswers.length > 0 ? (
                  <div className="button-row">
                    <button className="button" type="button" disabled={saving} onClick={() => void saveEssayScores()}>
                      <Save size={16} />
                      Simpan nilai essay
                    </button>
                  </div>
                ) : null}
              </div>

              <div className="panel data-card">
                <div className="section-heading-inline">
                  <div>
                    <h3>Jawaban tersimpan</h3>
                    <p className="muted">Lihat semua jawaban yang sudah masuk untuk result ini.</p>
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
                        <span className="meta-key">Jawaban siswa</span>
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
            </div>
          ) : (
            <div className="empty-state">Pilih hasil ujian terlebih dahulu.</div>
          )}
        </div>
      </div>
    </AppShell>
  );
}
