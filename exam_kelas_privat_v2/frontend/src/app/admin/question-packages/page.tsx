"use client";

import { ChangeEvent, FormEvent, useCallback, useEffect, useState } from "react";
import { BookOpen, Download, FileSpreadsheet, ListChecks, Upload } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch, apiFetchForm, downloadApiFile } from "@/lib/api";

type QuestionPackageItem = {
  id: number;
  name: string;
  subject_id: number;
  description?: string | null;
  total_questions?: number;
};

type QuestionItem = {
  id: number;
  question_text: string;
  type: string;
  points: number;
  correct_answer?: string | null;
};

type ImportSummary = {
  success?: number;
  failed?: number;
  failures?: Array<Record<string, unknown>>;
};

export default function AdminQuestionPackagesPage() {
  const [packages, setPackages] = useState<QuestionPackageItem[]>([]);
  const [selectedPackageId, setSelectedPackageId] = useState<number | null>(null);
  const [questions, setQuestions] = useState<QuestionItem[]>([]);
  const [importFile, setImportFile] = useState<File | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [summary, setSummary] = useState<ImportSummary | null>(null);

  const loadPackages = useCallback(async () => {
    const data = await apiFetch<{ items: QuestionPackageItem[] }>("/api/admin/question-packages");
    setPackages(data.items);
    setSelectedPackageId((current) => current ?? data.items[0]?.id ?? null);
  }, []);

  useEffect(() => {
    Promise.resolve()
      .then(loadPackages)
      .catch((error) =>
        setMessage(error instanceof Error ? error.message : "Gagal memuat paket soal"),
      );
  }, [loadPackages]);

  useEffect(() => {
    if (!selectedPackageId) {
      return;
    }
    apiFetch<{ items: QuestionItem[] }>(
      `/api/admin/questions?question_package_id=${selectedPackageId}`,
    )
      .then((data) => setQuestions(data.items))
      .catch((error) =>
        setMessage(error instanceof Error ? error.message : "Gagal memuat daftar soal"),
      );
  }, [selectedPackageId]);

  const handleImportQuestions = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!selectedPackageId || !importFile) {
      setMessage("Pilih paket soal dan file Excel untuk import soal.");
      return;
    }
    try {
      const formData = new FormData();
      formData.append("file", importFile);
      const result = await apiFetchForm<ImportSummary>(
        `/api/admin/question-packages/${selectedPackageId}/import-questions`,
        formData,
        { method: "POST" },
      );
      setSummary(result);
      setMessage("Import soal selesai diproses.");
      await loadPackages();
      const questionsData = await apiFetch<{ items: QuestionItem[] }>(
        `/api/admin/questions?question_package_id=${selectedPackageId}`,
      );
      setQuestions(questionsData.items);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Gagal import soal");
    }
  };

  return (
    <AppShell
      title="Paket Soal"
      description="Kelola paket soal, pilih paket yang aktif, lalu import soal sesuai kebutuhan."
    >
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="attendance-grid">
        <div className="panel data-card">
          <div className="section-kicker">Daftar paket</div>
          <h2>Pilih paket soal tujuan</h2>
          <div className="compact-list">
            {packages.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`attendance-class-button ${selectedPackageId === item.id ? "active" : ""}`}
                onClick={() => setSelectedPackageId(item.id)}
              >
                <strong>{item.name}</strong>
                <span className="muted">{item.description || "Tanpa deskripsi"}</span>
                <span className="badge">{item.total_questions ?? 0} soal</span>
              </button>
            ))}
          </div>
        </div>

        <form className="import-card" onSubmit={handleImportQuestions}>
          <div className="import-card-header">
            <div className="import-icon">
              <FileSpreadsheet size={18} />
            </div>
            <div>
              <h3>Import soal ke paket aktif</h3>
              <p className="muted">
                Download template, isi data soal, lalu upload ke paket yang sedang dipilih.
              </p>
            </div>
          </div>
          <div className="button-row">
            <button
              type="button"
              className="button-secondary"
              onClick={() =>
                void downloadApiFile(
                  "/api/admin/question-packages/import-template",
                  "template-import-soal.xlsx",
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
                setImportFile(event.target.files?.[0] ?? null)
              }
            />
          </div>
          <button type="submit" className="button" disabled={!selectedPackageId}>
            <Upload size={16} />
            Upload dan import soal
          </button>
          {summary ? (
            <div className="detail-stack">
              <div className="muted">
                Berhasil {summary.success ?? 0}, gagal {summary.failed ?? 0}
              </div>
              {summary.failures?.length ? (
                <div className="feedback-wrap">
                  <table className="feedback-table">
                    <thead>
                      <tr>
                        <th>Baris</th>
                        <th>Alasan</th>
                      </tr>
                    </thead>
                    <tbody>
                      {summary.failures.map((row, index) => (
                        <tr key={index}>
                          <td>{String(row.row ?? "-")}</td>
                          <td>{String(row.reason ?? "-")}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : null}
            </div>
          ) : null}
        </form>
      </div>

      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Soal pada paket terpilih</h3>
            <p className="muted">Lihat daftar soal yang sudah masuk ke paket ini.</p>
          </div>
        </div>
        <div className="results-grid">
          {questions.map((question) => (
            <article key={question.id} className="result-card">
              <div className="result-card-header">
                <div className="button-row">
                  <div className="stat-icon purple">
                    {question.type === "essay" ? <BookOpen size={18} /> : <ListChecks size={18} />}
                  </div>
                  <div>
                    <h3>{question.question_text}</h3>
                    <p className="muted">{question.type}</p>
                  </div>
                </div>
                <span className="badge">{question.points} poin</span>
              </div>
              {question.correct_answer ? (
                <div className="meta-row">
                  <span className="meta-key">Jawaban benar</span>
                  <span className="meta-value">{question.correct_answer}</span>
                </div>
              ) : null}
            </article>
          ))}
        </div>
      </div>
    </AppShell>
  );
}
