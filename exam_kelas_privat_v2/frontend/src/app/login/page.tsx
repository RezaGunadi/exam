"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { PublicAuthShell } from "@/components/landing/public-auth-shell";
import { apiFetch, setToken } from "@/lib/api";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const data = await apiFetch<{ token: string; home: string; school_active: boolean }>(
        "/api/auth/login",
        {
        method: "POST",
        body: JSON.stringify({ email, password }),
        },
      );
      setToken(data.token);
      router.push(data.school_active ? (data.home || "/dashboard") : "/ads");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login gagal");
    } finally {
      setLoading(false);
    }
  }

  return (
    <PublicAuthShell>
      <div className="panel auth-card">
        <h1>Login</h1>
        <p className="muted">
          Masuk untuk mengelola data sekolah, ujian, dan absensi.
        </p>
        <form className="form-grid" onSubmit={onSubmit}>
          <div className="field">
            <label htmlFor="email">Email</label>
            <input
              id="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="admin@sekolah.com"
            />
          </div>
          <div className="field">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Masukkan password"
            />
          </div>
          <div className="button-row">
            <button className="button" disabled={loading} type="submit">
              {loading ? "Memproses..." : "Masuk"}
            </button>
            <Link className="button-secondary" href="/register">
              Buat akun baru
            </Link>
          </div>
          <div className="button-row">
            <Link className="button-secondary" href="/forgot-password">
              Lupa password
            </Link>
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
