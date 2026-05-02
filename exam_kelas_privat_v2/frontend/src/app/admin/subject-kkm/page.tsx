"use client";

import { useCallback, useEffect, useState } from "react";
import { Save } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type Subject = {
  id: number;
  name: string;
  code?: string | null;
  kkm?: number | null;
};

export default function SubjectKKMPage() {
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [kkm, setKkm] = useState<Record<number, number>>({});
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const data = await apiFetch<{ items: Subject[] }>("/api/admin/subject-kkm");
    setSubjects(data.items);
    setKkm(Object.fromEntries(data.items.map((item) => [item.id, item.kkm ?? 75])));
  }, []);

  useEffect(() => {
    Promise.resolve()
      .then(load)
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat KKM"));
  }, [load]);

  async function saveAll() {
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/admin/subject-kkm/update-multiple", {
        method: "POST",
        body: JSON.stringify({
          items: subjects.map((subject) => ({ id: subject.id, kkm: kkm[subject.id] ?? 75 })),
        }),
      });
      setMessage("KKM mapel berhasil diperbarui.");
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan KKM");
    }
  }

  return (
    <AppShell title="KKM Mapel" description="Samakan pengaturan KKM seperti modul Subject KKM Laravel.">
      {message ? <div className="inline-alert">{message}</div> : null}
      {error ? <div className="inline-alert danger">{error}</div> : null}
      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Daftar KKM</h3>
            <p className="muted">Atur nilai KKM per mata pelajaran.</p>
          </div>
          <button className="button" type="button" onClick={() => void saveAll()}>
            <Save size={16} />
            Simpan semua
          </button>
        </div>
        <div className="resource-list">
          {subjects.map((subject) => (
            <article className="resource-card" key={subject.id}>
              <div className="resource-card-top">
                <div>
                  <h4>{subject.name}</h4>
                  <span className="badge">{subject.code ?? `#${subject.id}`}</span>
                </div>
                <label className="field" style={{ maxWidth: 140 }}>
                  <span>KKM</span>
                  <input
                    type="number"
                    min={0}
                    max={100}
                    value={kkm[subject.id] ?? 75}
                    onChange={(event) =>
                      setKkm((prev) => ({ ...prev, [subject.id]: Number(event.target.value) }))
                    }
                  />
                </label>
              </div>
            </article>
          ))}
        </div>
      </div>
    </AppShell>
  );
}
