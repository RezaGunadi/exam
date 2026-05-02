"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { PublicAuthShell } from "@/components/landing/public-auth-shell";
import { apiFetch } from "@/lib/api";

export default function ForgotPasswordPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    setMessage(null);
    try {
      const data = await apiFetch<{ message?: string; reset_token?: string; mail_status?: string }>("/api/auth/forgot-password", {
        method: "POST",
        body: JSON.stringify({ email }),
      });
      if (data.reset_token) {
        router.push(
          `/reset-password?email=${encodeURIComponent(email)}&token=${encodeURIComponent(data.reset_token)}`,
        );
        return;
      }
      setMessage(data.message ?? "Link reset password sudah dikirim jika email terdaftar.");
      setLoading(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memproses lupa password");
      setLoading(false);
    }
  }

  return (
    <PublicAuthShell>
      <div className="panel auth-card">
        <h1>Lupa Password</h1>
        <p className="muted">Masukkan email akun, lalu lanjut buat password baru.</p>

        <form className="form-grid" onSubmit={onSubmit}>
          <div className="field">
            <label htmlFor="email">Email</label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="admin@sekolah.com"
              required
            />
          </div>

          <div className="button-row">
            <button className="button" disabled={loading} type="submit">
              {loading ? "Memproses..." : "Lanjut reset password"}
            </button>
            <Link className="button-secondary" href="/login">
              Kembali ke login
            </Link>
          </div>
        </form>

        {error ? <p className="muted">{error}</p> : null}
        {message ? <div className="inline-alert">{message}</div> : null}
      </div>
    </PublicAuthShell>
  );
}
