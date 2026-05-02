"use client";

import { FormEvent, useEffect, useState } from "react";
import { Building2, Save } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type SchoolForm = {
  name: string;
  address: string;
  phone: string;
  email: string;
  website: string;
  description: string;
  principal_name: string;
  principal_phone: string;
  principal_email: string;
  max_user: number;
  max_total_export: number;
  max_concurent_exam: number;
};

const defaultForm: SchoolForm = {
  name: "",
  address: "",
  phone: "",
  email: "",
  website: "",
  description: "",
  principal_name: "",
  principal_phone: "",
  principal_email: "",
  max_user: 0,
  max_total_export: 0,
  max_concurent_exam: 0,
};

export default function AdminSchoolPage() {
  const [form, setForm] = useState<SchoolForm>(defaultForm);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    apiFetch<{ school: Partial<SchoolForm> }>("/api/admin/school")
      .then((data) =>
        setForm({
          ...defaultForm,
          ...data.school,
          max_user: Number(data.school.max_user ?? 0),
          max_total_export: Number(data.school.max_total_export ?? 0),
          max_concurent_exam: Number(data.school.max_concurent_exam ?? 0),
        }),
      )
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat data sekolah"));
  }, []);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/admin/school", {
        method: "PUT",
        body: JSON.stringify(form),
      });
      setMessage("Data sekolah berhasil diperbarui.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memperbarui data sekolah");
    } finally {
      setSaving(false);
    }
  }

  return (
    <AppShell
      title="Sekolah"
      description="Kelola identitas sekolah, kontak utama, dan kapasitas operasional dari satu halaman."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <Building2 size={18} />
          </div>
          <div className="muted">Nama sekolah</div>
          <div className="stat-value stat-value-sm">{form.name || "-"}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon purple">
            <Building2 size={18} />
          </div>
          <div className="muted">Kapasitas siswa</div>
          <div className="stat-value">{form.max_user}</div>
        </div>
      </div>

      <form className="panel data-card" onSubmit={onSubmit}>
        <div className="section-heading-inline">
          <div>
            <h3>Profil sekolah</h3>
            <p className="muted">Informasi ini dipakai di dashboard, hasil, dan komunikasi sekolah.</p>
          </div>
        </div>
        <div className="resource-form-grid">
          {[
            ["name", "Nama sekolah"],
            ["address", "Alamat"],
            ["phone", "Telepon"],
            ["email", "Email"],
            ["website", "Website"],
            ["description", "Deskripsi"],
            ["principal_name", "Nama pimpinan"],
            ["principal_phone", "Telepon pimpinan"],
            ["principal_email", "Email pimpinan"],
          ].map(([key, label]) => (
            <label key={key} className="field">
              <span>{label}</span>
              <input
                value={String(form[key as keyof SchoolForm] ?? "")}
                onChange={(event) =>
                  setForm((prev) => ({ ...prev, [key]: event.target.value }))
                }
              />
            </label>
          ))}
          {[
            ["max_user", "Kapasitas siswa"],
            ["max_total_export", "Batas export"],
            ["max_concurent_exam", "Batas ujian bersamaan"],
          ].map(([key, label]) => (
            <label key={key} className="field">
              <span>{label}</span>
              <input
                type="number"
                value={Number(form[key as keyof SchoolForm] ?? 0)}
                onChange={(event) =>
                  setForm((prev) => ({ ...prev, [key]: Number(event.target.value) }))
                }
              />
            </label>
          ))}
        </div>
        <div className="button-row">
          <button className="button" disabled={saving} type="submit">
            <Save size={16} />
            {saving ? "Menyimpan..." : "Simpan data sekolah"}
          </button>
        </div>
      </form>
    </AppShell>
  );
}
