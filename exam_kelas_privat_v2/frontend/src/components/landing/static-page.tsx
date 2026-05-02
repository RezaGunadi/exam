"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { apiFetch } from "@/lib/api";

type StaticPageProps = {
  slug: string;
};

type StaticPageData = {
  title: string;
  body: string;
};

export function StaticPage({ slug }: StaticPageProps) {
  const [page, setPage] = useState<StaticPageData | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<{ page: StaticPageData }>(`/api/pages/${slug}`)
      .then((data) => setPage(data.page))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat halaman"));
  }, [slug]);

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
        <Link className="button" href="/login">
          Masuk
        </Link>
      </nav>
      <section className="landing-section">
        <div className="panel data-card static-prose">
          {error ? <p className="muted">{error}</p> : null}
          {page ? (
            <>
              <div className="section-kicker">Informasi</div>
              <h1>{page.title}</h1>
              <p className="muted">{page.body}</p>
            </>
          ) : !error ? (
            <p className="muted">Memuat halaman...</p>
          ) : null}
        </div>
      </section>
      <footer className="landing-footer">
        <span>Exam Kelas Privat</span>
        <span>Ujian, absensi, tugas, dan laporan sekolah.</span>
      </footer>
    </main>
  );
}
