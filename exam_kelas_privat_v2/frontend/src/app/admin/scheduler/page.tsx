"use client";

import { useCallback, useEffect, useState } from "react";
import { CalendarClock, RefreshCw, ShieldCheck, Wrench } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type SchedulerJob = {
  name: string;
  schedule: string;
};

export default function AdminSchedulerPage() {
  const [jobs, setJobs] = useState<SchedulerJob[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const data = await apiFetch<{ jobs: SchedulerJob[] }>("/api/scheduler/status");
    setJobs(data.jobs);
  }, []);

  useEffect(() => {
    Promise.resolve()
      .then(load)
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat scheduler"));
  }, [load]);

  async function runAction(path: string, successMessage: string) {
    setError(null);
    try {
      const data = await apiFetch<{ message?: string; processed?: number }>(path, { method: "POST" });
      if (typeof data.processed === "number") {
        setMessage(`${successMessage}. Diproses ${data.processed} data.`);
      } else {
        setMessage(data.message ?? successMessage);
      }
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menjalankan scheduler");
    }
  }

  return (
    <AppShell
      title="Scheduler"
      description="Lihat jadwal worker dan jalankan proses penting saat dibutuhkan."
    >
      {message ? <div className="inline-alert">{message}</div> : null}
      {error ? <div className="inline-alert danger">{error}</div> : null}

      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <CalendarClock size={18} />
          </div>
          <div className="muted">Total job</div>
          <div className="stat-value">{jobs.length}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon green">
            <ShieldCheck size={18} />
          </div>
          <div className="muted">Kontrol manual</div>
          <div className="stat-value stat-value-sm">Double checker, recovery, dan sync semester</div>
        </div>
      </div>

      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Aksi cepat</h3>
            <p className="muted">Gunakan saat perlu menjalankan proses penting tanpa menunggu jadwal berikutnya.</p>
          </div>
        </div>
        <div className="button-row">
          <button
            className="button-secondary"
            onClick={() => void runAction("/api/scheduler/run/ai-scoring", "AI scoring queue selesai dijalankan")}
          >
            <RefreshCw size={16} />
            Jalankan AI scoring
          </button>
          <button
            className="button"
            onClick={() => void runAction("/api/scheduler/run/double-checker", "Double checker selesai dijalankan")}
          >
            <RefreshCw size={16} />
            Jalankan double checker
          </button>
          <button
            className="button-secondary"
            onClick={() => void runAction("/api/scheduler/run/recovery", "Recovery selesai dijalankan")}
          >
            <Wrench size={16} />
            Jalankan recovery
          </button>
          <button
            className="button-secondary"
            onClick={() => void runAction("/api/scheduler/run/sync-semesters", "Sync semester selesai dijalankan")}
          >
            <CalendarClock size={16} />
            Sync semester
          </button>
        </div>
      </div>

      <div className="results-grid">
        {jobs.map((job) => (
          <article key={job.name} className="result-card">
            <div className="result-card-header">
              <div>
                <h3>{job.name}</h3>
                <p className="muted">Jadwal worker</p>
              </div>
              <span className="badge">{job.schedule}</span>
            </div>
          </article>
        ))}
      </div>
    </AppShell>
  );
}
