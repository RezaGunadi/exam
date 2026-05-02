"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";
import { ApiUser } from "@/lib/types";

type TutorUser = {
  id: number;
  name: string;
  email: string;
  phone?: string | null;
};

type TutorAssignmentRow = {
  id: number;
  tutor_id: number;
  class_id: number;
  subject_id: number;
  school_id: number;
};

type ClassItem = { id: number; name: string };
type SubjectItem = { id: number; name: string };

export default function AdminTutorsPage() {
  const [role, setRole] = useState<ApiUser["role"] | null>(null);
  const [tutors, setTutors] = useState<TutorUser[]>([]);
  const [assignments, setAssignments] = useState<TutorAssignmentRow[]>([]);
  const [classes, setClasses] = useState<ClassItem[]>([]);
  const [subjects, setSubjects] = useState<SubjectItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const [assignForm, setAssignForm] = useState({
    tutor_id: 0,
    class_id: 0,
    subject_id: 0,
  });

  const [userForm, setUserForm] = useState({
    name: "",
    email: "",
    password: "",
    phone: "",
  });
  const [editingUser, setEditingUser] = useState<TutorUser | null>(null);
  const [saving, setSaving] = useState(false);

  const loadAll = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const me = await apiFetch<{ user: ApiUser }>("/api/auth/me");
      setRole(me.user.role);

      const [ov, cls, subj] = await Promise.all([
        apiFetch<{ tutors: TutorUser[]; assignments: TutorAssignmentRow[] }>("/api/admin/tutors"),
        apiFetch<{ items: ClassItem[] }>("/api/admin/classes"),
        apiFetch<{ items: SubjectItem[] }>("/api/admin/subjects"),
      ]);
      setTutors(ov.tutors);
      setAssignments(ov.assignments);
      setClasses(cls.items);
      setSubjects(subj.items);

      const firstTutor = ov.tutors[0];
      const firstClass = cls.items[0];
      const firstSubj = subj.items[0];
      setAssignForm((prev) => ({
        tutor_id: prev.tutor_id || firstTutor?.id || 0,
        class_id: prev.class_id || firstClass?.id || 0,
        subject_id: prev.subject_id || firstSubj?.id || 0,
      }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat data tutor");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadAll();
  }, [loadAll]);

  const tutorName = useMemo(() => {
    const m = new Map<number, string>();
    for (const t of tutors) {
      m.set(t.id, t.name);
    }
    return m;
  }, [tutors]);

  const className = useMemo(() => {
    const m = new Map<number, string>();
    for (const c of classes) {
      m.set(c.id, c.name);
    }
    return m;
  }, [classes]);

  const subjectName = useMemo(() => {
    const m = new Map<number, string>();
    for (const s of subjects) {
      m.set(s.id, s.name);
    }
    return m;
  }, [subjects]);

  const isAdmin = role === "admin";

  async function handleCreateAssignment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!assignForm.tutor_id || !assignForm.class_id || !assignForm.subject_id) {
      setError("Pilih tutor, kelas, dan mapel.");
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/admin/tutors", {
        method: "POST",
        body: JSON.stringify({
          tutor_id: assignForm.tutor_id,
          class_id: assignForm.class_id,
          subject_id: assignForm.subject_id,
        }),
      });
      setMessage("Penugasan tutor ditambahkan.");
      await loadAll();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menambah penugasan");
    } finally {
      setSaving(false);
    }
  }

  async function removeAssignment(id: number) {
    if (!window.confirm("Hapus penugasan ini?")) {
      return;
    }
    try {
      await apiFetch(`/api/admin/tutors/${id}`, { method: "DELETE" });
      setMessage("Penugasan dihapus.");
      await loadAll();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus");
    }
  }

  async function handleCreateUser(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!userForm.name.trim() || !userForm.email.trim() || !userForm.password) {
      setError("Nama, email, dan password wajib diisi.");
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/admin/tutor-users", {
        method: "POST",
        body: JSON.stringify({
          name: userForm.name.trim(),
          email: userForm.email.trim(),
          password: userForm.password,
          phone: userForm.phone.trim() || undefined,
        }),
      });
      setMessage("Akun tutor dibuat.");
      setUserForm({ name: "", email: "", password: "", phone: "" });
      await loadAll();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal membuat akun");
    } finally {
      setSaving(false);
    }
  }

  async function handleUpdateUser(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!editingUser) {
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const payload: Record<string, string | undefined> = {
        name: userForm.name.trim(),
        email: userForm.email.trim(),
        phone: userForm.phone.trim() || undefined,
      };
      if (userForm.password.trim()) {
        payload.password = userForm.password;
      }
      await apiFetch(`/api/admin/tutor-users/${editingUser.id}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      });
      setMessage("Data tutor diperbarui.");
      setEditingUser(null);
      setUserForm({ name: "", email: "", password: "", phone: "" });
      await loadAll();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memperbarui");
    } finally {
      setSaving(false);
    }
  }

  async function deleteUser(id: number) {
    if (!window.confirm("Nonaktifkan dan hapus akun tutor ini?")) {
      return;
    }
    try {
      await apiFetch(`/api/admin/tutor-users/${id}`, { method: "DELETE" });
      setMessage("Akun tutor dihapus.");
      if (editingUser?.id === id) {
        setEditingUser(null);
      }
      await loadAll();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus");
    }
  }

  function startEdit(u: TutorUser) {
    setEditingUser(u);
    setUserForm({
      name: u.name,
      email: u.email,
      password: "",
      phone: u.phone ?? "",
    });
  }

  return (
    <AppShell
      title="Tutor"
      description="Kelola penugasan tutor ke kelas dan mapel, serta akun tutor sekolah."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      {loading ? <p className="muted">Memuat…</p> : null}

      <div className="attendance-grid">
        <form className="panel data-card" onSubmit={handleCreateAssignment}>
          <div className="section-heading-inline">
            <div>
              <h3>Penugasan tutor</h3>
              <p className="muted">Hubungkan tutor dengan kelas dan mata pelajaran.</p>
            </div>
          </div>
          <div className="resource-form-grid">
            <label className="field">
              <span>Tutor</span>
              <select
                value={assignForm.tutor_id}
                onChange={(e) =>
                  setAssignForm((p) => ({ ...p, tutor_id: Number(e.target.value) }))
                }
              >
                <option value={0}>— pilih —</option>
                {tutors.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>Kelas</span>
              <select
                value={assignForm.class_id}
                onChange={(e) =>
                  setAssignForm((p) => ({ ...p, class_id: Number(e.target.value) }))
                }
              >
                <option value={0}>— pilih —</option>
                {classes.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>Mapel</span>
              <select
                value={assignForm.subject_id}
                onChange={(e) =>
                  setAssignForm((p) => ({ ...p, subject_id: Number(e.target.value) }))
                }
              >
                <option value={0}>— pilih —</option>
                {subjects.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <div className="button-row">
            <button className="button" type="submit" disabled={saving}>
              Tambah penugasan
            </button>
          </div>
        </form>

        <div className="panel data-card">
          <h3>Daftar penugasan ({assignments.length})</h3>
          <div className="feedback-wrap">
            <table className="feedback-table">
              <thead>
                <tr>
                  <th>Tutor</th>
                  <th>Kelas</th>
                  <th>Mapel</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {assignments.map((a) => (
                  <tr key={a.id}>
                    <td>{tutorName.get(a.tutor_id) ?? `#${a.tutor_id}`}</td>
                    <td>{className.get(a.class_id) ?? `#${a.class_id}`}</td>
                    <td>{subjectName.get(a.subject_id) ?? `#${a.subject_id}`}</td>
                    <td>
                      <button
                        className="button-danger"
                        type="button"
                        onClick={() => void removeAssignment(a.id)}
                      >
                        Hapus
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {assignments.length === 0 ? <p className="muted">Belum ada penugasan.</p> : null}
        </div>
      </div>

      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Akun tutor</h3>
            <p className="muted">Buat atau edit kredensial tutor. {isAdmin ? null : "Lihat saja."}</p>
          </div>
        </div>

        {editingUser ? (
          <form className="resource-form-grid" onSubmit={handleUpdateUser}>
            <label className="field">
              <span>Nama</span>
              <input
                value={userForm.name}
                onChange={(e) => setUserForm((p) => ({ ...p, name: e.target.value }))}
                required
              />
            </label>
            <label className="field">
              <span>Email</span>
              <input
                type="email"
                value={userForm.email}
                onChange={(e) => setUserForm((p) => ({ ...p, email: e.target.value }))}
                required
              />
            </label>
            <label className="field">
              <span>Password baru (opsional)</span>
              <input
                type="password"
                value={userForm.password}
                onChange={(e) => setUserForm((p) => ({ ...p, password: e.target.value }))}
                placeholder="Kosongkan jika tidak mengganti"
              />
            </label>
            <label className="field">
              <span>Telepon</span>
              <input
                value={userForm.phone}
                onChange={(e) => setUserForm((p) => ({ ...p, phone: e.target.value }))}
              />
            </label>
            <div className="button-row" style={{ gridColumn: "1 / -1" }}>
              <button className="button" type="submit" disabled={saving || !isAdmin}>
                Simpan perubahan
              </button>
              <button
                className="button-secondary"
                type="button"
                onClick={() => {
                  setEditingUser(null);
                  setUserForm({ name: "", email: "", password: "", phone: "" });
                }}
              >
                Batal edit
              </button>
            </div>
          </form>
        ) : (
          <form className="resource-form-grid" onSubmit={handleCreateUser}>
            <label className="field">
              <span>Nama</span>
              <input
                value={userForm.name}
                onChange={(e) => setUserForm((p) => ({ ...p, name: e.target.value }))}
                required
              />
            </label>
            <label className="field">
              <span>Email</span>
              <input
                type="email"
                value={userForm.email}
                onChange={(e) => setUserForm((p) => ({ ...p, email: e.target.value }))}
                required
              />
            </label>
            <label className="field">
              <span>Password awal</span>
              <input
                type="password"
                value={userForm.password}
                onChange={(e) => setUserForm((p) => ({ ...p, password: e.target.value }))}
                required
              />
            </label>
            <label className="field">
              <span>Telepon</span>
              <input
                value={userForm.phone}
                onChange={(e) => setUserForm((p) => ({ ...p, phone: e.target.value }))}
              />
            </label>
            <div className="button-row" style={{ gridColumn: "1 / -1" }}>
              <button className="button" type="submit" disabled={saving || !isAdmin}>
                Buat akun tutor
              </button>
            </div>
          </form>
        )}

        <div className="feedback-wrap" style={{ marginTop: 16 }}>
          <table className="feedback-table">
            <thead>
              <tr>
                <th>Nama</th>
                <th>Email</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {tutors.map((u) => (
                <tr key={u.id}>
                  <td>{u.name}</td>
                  <td>{u.email}</td>
                  <td>
                    {isAdmin ? (
                      <div className="button-row">
                        <button
                          className="button-secondary"
                          type="button"
                          onClick={() => startEdit(u)}
                        >
                          Edit
                        </button>
                        <button
                          className="button-danger"
                          type="button"
                          onClick={() => void deleteUser(u.id)}
                        >
                          Hapus
                        </button>
                      </div>
                    ) : (
                      <span className="muted">—</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="muted">Login tutor di halaman yang sama dengan admin/siswa; peran ditentukan oleh akun.</p>
      </div>
    </AppShell>
  );
}
