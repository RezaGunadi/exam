"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { GraduationCap, RotateCcw, Send, XCircle, Trash2, Users } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type ExamItem = {
  id: number;
  question_package_id: number;
  title: string;
  exam_type: string;
  description?: string | null;
  start_time: string;
  end_time: string;
  duration: number;
  total_questions: number;
  passing_score: number;
  status: string;
  shuffle_questions: boolean;
  show_results: boolean;
};

type PackageItem = { id: number; name: string; subject_id: number };
type ClassItem = { id: number; name: string };
type StudentItem = { id: number; name: string; email: string; class_id?: number | null };
type AssignmentItem = {
  id: number;
  exam_id: number;
  user_id: number;
  total_attempt: number;
  assignment_type: string;
};

function fromLocalInputValue(local: string) {
  return new Date(local).toISOString();
}

function statusPillClass(status: string) {
  if (status === "published") {
    return "status-pill success";
  }
  if (status === "cancelled") {
    return "status-pill danger";
  }
  return "status-pill warning";
}

export default function AdminExamsPage() {
  const [exams, setExams] = useState<ExamItem[]>([]);
  const [packages, setPackages] = useState<PackageItem[]>([]);
  const [classes, setClasses] = useState<ClassItem[]>([]);
  const [students, setStudents] = useState<StudentItem[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [assignments, setAssignments] = useState<AssignmentItem[]>([]);
  const [loadingExams, setLoadingExams] = useState(true);
  const [loadingMeta, setLoadingMeta] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState("");
  const [assignMode, setAssignMode] = useState<"class" | "individual">("class");
  const [selectedClassIds, setSelectedClassIds] = useState<number[]>([]);
  const [selectedUserIds, setSelectedUserIds] = useState<number[]>([]);
  const [totalAttempt, setTotalAttempt] = useState(1);
  const [studentSearch, setStudentSearch] = useState("");
  const [createStep, setCreateStep] = useState(1);

  const [createForm, setCreateForm] = useState({
    question_package_id: 0,
    title: "",
    exam_type: "ulangan_harian",
    description: "",
    start_local: "",
    end_local: "",
    duration: 60,
    total_questions: 20,
    passing_score: 70,
    shuffle_questions: true,
    show_results: true,
  });

  const loadExams = useCallback(async () => {
    setLoadingExams(true);
    setError(null);
    try {
      const q = statusFilter ? `?status=${encodeURIComponent(statusFilter)}` : "";
      const data = await apiFetch<{ items: ExamItem[] }>(`/api/admin/exams${q}`);
      setExams(data.items);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat ujian");
    } finally {
      setLoadingExams(false);
    }
  }, [statusFilter]);

  useEffect(() => {
    setLoadingMeta(true);
    Promise.all([
      apiFetch<{ items: PackageItem[] }>("/api/admin/question-packages"),
      apiFetch<{ items: ClassItem[] }>("/api/admin/classes"),
      apiFetch<{ items: StudentItem[] }>("/api/admin/students"),
    ])
      .then(([pkg, cls, st]) => {
        setPackages(pkg.items);
        setClasses(cls.items);
        setStudents(st.items);
        setCreateForm((prev) => ({
          ...prev,
          question_package_id: prev.question_package_id || pkg.items[0]?.id || 0,
        }));
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat data master"))
      .finally(() => setLoadingMeta(false));
  }, []);

  useEffect(() => {
    void loadExams();
  }, [loadExams]);

  const selected = useMemo(
    () => exams.find((e) => e.id === selectedId) ?? null,
    [exams, selectedId],
  );

  useEffect(() => {
    if (!selectedId) {
      setAssignments([]);
      return;
    }
    apiFetch<{ items: AssignmentItem[] }>(`/api/admin/exams/${selectedId}/assignments`)
      .then((data) => setAssignments(data.items))
      .catch(() => setAssignments([]));
  }, [selectedId]);

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setMessage(null);
    if (!createForm.question_package_id || !createForm.title.trim() || !createForm.start_local || !createForm.end_local) {
      setError("Lengkapi paket soal, judul, dan jadwal mulai/selesai.");
      return;
    }
    try {
      await apiFetch("/api/admin/exams", {
        method: "POST",
        body: JSON.stringify({
          question_package_id: createForm.question_package_id,
          title: createForm.title.trim(),
          exam_type: createForm.exam_type,
          description: createForm.description.trim() || undefined,
          start_time: fromLocalInputValue(createForm.start_local),
          end_time: fromLocalInputValue(createForm.end_local),
          duration: createForm.duration,
          total_questions: createForm.total_questions,
          passing_score: createForm.passing_score,
          shuffle_questions: createForm.shuffle_questions,
          show_results: createForm.show_results,
        }),
      });
      setMessage("Ujian berhasil dibuat (status draft).");
      await loadExams();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal membuat ujian");
    }
  }

  async function setExamStatus(id: number, action: "publish" | "cancel") {
    setError(null);
    setMessage(null);
    try {
      await apiFetch(`/api/admin/exams/${id}/${action}`, { method: "POST" });
      setMessage(action === "publish" ? "Ujian dipublikasikan." : "Ujian dibatalkan.");
      await loadExams();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memperbarui status");
    }
  }

  async function removeExam(id: number) {
    if (!window.confirm("Hapus ujian ini? Pastikan tidak ada siswa yang masih aktif.")) {
      return;
    }
    setError(null);
    setMessage(null);
    try {
      await apiFetch(`/api/admin/exams/${id}`, { method: "DELETE" });
      setMessage("Ujian dihapus.");
      if (selectedId === id) {
        setSelectedId(null);
      }
      await loadExams();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus ujian");
    }
  }

  async function submitAssignments() {
    if (!selectedId) {
      return;
    }
    setError(null);
    setMessage(null);
    try {
      const body =
        assignMode === "class"
          ? {
              assignment_type: "class",
              class_ids: selectedClassIds,
              total_attempt: totalAttempt,
            }
          : {
              assignment_type: "individual",
              user_ids: selectedUserIds,
              total_attempt: totalAttempt,
            };
      await apiFetch(`/api/admin/exams/${selectedId}/assignments`, {
        method: "POST",
        body: JSON.stringify(body),
      });
      setMessage("Penugasan diperbarui.");
      setSelectedClassIds([]);
      setSelectedUserIds([]);
      const data = await apiFetch<{ items: AssignmentItem[] }>(
        `/api/admin/exams/${selectedId}/assignments`,
      );
      setAssignments(data.items);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menugaskan ujian");
    }
  }

  async function removeAssignment(assignmentId: number) {
    if (!selectedId || !window.confirm("Hapus penugasan ini?")) {
      return;
    }
    try {
      await apiFetch(`/api/admin/exams/${selectedId}/assignments/${assignmentId}`, {
        method: "DELETE",
      });
      setAssignments((prev) => prev.filter((a) => a.id !== assignmentId));
      setMessage("Penugasan dihapus.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus penugasan");
    }
  }

  async function repickExam(scope: "all" | "selected", resetAttempt = true, preserveHistory = false) {
    if (!selectedId) {
      return;
    }
    const selectedUserCount = selectedUserIds.length;
    if (scope === "selected" && selectedUserCount === 0) {
      setError("Pilih minimal satu siswa untuk repick terarah.");
      return;
    }
    const confirmMessage =
      scope === "all"
        ? `Repick semua assignment akan ${preserveHistory ? "mengarsipkan" : "menghapus"} progres/jawaban/hasil ujian lama untuk ujian ini${resetAttempt ? " dan reset attempt" : " tanpa reset attempt"}. Lanjutkan?`
        : `Repick ${selectedUserCount} siswa terpilih akan ${preserveHistory ? "mengarsipkan" : "menghapus"} progres/jawaban/hasil lama mereka${resetAttempt ? " dan reset attempt" : " tanpa reset attempt"}. Lanjutkan?`;
    if (!window.confirm(confirmMessage)) {
      return;
    }
    setError(null);
    setMessage(null);
    try {
      const data = await apiFetch<{
        affected_user_count: number;
        affected_result_count: number;
      }>(`/api/admin/exams/${selectedId}/repick`, {
        method: "POST",
        body: JSON.stringify({
          user_ids: scope === "selected" ? selectedUserIds : undefined,
          reset_attempt: resetAttempt,
          preserve_history: preserveHistory,
        }),
      });
      setMessage(
        `Repick selesai: ${data.affected_user_count} siswa, ${data.affected_result_count} result dibersihkan.`,
      );
      const refreshed = await apiFetch<{ items: AssignmentItem[] }>(
        `/api/admin/exams/${selectedId}/assignments`,
      );
      setAssignments(refreshed.items);
      if (scope === "selected") {
        setSelectedUserIds([]);
      }
      await loadExams();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menjalankan repick ujian");
    }
  }

  const studentNameById = useMemo(() => {
    const m = new Map<number, string>();
    for (const s of students) {
      m.set(s.id, s.name);
    }
    return m;
  }, [students]);

  const filteredStudents = useMemo(() => {
    const q = studentSearch.trim().toLowerCase();
    if (!q) {
      return students;
    }
    return students.filter(
      (s) =>
        s.name.toLowerCase().includes(q) ||
        s.email.toLowerCase().includes(q) ||
        String(s.id).includes(q),
    );
  }, [students, studentSearch]);

  function toggleClass(id: number) {
    setSelectedClassIds((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id],
    );
  }

  function toggleUser(id: number) {
    setSelectedUserIds((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id],
    );
  }

  return (
    <AppShell
      title="Ujian"
      description="Buat ujian dari paket soal, publikasikan, lalu tugaskan ke kelas atau siswa perorangan."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="attendance-grid">
        <form className="panel data-card" onSubmit={handleCreate}>
          <div className="section-heading-inline">
            <div>
              <div className="section-kicker">
                <GraduationCap size={16} />
                Buat ujian
              </div>
              <h3>Ujian baru</h3>
              <p className="muted">Disimpan sebagai draft hingga Anda klik Publish.</p>
            </div>
          </div>
          <div className="dashboard-actions" style={{ marginBottom: 12 }}>
            {[
              ["1", "Paket & identitas"],
              ["2", "Jadwal & aturan"],
              ["3", "Review & simpan"],
            ].map(([step, label]) => (
              <button
                key={step}
                type="button"
                className={createStep === Number(step) ? "button" : "button-secondary"}
                onClick={() => setCreateStep(Number(step))}
              >
                Langkah {step}: {label}
              </button>
            ))}
          </div>
          <div className="resource-form-grid">
            <label className="field" style={{ display: createStep === 1 ? undefined : "none" }}>
              <span>Paket soal</span>
              <select
                value={createForm.question_package_id}
                onChange={(e) =>
                  setCreateForm((p) => ({ ...p, question_package_id: Number(e.target.value) }))
                }
              >
                <option value={0}>— pilih —</option>
                {packages.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name} (#{p.id})
                  </option>
                ))}
              </select>
            </label>
            <label className="field" style={{ display: createStep === 1 ? undefined : "none" }}>
              <span>Jenis ujian</span>
              <select
                value={createForm.exam_type}
                onChange={(e) => setCreateForm((p) => ({ ...p, exam_type: e.target.value }))}
              >
                <option value="ulangan_harian">Ulangan harian</option>
                <option value="uts">UTS</option>
                <option value="uas">UAS</option>
                <option value="latihan">Latihan</option>
                <option value="lainnya">Lainnya</option>
              </select>
            </label>
            <label className="field" style={{ gridColumn: "1 / -1", display: createStep === 1 ? undefined : "none" }}>
              <span>Judul</span>
              <input
                value={createForm.title}
                onChange={(e) => setCreateForm((p) => ({ ...p, title: e.target.value }))}
                required
              />
            </label>
            <label className="field" style={{ gridColumn: "1 / -1", display: createStep === 1 ? undefined : "none" }}>
              <span>Deskripsi (opsional)</span>
              <textarea
                rows={2}
                value={createForm.description}
                onChange={(e) => setCreateForm((p) => ({ ...p, description: e.target.value }))}
              />
            </label>
            <label className="field" style={{ display: createStep === 2 ? undefined : "none" }}>
              <span>Mulai (waktu lokal)</span>
              <input
                type="datetime-local"
                value={createForm.start_local}
                onChange={(e) => setCreateForm((p) => ({ ...p, start_local: e.target.value }))}
                required
              />
            </label>
            <label className="field" style={{ display: createStep === 2 ? undefined : "none" }}>
              <span>Selesai (waktu lokal)</span>
              <input
                type="datetime-local"
                value={createForm.end_local}
                onChange={(e) => setCreateForm((p) => ({ ...p, end_local: e.target.value }))}
                required
              />
            </label>
            <label className="field" style={{ display: createStep === 2 ? undefined : "none" }}>
              <span>Durasi (menit)</span>
              <input
                type="number"
                min={1}
                value={createForm.duration}
                onChange={(e) =>
                  setCreateForm((p) => ({ ...p, duration: Number(e.target.value) || 0 }))
                }
              />
            </label>
            <label className="field" style={{ display: createStep === 2 ? undefined : "none" }}>
              <span>Jumlah soal diambil</span>
              <input
                type="number"
                min={1}
                value={createForm.total_questions}
                onChange={(e) =>
                  setCreateForm((p) => ({ ...p, total_questions: Number(e.target.value) || 0 }))
                }
              />
            </label>
            <label className="field" style={{ display: createStep === 2 ? undefined : "none" }}>
              <span>Nilai lulus minimum</span>
              <input
                type="number"
                min={0}
                value={createForm.passing_score}
                onChange={(e) =>
                  setCreateForm((p) => ({ ...p, passing_score: Number(e.target.value) || 0 }))
                }
              />
            </label>
            <label className="field checkbox-field" style={{ display: createStep === 2 ? undefined : "none" }}>
              <span>Acak urutan soal</span>
              <input
                type="checkbox"
                checked={createForm.shuffle_questions}
                onChange={(e) =>
                  setCreateForm((p) => ({ ...p, shuffle_questions: e.target.checked }))
                }
              />
            </label>
            <label className="field checkbox-field" style={{ display: createStep === 2 ? undefined : "none" }}>
              <span>Tampilkan hasil ke siswa</span>
              <input
                type="checkbox"
                checked={createForm.show_results}
                onChange={(e) => setCreateForm((p) => ({ ...p, show_results: e.target.checked }))}
              />
            </label>
            {createStep === 3 ? (
              <div className="result-card" style={{ gridColumn: "1 / -1" }}>
                <div className="section-heading-inline">
                  <div>
                    <h3>Review ujian</h3>
                    <p className="muted">Periksa ringkasan sebelum menyimpan draft.</p>
                  </div>
                  <span className="status-pill warning">Draft</span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Paket</span>
                  <span className="meta-value">
                    {packages.find((item) => item.id === createForm.question_package_id)?.name ?? "-"}
                  </span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Judul</span>
                  <span className="meta-value">{createForm.title || "-"}</span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Jenis</span>
                  <span className="meta-value">{createForm.exam_type}</span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Jadwal</span>
                  <span className="meta-value">
                    {createForm.start_local || "-"} - {createForm.end_local || "-"}
                  </span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Aturan</span>
                  <span className="meta-value">
                    {createForm.duration} menit, {createForm.total_questions} soal, lulus {createForm.passing_score}
                  </span>
                </div>
              </div>
            ) : null}
          </div>
          <div className="button-row">
            <button
              className="button-secondary"
              type="button"
              disabled={createStep === 1}
              onClick={() => setCreateStep((step) => Math.max(1, step - 1))}
            >
              Sebelumnya
            </button>
            <button
              className="button-secondary"
              type="button"
              disabled={createStep === 3}
              onClick={() => setCreateStep((step) => Math.min(3, step + 1))}
            >
              Berikutnya
            </button>
            <button className="button" type="submit" disabled={loadingMeta}>
              Simpan sebagai draft
            </button>
          </div>
        </form>

        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>Daftar ujian</h3>
              <p className="muted">Klik kartu untuk mengatur penugasan.</p>
            </div>
            <label className="field">
              <span>Status</span>
              <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
                <option value="">Semua</option>
                <option value="draft">Draft</option>
                <option value="published">Published</option>
                <option value="cancelled">Cancelled</option>
              </select>
            </label>
          </div>
          {loadingExams ? (
            <p className="muted">Memuat ujian…</p>
          ) : (
            <div className="compact-list">
              {exams.map((exam) => (
                <div
                  key={exam.id}
                  className={`compact-list-item ${selectedId === exam.id ? "is-selected" : ""}`}
                  role="presentation"
                  onClick={() => setSelectedId(exam.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      setSelectedId(exam.id);
                    }
                  }}
                >
                  <div className="resource-card-top">
                    <div>
                      <h4>{exam.title}</h4>
                      <p className="muted small">
                        {exam.exam_type} · Paket #{exam.question_package_id}
                      </p>
                      <p className="muted small">
                        {new Date(exam.start_time).toLocaleString("id-ID")} —{" "}
                        {new Date(exam.end_time).toLocaleString("id-ID")}
                      </p>
                    </div>
                    <span className={statusPillClass(exam.status)}>{exam.status}</span>
                  </div>
                  <div className="button-row" onClick={(e) => e.stopPropagation()}>
                    {exam.status === "draft" ? (
                      <button
                        className="button-secondary"
                        type="button"
                        onClick={() => void setExamStatus(exam.id, "publish")}
                      >
                        <Send size={14} />
                        Publish
                      </button>
                    ) : null}
                    {exam.status !== "cancelled" ? (
                      <button
                        className="button-secondary"
                        type="button"
                        onClick={() => void setExamStatus(exam.id, "cancel")}
                      >
                        <XCircle size={14} />
                        Batalkan
                      </button>
                    ) : null}
                    <button
                      className="button-danger"
                      type="button"
                      onClick={() => void removeExam(exam.id)}
                    >
                      <Trash2 size={14} />
                      Hapus
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
          {!loadingExams && exams.length === 0 ? <p className="muted">Belum ada ujian.</p> : null}
        </div>
      </div>

      {selected ? (
        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>
                <Users size={18} style={{ verticalAlign: "text-bottom", marginRight: 6 }} />
                Penugasan: {selected.title}
              </h3>
              <p className="muted">
                Durasi {selected.duration} menit · Maks percobaan per siswa di bawah berlaku untuk penugasan baru.
              </p>
            </div>
          </div>

          <div className="button-row" style={{ flexWrap: "wrap" }}>
            <button
              type="button"
              className={assignMode === "class" ? "button" : "button-secondary"}
              onClick={() => setAssignMode("class")}
            >
              Per kelas
            </button>
            <button
              type="button"
              className={assignMode === "individual" ? "button" : "button-secondary"}
              onClick={() => setAssignMode("individual")}
            >
              Per siswa
            </button>
          </div>

          <div className="resource-form-grid">
            <label className="field">
              <span>Maks. percobaan</span>
              <input
                type="number"
                min={1}
                value={totalAttempt}
                onChange={(e) => setTotalAttempt(Number(e.target.value) || 1)}
              />
            </label>
          </div>

          {assignMode === "class" ? (
            <div className="resource-form-grid">
              {classes.map((c) => (
                <label key={c.id} className="field checkbox-field">
                  <span>{c.name}</span>
                  <input
                    type="checkbox"
                    checked={selectedClassIds.includes(c.id)}
                    onChange={() => toggleClass(c.id)}
                  />
                </label>
              ))}
            </div>
          ) : (
            <>
              <label className="field">
                <span>Cari siswa</span>
                <input
                  value={studentSearch}
                  onChange={(e) => setStudentSearch(e.target.value)}
                  placeholder="Nama atau email"
                />
              </label>
              <div className="feedback-wrap" style={{ maxHeight: 220 }}>
                <table className="feedback-table">
                  <tbody>
                    {filteredStudents.map((s) => (
                      <tr key={s.id}>
                        <td>
                          <label className="checkbox-field" style={{ display: "flex", gap: 8 }}>
                            <input
                              type="checkbox"
                              checked={selectedUserIds.includes(s.id)}
                              onChange={() => toggleUser(s.id)}
                            />
                            <span>
                              {s.name} <span className="muted">({s.email})</span>
                            </span>
                          </label>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}

          <div className="button-row">
            <button className="button" type="button" onClick={() => void submitAssignments()}>
              Terapkan penugasan
            </button>
            <button className="button-secondary" type="button" onClick={() => void repickExam("all")}>
              <RotateCcw size={16} />
              Repick semua assignment
            </button>
            <button className="button-secondary" type="button" onClick={() => void repickExam("all", false)}>
              <RotateCcw size={16} />
              Repick tanpa reset attempt
            </button>
            <button className="button-secondary" type="button" onClick={() => void repickExam("all", true, true)}>
              <RotateCcw size={16} />
              Repick arsipkan histori
            </button>
            {assignMode === "individual" ? (
              <button
                className="button-secondary"
                type="button"
                disabled={selectedUserIds.length === 0}
                onClick={() => void repickExam("selected")}
              >
                <RotateCcw size={16} />
                Repick siswa terpilih
              </button>
            ) : null}
          </div>

          <h4 style={{ margin: "16px 0 8px" }}>Penugasan aktif ({assignments.length})</h4>
          <div className="feedback-wrap">
            <table className="feedback-table">
              <thead>
                <tr>
                  <th>Siswa</th>
                  <th>Max attempt</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {assignments.map((a) => (
                  <tr key={a.id}>
                    <td>{studentNameById.get(a.user_id) ?? `user #${a.user_id}`}</td>
                    <td>{a.total_attempt}</td>
                    <td>
                      <button
                        className="button-danger"
                        type="button"
                        onClick={() => void removeAssignment(a.id)}
                      >
                        Hapus
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {assignments.length === 0 ? <p className="muted">Belum ada penugasan.</p> : null}
        </div>
      ) : (
        <p className="muted">Pilih ujian di daftar untuk mengatur penugasan.</p>
      )}
    </AppShell>
  );
}
