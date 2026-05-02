"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { ReactNode, useEffect, useMemo, useState } from "react";
import { apiFetch, clearToken } from "@/lib/api";
import { ApiUser } from "@/lib/types";

type AppShellProps = {
  children: ReactNode;
  title: string;
  description?: string;
};

type NavLinkItem = {
  href: string;
  label: string;
  icon: string;
  roles: Array<ApiUser["role"]>;
};

type NavSection = {
  title: string;
  links: NavLinkItem[];
};

const navSections: NavSection[] = [
  {
    title: "Umum",
    links: [
      { href: "/dashboard", label: "Dashboard", icon: "fas fa-tachometer-alt", roles: ["admin", "tutor", "student"] },
      { href: "/profile", label: "Profile", icon: "fas fa-user", roles: ["admin", "tutor", "student"] },
    ],
  },
  {
    title: "Data Sekolah",
    links: [
      { href: "/admin/school", label: "Data Sekolah", icon: "fas fa-school", roles: ["admin"] },
      { href: "/admin/students", label: "Siswa", icon: "fas fa-users", roles: ["admin"] },
      { href: "/admin/classes", label: "Kelas", icon: "fas fa-chalkboard", roles: ["admin"] },
      { href: "/tutor/students", label: "Siswa Saya", icon: "fas fa-users", roles: ["tutor"] },
      { href: "/tutor/classes", label: "Kelas Saya", icon: "fas fa-chalkboard", roles: ["tutor"] },
      { href: "/admin/subjects", label: "Mata Pelajaran", icon: "fas fa-book", roles: ["admin"] },
      { href: "/tutor/subjects", label: "Mata Pelajaran", icon: "fas fa-book", roles: ["tutor"] },
      { href: "/admin/subject-orders", label: "Urutan Mata Pelajaran", icon: "fas fa-sort", roles: ["admin"] },
      { href: "/admin/subject-kkm", label: "KKM Mata Pelajaran", icon: "fas fa-graduation-cap", roles: ["admin"] },
      { href: "/admin/tutors", label: "Tutor Management", icon: "fas fa-user-tie", roles: ["admin"] },
    ],
  },
  {
    title: "Sistem Ujian",
    links: [
      { href: "/admin/question-packages", label: "Paket Soal", icon: "fas fa-folder", roles: ["admin"] },
      { href: "/tutor/question-packages", label: "Paket Soal", icon: "fas fa-folder", roles: ["tutor"] },
      { href: "/admin/questions", label: "Soal", icon: "fas fa-question-circle", roles: ["admin"] },
      { href: "/tutor/questions", label: "Soal", icon: "fas fa-file-alt", roles: ["tutor"] },
      { href: "/admin/exams", label: "Ujian", icon: "fas fa-file-alt", roles: ["admin"] },
      { href: "/tutor/exams", label: "Ujian", icon: "fas fa-file-alt", roles: ["tutor"] },
      { href: "/admin/attempt-management", label: "Manajemen Attempt", icon: "fas fa-redo", roles: ["admin"] },
      { href: "/tutor/attempt-management", label: "Manajemen Attempt", icon: "fas fa-redo", roles: ["tutor"] },
      { href: "/admin/exam-results", label: "Hasil Ujian", icon: "fas fa-chart-bar", roles: ["admin"] },
      { href: "/tutor/exam-results", label: "Hasil Ujian", icon: "fas fa-chart-bar", roles: ["tutor"] },
      { href: "/admin/ai-scoring", label: "AI Scoring", icon: "fas fa-robot", roles: ["admin", "tutor"] },
      { href: "/student/exams", label: "Ujian Saya", icon: "fas fa-file-alt", roles: ["student"] },
      { href: "/student/results", label: "Hasil Ujian", icon: "fas fa-chart-line", roles: ["student"] },
    ],
  },
  {
    title: "Operasional",
    links: [
      { href: "/admin/attendance", label: "Absensi", icon: "fas fa-clipboard-check", roles: ["admin", "tutor"] },
      { href: "/admin/tasks", label: "Tugas Sekolah", icon: "fas fa-tasks", roles: ["admin", "tutor"] },
      { href: "/admin/reports", label: "Laporan", icon: "fas fa-file-excel", roles: ["admin"] },
      { href: "/admin/reports-config", label: "Konfigurasi Laporan", icon: "fas fa-cog", roles: ["admin"] },
      { href: "/admin/raports", label: "Raport", icon: "fas fa-file-alt", roles: ["admin"] },
      { href: "/student/tasks", label: "Tugas Sekolah", icon: "fas fa-tasks", roles: ["student"] },
      { href: "/student/raports", label: "Raport Saya", icon: "fas fa-file-alt", roles: ["student"] },
      { href: "/student/seb", label: "Download SEB", icon: "fas fa-shield-alt", roles: ["student"] },
      { href: "/admin/scheduler", label: "Scheduler", icon: "fas fa-cog", roles: ["admin", "tutor"] },
      { href: "/referrals", label: "Referral & Credit", icon: "fas fa-gift", roles: ["admin", "tutor"] },
    ],
  },
];

export function AppShell({ children, title, description }: AppShellProps) {
  const pathname = usePathname();
  const router = useRouter();
  const [user, setUser] = useState<ApiUser | null>(null);
  const [isNavOpen, setIsNavOpen] = useState(false);

  useEffect(() => {
    apiFetch<{ user: ApiUser }>("/api/auth/me")
      .then((data) => {
        setUser(data.user);
      })
      .catch((err) => {
        clearToken();
        router.push("/login");
      });
  }, [pathname, router]);

  const visibleSections = useMemo(() => {
    if (!user) {
      return [];
    }
    return navSections
      .map((section) => ({
        ...section,
        links: section.links.filter((link) => link.roles.includes(user.role)),
      }))
      .filter((section) => section.links.length > 0);
  }, [user]);

  const isSchoolActive = useMemo(() => {
    const activeUntil = user?.school?.active_until;
    return Boolean(activeUntil && new Date(activeUntil).getTime() > Date.now());
  }, [user]);

  const onLogout = async () => {
    try {
      await apiFetch("/api/auth/logout", { method: "POST" });
    } finally {
      clearToken();
      router.push("/login");
    }
  };

  return (
    <div className={`shell shell-${user?.role ?? "loading"}`}>
      {user?.role === "student" ? (
        <nav className="student-topbar navbar navbar-expand-lg navbar-dark bg-primary">
          <div className="container-fluid">
            <Link className="navbar-brand" href="/dashboard">
              <i className="fas fa-graduation-cap me-2" aria-hidden="true" />
              <strong>{user.school?.name ?? "Sistem Ujian Online"}</strong>
            </Link>
            <div className="navbar-nav me-auto student-topbar-links">
              <Link className={`nav-link ${pathname === "/dashboard" ? "active" : ""}`} href="/dashboard">
                <i className="fas fa-tachometer-alt me-1" aria-hidden="true" />
                Dashboard
              </Link>
              <Link className={`nav-link ${pathname.startsWith("/student/exams") ? "active" : ""}`} href="/student/exams">
                <i className="fas fa-file-alt me-1" aria-hidden="true" />
                Ujian Saya
              </Link>
              <Link className={`nav-link ${pathname.startsWith("/student/results") ? "active" : ""}`} href="/student/results">
                <i className="fas fa-chart-line me-1" aria-hidden="true" />
                Hasil Ujian
              </Link>
              <Link className={`nav-link ${pathname.startsWith("/student/tasks") ? "active" : ""}`} href="/student/tasks">
                <i className="fas fa-tasks me-1" aria-hidden="true" />
                Tugas Sekolah
              </Link>
            </div>
            <button type="button" className="btn btn-link nav-link text-white" onClick={onLogout}>
              <i className="fas fa-sign-out-alt me-1" aria-hidden="true" />
              Logout
            </button>
          </div>
        </nav>
      ) : null}
      <aside className={`sidebar ${isNavOpen ? "open" : ""}`}>
        <div className="sidebar-brand">
          <div className="sidebar-logo">
            <i className="fas fa-graduation-cap" aria-hidden="true" />
          </div>
          <div>
            <h2>{user?.role === "student" ? (user.school?.name ?? "Sistem Ujian Online") : "Sistem Admin"}</h2>
            <p className="muted sidebar-subtitle">
              {user ? `${user.name} - ${user.role}` : "Memuat sesi..."}
            </p>
          </div>
        </div>

        {user?.role !== "student" ? (
          <div className="token-chip-sidebar">
            <i className="fas fa-coins" aria-hidden="true" />
            <span>Token</span>
            <strong>{user?.school?.token_balance ?? 0}</strong>
            <small>{user?.school?.subscription_type ?? "token_based"}</small>
          </div>
        ) : null}

        <nav className="sidebar-sections">
          {visibleSections.map((section) => (
            <div key={section.title} className="sidebar-section">
              <div className="sidebar-section-title">{section.title}</div>
              <div className="sidebar-link-list">
                {section.links.map((link) => {
                  return (
                    <Link
                      key={link.href}
                      href={link.href}
                      onClick={() => setIsNavOpen(false)}
                      className={`nav-link ${pathname === link.href || pathname.startsWith(`${link.href}/`) ? "active" : ""}`}
                    >
                      <i className={link.icon} aria-hidden="true" />
                      <span>{link.label}</span>
                    </Link>
                  );
                })}
              </div>
            </div>
          ))}
        </nav>

        <div className="button-row">
          <button className="button-secondary" onClick={onLogout}>
            <i className="fas fa-sign-out-alt" aria-hidden="true" />
            Logout
          </button>
        </div>
      </aside>

      <main className="content">
        <div className="toolbar">
          <div>
            <button
              className="button-secondary shell-menu-button"
              type="button"
              onClick={() => setIsNavOpen((value) => !value)}
            >
              <i className="fas fa-bars" aria-hidden="true" />
              Menu
            </button>
            <div className="page-heading-chip">
              <i className="fas fa-home" aria-hidden="true" />
              {title}
            </div>
            <h1 className="page-title">{title}</h1>
            {description ? <p className="muted">{description}</p> : null}
          </div>
        </div>
        {user && !isSchoolActive ? (
          <div className="inline-alert danger" style={{ marginBottom: 16 }}>
            <div className="button-row" style={{ justifyContent: "space-between", alignItems: "center" }}>
              <div>
                <strong>Sekolah belum berlangganan aktif</strong>
                <p className="muted" style={{ margin: "6px 0 0" }}>
                  Akses tetap dibuka dengan batasan informasi aktivasi. Anda masih bisa masuk ke
                  sistem sambil melihat detail aktivasi sekolah.
                </p>
              </div>
              <Link href="/ads" className="button-secondary">
                Lihat info aktivasi
              </Link>
            </div>
          </div>
        ) : null}
        {children}
      </main>
    </div>
  );
}
