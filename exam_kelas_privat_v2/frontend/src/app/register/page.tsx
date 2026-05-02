"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { PublicAuthShell } from "@/components/landing/public-auth-shell";
import { apiFetch, setToken } from "@/lib/api";

export default function RegisterPage() {
  const router = useRouter();
  const [form, setForm] = useState({
    name: "",
    email: "",
    phone: "",
    password: "",
    password_confirmation: "",
    school_name: "",
    total_siswa: 20,
    referral_code: "",
  });
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const data = await apiFetch<{ token: string; school_active: boolean }>("/api/auth/register", {
        method: "POST",
        body: JSON.stringify(form),
      });
      setToken(data.token);
      router.push(data.school_active ? "/dashboard" : "/ads");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Register gagal");
    } finally {
      setLoading(false);
    }
  }

  return (
    <PublicAuthShell>
      <div className="panel auth-card">
        <h1>Register</h1>
        <p className="muted">
          Daftarkan akun admin dan data sekolah untuk mulai menggunakan sistem.
        </p>
        <div className="page-heading-chip">Referral aktif memberi masa coba awal untuk sekolah baru.</div>

        <form className="form-grid" onSubmit={onSubmit}>
          {[
            ["name", "Nama admin"],
            ["email", "Email"],
            ["phone", "Nomor HP"],
            ["school_name", "Nama sekolah"],
            ["referral_code", "Kode referral (opsional)"],
          ].map(([key, label]) => (
            <div className="field" key={key}>
              <label htmlFor={key}>{label}</label>
              <input
                id={key}
                value={String(form[key as keyof typeof form])}
                onChange={(event) =>
                  setForm((prev) => ({ ...prev, [key]: event.target.value }))
                }
              />
            </div>
          ))}

          <div className="field">
            <label htmlFor="total_siswa">Total siswa</label>
            <input
              id="total_siswa"
              type="number"
              value={form.total_siswa}
              onChange={(event) =>
                setForm((prev) => ({
                  ...prev,
                  total_siswa: Number(event.target.value),
                }))
              }
            />
          </div>

          <div className="field">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              type="password"
              value={form.password}
              onChange={(event) =>
                setForm((prev) => ({ ...prev, password: event.target.value }))
              }
            />
          </div>

          <div className="field">
            <label htmlFor="password_confirmation">Konfirmasi password</label>
            <input
              id="password_confirmation"
              type="password"
              value={form.password_confirmation}
              onChange={(event) =>
                setForm((prev) => ({
                  ...prev,
                  password_confirmation: event.target.value,
                }))
              }
            />
          </div>

          <div className="button-row">
            <button className="button" disabled={loading} type="submit">
              {loading ? "Memproses..." : "Daftar"}
            </button>
            <Link className="button-secondary" href="/login">
              Sudah punya akun
            </Link>
          </div>
          <div className="button-row">
            <Link className="button-secondary" href="/">
              Kembali ke beranda
            </Link>
          </div>
        </form>

        {error ? <p className="muted">{error}</p> : null}
      </div>
    </PublicAuthShell>
  );
}
