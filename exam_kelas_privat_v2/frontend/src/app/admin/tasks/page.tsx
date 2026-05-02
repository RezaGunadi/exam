"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { ClipboardList, Save } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type TaskItem = {
  id: number;
  class_id: number;
  title: string;
  description?: string | null;
};

type ClassItem = {
  id: number;
  name: string;
};

type SubmissionItem = {
  user_id: number;
  text?: string | null;
  nilai?: number | null;
  note?: string | null;
  updated_at?: string | null;
};

type TaskDetail = {
  item: TaskItem;
  assignments: Array<Record<string, unknown>>;
  submissions: SubmissionItem[];
};

export default function AdminTasksPage() {
  const [tasks, setTasks] = useState<TaskItem[]>([]);
  const [classes, setClasses] = useState<ClassItem[]>([]);
  const [selectedTaskId, setSelectedTaskId] = useState<number | null>(null);
  const [detail, setDetail] = useState<TaskDetail | null>(null);
  const [taskForm, setTaskForm] = useState({
    class_id: 0,
    title: "",
    description: "",
  });
  const [gradeForm, setGradeForm] = useState<Record<number, { nilai: number; note: string }>>({});
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const loadTasks = useCallback(async () => {
    const data = await apiFetch<{ items: TaskItem[] }>("/api/admin/tasks");
    setTasks(data.items);
    setSelectedTaskId((current) => current ?? data.items[0]?.id ?? null);
  }, []);

  useEffect(() => {
    apiFetch<{ items: ClassItem[] }>("/api/admin/classes")
      .then((data) => setClasses(data.items))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat kelas"));
    void loadTasks().catch((err) =>
      setError(err instanceof Error ? err.message : "Gagal memuat tugas sekolah"),
    );
  }, [loadTasks]);

  useEffect(() => {
    if (!selectedTaskId) {
      return;
    }
    apiFetch<TaskDetail>(`/api/admin/tasks/${selectedTaskId}`)
      .then((data) => {
        setDetail(data);
        setGradeForm(
          Object.fromEntries(
            data.submissions.map((item) => [
              item.user_id,
              { nilai: Number(item.nilai ?? 0), note: item.note ?? "" },
            ]),
          ),
        );
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat detail tugas"));
  }, [selectedTaskId]);

  const selectedClassName = useMemo(
    () => classes.find((item) => item.id === detail?.item.class_id)?.name ?? "-",
    [classes, detail],
  );

  async function handleCreateTask(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const created = await apiFetch<{ item: TaskItem }>("/api/admin/tasks", {
        method: "POST",
        body: JSON.stringify({
          class_id: taskForm.class_id,
          title: taskForm.title,
          description: taskForm.description,
          files: [],
        }),
      });
      await apiFetch(`/api/admin/tasks/${created.item.id}/assignments`, {
        method: "POST",
        body: JSON.stringify({ assignment_type: "class", user_ids: [] }),
      });
      setTaskForm({ class_id: 0, title: "", description: "" });
      setMessage("Tugas berhasil dibuat dan langsung dibagikan ke kelas.");
      await loadTasks();
      setSelectedTaskId(created.item.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal membuat tugas");
    } finally {
      setSaving(false);
    }
  }

  async function handleSaveGrade(userId: number) {
    if (!selectedTaskId) {
      return;
    }
    const current = gradeForm[userId];
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch(`/api/admin/tasks/${selectedTaskId}/grade/${userId}`, {
        method: "POST",
        body: JSON.stringify(current),
      });
      setMessage("Nilai tugas berhasil diperbarui.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan nilai tugas");
    } finally {
      setSaving(false);
    }
  }

  return (
    <AppShell
      title="Tugas Sekolah"
      description="Kelola tugas sekolah, pembagian tugas, dan penilaian siswa."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="attendance-grid">
        <form className="panel data-card" onSubmit={handleCreateTask}>
          <div className="section-heading-inline">
            <div>
              <h3>Buat tugas baru</h3>
              <p className="muted">Tugas akan langsung dibagikan ke seluruh siswa dalam kelas yang dipilih.</p>
            </div>
          </div>
          <div className="resource-form-grid">
            <label className="field">
              <span>Kelas</span>
              <select
                value={taskForm.class_id}
                onChange={(event) =>
                  setTaskForm((prev) => ({ ...prev, class_id: Number(event.target.value) }))
                }
                required
              >
                <option value={0}>Pilih kelas</option>
                {classes.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>Judul</span>
              <input
                value={taskForm.title}
                onChange={(event) => setTaskForm((prev) => ({ ...prev, title: event.target.value }))}
                required
              />
            </label>
            <label className="field" style={{ gridColumn: "1 / -1" }}>
              <span>Deskripsi</span>
              <textarea
                rows={4}
                value={taskForm.description}
                onChange={(event) =>
                  setTaskForm((prev) => ({ ...prev, description: event.target.value }))
                }
              />
            </label>
          </div>
          <div className="button-row">
            <button className="button" disabled={saving} type="submit">
              <ClipboardList size={16} />
              {saving ? "Menyimpan..." : "Buat dan bagikan tugas"}
            </button>
          </div>
        </form>

        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>Daftar tugas</h3>
              <p className="muted">Pilih tugas untuk melihat submission dan melakukan penilaian.</p>
            </div>
          </div>
          <div className="compact-list">
            {tasks.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`attendance-class-button ${selectedTaskId === item.id ? "active" : ""}`}
                onClick={() => setSelectedTaskId(item.id)}
              >
                <strong>{item.title}</strong>
                <span className="muted">{item.description || "Tanpa deskripsi"}</span>
                <span className="badge">Task #{item.id}</span>
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="panel data-card">
        {detail ? (
          <div className="detail-stack">
            <div className="section-heading-inline">
              <div>
                <h3>Detail tugas</h3>
                <p className="muted">Kelas: {selectedClassName}</p>
              </div>
            </div>

            <div className="results-grid">
              <article className="result-card">
                <div className="result-card-header">
                  <div className="button-row">
                    <div className="stat-icon blue">
                      <ClipboardList size={18} />
                    </div>
                    <div>
                      <h3>{detail.item.title}</h3>
                      <p className="muted">{detail.item.description || "Tanpa deskripsi"}</p>
                    </div>
                  </div>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Assignment</span>
                  <span className="meta-value">{detail.assignments.length}</span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Submission</span>
                  <span className="meta-value">{detail.submissions.length}</span>
                </div>
              </article>
            </div>

            <div className="section-heading-inline">
              <div>
                <h3>Pengumpulan siswa</h3>
                <p className="muted">Nilai tugas dan simpan catatan untuk tiap submission siswa.</p>
              </div>
            </div>

            {detail.submissions.length === 0 ? (
              <div className="empty-state">Belum ada submission untuk tugas ini.</div>
            ) : (
              <div className="results-grid">
                {detail.submissions.map((item) => (
                  <article key={`${item.user_id}-${item.updated_at}`} className="result-card">
                    <div className="meta-row">
                      <span className="meta-key">User ID</span>
                      <span className="meta-value">{item.user_id}</span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Jawaban</span>
                      <span className="meta-value">{item.text || "-"}</span>
                    </div>
                    <div className="meta-row">
                      <span className="meta-key">Update terakhir</span>
                      <span className="meta-value">
                        {item.updated_at?.slice(0, 19).replace("T", " ") ?? "-"}
                      </span>
                    </div>
                    <label className="field">
                      <span>Nilai</span>
                      <input
                        type="number"
                        value={gradeForm[item.user_id]?.nilai ?? 0}
                        onChange={(event) =>
                          setGradeForm((prev) => ({
                            ...prev,
                            [item.user_id]: {
                              nilai: Number(event.target.value),
                              note: prev[item.user_id]?.note ?? "",
                            },
                          }))
                        }
                      />
                    </label>
                    <label className="field">
                      <span>Catatan</span>
                      <textarea
                        rows={3}
                        value={gradeForm[item.user_id]?.note ?? ""}
                        onChange={(event) =>
                          setGradeForm((prev) => ({
                            ...prev,
                            [item.user_id]: {
                              nilai: prev[item.user_id]?.nilai ?? 0,
                              note: event.target.value,
                            },
                          }))
                        }
                      />
                    </label>
                    <div className="button-row">
                      <button
                        className="button-secondary"
                        type="button"
                        disabled={saving}
                        onClick={() => void handleSaveGrade(item.user_id)}
                      >
                        <Save size={16} />
                        Simpan nilai
                      </button>
                    </div>
                  </article>
                ))}
              </div>
            )}
          </div>
        ) : (
          <div className="empty-state">Pilih tugas terlebih dahulu untuk melihat detailnya.</div>
        )}
      </div>
    </AppShell>
  );
}
