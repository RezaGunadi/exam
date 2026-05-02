"use client";

import { ChangeEvent, FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { Pencil, Plus, Save, ScrollText, Trash2, X } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch, apiFetchForm, apiUrl } from "@/lib/api";

type QuestionRow = {
  id: number;
  subject_id: number;
  question_package_id: number;
  type: string;
  question_text: string;
  image?: string | null;
  video_url?: string | null;
  attachments?: Array<{ label?: string; url?: string }> | null;
  options?: Record<string, string> | null;
  correct_answer?: string | null;
  essay_answer?: string | null;
  points: number;
  order: number;
  is_active: boolean;
};

type PackageItem = { id: number; name: string; subject_id: number };
type SubjectItem = { id: number; name: string };

const LABELS = ["A", "B", "C", "D", "E"] as const;

function optionsToLines(opts: unknown): string[] {
  if (!opts || typeof opts !== "object") {
    return ["", "", "", "", ""];
  }
  const o = opts as Record<string, string>;
  return LABELS.map((k) => o[k] ?? "");
}

type QuestionFormState = {
  question_package_id: number;
  subject_id: number;
  type: "multiple_choice" | "essay";
  question_text: string;
  optLines: string[];
  correct_answer: string;
  essay_answer: string;
  video_url: string;
  attachmentLines: string[];
  points: number;
  order: number;
  is_active: boolean;
};

function emptyForm(pkgId: number, subjectId: number): QuestionFormState {
  return {
    question_package_id: pkgId,
    subject_id: subjectId,
    type: "multiple_choice",
    question_text: "",
    optLines: ["", "", "", "", ""],
    correct_answer: "A",
    essay_answer: "",
    video_url: "",
    attachmentLines: [""],
    points: 10,
    order: 0,
    is_active: true,
  };
}

export default function AdminQuestionsPage() {
  const [packages, setPackages] = useState<PackageItem[]>([]);
  const [subjects, setSubjects] = useState<SubjectItem[]>([]);
  const [filterPackageId, setFilterPackageId] = useState(0);
  const [items, setItems] = useState<QuestionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [panelOpen, setPanelOpen] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [currentImageUrl, setCurrentImageUrl] = useState<string | null>(null);
  const [form, setForm] = useState<QuestionFormState>(() => emptyForm(0, 0));

  const subjectName = useMemo(() => {
    const m = new Map<number, string>();
    for (const s of subjects) {
      m.set(s.id, s.name);
    }
    return m;
  }, [subjects]);

  const pkgById = useMemo(() => {
    const m = new Map<number, PackageItem>();
    for (const p of packages) {
      m.set(p.id, p);
    }
    return m;
  }, [packages]);

  const loadMeta = useCallback(async () => {
    const [pkg, subj] = await Promise.all([
      apiFetch<{ items: PackageItem[] }>("/api/admin/question-packages"),
      apiFetch<{ items: SubjectItem[] }>("/api/admin/subjects"),
    ]);
    setPackages(pkg.items);
    setSubjects(subj.items);
    const first = pkg.items[0];
    setFilterPackageId((cur) => cur || first?.id || 0);
    setForm((prev) =>
      emptyForm(
        first?.id ?? 0,
        first?.subject_id ?? prev.subject_id ?? subj.items[0]?.id ?? 0,
      ),
    );
  }, []);

  const loadQuestions = useCallback(async () => {
    if (!filterPackageId) {
      setItems([]);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const data = await apiFetch<{ items: QuestionRow[] }>(
        `/api/admin/questions?question_package_id=${filterPackageId}`,
      );
      setItems(data.items);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat soal");
    } finally {
      setLoading(false);
    }
  }, [filterPackageId]);

  useEffect(() => {
    void loadMeta().catch((err) =>
      setError(err instanceof Error ? err.message : "Gagal memuat master data"),
    );
  }, [loadMeta]);

  useEffect(() => {
    void loadQuestions();
  }, [loadQuestions]);

  function openCreate() {
    const p = pkgById.get(filterPackageId);
    setEditingId(null);
    setCurrentImageUrl(null);
    setForm(emptyForm(filterPackageId, p?.subject_id ?? 0));
    setPanelOpen(true);
    setMessage(null);
  }

  function openEdit(row: QuestionRow) {
    setEditingId(row.id);
    setCurrentImageUrl(row.image ?? null);
    setForm({
      question_package_id: row.question_package_id,
      subject_id: row.subject_id,
      type: row.type === "essay" ? "essay" : "multiple_choice",
      question_text: row.question_text,
      optLines: optionsToLines(row.options),
      correct_answer: row.correct_answer?.slice(0, 1).toUpperCase() ?? "A",
      essay_answer: row.essay_answer ?? "",
      video_url: row.video_url ?? "",
      attachmentLines:
        row.attachments?.length
          ? row.attachments.map((item) => `${item.label ?? ""}|${item.url ?? ""}`)
          : [""],
      points: row.points,
      order: row.order,
      is_active: row.is_active,
    });
    setPanelOpen(true);
    setMessage(null);
  }

  function closePanel() {
    setPanelOpen(false);
    setEditingId(null);
    setCurrentImageUrl(null);
  }

  async function handleImageFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file || !editingId) {
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const data = await apiFetchForm<{ image: string }>(
        `/api/admin/questions/${editingId}/image`,
        fd,
        { method: "POST" },
      );
      setCurrentImageUrl(data.image);
      setMessage("Gambar soal diunggah.");
      await loadQuestions();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal mengunggah gambar");
    } finally {
      setSaving(false);
    }
  }

  async function handleClearImage() {
    if (!editingId || !currentImageUrl) {
      return;
    }
    if (!window.confirm("Hapus gambar dari soal ini?")) {
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch(`/api/admin/questions/${editingId}/image`, { method: "DELETE" });
      setCurrentImageUrl(null);
      setMessage("Gambar dihapus.");
      await loadQuestions();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus gambar");
    } finally {
      setSaving(false);
    }
  }

  async function handleAttachmentFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file || !editingId) {
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const fd = new FormData();
      fd.append("file", file);
      fd.append("label", file.name);
      const data = await apiFetchForm<{ attachment: { label?: string; url?: string } }>(
        `/api/admin/questions/${editingId}/attachments`,
        fd,
        { method: "POST" },
      );
      const line = `${data.attachment.label ?? file.name}|${data.attachment.url ?? ""}`;
      setForm((prev) => ({ ...prev, attachmentLines: [...prev.attachmentLines.filter(Boolean), line] }));
      setMessage("Lampiran soal diunggah.");
      await loadQuestions();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal mengunggah lampiran");
    } finally {
      setSaving(false);
    }
  }

  async function removeAttachmentLine(index: number) {
    const line = form.attachmentLines[index] ?? "";
    const [, ...urlParts] = line.split("|");
    const url = urlParts.join("|").trim();
    setForm((prev) => ({
      ...prev,
      attachmentLines: prev.attachmentLines.filter((_, idx) => idx !== index),
    }));
    if (!editingId || !url.startsWith("/api/files/")) {
      return;
    }
    try {
      await apiFetch(`/api/admin/questions/${editingId}/attachments`, {
        method: "DELETE",
        body: JSON.stringify({ url }),
      });
      setMessage("Lampiran soal dihapus.");
      await loadQuestions();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus lampiran");
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form.question_text.trim()) {
      setError("Isi teks soal.");
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const attachments = form.attachmentLines
        .map((line) => {
          const [label, ...urlParts] = line.split("|");
          return { label: label.trim(), url: urlParts.join("|").trim() };
        })
        .filter((item) => item.label || item.url);
      if (editingId) {
        const payload: Record<string, unknown> = {
          question_text: form.question_text.trim(),
          type: form.type,
          video_url: form.video_url.trim() || null,
          attachments,
          points: form.points,
          order: form.order,
          is_active: form.is_active,
        };
        if (form.type === "multiple_choice") {
          payload.options = form.optLines;
          payload.correct_answer = form.correct_answer;
          payload.essay_answer = null;
        } else {
          payload.essay_answer = form.essay_answer.trim() || null;
          payload.correct_answer = null;
          payload.options = [];
        }
        await apiFetch(`/api/admin/questions/${editingId}`, {
          method: "PUT",
          body: JSON.stringify(payload),
        });
        setMessage("Soal diperbarui.");
      } else {
        await apiFetch("/api/admin/questions", {
          method: "POST",
          body: JSON.stringify({
            subject_id: form.subject_id,
            question_package_id: form.question_package_id,
            type: form.type,
            question_text: form.question_text.trim(),
            video_url: form.video_url.trim() || undefined,
            attachments,
            options: form.type === "multiple_choice" ? form.optLines : [],
            correct_answer:
              form.type === "multiple_choice" ? form.correct_answer : undefined,
            essay_answer: form.type === "essay" ? form.essay_answer.trim() || undefined : undefined,
            points: form.points,
            order: form.order,
            is_active: form.is_active,
          }),
        });
        setMessage("Soal ditambahkan.");
      }
      closePanel();
      await loadQuestions();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan soal");
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(id: number) {
    if (!window.confirm("Hapus soal ini?")) {
      return;
    }
    setError(null);
    try {
      await apiFetch(`/api/admin/questions/${id}`, { method: "DELETE" });
      setMessage("Soal dihapus.");
      await loadQuestions();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus");
    }
  }

  const selectedPkg = filterPackageId ? pkgById.get(filterPackageId) : undefined;

  return (
    <AppShell
      title="Soal"
      description="Bank soal per paket: PG, essay, gambar ilustrasi (unggah setelah simpan), dan import massal dari halaman Paket Soal."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="section-heading-inline" style={{ marginBottom: 12 }}>
        <p className="muted" style={{ margin: 0 }}>
          <Link href="/admin/question-packages">Paket Soal</Link>
          {" · "}
          Gunakan filter paket untuk mengelola soal dalam satu set.
        </p>
      </div>

      <div className="attendance-grid">
        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <div className="section-kicker">
                <ScrollText size={16} />
                Filter
              </div>
              <h3>Paket soal</h3>
            </div>
            <button className="button" type="button" onClick={openCreate} disabled={!filterPackageId}>
              <Plus size={16} />
              Soal baru
            </button>
          </div>
          <label className="field">
            <span>Paket</span>
            <select
              value={filterPackageId}
              onChange={(e) => setFilterPackageId(Number(e.target.value))}
            >
              <option value={0}>— pilih paket —</option>
              {packages.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} (mapel: {subjectName.get(p.subject_id) ?? p.subject_id})
                </option>
              ))}
            </select>
          </label>
          {selectedPkg ? (
            <p className="muted">
              Subject ID {selectedPkg.subject_id} — pastikan konsisten saat menambah soal manual.
            </p>
          ) : null}
        </div>

        <div className="panel data-card">
          <h3>Daftar soal ({items.length})</h3>
          {loading ? (
            <p className="muted">Memuat…</p>
          ) : !filterPackageId ? (
            <p className="muted">Pilih paket soal.</p>
          ) : items.length === 0 ? (
            <p className="muted">Belum ada soal di paket ini.</p>
          ) : (
            <div className="compact-list">
              {items.map((row) => (
                <div key={row.id} className="compact-list-item">
                  <div className="resource-card-top">
                    <div>
                      <span
                        className={
                          row.type === "essay" ? "status-pill warning" : "status-pill success"
                        }
                      >
                        {row.type === "essay" ? "Essay" : "PG"}
                      </span>
                      <h4 style={{ margin: "8px 0 4px" }}>{row.question_text.slice(0, 120)}</h4>
                      <p className="muted">
                        Poin {row.points} · Urutan {row.order} · #{row.id}
                        {row.image ? " · ber-gambar" : ""}
                        {row.video_url ? " · video" : ""}
                        {row.attachments?.length ? ` · ${row.attachments.length} lampiran` : ""}
                      </p>
                      {row.image ? (
                        // eslint-disable-next-line @next/next/no-img-element -- URL API dinamis
                        <img
                          src={apiUrl(row.image)}
                          alt=""
                          style={{
                            maxWidth: 200,
                            maxHeight: 100,
                            borderRadius: 8,
                            marginTop: 8,
                            objectFit: "cover",
                          }}
                        />
                      ) : null}
                    </div>
                    <div className="button-row">
                      <button
                        className="button-secondary"
                        type="button"
                        onClick={() => openEdit(row)}
                      >
                        <Pencil size={16} />
                        Edit
                      </button>
                      <button
                        className="button-danger"
                        type="button"
                        onClick={() => void handleDelete(row.id)}
                      >
                        <Trash2 size={16} />
                      </button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {panelOpen ? (
        <div className="modal-backdrop" role="presentation" onClick={closePanel}>
          <div
            className="panel data-card modal-card"
            role="dialog"
            aria-modal="true"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="resource-card-top">
              <h3>{editingId ? "Edit soal" : "Soal baru"}</h3>
              <button className="button-secondary" type="button" onClick={closePanel} aria-label="Tutup">
                <X size={18} />
              </button>
            </div>
            <form className="resource-form-card" onSubmit={handleSubmit}>
              <div className="resource-form-grid">
              {!editingId ? (
                <>
                  <label className="field">
                    <span>Paket soal</span>
                    <select
                      value={form.question_package_id}
                      onChange={(e) => {
                        const pid = Number(e.target.value);
                        const p = pkgById.get(pid);
                        setForm((prev) => ({
                          ...prev,
                          question_package_id: pid,
                          subject_id: p?.subject_id ?? prev.subject_id,
                        }));
                      }}
                    >
                      {packages.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.name}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="field">
                    <span>Mapel (subject_id)</span>
                    <select
                      value={form.subject_id}
                      onChange={(e) =>
                        setForm((p) => ({ ...p, subject_id: Number(e.target.value) }))
                      }
                    >
                      {subjects.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.name}
                        </option>
                      ))}
                    </select>
                  </label>
                </>
              ) : null}

              <label className="field">
                <span>Jenis</span>
                <select
                  value={form.type}
                  onChange={(e) =>
                    setForm((p) => ({
                      ...p,
                      type: e.target.value as "multiple_choice" | "essay",
                    }))
                  }
                >
                  <option value="multiple_choice">Pilihan ganda</option>
                  <option value="essay">Essay</option>
                </select>
              </label>

              <label className="field" style={{ gridColumn: "1 / -1" }}>
                <span>Teks soal</span>
                <textarea
                  rows={4}
                  value={form.question_text}
                  onChange={(e) => setForm((p) => ({ ...p, question_text: e.target.value }))}
                  required
                />
              </label>

              {form.type === "multiple_choice" ? (
                <>
                  {LABELS.map((label, idx) => (
                    <label key={label} className="field">
                      <span>Opsi {label}</span>
                      <input
                        value={form.optLines[idx] ?? ""}
                        onChange={(e) =>
                          setForm((p) => {
                            const next = [...p.optLines];
                            next[idx] = e.target.value;
                            return { ...p, optLines: next };
                          })
                        }
                      />
                    </label>
                  ))}
                  <label className="field">
                    <span>Jawaban benar</span>
                    <select
                      value={form.correct_answer}
                      onChange={(e) =>
                        setForm((p) => ({ ...p, correct_answer: e.target.value }))
                      }
                    >
                      {LABELS.map((l) => (
                        <option key={l} value={l}>
                          {l}
                        </option>
                      ))}
                    </select>
                  </label>
                </>
              ) : (
                <label className="field" style={{ gridColumn: "1 / -1" }}>
                  <span>Kunci jawaban essay (opsional)</span>
                  <textarea
                    rows={3}
                    value={form.essay_answer}
                    onChange={(e) => setForm((p) => ({ ...p, essay_answer: e.target.value }))}
                  />
                </label>
              )}

              <label className="field" style={{ gridColumn: "1 / -1" }}>
                <span>Video URL (opsional)</span>
                <input
                  value={form.video_url}
                  onChange={(e) => setForm((p) => ({ ...p, video_url: e.target.value }))}
                  placeholder="https://... atau URL video pembelajaran"
                />
              </label>

              <div className="field" style={{ gridColumn: "1 / -1" }}>
                <span>Lampiran tambahan (opsional)</span>
                <p className="muted" style={{ margin: "0 0 8px" }}>
                  Satu lampiran per baris dengan format: Label|URL. Contoh: Materi PDF|https://...
                </p>
                {form.attachmentLines.map((line, idx) => (
                  <div className="button-row" key={idx} style={{ marginBottom: 8 }}>
                    <input
                      value={line}
                      onChange={(e) =>
                        setForm((p) => {
                          const next = [...p.attachmentLines];
                          next[idx] = e.target.value;
                          return { ...p, attachmentLines: next };
                        })
                      }
                      placeholder="Label|URL"
                    />
                    <button className="button-secondary" type="button" onClick={() => void removeAttachmentLine(idx)}>
                      Hapus
                    </button>
                  </div>
                ))}
                <div className="button-row" style={{ flexWrap: "wrap" }}>
                  <button
                    className="button-secondary"
                    type="button"
                    onClick={() => setForm((p) => ({ ...p, attachmentLines: [...p.attachmentLines, ""] }))}
                  >
                    Tambah URL lampiran
                  </button>
                  {editingId ? (
                    <label className="button-secondary" style={{ cursor: "pointer" }}>
                      Upload file lampiran
                      <input
                        type="file"
                        style={{ display: "none" }}
                        disabled={saving}
                        onChange={(e) => void handleAttachmentFileChange(e)}
                      />
                    </label>
                  ) : null}
                </div>
              </div>

              <label className="field">
                <span>Poin</span>
                <input
                  type="number"
                  min={1}
                  value={form.points}
                  onChange={(e) =>
                    setForm((p) => ({ ...p, points: Number(e.target.value) || 0 }))
                  }
                />
              </label>
              <label className="field">
                <span>Urutan</span>
                <input
                  type="number"
                  value={form.order}
                  onChange={(e) =>
                    setForm((p) => ({ ...p, order: Number(e.target.value) || 0 }))
                  }
                />
              </label>
              <label className="field checkbox-field">
                <span>Aktif</span>
                <input
                  type="checkbox"
                  checked={form.is_active}
                  onChange={(e) => setForm((p) => ({ ...p, is_active: e.target.checked }))}
                />
              </label>

              {editingId ? (
                <div className="field" style={{ gridColumn: "1 / -1" }}>
                  <span>Gambar ilustrasi (opsional)</span>
                  <p className="muted" style={{ margin: "0 0 8px" }}>
                    Maks. 5 MB — JPEG, PNG, GIF, atau WebP. Ditampilkan ke siswa saat ujian.
                  </p>
                  {currentImageUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element -- URL API dinamis
                    <img
                      src={apiUrl(currentImageUrl)}
                      alt=""
                      style={{
                        maxWidth: "100%",
                        maxHeight: 200,
                        borderRadius: 10,
                        marginBottom: 10,
                        display: "block",
                        border: "1px solid var(--line)",
                      }}
                    />
                  ) : null}
                  <div className="button-row" style={{ flexWrap: "wrap" }}>
                    <label className="button-secondary" style={{ cursor: "pointer" }}>
                      Pilih file
                      <input
                        type="file"
                        accept="image/jpeg,image/png,image/gif,image/webp,.jpg,.jpeg,.png,.gif,.webp"
                        style={{ display: "none" }}
                        disabled={saving}
                        onChange={(e) => void handleImageFileChange(e)}
                      />
                    </label>
                    {currentImageUrl ? (
                      <button
                        className="button-danger"
                        type="button"
                        disabled={saving}
                        onClick={() => void handleClearImage()}
                      >
                        Hapus gambar
                      </button>
                    ) : null}
                  </div>
                </div>
              ) : (
                <p className="muted" style={{ gridColumn: "1 / -1", margin: 0 }}>
                  Simpan soal baru terlebih dulu; setelah itu panel ini memungkinkan unggah gambar.
                </p>
              )}
              </div>

              <div className="button-row">
                <button className="button" type="submit" disabled={saving}>
                  <Save size={16} />
                  {saving ? "Menyimpan…" : "Simpan"}
                </button>
                <button className="button-secondary" type="button" onClick={closePanel}>
                  Batal
                </button>
              </div>
            </form>
          </div>
        </div>
      ) : null}
    </AppShell>
  );
}
