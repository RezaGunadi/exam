"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
  BookOpen,
  CheckCircle2,
  ClipboardList,
  Cog,
  ClipboardCheck,
  FileEdit,
  FileSpreadsheet,
  GraduationCap,
  Layers,
  ListChecks,
  ReceiptText,
  Rocket,
  School,
  Send,
  Shield,
  Shapes,
  UserSquare2,
  Users,
  XCircle,
} from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type StatTone = "blue" | "purple" | "green" | "orange";

type StatDef = {
  label: string;
  tone: StatTone;
};

const STAFF_STAT_DEF: Record<string, StatDef> = {
  students: { label: "Siswa", tone: "blue" },
  classes: { label: "Kelas aktif", tone: "green" },
  subjects: { label: "Mapel", tone: "purple" },
  question_packages: { label: "Paket soal", tone: "purple" },
  questions: { label: "Soal (bank)", tone: "blue" },
  exams: { label: "Ujian (total)", tone: "green" },
  draft_exams: { label: "Ujian draft", tone: "orange" },
  published_exams: { label: "Ujian terbit", tone: "green" },
  cancelled_exams: { label: "Ujian batal", tone: "orange" },
  results: { label: "Riwayat hasil ujian", tone: "blue" },
  tasks: { label: "Tugas sekolah", tone: "purple" },
  tutor_accounts: { label: "Akun tutor", tone: "orange" },
};

const STUDENT_STAT_DEF: Record<string, StatDef> = {
  assignments: { label: "Penugasan ujian", tone: "blue" },
  published_exams: { label: "Ujian terbit untuk Anda", tone: "green" },
  completed_exams: { label: "Ujian selesai", tone: "green" },
  results: { label: "Catatan hasil (semua status)", tone: "purple" },
  tasks: { label: "Tugas aktif", tone: "orange" },
  submitted_tasks: { label: "Tugas terkumpul", tone: "green" },
  graded_tasks: { label: "Tugas dinilai", tone: "purple" },
  raports: { label: "Raport terbit", tone: "blue" },
};

const STAFF_STAT_ORDER = [
  "students",
  "classes",
  "subjects",
  "question_packages",
  "questions",
  "exams",
  "draft_exams",
  "published_exams",
  "cancelled_exams",
  "results",
  "tasks",
  "tutor_accounts",
] as const;

const STUDENT_STAT_ORDER = [
  "assignments",
  "published_exams",
  "completed_exams",
  "results",
  "tasks",
  "submitted_tasks",
  "graded_tasks",
  "raports",
] as const;

const STAFF_ICONS: Record<string, typeof Users> = {
  students: Users,
  classes: School,
  subjects: BookOpen,
  question_packages: Shapes,
  questions: ListChecks,
  exams: GraduationCap,
  draft_exams: FileEdit,
  published_exams: Rocket,
  cancelled_exams: XCircle,
  results: FileSpreadsheet,
  tasks: ClipboardList,
  tutor_accounts: UserSquare2,
};

const STUDENT_ICONS: Record<string, typeof Users> = {
  assignments: Layers,
  published_exams: Send,
  completed_exams: CheckCircle2,
  results: FileSpreadsheet,
  tasks: ClipboardList,
  submitted_tasks: CheckCircle2,
  graded_tasks: FileEdit,
  raports: ReceiptText,
};

type DashboardData = {
  stats?: Record<string, number>;
  trends?: {
    exam_results_7d?: Array<{
      date: string;
      label: string;
      count: number;
    }>;
  };
  tutor?: { assignments: number };
  user?: {
    name: string;
    role: string;
  };
};

export default function DashboardPage() {
  const [data, setData] = useState<DashboardData | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<DashboardData>("/api/dashboard")
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat dashboard"));
  }, []);

  const statTiles = useMemo(() => {
    const stats = data?.stats ?? {};
    const role = data?.user?.role;
    if (role === "student") {
      return STUDENT_STAT_ORDER.filter((k) => k in stats).map((key) => ({
        key,
        value: stats[key] ?? 0,
        label: STUDENT_STAT_DEF[key]?.label ?? key,
        tone: STUDENT_STAT_DEF[key]?.tone ?? "blue",
        Icon: STUDENT_ICONS[key] ?? Users,
      }));
    }
    return STAFF_STAT_ORDER.filter((k) => k in stats).map((key) => ({
      key,
      value: stats[key] ?? 0,
      label: STAFF_STAT_DEF[key]?.label ?? key,
      tone: STAFF_STAT_DEF[key]?.tone ?? "blue",
      Icon: STAFF_ICONS[key] ?? Users,
    }));
  }, [data?.stats, data?.user?.role]);

  const description =
    data?.user?.role === "student"
      ? "Ringkasan penugasan ujian, tugas, dan hasil untuk akun Anda."
      : data?.user?.role === "tutor"
        ? "Ringkasan data sekolah dan penugasan mengajar Anda."
        : "Ringkasan data sekolah dan aktivitas ujian dari satu layar.";

  const resultTrend = data?.trends?.exam_results_7d ?? [];
  const maxTrend = Math.max(1, ...resultTrend.map((item) => item.count));

  return (
    <AppShell title="Dashboard" description={description}>
      {error ? <div className="panel data-card">{error}</div> : null}

      {data?.user?.role === "tutor" && data.tutor ? (
        <div className="panel data-card" style={{ marginBottom: 14 }}>
          <div className="section-kicker">Tutor</div>
          <h2 style={{ margin: "0 0 8px" }}>Penugasan mengajar</h2>
          <p className="muted" style={{ margin: 0 }}>
            Anda terdaftar pada{" "}
            <strong>{data.tutor.assignments}</strong> kombinasi kelas–mapel.{" "}
            <Link href="/tutor/classes">Lihat kelas saya</Link>
          </p>
        </div>
      ) : null}

      <div className="card-grid">
        {statTiles.map(({ key, value, label, tone, Icon }) => (
          <div key={key} className="panel stat-card stat-card-soft">
            <div className={`stat-icon ${tone}`}>
              <Icon size={18} />
            </div>
            <div className="muted">{label}</div>
            <div className="stat-value">{value}</div>
          </div>
        ))}
      </div>

      {resultTrend.length ? (
        <div className="panel data-card" style={{ margin: "16px 0" }}>
          <div className="section-heading-inline">
            <div>
              <div className="section-kicker">Tren 7 Hari</div>
              <h2 style={{ margin: "0 0 6px" }}>Aktivitas hasil ujian</h2>
              <p className="muted" style={{ margin: 0 }}>
                Grafik ringkas jumlah hasil ujian yang masuk per hari.
              </p>
            </div>
          </div>
          <div className="dashboard-trend-bars">
            {resultTrend.map((item) => (
              <div className="trend-bar-item" key={item.date}>
                <div className="trend-bar-track">
                  <div
                    className="trend-bar-fill"
                    style={{ height: `${Math.max(8, (item.count / maxTrend) * 100)}%` }}
                  />
                </div>
                <strong>{item.count}</strong>
                <span className="muted">{item.label}</span>
              </div>
            ))}
          </div>
        </div>
      ) : null}

      <div className="dashboard-grid">
        <div className="panel data-card">
          <div className="section-kicker">Aksi Cepat</div>
          <h2>Pilih menu yang ingin dikelola</h2>
          <p className="muted">
            Gunakan menu berikut untuk mengelola data sekolah, ujian, dan
            absensi.
          </p>
          <div className="dashboard-actions">
            {data?.user?.role === "student" ? (
              <>
                <Link href="/student/exams" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon green">
                      <GraduationCap size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Ujian Siswa</h3>
                  <p className="muted">Lihat ujian yang tersedia dan mulai ujian.</p>
                </Link>
                <Link href="/student/results" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon blue">
                      <FileSpreadsheet size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Hasil</h3>
                  <p className="muted">Pantau hasil ujian yang sudah tersedia untuk akun siswa.</p>
                </Link>
                <Link href="/student/raports" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon purple">
                      <ReceiptText size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Raport Saya</h3>
                  <p className="muted">Lihat raport yang sudah dipublish sekolah beserta rincian nilai mapel.</p>
                </Link>
                <Link href="/student/seb" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon orange">
                      <Shield size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Download SEB</h3>
                  <p className="muted">Buka panduan dan download Safe Exam Browser bila dibutuhkan sekolah.</p>
                </Link>
              </>
            ) : data?.user?.role === "tutor" ? (
              <>
                <Link href="/tutor/students" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon blue">
                      <Users size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Siswa Saya</h3>
                  <p className="muted">Lihat siswa dari kelas yang diampu tutor.</p>
                </Link>
                <Link href="/tutor/classes" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon purple">
                      <BookOpen size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Kelas Saya</h3>
                  <p className="muted">Pantau kelas aktif yang sedang diampu dari akun tutor.</p>
                </Link>
                <Link href="/tutor/question-packages" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon green">
                      <Shapes size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Paket Soal</h3>
                  <p className="muted">Tinjau paket soal yang tersedia untuk proses belajar dan ujian.</p>
                </Link>
                <Link href="/tutor/exams" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon green">
                      <GraduationCap size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Ujian</h3>
                  <p className="muted">Pantau daftar ujian seperti panel tutor Laravel.</p>
                </Link>
                <Link href="/tutor/exam-results" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon blue">
                      <FileSpreadsheet size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Hasil Ujian</h3>
                  <p className="muted">Buka laporan hasil ujian siswa dari panel tutor.</p>
                </Link>
                <Link href="/admin/attendance" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon orange">
                      <ClipboardCheck size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Absensi</h3>
                  <p className="muted">Buka absensi harian, cek tanggal, kelas, dan detail siswa.</p>
                </Link>
                <Link href="/admin/scheduler" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon green">
                      <Cog size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Scheduler</h3>
                  <p className="muted">Lihat jadwal worker dan jalankan proses penting saat dibutuhkan.</p>
                </Link>
              </>
            ) : (
              <>
                <Link href="/admin/students" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon blue">
                      <Users size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Siswa</h3>
                  <p className="muted">Lihat daftar siswa, import Excel, dan bulk password.</p>
                </Link>
                <Link href="/admin/question-packages" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon purple">
                      <Shapes size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Paket Soal</h3>
                  <p className="muted">Kelola paket, import soal, dan susun materi ujian.</p>
                </Link>
                <Link href="/admin/exams" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon green">
                      <GraduationCap size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Ujian</h3>
                  <p className="muted">Atur publish, assignment, attempt, dan pelaksanaan ujian.</p>
                </Link>
                <Link href="/admin/attendance" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon orange">
                      <ClipboardCheck size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Absensi</h3>
                  <p className="muted">Telusuri tanggal, kelas, siswa, dan detail kehadiran.</p>
                </Link>
                <Link href="/admin/scheduler" className="action-card">
                  <div className="action-card-top">
                    <div className="stat-icon purple">
                      <Cog size={18} />
                    </div>
                    <ArrowRight size={18} />
                  </div>
                  <h3>Scheduler</h3>
                  <p className="muted">Cek job penting dan jalankan double checker, recovery, atau sync semester.</p>
                </Link>
              </>
            )}
          </div>
        </div>

        <div className="panel data-card">
          <div className="section-kicker">Informasi</div>
          <h2>Ringkasan</h2>
          <div className="compact-list">
            <div className="compact-list-item">
              <div className="button-row">
                <div className="stat-icon blue">
                  <BookOpen size={18} />
                </div>
                <div>
                  <strong>Data Sekolah</strong>
                  <p className="muted">Kelola siswa, kelas, mata pelajaran, tutor, dan referral dari menu yang tersedia.</p>
                </div>
              </div>
            </div>
            <div className="compact-list-item">
              <div className="button-row">
                <div className="stat-icon green">
                  <FileSpreadsheet size={18} />
                </div>
                <div>
                  <strong>Hasil Ujian</strong>
                  <p className="muted">Lihat hasil ujian, periksa nilai, dan unduh data yang diperlukan.</p>
                </div>
              </div>
            </div>
            <div className="compact-list-item">
              <div className="button-row">
                <div className="stat-icon purple">
                  <GraduationCap size={18} />
                </div>
                <div>
                  <strong>Pelaksanaan Ujian</strong>
                  <p className="muted">Jawaban siswa disimpan otomatis selama ujian berlangsung.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
