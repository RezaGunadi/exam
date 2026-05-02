"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, Clock4, History, RotateCcw } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type AttemptItem = {
  id: number;
  exam_id: number;
  user_id: number;
  attempt: number;
  total_attempt: number;
  is_active: boolean;
  exam?: { title?: string };
  user?: { name?: string; email?: string };
};

type AttemptDetails = {
  remaining_attempt: number;
  cheating_history: Array<Record<string, unknown>>;
  exam_results: Array<Record<string, unknown>>;
};

export default function AttemptManagementPage() {
  const [items, setItems] = useState<AttemptItem[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<AttemptDetails | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const loadItems = () => {
    apiFetch<{ items: AttemptItem[] }>("/api/admin/attempt-management")
      .then((data) => {
        setItems(data.items);
        setSelectedId((current) => current ?? data.items[0]?.id ?? null);
      })
      .catch((error) =>
        setMessage(error instanceof Error ? error.message : "Gagal memuat attempt management"),
      );
  };

  useEffect(() => {
    loadItems();
  }, []);

  useEffect(() => {
    if (!selectedId) {
      return;
    }
    apiFetch<AttemptDetails>(`/api/admin/attempt-management/${selectedId}/details`)
      .then(setDetail)
      .catch((error) =>
        setMessage(error instanceof Error ? error.message : "Gagal memuat detail attempt"),
      );
  }, [selectedId]);

  const resetAttempt = async (assignmentId: number) => {
    try {
      const response = await apiFetch<{ message?: string }>("/api/admin/attempt-management/reset", {
        method: "POST",
        body: JSON.stringify({ assignment_id: assignmentId }),
      });
      setMessage(response.message ?? "Attempt berhasil direset.");
      loadItems();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Gagal reset attempt");
    }
  };

  const toggleActive = async (assignmentId: number) => {
    try {
      const response = await apiFetch<{ message?: string }>(
        `/api/admin/attempt-management/${assignmentId}/toggle-active`,
        {
          method: "POST",
        },
      );
      setMessage(response.message ?? "Status attempt diperbarui.");
      loadItems();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Gagal mengubah status attempt");
    }
  };

  return (
    <AppShell
      title="Manajemen Attempt"
      description="Lihat kesempatan ujian siswa, reset attempt, dan periksa riwayat ujian."
    >
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="two-column-section">
        <div className="panel data-card">
          <h2>Daftar Attempt</h2>
          <div className="list">
            {items.map((item) => (
              <div
                key={item.id}
                className={`list-item attempt-card ${selectedId === item.id ? "selected" : ""}`}
              >
                <button
                  className="attempt-select"
                  type="button"
                  onClick={() => setSelectedId(item.id)}
                >
                  <strong>{item.user?.name ?? `User #${item.user_id}`}</strong>
                  <span className="muted">{item.exam?.title ?? `Exam #${item.exam_id}`}</span>
                  <span className="muted">
                    Attempt {item.attempt}/{item.total_attempt}
                  </span>
                </button>
                <div className="button-row">
                  <button className="button-secondary" onClick={() => toggleActive(item.id)}>
                    {item.is_active ? "Nonaktifkan" : "Aktifkan"}
                  </button>
                  <button className="button" onClick={() => resetAttempt(item.id)}>
                    Reset
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="panel data-card">
          <h2>Detail Attempt</h2>
          {detail ? (
            <>
              <div className="card-grid">
                <div className="panel stat-card stat-card-soft">
                  <div className="stat-icon blue">
                    <RotateCcw size={18} />
                  </div>
                  <div className="muted">Sisa attempt</div>
                  <div className="stat-value">{detail.remaining_attempt}</div>
                </div>
                <div className="panel stat-card stat-card-soft">
                  <div className="stat-icon purple">
                    <History size={18} />
                  </div>
                  <div className="muted">Riwayat result</div>
                  <div className="stat-value">{detail.exam_results.length}</div>
                </div>
              </div>
              <div className="detail-stack">
                <div className="button-row">
                  <div className="stat-icon orange">
                    <AlertTriangle size={18} />
                  </div>
                  <h3>Riwayat pelanggaran</h3>
                </div>
                <div className="compact-list">
                  {detail.cheating_history.map((row, index) => (
                    <div key={index} className="compact-list-item">
                      <div className="meta-row">
                        <span className="meta-key">Status</span>
                        <span className="meta-value">{String(row.status ?? "-")}</span>
                      </div>
                      <div className="meta-row">
                        <span className="meta-key">Mulai</span>
                        <span className="meta-value">{String(row.started_at ?? "-")}</span>
                      </div>
                      <div className="meta-row">
                        <span className="meta-key">Pelanggaran</span>
                        <span className="meta-value">
                          {Array.isArray(row.cheating_entries) ? row.cheating_entries.length : 0}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
              <div className="detail-stack">
                <div className="button-row">
                  <div className="stat-icon green">
                    <Clock4 size={18} />
                  </div>
                  <h3>Riwayat hasil ujian</h3>
                </div>
                <div className="compact-list">
                  {detail.exam_results.map((row, index) => {
                    const item = row as Record<string, unknown>;
                    return (
                      <div key={index} className="compact-list-item">
                        <div className="meta-row">
                          <span className="meta-key">Status</span>
                          <span className="meta-value">{String(item.status ?? "-")}</span>
                        </div>
                        <div className="meta-row">
                          <span className="meta-key">Score</span>
                          <span className="meta-value">{String(item.score ?? "-")}</span>
                        </div>
                        <div className="meta-row">
                          <span className="meta-key">Mulai</span>
                          <span className="meta-value">{String(item.started_at ?? "-")}</span>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </>
          ) : (
            <div className="empty-state">Pilih assignment untuk melihat detail.</div>
          )}
        </div>
      </div>
    </AppShell>
  );
}
