"use client";

import { useCallback, useEffect, useState } from "react";
import { Brain, CheckCircle2, RefreshCw, RotateCcw, Wand2 } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type AIStats = {
  total: number;
  pending: number;
  graded: number;
};

type EssayItem = {
  id: number;
  exam_result_id: number;
  exam_id: number;
  user_id: number;
  question_id: number;
  student_answer: string;
  answer: string;
  correct_answer: string;
  points_earned: number;
  max_points: number;
  is_graded: boolean;
  is_ai_scheduler: boolean;
  ai_score_suggested: number;
  ai_type?: string | null;
  additional_data?: {
    ai_scoring_audit?: Array<{
      at?: string;
      model?: string;
      score?: number;
      source?: string;
    }>;
  } | null;
  updated_at?: string | null;
};

export default function AdminAIScoringPage() {
  const [stats, setStats] = useState<AIStats | null>(null);
  const [items, setItems] = useState<EssayItem[]>([]);
  const [processingId, setProcessingId] = useState<number | "queue" | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [statsData, listData] = await Promise.all([
      apiFetch<AIStats>("/api/admin/ai-scoring/stats"),
      apiFetch<{ items: EssayItem[] }>("/api/admin/ai-scoring"),
    ]);
    setStats(statsData);
    setItems(listData.items);
  }, []);

  useEffect(() => {
    Promise.resolve()
      .then(load)
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat statistik AI"));
  }, [load]);

  async function runQueue() {
    setError(null);
    setMessage(null);
    setProcessingId("queue");
    try {
      const data = await apiFetch<{ processed: number }>("/api/admin/ai-scoring/score-multiple", {
        method: "POST",
        body: JSON.stringify({}),
      });
      setMessage(`AI scoring diproses untuk ${data.processed} essay.`);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menjalankan AI scoring");
    } finally {
      setProcessingId(null);
    }
  }

  async function scoreOne(id: number) {
    setError(null);
    setMessage(null);
    setProcessingId(id);
    try {
      const data = await apiFetch<{ suggested_score: number; ai_type?: string }>(
        `/api/admin/ai-scoring/score-essay/${id}`,
        { method: "POST" },
      );
      setMessage(`Essay #${id} dinilai AI: ${data.suggested_score} (${data.ai_type ?? "provider"})`);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menjalankan scoring essay");
    } finally {
      setProcessingId(null);
    }
  }

  async function resetOne(id: number) {
    setError(null);
    setMessage(null);
    setProcessingId(id);
    try {
      await apiFetch(`/api/admin/ai-scoring/reset-scoring/${id}`, { method: "POST" });
      setMessage(`Scoring essay #${id} direset.`);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal reset scoring essay");
    } finally {
      setProcessingId(null);
    }
  }

  return (
    <AppShell title="AI Scoring" description="Kelola queue dan status penilaian essay otomatis.">
      {message ? <div className="inline-alert">{message}</div> : null}
      {error ? <div className="inline-alert danger">{error}</div> : null}
      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon purple">
            <Brain size={18} />
          </div>
          <div className="muted">Essay pending</div>
          <div className="stat-value">{stats?.pending ?? 0}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon green">
            <CheckCircle2 size={18} />
          </div>
          <div className="muted">Essay sudah dinilai</div>
          <div className="stat-value">{stats?.graded ?? 0}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <Brain size={18} />
          </div>
          <div className="muted">Total essay</div>
          <div className="stat-value">{stats?.total ?? 0}</div>
        </div>
      </div>
      <div className="button-row" style={{ marginBottom: 16 }}>
        <button className="button" type="button" disabled={processingId !== null} onClick={() => void runQueue()}>
          <RefreshCw size={16} />
          {processingId === "queue" ? "Memproses queue..." : "Jalankan scoring queue"}
        </button>
      </div>

      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Monitoring essay terbaru</h3>
            <p className="muted">
              Pantau provider AI, skor saran, status grading, dan jalankan ulang scoring per essay.
            </p>
          </div>
        </div>
        <div className="compact-list">
          {items.map((item) => {
            const answer = item.student_answer || item.answer || "-";
            return (
              <article className="compact-list-item" key={item.id}>
                <div className="result-card-header">
                  <div>
                    <span className={`status-pill ${item.is_graded ? "success" : "warning"}`}>
                      {item.is_graded ? "Sudah dinilai" : "Pending"}
                    </span>
                    <h3 style={{ margin: "8px 0 4px" }}>Essay #{item.id}</h3>
                    <p className="muted" style={{ margin: 0 }}>
                      Result #{item.exam_result_id} • Exam #{item.exam_id} • User #{item.user_id} • Question #
                      {item.question_id}
                    </p>
                  </div>
                  <div className="button-row">
                    <button
                      className="button-secondary"
                      type="button"
                      disabled={processingId !== null}
                      onClick={() => void scoreOne(item.id)}
                    >
                      <Wand2 size={16} />
                      Score
                    </button>
                    <button
                      className="button-secondary"
                      type="button"
                      disabled={processingId !== null}
                      onClick={() => void resetOne(item.id)}
                    >
                      <RotateCcw size={16} />
                      Reset
                    </button>
                  </div>
                </div>
                <div className="results-grid">
                  <div className="result-card">
                    <div className="meta-row">
                      <span className="meta-key">Skor tersimpan</span>
                      <span className="meta-value">
                        {item.points_earned} / {item.max_points}
                      </span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Saran AI</span>
                      <span className="meta-value">{item.ai_score_suggested || "-"}</span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Provider</span>
                      <span className="meta-value">{item.ai_type ?? "-"}</span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Update</span>
                      <span className="meta-value">{item.updated_at?.slice(0, 19).replace("T", " ") ?? "-"}</span>
                    </div>
                  </div>
                  <div className="result-card">
                    <strong>Jawaban siswa</strong>
                    <p className="muted" style={{ margin: 0, whiteSpace: "pre-wrap" }}>
                      {answer.slice(0, 700)}
                      {answer.length > 700 ? "..." : ""}
                    </p>
                  </div>
                  <div className="result-card">
                    <strong>Audit AI</strong>
                    <div className="compact-list">
                      {(item.additional_data?.ai_scoring_audit ?? []).slice(-4).map((audit, index) => (
                        <div className="meta-row" key={`${audit.at ?? "audit"}-${index}`}>
                          <span className="meta-key">{audit.at?.slice(0, 19).replace("T", " ") ?? "-"}</span>
                          <span className="meta-value">
                            {audit.source ?? audit.model ?? "ai"}: {audit.score ?? "-"}
                          </span>
                        </div>
                      ))}
                      {item.additional_data?.ai_scoring_audit?.length ? null : (
                        <p className="muted" style={{ margin: 0 }}>Belum ada audit scoring.</p>
                      )}
                    </div>
                  </div>
                </div>
              </article>
            );
          })}
          {items.length === 0 ? <div className="empty-state">Belum ada essay untuk dimonitor.</div> : null}
        </div>
      </div>
    </AppShell>
  );
}
