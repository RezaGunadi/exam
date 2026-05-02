"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { Archive, CheckCircle2, FileSpreadsheet, Play, Printer, Search } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch, downloadApiFile } from "@/lib/api";

type GenerateTarget = "student" | "class" | "school";

type StudentOption = {
  id: number;
  name: string;
  email: string;
  class_id?: number | null;
};

type ClassOption = {
  id: number;
  name: string;
};

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
  user_id: number;
  class_id?: number | null;
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

export default function AdminRaportsPage() {
  const [items, setItems] = useState<Raport[]>([]);
  const [students, setStudents] = useState<StudentOption[]>([]);
  const [classes, setClasses] = useState<ClassOption[]>([]);
  const [target, setTarget] = useState<GenerateTarget>("student");
  const [userId, setUserId] = useState("");
  const [classId, setClassId] = useState("");
  const [academicYear, setAcademicYear] = useState("");
  const [semester, setSemester] = useState("ganjil");
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<Raport | null>(null);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [processing, setProcessing] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const data = await apiFetch<{ items: Raport[] }>("/api/admin/raports");
    setItems(data.items);
    setSelectedId((current) => current ?? data.items[0]?.id ?? null);
  }, []);

  useEffect(() => {
    Promise.resolve()
      .then(async () => {
        const form = await apiFetch<{ students: StudentOption[]; classes: ClassOption[] }>(
          "/api/admin/raports/generate/form",
        );
        setStudents(form.students);
        setClasses(form.classes);
        setUserId(String(form.students[0]?.id ?? ""));
        setClassId(String(form.classes[0]?.id ?? ""));
        await load();
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat raport"));
  }, [load]);

  useEffect(() => {
    if (!selectedId) {
      return;
    }
    apiFetch<{ item: Raport }>(`/api/admin/raports/${selectedId}`)
      .then((data) => setDetail(data.item))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat detail raport"));
  }, [selectedId]);

  const studentNameById = useMemo(() => {
    return new Map(students.map((student) => [student.id, student.name]));
  }, [students]);

  const filteredItems = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    return items.filter((item) => {
      const studentName = studentNameById.get(item.user_id) ?? "";
      const matchesSearch =
        !keyword ||
        `raport ${item.id} user ${item.user_id} ${studentName} ${item.academic_year} ${item.semester}`
          .toLowerCase()
          .includes(keyword);
      const matchesStatus = statusFilter === "all" || item.status === statusFilter;
      return matchesSearch && matchesStatus;
    });
  }, [items, search, statusFilter, studentNameById]);

  const summary = useMemo(() => {
    const published = items.filter((item) => item.status === "published").length;
    const draft = items.filter((item) => item.status === "draft").length;
    const archived = items.filter((item) => item.status === "archived").length;
    return { published, draft, archived };
  }, [items]);

  async function generate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setMessage(null);
    setProcessing(true);
    try {
      const path =
        target === "student"
          ? "/api/admin/raports-generate/student"
          : target === "class"
            ? "/api/admin/raports-generate/class"
            : "/api/admin/raports-generate/school";
      const body =
        target === "student"
          ? { user_id: Number(userId), academic_year: academicYear, semester }
          : target === "class"
            ? { class_id: Number(classId), academic_year: academicYear, semester }
            : { academic_year: academicYear, semester };
      const result = await apiFetch<{ message?: string; created?: number; item?: Raport }>(path, {
        method: "POST",
        body: JSON.stringify(body),
      });
      setMessage(result.created ? `Raport berhasil dibuat untuk ${result.created} siswa.` : "Raport berhasil dibuat.");
      await load();
      if (result.item?.id) {
        setSelectedId(result.item.id);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal generate raport");
    } finally {
      setProcessing(false);
    }
  }

  async function updateStatus(id: number, status: "publish" | "archive") {
    setError(null);
    setMessage(null);
    setProcessing(true);
    try {
      await apiFetch(`/api/admin/raports/${id}/${status}`, { method: "POST" });
      setMessage(status === "publish" ? "Raport berhasil dipublish." : "Raport berhasil diarsipkan.");
      await load();
      const refreshed = await apiFetch<{ item: Raport }>(`/api/admin/raports/${id}`);
      setDetail(refreshed.item);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memperbarui status raport");
    } finally {
      setProcessing(false);
    }
  }

  const subjects = Array.isArray(detail?.subjects_data) ? detail.subjects_data : [];

  return (
    <AppShell title="Raport" description="Generate, lihat, dan pantau status raport seperti modul Laravel lama.">
      {message ? <div className="inline-alert">{message}</div> : null}
      {error ? <div className="inline-alert danger">{error}</div> : null}

      <div className="card-grid" style={{ marginBottom: 16 }}>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon green">
            <CheckCircle2 size={18} />
          </div>
          <div className="muted">Published</div>
          <div className="stat-value">{summary.published}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon orange">
            <FileSpreadsheet size={18} />
          </div>
          <div className="muted">Draft</div>
          <div className="stat-value">{summary.draft}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon purple">
            <Archive size={18} />
          </div>
          <div className="muted">Archived</div>
          <div className="stat-value">{summary.archived}</div>
        </div>
      </div>

      <form className="panel data-card resource-form-card" onSubmit={generate}>
        <div className="section-heading-inline">
          <div>
            <h3>Generate raport</h3>
            <p className="muted">Buat ulang raport dari hasil ujian berbobot per siswa, kelas, atau seluruh sekolah.</p>
          </div>
        </div>
        <div className="resource-form-grid">
          <label className="field">
            <span>Target generate</span>
            <select value={target} onChange={(event) => setTarget(event.target.value as GenerateTarget)}>
              <option value="student">Satu siswa</option>
              <option value="class">Satu kelas</option>
              <option value="school">Seluruh sekolah</option>
            </select>
          </label>
          {target === "student" ? (
            <label className="field">
              <span>Siswa</span>
              <select value={userId} onChange={(event) => setUserId(event.target.value)}>
                {students.map((student) => (
                  <option key={student.id} value={student.id}>
                    {student.name} - #{student.id}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          {target === "class" ? (
            <label className="field">
              <span>Kelas</span>
              <select value={classId} onChange={(event) => setClassId(event.target.value)}>
                {classes.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          <label className="field">
            <span>Semester</span>
            <select value={semester} onChange={(event) => setSemester(event.target.value)}>
              <option value="ganjil">Ganjil</option>
              <option value="genap">Genap</option>
            </select>
          </label>
          <label className="field">
            <span>Tahun ajaran</span>
            <input
              value={academicYear}
              onChange={(event) => setAcademicYear(event.target.value)}
              placeholder="2026/2027"
            />
          </label>
        </div>
        <button className="button" type="submit" disabled={processing}>
          <Play size={16} />
          {processing ? "Memproses..." : "Generate raport"}
        </button>
      </form>

      <div className="panel data-card" style={{ margin: "16px 0" }}>
        <div className="section-heading-inline">
          <div>
            <h3>Filter raport</h3>
            <p className="muted">Cari siswa, tahun ajaran, semester, atau status raport.</p>
          </div>
          <Search size={18} />
        </div>
        <div className="resource-form-grid">
          <label className="field">
            <span>Pencarian</span>
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Nama siswa / tahun ajaran"
            />
          </label>
          <label className="field">
            <span>Status</span>
            <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
              <option value="all">Semua</option>
              <option value="draft">Draft</option>
              <option value="published">Published</option>
              <option value="archived">Archived</option>
            </select>
          </label>
        </div>
      </div>

      <div className="attendance-grid">
        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>Daftar raport</h3>
              <p className="muted">Pilih raport untuk melihat detail nilai dan melakukan publish/archive.</p>
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
                <strong>{studentNameById.get(item.user_id) ?? `User #${item.user_id}`}</strong>
                <span className="muted">
                  {item.academic_year} - {item.semester} • Raport #{item.id}
                </span>
                <span className={`status-pill ${item.status === "published" ? "success" : item.status === "archived" ? "danger" : "warning"}`}>
                  {item.status} • {formatScore(item.overall_score)}
                </span>
              </button>
            ))}
            {filteredItems.length === 0 ? <div className="empty-state">Raport tidak ditemukan.</div> : null}
          </div>
        </div>

        <div className="panel data-card">
          {detail ? (
            <div className="detail-stack">
              <div className="section-heading-inline">
                <div>
                  <h3>Raport #{detail.id}</h3>
                  <p className="muted">
                    {studentNameById.get(detail.user_id) ?? `User #${detail.user_id}`} • {detail.academic_year} •{" "}
                    {detail.semester}
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
                      void downloadApiFile(`/api/admin/raports/${detail.id}/print`, `raport-${detail.id}.pdf`)
                    }
                  >
                    <FileSpreadsheet size={16} />
                    PDF
                  </button>
                  {detail.status !== "published" ? (
                    <button
                      className="button-secondary"
                      type="button"
                      disabled={processing}
                      onClick={() => void updateStatus(detail.id, "publish")}
                    >
                      <CheckCircle2 size={16} />
                      Publish
                    </button>
                  ) : null}
                  {detail.status !== "archived" ? (
                    <button
                      className="button-secondary"
                      type="button"
                      disabled={processing}
                      onClick={() => void updateStatus(detail.id, "archive")}
                    >
                      <Archive size={16} />
                      Archive
                    </button>
                  ) : null}
                </div>
              </div>

              <div className="results-grid">
                <article className="result-card">
                  <div className="meta-row">
                    <span className="meta-key">Status</span>
                    <span className="meta-value">{detail.status}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Nilai akhir</span>
                    <span className="meta-value">{formatScore(detail.overall_score)}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Grade</span>
                    <span className="meta-value">{detail.overall_grade}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Ketuntasan</span>
                    <span className="meta-value">{detail.overall_passed ? "Tuntas" : "Belum tuntas"}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Generated</span>
                    <span className="meta-value">{formatDate(detail.generated_at)}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Published</span>
                    <span className="meta-value">{formatDate(detail.published_at)}</span>
                  </div>
                </article>
              </div>

              <div className="section-heading-inline">
                <div>
                  <h3>Breakdown mapel</h3>
                  <p className="muted">Rincian ini dipakai siswa pada halaman raport published.</p>
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
                {subjects.length === 0 ? <div className="empty-state">Belum ada breakdown mapel.</div> : null}
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
