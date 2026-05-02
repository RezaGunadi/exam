"use client";

import { useEffect, useState } from "react";
import { BookOpen, School, Users } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type TutorClassItem = {
  class: {
    id: number;
    name: string;
    is_active: boolean;
  };
  total_students: number;
  total_subjects: number;
};

export default function TutorClassesPage() {
  const [items, setItems] = useState<TutorClassItem[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<{ items: TutorClassItem[] }>("/api/tutor/classes")
      .then((data) => setItems(data.items))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat kelas tutor"));
  }, []);

  return (
    <AppShell title="Kelas Saya" description="Lihat kelas yang sudah diassign ke akun tutor.">
      {error ? <div className="inline-alert danger">{error}</div> : null}

      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <School size={18} />
          </div>
          <div className="muted">Total kelas</div>
          <div className="stat-value">{items.length}</div>
        </div>
      </div>

      <div className="results-grid">
        {items.map((item) => (
          <article key={item.class.id} className="result-card">
            <div className="result-card-header">
              <div className="button-row">
                <div className="stat-icon blue">
                  <School size={18} />
                </div>
                <div>
                  <h3>{item.class.name}</h3>
                  <p className="muted">Kelas yang ditangani tutor</p>
                </div>
              </div>
              <span className={`status-pill ${item.class.is_active ? "success" : "warning"}`}>
                {item.class.is_active ? "aktif" : "nonaktif"}
              </span>
            </div>
            <div className="meta-row">
              <span className="meta-key">Jumlah siswa</span>
              <span className="meta-value">
                <Users size={14} /> {item.total_students}
              </span>
            </div>
            <div className="meta-row">
              <span className="meta-key">Mapel diampu</span>
              <span className="meta-value">
                <BookOpen size={14} /> {item.total_subjects}
              </span>
            </div>
          </article>
        ))}
      </div>
    </AppShell>
  );
}
