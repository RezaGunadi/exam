"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { FormEvent, Suspense, useMemo, useState } from "react";
import { apiFetch } from "@/lib/api";

function ResetPasswordContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const email = useMemo(() => searchParams.get("email") ?? "", [searchParams]);
  const token = useMemo(() => searchParams.get("token") ?? "", [searchParams]);
  const [password, setPassword] = useState("");
  const [passwordConfirmation, setPasswordConfirmation] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    setSuccess(null);
    try {
      const data = await apiFetch<{ message?: string }>("/api/auth/reset-password", {
        method: "POST",
        body: JSON.stringify({
          email,
          token,
          password,
          password_confirmation: passwordConfirmation,
        }),
      });
      setSuccess(data.message ?? "Password berhasil diubah.");
      setTimeout(() => {
        router.push("/login");
      }, 1200);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal reset password");
      setLoading(false);
    }
  }

  if (!email || !token) {
    return (
      <div className="centered-page">
        <div className="panel auth-card">
          <h1>Reset Password</h1>
          <p className="muted">Link reset belum lengkap. Mulai lagi dari halaman lupa password.</p>
          <div className="button-row">
            <Link className="button" href="/forgot-password">
              Buka lupa password
            </Link>
            <Link className="button-secondary" href="/login">
              Kembali ke login
            </Link>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="centered-page">
      <div className="panel auth-card">
        <h1>Reset Password</h1>
        <p className="muted">Buat password baru untuk akun {email}.</p>

        <form className="form-grid" onSubmit={onSubmit}>
          <div className="field">
            <label htmlFor="email">Email</label>
            <input id="email" value={email} readOnly />
          </div>
          <div className="field">
            <label htmlFor="password">Password baru</label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Minimal 8 karakter"
              minLength={8}
              required
            />
          </div>
          <div className="field">
            <label htmlFor="password_confirmation">Konfirmasi password</label>
            <input
              id="password_confirmation"
              type="password"
              value={passwordConfirmation}
              onChange={(event) => setPasswordConfirmation(event.target.value)}
              placeholder="Ulangi password baru"
              minLength={8}
              required
            />
          </div>

          <div className="button-row">
            <button className="button" disabled={loading} type="submit">
              {loading ? "Menyimpan..." : "Simpan password baru"}
            </button>
            <Link className="button-secondary" href="/login">
              Kembali ke login
            </Link>
          </div>
        </form>

        {success ? <p className="muted">{success}</p> : null}
        {error ? <p className="muted">{error}</p> : null}
      </div>
    </div>
  );
}

export default function ResetPasswordPage() {
  return (
    <Suspense
      fallback={
        <div className="centered-page">
          <div className="panel auth-card">
            <h1>Reset Password</h1>
            <p className="muted">Menyiapkan form reset password...</p>
          </div>
        </div>
      }
    >
      <ResetPasswordContent />
    </Suspense>
  );
}
