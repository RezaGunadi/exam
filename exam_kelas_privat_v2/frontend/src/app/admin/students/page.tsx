"use client";

import { ChangeEvent, FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { Download, FileKey2, FileSpreadsheet, Search, Upload, Users } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch, apiFetchForm, downloadApiFile } from "@/lib/api";

type StudentItem = {
  id: number;
  name: string;
  email: string;
  gender?: string | null;
  class_id?: number | null;
  created_at?: string;
};

type ClassItem = {
  id: number;
  name: string;
};

type ImportSummary = {
  success?: number;
  failed?: number;
  failures?: Array<Record<string, unknown>>;
  updated?: number;
};

export default function AdminStudentsPage() {
  const [students, setStudents] = useState<StudentItem[]>([]);
  const [classes, setClasses] = useState<ClassItem[]>([]);
  const [selectedClassId, setSelectedClassId] = useState("");
  const [search, setSearch] = useState("");
  const [importFile, setImportFile] = useState<File | null>(null);
  const [bulkFile, setBulkFile] = useState<File | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [importSummary, setImportSummary] = useState<ImportSummary | null>(null);
  const [bulkSummary, setBulkSummary] = useState<ImportSummary | null>(null);

  useEffect(() => {
    apiFetch<{ items: ClassItem[] }>("/api/admin/classes")
      .then((data) => setClasses(data.items))
      .catch((error) =>
        setMessage(error instanceof Error ? error.message : "Gagal memuat daftar kelas"),
      );
  }, []);

  const loadStudents = useCallback(async () => {
    const query = new URLSearchParams();
    if (selectedClassId) {
      query.set("class_id", selectedClassId);
    }
    if (search.trim()) {
      query.set("search", search.trim());
    }
    const suffix = query.toString() ? `?${query.toString()}` : "";
    const data = await apiFetch<{ items: StudentItem[] }>(`/api/admin/students${suffix}`);
    setStudents(data.items);
  }, [search, selectedClassId]);

  useEffect(() => {
    Promise.resolve()
      .then(loadStudents)
      .catch((error) =>
        setMessage(error instanceof Error ? error.message : "Gagal memuat siswa"),
      );
  }, [loadStudents]);

  const filteredStudents = useMemo(() => {
    if (!search.trim()) {
      return students;
    }
    const keyword = search.toLowerCase();
    return students.filter(
      (item) =>
        item.name.toLowerCase().includes(keyword) || item.email.toLowerCase().includes(keyword),
    );
  }, [search, students]);

  const handleStudentImport = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!selectedClassId || !importFile) {
      setMessage("Pilih kelas dan file Excel untuk import siswa.");
      return;
    }
    try {
      const formData = new FormData();
      formData.append("class_id", selectedClassId);
      formData.append("file", importFile);
      const result = await apiFetchForm<ImportSummary>("/api/admin/students/import", formData, {
        method: "POST",
      });
      setImportSummary(result);
      setMessage("Import siswa selesai diproses.");
      await loadStudents();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Gagal import siswa");
    }
  };

  const handleBulkPassword = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!bulkFile) {
      setMessage("Pilih file Excel untuk bulk password.");
      return;
    }
    try {
      const formData = new FormData();
      formData.append("file", bulkFile);
      const result = await apiFetchForm<ImportSummary>("/api/admin/students/bulk-password", formData, {
        method: "POST",
      });
      setBulkSummary(result);
      setMessage("Bulk password selesai diproses.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Gagal memproses bulk password");
    }
  };

  const renderFailures = (summary: ImportSummary | null) => {
    if (!summary?.failures?.length) {
      return null;
    }
    return (
      <div className="feedback-wrap">
        <table className="feedback-table">
          <thead>
            <tr>
              <th>Baris</th>
              <th>Alasan</th>
              <th>Email</th>
            </tr>
          </thead>
          <tbody>
            {summary.failures.map((row, index) => (
              <tr key={index}>
                <td>{String(row.row ?? "-")}</td>
                <td>{String(row.reason ?? "-")}</td>
                <td>{String(row.email ?? "-")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  };

  return (
    <AppShell
      title="Siswa"
      description="Kelola data siswa, import file Excel, dan ubah password massal."
    >
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <Users size={18} />
          </div>
          <div className="muted">Total siswa tampil</div>
          <div className="stat-value">{filteredStudents.length}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon green">
            <FileSpreadsheet size={18} />
          </div>
          <div className="muted">Kelas aktif</div>
          <div className="stat-value">{classes.length}</div>
        </div>
      </div>

      <div className="import-grid">
        <form className="import-card" onSubmit={handleStudentImport}>
          <div className="import-card-header">
            <div className="import-icon">
              <FileSpreadsheet size={18} />
            </div>
            <div>
              <h3>Import siswa</h3>
              <p className="muted">Unduh template, pilih kelas, lalu upload Excel siswa.</p>
            </div>
          </div>
          <div className="button-row">
            <button
              type="button"
              className="button-secondary"
              onClick={() =>
                void downloadApiFile(
                  "/api/admin/students/import/template",
                  "template-import-siswa.xlsx",
                )
              }
            >
              <Download size={16} />
              Download template
            </button>
          </div>
          <label className="field">
            <span>Pilih kelas tujuan</span>
            <select
              value={selectedClassId}
              onChange={(event) => setSelectedClassId(event.target.value)}
              required
            >
              <option value="">Pilih kelas</option>
              {classes.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}
                </option>
              ))}
            </select>
          </label>
          <div className="upload-box">
            <input
              type="file"
              accept=".xlsx,.xls,.csv"
              onChange={(event: ChangeEvent<HTMLInputElement>) =>
                setImportFile(event.target.files?.[0] ?? null)
              }
            />
          </div>
          <button type="submit" className="button">
            <Upload size={16} />
            Upload dan import
          </button>
          {importSummary ? (
            <div className="detail-stack">
              <div className="muted">
                Berhasil {importSummary.success ?? 0}, gagal {importSummary.failed ?? 0}
              </div>
              {renderFailures(importSummary)}
            </div>
          ) : null}
        </form>

        <form className="import-card" onSubmit={handleBulkPassword}>
          <div className="import-card-header">
            <div className="import-icon">
              <FileKey2 size={18} />
            </div>
            <div>
              <h3>Bulk edit password</h3>
              <p className="muted">Gunakan template email dan password baru untuk update massal.</p>
            </div>
          </div>
          <div className="button-row">
            <button
              type="button"
              className="button-secondary"
              onClick={() =>
                void downloadApiFile(
                  "/api/admin/students/bulk-password/template",
                  "template-bulk-password-siswa.xlsx",
                )
              }
            >
              <Download size={16} />
              Download template
            </button>
          </div>
          <div className="upload-box">
            <input
              type="file"
              accept=".xlsx,.xls,.csv"
              onChange={(event: ChangeEvent<HTMLInputElement>) =>
                setBulkFile(event.target.files?.[0] ?? null)
              }
            />
          </div>
          <button type="submit" className="button">
            <Upload size={16} />
            Upload bulk password
          </button>
          {bulkSummary ? (
            <div className="detail-stack">
              <div className="muted">
                Terupdate {bulkSummary.updated ?? 0}, gagal {bulkSummary.failed ?? 0}
              </div>
              {renderFailures(bulkSummary)}
            </div>
          ) : null}
        </form>
      </div>

      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Daftar siswa</h3>
            <p className="muted">Lihat data siswa berdasarkan kelas atau pencarian nama.</p>
          </div>
        </div>
        <div className="button-row">
          <label className="field" style={{ minWidth: 220 }}>
            <span>Pencarian</span>
            <div className="button-row">
              <div className="page-heading-chip">
                <Search size={14} />
                Filter lokal
              </div>
            </div>
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Cari nama atau email"
            />
          </label>
        </div>
        <div className="student-grid">
          {filteredStudents.map((student) => {
            const className =
              classes.find((item) => String(item.id) === String(student.class_id))?.name ?? "-";
            return (
              <article key={student.id} className="student-card">
                <div className="student-card-header">
                  <div>
                    <h3>{student.name}</h3>
                    <p className="muted">{student.email}</p>
                  </div>
                  <span className="badge">{className}</span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Gender</span>
                  <span className="meta-value">{student.gender ?? "-"}</span>
                </div>
                <div className="meta-row">
                  <span className="meta-key">Terdaftar</span>
                  <span className="meta-value">{student.created_at?.slice(0, 10) ?? "-"}</span>
                </div>
              </article>
            );
          })}
        </div>
      </div>
    </AppShell>
  );
}
