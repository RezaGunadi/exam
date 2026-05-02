"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiFetch, apiUrl } from "@/lib/api";

type Question = {
  id: number;
  type: "multiple_choice" | "essay";
  order: number;
  question_text: string;
  image?: string | null;
  video_url?: string | null;
  attachments?: Array<{ label?: string; url?: string }> | null;
  options?: Record<string, string>;
  points: number;
};

type ExamPayload = {
  exam: {
    id: number;
    title: string;
    duration: number;
  };
  exam_result: {
    id: number;
  };
  questions: Question[];
  time_limit: number;
};

type ExamWorkspaceProps = {
  examId: number;
};

export function ExamWorkspace({ examId }: ExamWorkspaceProps) {
  const [payload, setPayload] = useState<ExamPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [pgAnswers, setPgAnswers] = useState<Record<string, string>>({});
  const [saveState, setSaveState] = useState("Belum ada perubahan");
  const [error, setError] = useState<string | null>(null);
  const [remaining, setRemaining] = useState<number>(0);
  const queuedRef = useRef<{
    answers: Record<string, string>;
    pgAnswers: Record<string, string>;
    currentQuestion: number;
    version: number;
  } | null>(null);
  const inFlightRef = useRef(false);
  const versionRef = useRef(0);
  const lastFlushRef = useRef<number | null>(null);

  const startExam = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiFetch<ExamPayload>(`/api/student/exams/${examId}/start`, {
        method: "POST",
        body: JSON.stringify({}),
      });
      setPayload(data);
      setRemaining(data.time_limit);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memulai ujian");
    } finally {
      setLoading(false);
    }
  }, [examId]);

  useEffect(() => {
    void startExam();
  }, [startExam]);

  useEffect(() => {
    if (!payload) {
      return;
    }
    const timer = window.setInterval(() => {
      setRemaining((prev) => Math.max(0, prev - 1));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [payload]);

  useEffect(() => {
    if (!payload) {
      return;
    }
    const sendSnapshot = () =>
      apiFetch(`/api/student/exams/${examId}/proctor-upload`, {
        method: "POST",
        body: JSON.stringify({
          exam_result_id: payload.exam_result.id,
          current_question: currentIndex + 1,
          visibility_state: document.visibilityState,
          source: "browser-monitor",
        }),
      }).catch(() => undefined);
    void sendSnapshot();
    const timer = window.setInterval(sendSnapshot, 60000);
    return () => window.clearInterval(timer);
  }, [currentIndex, examId, payload]);

  useEffect(() => {
    if (!payload) {
      return;
    }
    const onVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        void apiFetch(`/api/student/exams/${examId}/record-cheating`, {
          method: "POST",
          body: JSON.stringify({
            event: "tab_hidden",
            note: `Siswa meninggalkan tab pada soal ${currentIndex + 1}`,
          }),
        }).catch(() => undefined);
      }
    };
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => document.removeEventListener("visibilitychange", onVisibilityChange);
  }, [currentIndex, examId, payload]);

  const currentQuestion = useMemo(
    () => payload?.questions[currentIndex] ?? null,
    [currentIndex, payload],
  );

  function queueSync(mode: "draft" | "submit" = "draft") {
    if (!payload) {
      return;
    }
    versionRef.current += 1;
    queuedRef.current = {
      answers,
      pgAnswers,
      currentQuestion: currentIndex + 1,
      version: versionRef.current,
    };
    setSaveState(mode === "submit" ? "Menyimpan sebelum submit..." : "Perubahan masuk antrian simpan");
    if (lastFlushRef.current) {
      window.clearTimeout(lastFlushRef.current);
    }
    lastFlushRef.current = window.setTimeout(() => {
      void flushQueue();
    }, 700);
  }

  async function flushQueue() {
    if (!payload || inFlightRef.current || !queuedRef.current) {
      return;
    }
    inFlightRef.current = true;
    const snapshot = queuedRef.current;
    queuedRef.current = null;
    setSaveState("Menyimpan ke server...");
    try {
      await apiFetch(`/api/student/exams/${examId}/sync`, {
        method: "POST",
        body: JSON.stringify({
          exam_result_id: payload.exam_result.id,
          answers: snapshot.answers,
          pg_answers: snapshot.pgAnswers,
          current_question: snapshot.currentQuestion,
          client_version: snapshot.version,
          save_mode: "autosave",
        }),
      });
      setSaveState("Semua jawaban sudah tersimpan");
    } catch (err) {
      setSaveState(err instanceof Error ? err.message : "Gagal menyimpan");
    } finally {
      inFlightRef.current = false;
      if (queuedRef.current) {
        void flushQueue();
      }
    }
  }

  function updateEssay(questionId: number, value: string) {
    setAnswers((prev) => {
      const next = { ...prev, [String(questionId)]: value };
      return next;
    });
  }

  function updatePG(questionId: number, optionKey: string) {
    setPgAnswers((prev) => {
      const next = { ...prev, [String(questionId)]: optionKey };
      return next;
    });
    setAnswers((prev) => ({
      ...prev,
      [String(questionId)]: optionKey,
    }));
  }

  useEffect(() => {
    if (!payload) {
      return;
    }
    queueSync();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [answers, pgAnswers, currentIndex]);

  async function onSubmit() {
    if (!payload) {
      return;
    }
    await flushQueue();
    try {
      const data = await apiFetch<{
        message: string;
        score: number;
        is_passed: boolean;
      }>(`/api/student/exams/${examId}/submit`, {
        method: "POST",
        body: JSON.stringify({
          exam_result_id: payload.exam_result.id,
          answers,
          pg_answers: pgAnswers,
          current_question: currentIndex + 1,
          submit_type: "normal",
          violations: [],
        }),
      });
      setSaveState(`${data.message}. Skor: ${data.score}`);
    } catch (err) {
      setSaveState(err instanceof Error ? err.message : "Gagal submit");
    }
  }

  if (loading) {
    return <div className="panel data-card">Memulai ujian...</div>;
  }

  if (!payload || !currentQuestion) {
    return <div className="panel data-card">{error ?? "Ujian tidak tersedia."}</div>;
  }

  return (
    <div className="exam-layout">
      <section className="panel question-card">
        <div className="toolbar">
          <div>
            <span className="badge">Soal {currentIndex + 1}</span>
            <h2>{payload.exam.title}</h2>
          </div>
          <div className="autosave-status">{saveState}</div>
        </div>

        <div className="data-card">
          <h3>Soal</h3>
          <p>{currentQuestion.question_text}</p>
          {currentQuestion.image ? (
            // eslint-disable-next-line @next/next/no-img-element -- URL API dinamis
            <img
              src={apiUrl(currentQuestion.image)}
              alt="Ilustrasi soal"
              style={{
                maxWidth: "100%",
                maxHeight: 360,
                borderRadius: 12,
                marginTop: 12,
                objectFit: "contain",
                border: "1px solid var(--line)",
              }}
            />
          ) : null}
          {currentQuestion.video_url ? (
            <div className="result-card" style={{ marginTop: 12 }}>
              <strong>Video pendukung</strong>
              <a href={currentQuestion.video_url} target="_blank" rel="noreferrer">
                Buka video soal
              </a>
            </div>
          ) : null}
          {currentQuestion.attachments?.length ? (
            <div className="result-card" style={{ marginTop: 12 }}>
              <strong>Lampiran soal</strong>
              <div className="compact-list">
                {currentQuestion.attachments.map((attachment, index) => (
                  <a key={`${attachment.url ?? "attachment"}-${index}`} href={attachment.url ?? "#"} target="_blank" rel="noreferrer">
                    {attachment.label || attachment.url || `Lampiran ${index + 1}`}
                  </a>
                ))}
              </div>
            </div>
          ) : null}

          {currentQuestion.type === "multiple_choice" ? (
            <div className="list">
              {Object.entries(currentQuestion.options ?? {}).map(([key, value]) => (
                <label key={key} className="list-item">
                  <input
                    type="radio"
                    name={`question-${currentQuestion.id}`}
                    checked={pgAnswers[String(currentQuestion.id)] === key}
                    onChange={() => updatePG(currentQuestion.id, key)}
                  />{" "}
                  {key}. {value}
                </label>
              ))}
            </div>
          ) : (
            <textarea
              rows={10}
              value={answers[String(currentQuestion.id)] ?? ""}
              onChange={(event) => updateEssay(currentQuestion.id, event.target.value)}
              placeholder="Tulis jawaban essay di sini..."
            />
          )}
        </div>

        <div className="question-actions">
          <button
            className="button-secondary"
            disabled={currentIndex === 0}
            onClick={() => setCurrentIndex((prev) => Math.max(0, prev - 1))}
          >
            Sebelumnya
          </button>
          <button
            className="button-secondary"
            disabled={currentIndex === payload.questions.length - 1}
            onClick={() =>
              setCurrentIndex((prev) =>
                Math.min(payload.questions.length - 1, prev + 1),
              )
            }
          >
            Berikutnya
          </button>
          <button className="button" onClick={onSubmit}>
            Submit Ujian
          </button>
        </div>
      </section>

      <aside className="panel side-card">
        <h3>Status Ujian</h3>
        <p className="muted">Waktu tersisa</p>
        <div className="stat-value">{remaining}s</div>

        <div className="list" style={{ marginTop: 16 }}>
          {payload.questions.map((question, index) => {
            const answered =
              answers[String(question.id)] !== undefined ||
              pgAnswers[String(question.id)] !== undefined;
            return (
              <button
                key={question.id}
                className="button-secondary"
                onClick={() => setCurrentIndex(index)}
                style={{
                  justifyContent: "space-between",
                  display: "flex",
                }}
              >
                <span>Soal {index + 1}</span>
                <span className={`badge ${answered ? "success" : ""}`}>
                  {answered ? "Terisi" : "Kosong"}
                </span>
              </button>
            );
          })}
        </div>
      </aside>
    </div>
  );
}
