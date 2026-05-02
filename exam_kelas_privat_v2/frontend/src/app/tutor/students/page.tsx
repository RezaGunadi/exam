"use client";

import { useEffect, useMemo, useState } from "react";
import { Search, Users } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type StudentItem = {
  id: number;
  name: string;
  email: string;
  gender?: string | null;
  created_at?: string;
  class_room?: {
    id: number;
    name: string;
  } | null;
};

export default function TutorStudentsPage() {
  const [items, setItems] = useState<StudentItem[]>([]);
  const [search, setSearch] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const query = search.trim() ? `?search=${encodeURIComponent(search.trim())}` : "";
    apiFetch<{ items: StudentItem[] }>(`/api/tutor/students${query}`)
      .then((data) => setItems(data.items))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat siswa tutor"));
  }, [search]);

  const totalClasses = useMemo(
    () => new Set(items.map((item) => item.class_room?.name).filter(Boolean)).size,
    [items],
  );

  return (
    <AppShell title="Siswa Saya" description="Lihat siswa dari kelas yang diampu tutor.">
      {error ? <div className="inline-alert danger">{error}</div> : null}

      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <Users size={18} />
          </div>
          <div className="muted">Total siswa</div>
          <div className="stat-value">{items.length}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon purple">
            <Search size={18} />
          </div>
          <div className="muted">Kelas tercakup</div>
          <div className="stat-value">{totalClasses}</div>
        </div>
      </div>

      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Daftar siswa</h3>
            <p className="muted">Cari siswa dari kelas yang diampu.</p>
          </div>
        </div>
        <label className="field" style={{ maxWidth: 320 }}>
          <span>Pencarian</span>
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Cari nama atau email"
          />
        </label>
        <div className="student-grid">
          {items.map((student) => (
            <article key={student.id} className="student-card">
              <div className="student-card-header">
                <div>
                  <h3>{student.name}</h3>
                  <p className="muted">{student.email}</p>
                </div>
                <span className="badge">{student.class_room?.name ?? "-"}</span>
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
          ))}
        </div>
      </div>
    </AppShell>
  );
}
