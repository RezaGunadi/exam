"use client";

import { FormEvent, useEffect, useState } from "react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";
import { ApiUser } from "@/lib/types";

type ProfilePayload = {
  name: string;
  email: string;
  phone: string;
  address: string;
  gender: string;
  birth_date: string;
  avatar: string;
};

export default function ProfilePage() {
  const [user, setUser] = useState<ApiUser | null>(null);
  const [form, setForm] = useState<ProfilePayload>({
    name: "",
    email: "",
    phone: "",
    address: "",
    gender: "",
    birth_date: "",
    avatar: "",
  });
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<{ user: ApiUser & Record<string, unknown> }>("/api/profile")
      .then((data) => {
        const currentUser = data.user;
        setUser(currentUser);
        setForm({
          name: currentUser.name ?? "",
          email: currentUser.email ?? "",
          phone: String(currentUser.phone ?? ""),
          address: String(currentUser.address ?? ""),
          gender: String(currentUser.gender ?? ""),
          birth_date: String(currentUser.birth_date ?? "").slice(0, 10),
          avatar: String(currentUser.avatar ?? ""),
        });
      })
      .catch((error) =>
        setMessage(error instanceof Error ? error.message : "Gagal memuat profile"),
      );
  }, []);

  const submitProfile = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    try {
      const payload = {
        name: form.name,
        email: form.email,
        phone: form.phone || null,
        address: form.address || null,
        gender: form.gender || null,
        birth_date: form.birth_date || null,
      };
      const response = await apiFetch<{ user: ApiUser; message?: string }>("/api/profile", {
        method: "PUT",
        body: JSON.stringify(payload),
      });
      setUser(response.user);
      setMessage(response.message ?? "Profil berhasil diperbarui.");
      if (form.avatar.trim()) {
        await apiFetch("/api/profile/avatar", {
          method: "PUT",
          body: JSON.stringify({ avatar: form.avatar }),
        });
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Gagal menyimpan profile");
    }
  };

  return (
    <AppShell
      title="Profile"
      description="Perbarui data akun dan foto profile Anda."
    >
      {message ? <div className="panel data-card">{message}</div> : null}

      <div className="two-column-section">
        <div className="panel data-card">
          <h2>Ringkasan akun</h2>
          <div className="profile-summary">
            <div className="profile-avatar">
              {form.avatar ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={form.avatar} alt={form.name || "Avatar"} />
              ) : (
                <span>{(form.name || "U").slice(0, 1).toUpperCase()}</span>
              )}
            </div>
            <div>
              <strong>{form.name || "-"}</strong>
              <p className="muted">{user?.email ?? "-"}</p>
              <p className="muted">Peran: {user?.role ?? "-"}</p>
            </div>
          </div>
        </div>

        <form className="panel data-card" onSubmit={submitProfile}>
          <h2>Edit Profile</h2>
          <div className="form-grid">
            <label className="field">
              <span>Nama</span>
              <input
                value={form.name}
                onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
                required
              />
            </label>
            <label className="field">
              <span>Email</span>
              <input
                type="email"
                value={form.email}
                onChange={(event) => setForm((prev) => ({ ...prev, email: event.target.value }))}
                required
              />
            </label>
            <label className="field">
              <span>Telepon</span>
              <input
                value={form.phone}
                onChange={(event) => setForm((prev) => ({ ...prev, phone: event.target.value }))}
              />
            </label>
            <label className="field">
              <span>Tanggal lahir</span>
              <input
                type="date"
                value={form.birth_date}
                onChange={(event) =>
                  setForm((prev) => ({ ...prev, birth_date: event.target.value }))
                }
              />
            </label>
            <label className="field">
              <span>Gender</span>
              <select
                value={form.gender}
                onChange={(event) => setForm((prev) => ({ ...prev, gender: event.target.value }))}
              >
                <option value="">Pilih</option>
                <option value="male">Laki-laki</option>
                <option value="female">Perempuan</option>
                <option value="other">Lainnya</option>
              </select>
            </label>
            <label className="field">
              <span>URL avatar</span>
              <input
                value={form.avatar}
                onChange={(event) => setForm((prev) => ({ ...prev, avatar: event.target.value }))}
                placeholder="https://..."
              />
            </label>
            <label className="field">
              <span>Alamat</span>
              <textarea
                rows={4}
                value={form.address}
                onChange={(event) =>
                  setForm((prev) => ({ ...prev, address: event.target.value }))
                }
              />
            </label>
          </div>
          <div className="button-row">
            <button type="submit" className="button">
              Simpan perubahan
            </button>
          </div>
        </form>
      </div>
    </AppShell>
  );
}
