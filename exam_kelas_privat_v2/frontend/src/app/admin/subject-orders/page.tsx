"use client";

import { useEffect, useState } from "react";
import { ArrowDownUp, Save } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type SubjectOrderItem = {
  subject_id: number;
  name: string;
  code?: string | null;
  kkm?: number | null;
  order: number;
  is_active: boolean;
};

export default function AdminSubjectOrdersPage() {
  const [items, setItems] = useState<SubjectOrderItem[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    apiFetch<{ items: SubjectOrderItem[] }>("/api/admin/subject-orders")
      .then((data) => setItems(data.items))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat urutan mapel"));
  }, []);

  async function onSave() {
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/admin/subject-orders", {
        method: "PUT",
        body: JSON.stringify({
          items: items.map((item) => ({
            subject_id: item.subject_id,
            order: Number(item.order),
          })),
        }),
      });
      setMessage("Urutan mapel berhasil diperbarui.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan urutan mapel");
    } finally {
      setSaving(false);
    }
  }

  return (
    <AppShell
      title="Urutan Mapel"
      description="Atur urutan mapel yang dipakai sekolah agar tampilan dan pengolahan data tetap konsisten."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <ArrowDownUp size={18} />
          </div>
          <div className="muted">Total mapel</div>
          <div className="stat-value">{items.length}</div>
        </div>
      </div>

      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Susunan mapel</h3>
            <p className="muted">Gunakan angka urutan agar daftar mapel tampil lebih rapi dan konsisten.</p>
          </div>
        </div>
        <div className="results-grid">
          {items.map((item) => (
            <article key={item.subject_id} className="result-card">
              <div className="result-card-header">
                <div>
                  <h3>{item.name}</h3>
                  <p className="muted">
                    {item.code ?? "Tanpa kode"} • KKM {item.kkm ?? "-"}
                  </p>
                </div>
                <span className={`status-pill ${item.is_active ? "success" : "warning"}`}>
                  {item.is_active ? "aktif" : "nonaktif"}
                </span>
              </div>
              <label className="field">
                <span>Urutan</span>
                <input
                  type="number"
                  min={1}
                  value={item.order}
                  onChange={(event) =>
                    setItems((prev) =>
                      prev.map((current) =>
                        current.subject_id === item.subject_id
                          ? { ...current, order: Number(event.target.value) }
                          : current,
                      ),
                    )
                  }
                />
              </label>
            </article>
          ))}
        </div>
        <div className="button-row">
          <button className="button" disabled={saving} type="button" onClick={() => void onSave()}>
            <Save size={16} />
            {saving ? "Menyimpan..." : "Simpan urutan mapel"}
          </button>
        </div>
      </div>
    </AppShell>
  );
}
