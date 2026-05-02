"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { CheckCircle2, ClipboardList, Save, Search, Star } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type TaskItem = {
  id: number;
  class_id: number;
  title: string;
  description?: string | null;
  created_at?: string | null;
};

type TaskDetail = {
  item: TaskItem;
  submission?: {
    text?: string | null;
    nilai?: number | null;
    note?: string | null;
    updated_at?: string | null;
  };
};

export default function StudentTasksPage() {
  const [items, setItems] = useState<TaskItem[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<TaskDetail | null>(null);
  const [text, setText] = useState("");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    apiFetch<{ items: TaskItem[] }>("/api/student/tasks")
      .then((data) => {
        setItems(data.items);
        setSelectedId(data.items[0]?.id ?? null);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat tugas siswa"));
  }, []);

  useEffect(() => {
    if (!selectedId) {
      return;
    }
    apiFetch<TaskDetail>(`/api/student/tasks/${selectedId}`)
      .then((data) => {
        setDetail(data);
        setText(data.submission?.text ?? "");
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat detail tugas"));
  }, [selectedId]);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedId) {
      return;
    }
    setSaving(true);
    setMessage(null);
    setError(null);
    try {
      await apiFetch(`/api/student/tasks/${selectedId}/submit`, {
        method: "POST",
        body: JSON.stringify({ text, files: [] }),
      });
      setMessage("Tugas berhasil dikumpulkan.");
      const refreshed = await apiFetch<TaskDetail>(`/api/student/tasks/${selectedId}`);
      setDetail(refreshed);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal mengumpulkan tugas");
    } finally {
      setSaving(false);
    }
  }

  const filteredItems = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    return items.filter((item) => {
      const matchesSearch =
        !keyword || `${item.title} ${item.description ?? ""} task ${item.id}`.toLowerCase().includes(keyword);
      if (!matchesSearch) {
        return false;
      }
      if (statusFilter === "all") {
        return true;
      }
      if (statusFilter === "selected") {
        return item.id === selectedId;
      }
      if (statusFilter === "submitted") {
        return item.id === selectedId && Boolean(detail?.submission?.text);
      }
      if (statusFilter === "graded") {
        return item.id === selectedId && typeof detail?.submission?.nilai === "number";
      }
      return true;
    });
  }, [detail?.submission?.nilai, detail?.submission?.text, items, search, selectedId, statusFilter]);

  const summary = useMemo(() => {
    const submitted = detail?.submission?.text ? 1 : 0;
    const graded = typeof detail?.submission?.nilai === "number" ? 1 : 0;
    return { total: items.length, submitted, graded };
  }, [detail?.submission?.nilai, detail?.submission?.text, items.length]);

  const answerLength = text.trim().length;

  return (
    <AppShell
      title="Tugas Siswa"
      description="Lihat tugas yang diberikan dan kirim jawaban sesuai petunjuk."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="card-grid" style={{ marginBottom: 16 }}>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <ClipboardList size={18} />
          </div>
          <div className="muted">Tugas aktif</div>
          <div className="stat-value">{summary.total}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon green">
            <CheckCircle2 size={18} />
          </div>
          <div className="muted">Tugas terpilih sudah dikirim</div>
          <div className="stat-value">{summary.submitted}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon purple">
            <Star size={18} />
          </div>
          <div className="muted">Tugas terpilih sudah dinilai</div>
          <div className="stat-value">{summary.graded}</div>
        </div>
      </div>

      <div className="panel data-card" style={{ marginBottom: 16 }}>
        <div className="section-heading-inline">
          <div>
            <h3>Filter tugas</h3>
            <p className="muted">Cari judul/deskripsi dan fokuskan tugas yang sedang dikerjakan.</p>
          </div>
          <Search size={18} />
        </div>
        <div className="resource-form-grid">
          <label className="field">
            <span>Pencarian</span>
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Judul tugas" />
          </label>
          <label className="field">
            <span>Status tampilan</span>
            <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
              <option value="all">Semua tugas</option>
              <option value="selected">Tugas terpilih</option>
              <option value="submitted">Terpilih dan sudah dikirim</option>
              <option value="graded">Terpilih dan sudah dinilai</option>
            </select>
          </label>
        </div>
      </div>

      <div className="attendance-grid">
        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>Daftar tugas</h3>
              <p className="muted">Pilih tugas yang ingin dikerjakan atau diperbarui jawabannya.</p>
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
                <strong>{item.title}</strong>
                <span className="muted">{item.description || "Tanpa deskripsi"}</span>
                <span className={`status-pill ${selectedId === item.id && detail?.submission?.text ? "success" : "warning"}`}>
                  Task #{item.id}
                  {selectedId === item.id && detail?.submission?.text ? " • sudah dikirim" : " • perlu dicek"}
                </span>
              </button>
            ))}
            {filteredItems.length === 0 ? <div className="empty-state">Tidak ada tugas sesuai filter.</div> : null}
          </div>
        </div>

        <div className="panel data-card">
          {detail ? (
            <form className="detail-stack" onSubmit={onSubmit}>
              <div className="section-heading-inline">
                <div>
                  <h3>{detail.item.title}</h3>
                  <p className="muted">{detail.item.description || "Tanpa deskripsi"}</p>
                </div>
              </div>
              <div className="results-grid">
                <article className="result-card">
                  <div className="meta-row">
                    <span className="meta-key">Status pengumpulan</span>
                    <span className="meta-value">{detail.submission?.text ? "Sudah dikirim" : "Belum dikirim"}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Nilai terakhir</span>
                    <span className="meta-value">{detail.submission?.nilai ?? "-"}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Catatan guru</span>
                    <span className="meta-value">{detail.submission?.note ?? "-"}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Update terakhir</span>
                    <span className="meta-value">
                      {detail.submission?.updated_at?.slice(0, 19).replace("T", " ") ?? "-"}
                    </span>
                  </div>
                </article>
              </div>
              {detail.submission?.text ? (
                <div className="result-card">
                  <strong>Jawaban tersimpan terakhir</strong>
                  <p className="muted" style={{ margin: 0, whiteSpace: "pre-wrap" }}>
                    {detail.submission.text}
                  </p>
                </div>
              ) : null}
              <label className="field">
                <span>Jawaban tugas</span>
                <textarea
                  rows={8}
                  value={text}
                  onChange={(event) => setText(event.target.value)}
                  placeholder="Tulis jawaban atau catatan pengumpulan tugas di sini"
                />
              </label>
              <p className="muted" style={{ margin: 0 }}>
                Panjang jawaban saat ini: {answerLength} karakter. Anda bisa memperbarui jawaban sebelum dinilai guru.
              </p>
              <div className="button-row">
                <button className="button" disabled={saving} type="submit">
                  <Save size={16} />
                  {saving ? "Mengirim..." : "Kumpulkan tugas"}
                </button>
              </div>
            </form>
          ) : (
            <div className="empty-state">Belum ada tugas yang diassign untuk akun ini.</div>
          )}
        </div>
      </div>
    </AppShell>
  );
}
