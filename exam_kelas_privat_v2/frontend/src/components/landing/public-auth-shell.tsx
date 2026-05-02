import Link from "next/link";
import { ReactNode } from "react";

type PublicAuthShellProps = {
  children: ReactNode;
};

export function PublicAuthShell({ children }: PublicAuthShellProps) {
  return (
    <main className="landing-shell">
      <nav className="landing-nav">
        <Link href="/" className="landing-brand">
          <span className="landing-brand-mark">KP</span>
          <span>KelasPrivat</span>
        </Link>
        <div className="landing-nav-links">
          <Link href="/about">Tentang</Link>
          <Link href="/contact">Kontak</Link>
          <Link href="/privacy-policy">Privasi</Link>
          <Link href="/terms">Syarat</Link>
        </div>
        <div className="button-row">
          <Link className="button-secondary" href="/login">
            Masuk
          </Link>
          <Link className="button" href="/register">
            Daftar
          </Link>
        </div>
      </nav>
      <div className="centered-page public-auth-centered">{children}</div>
    </main>
  );
}
