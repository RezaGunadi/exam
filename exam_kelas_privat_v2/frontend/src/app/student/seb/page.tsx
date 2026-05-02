"use client";

import Link from "next/link";
import { ArrowUpRight, Laptop, Shield, Smartphone } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";

const downloads = [
  {
    title: "Windows",
    description: "Windows 10/11 (64-bit)",
    href: "https://safeexambrowser.org/download_en.html",
    icon: Laptop,
  },
  {
    title: "Android",
    description: "Android 8.0 ke atas",
    href: "https://play.google.com/store/apps/details?id=org.safeexambrowser.seb",
    icon: Smartphone,
  },
  {
    title: "iPhone / iPad",
    description: "iOS 12 ke atas",
    href: "https://apps.apple.com/app/safe-exam-browser/id1450036683",
    icon: Smartphone,
  },
];

export default function StudentSebPage() {
  return (
    <AppShell
      title="Download SEB"
      description="Gunakan Safe Exam Browser saat sekolah mewajibkan mode ujian aman."
    >
      <div className="panel data-card">
        <div className="button-row">
          <div className="stat-icon orange">
            <Shield size={18} />
          </div>
          <div>
            <h2>Mode ujian aman</h2>
            <p className="muted">
              SEB membantu sekolah menjalankan ujian dengan layar penuh dan akses perangkat yang lebih terbatas.
            </p>
          </div>
        </div>
        <div className="compact-list">
          <div className="compact-list-item">Mencegah buka tab baru saat ujian berlangsung.</div>
          <div className="compact-list-item">Membantu menjaga fokus siswa selama ujian aktif.</div>
          <div className="compact-list-item">Dipakai saat sekolah mewajibkan ujian dengan Safe Exam Browser.</div>
        </div>
        <div className="button-row">
          <a
            className="button"
            href="https://ujian.kelasprivat.id/config/ujian-kelasprivat.seb"
            target="_blank"
            rel="noreferrer"
          >
            <ArrowUpRight size={16} />
            Buka konfigurasi ujian
          </a>
          <Link className="button-secondary" href="/student/exams">
            Kembali ke ujian
          </Link>
        </div>
      </div>

      <div className="results-grid">
        {downloads.map((item) => {
          const Icon = item.icon;
          return (
            <article key={item.title} className="result-card">
              <div className="result-card-header">
                <div className="button-row">
                  <div className="stat-icon blue">
                    <Icon size={18} />
                  </div>
                  <div>
                    <h3>{item.title}</h3>
                    <p className="muted">{item.description}</p>
                  </div>
                </div>
              </div>
              <a className="button-secondary" href={item.href} target="_blank" rel="noreferrer">
                <ArrowUpRight size={16} />
                Download
              </a>
            </article>
          );
        })}
      </div>
    </AppShell>
  );
}
