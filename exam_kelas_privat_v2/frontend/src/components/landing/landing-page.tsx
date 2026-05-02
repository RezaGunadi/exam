"use client";

import Link from "next/link";
import Script from "next/script";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { apiFetch } from "@/lib/api";

type LandingStats = {
  schools: number;
  exams: number;
  questions: number;
  exam_results: number;
};

type ContactFormState = {
  name: string;
  school: string;
  phone: string;
  email: string;
  message: string;
};

const defaultForm: ContactFormState = {
  name: "",
  school: "",
  phone: "",
  email: "",
  message: "",
};

const featureCards = [
  {
    icon: "fas fa-school",
    title: "Manajemen sekolah",
    description:
      "Kelola profil sekolah, struktur kelas, dan data utama supaya operasional harian tetap rapi dari awal.",
  },
  {
    icon: "fas fa-users",
    title: "User dan kelas",
    description:
      "Admin bisa mengatur siswa, kelas, tutor, dan akun pendamping tanpa memecah alur ke banyak halaman.",
  },
  {
    icon: "fas fa-book",
    title: "Mata pelajaran",
    description:
      "Mapel tetap tersusun jelas agar penyusunan paket soal, ujian, dan penugasan lebih mudah dipantau.",
  },
  {
    icon: "fas fa-folder",
    title: "Paket soal cerdas",
    description:
      "Susun paket, hitung total soal, dan siapkan kebutuhan import atau edit manual dari satu area kerja.",
  },
  {
    icon: "fas fa-question-circle",
    title: "Bank soal multimedia",
    description:
      "Soal pilihan ganda dan essay tetap bisa dikelola rapi untuk kebutuhan ujian sekolah sehari-hari.",
  },
  {
    icon: "fas fa-file-alt",
    title: "Ujian online terintegrasi",
    description:
      "Publish ujian, atur assignment, autosave jawaban, dan pantau pelaksanaan dari dashboard yang familiar.",
  },
  {
    icon: "fas fa-id-badge",
    title: "Penugasan fleksibel",
    description:
      "Tentukan peserta per siswa atau per kelas dengan kontrol attempt yang tetap mudah ditelusuri.",
  },
  {
    icon: "fas fa-chart-bar",
    title: "Analisis hasil",
    description:
      "Nilai, koreksi essay, catatan hasil, dan export data tetap tersedia untuk kebutuhan evaluasi sekolah.",
  },
  {
    icon: "fas fa-shield-alt",
    title: "Keamanan dan kontrol",
    description:
      "SEB, scheduler, recovery, dan worker penting tetap dipertahankan untuk menjaga proses ujian lebih stabil.",
  },
];

const moduleCards = [
  {
    icon: "fas fa-file-alt",
    title: "Ujian online",
    description:
      "Publish ujian, assignment siswa, autosave lebih stabil, attempt management, dan pemantauan hasil tetap dalam satu alur kerja.",
  },
  {
    icon: "fas fa-clipboard-check",
    title: "Absensi harian",
    description:
      "Pilih tanggal, lihat kelas, buka siswa, lalu cek detail absensi per hari tanpa lompat-lompat halaman.",
  },
  {
    icon: "fas fa-upload",
    title: "Import Excel",
    description:
      "Import siswa, bulk password, dan import soal per paket tetap memakai pola download template lalu upload Excel seperti sistem lama.",
  },
  {
    icon: "fas fa-chart-bar",
    title: "Hasil ujian",
    description:
      "Nilai, koreksi essay, export data, dan kontrol hasil ujian tetap mudah diakses dari menu operasional sekolah.",
  },
  {
    icon: "fas fa-question-circle",
    title: "Bank soal",
    description:
      "Mapel, paket soal, dan daftar soal tetap dipisah rapi supaya penyusunan materi ujian lebih mudah dipantau.",
  },
  {
    icon: "fas fa-gift",
    title: "Referral & credit",
    description:
      "Kode referral, saldo credit, dan histori transaksi tetap tersedia untuk sekolah yang memakainya.",
  },
];

const roleCards = [
  {
    title: "Admin sekolah",
    description:
      "Kelola siswa, kelas, mapel, tutor, paket soal, ujian, hasil ujian, absensi, tugas sekolah, dan scheduler.",
  },
  {
    title: "Tutor",
    description:
      "Masuk ke kelas yang diampu, lihat siswa, pantau hasil ujian, absensi, tugas sekolah, dan jalankan menu operasional yang dibutuhkan.",
  },
  {
    title: "Siswa",
    description:
      "Lihat ujian, kerjakan soal dengan autosave, cek hasil ujian, kirim tugas, dan unduh SEB saat dibutuhkan sekolah.",
  },
];

const showcaseCards = [
  {
    title: "Admin dashboard",
    description: "Pantau siswa, ujian, hasil, dan absensi dari ringkasan yang mudah dibaca.",
    pills: ["Data siswa", "Ujian aktif", "Laporan"],
    rows: ["1.250 siswa", "45 ujian aktif", "89% tingkat kelulusan"],
  },
  {
    title: "Tutor management",
    description: "Tutor langsung masuk ke kelas yang diampu dan memantau siswa tanpa menu yang membingungkan.",
    pills: ["Kelas saya", "Siswa saya", "Koreksi"],
    rows: ["Kelas 10A - Matematika", "Kelas 11B - Fisika", "2 tugas perlu ditinjau"],
  },
  {
    title: "Student portal",
    description: "Siswa melihat ujian, hasil, dan tugas dari portal yang tetap ringan dan jelas dipakai.",
    pills: ["Ujian tersedia", "Hasil terbaru", "Tugas aktif"],
    rows: ["UTS Fisika - 10:00", "UTS Matematika - 85", "1 tugas menunggu upload"],
  },
];

const workflowSteps = [
  {
    title: "Daftar dan siapkan sekolah",
    description:
      "Admin mendaftarkan sekolah, lalu melengkapi data kelas, mapel, siswa, dan tutor.",
  },
  {
    title: "Masukkan data utama",
    description:
      "Gunakan import Excel untuk siswa atau soal, lalu susun bank soal dan paket sesuai kebutuhan.",
  },
  {
    title: "Jalankan operasional harian",
    description:
      "Absensi, ujian, tugas sekolah, hasil, dan assignment tetap bergerak dari alur kerja yang sama.",
  },
  {
    title: "Pantau hasil dan tindak lanjut",
    description:
      "Admin dan tutor melihat hasil ujian, koreksi essay, export data, dan mengecek worker penting bila dibutuhkan.",
  },
];

const benefitItems = [
  {
    title: "Terasa seperti sistem yang sama",
    description:
      "Istilah menu dan alur kerja utama tetap diselaraskan dengan project sebelumnya agar adaptasi user tetap ringan.",
  },
  {
    title: "Lebih rapi dipakai harian",
    description:
      "Landing, dashboard, dan area operasional dirapikan tanpa menghilangkan fungsi yang benar-benar dipakai sekolah.",
  },
  {
    title: "Autosave dan kontrol ujian",
    description:
      "Penyimpanan jawaban, attempt management, dan monitoring hasil tetap diprioritaskan untuk area yang paling sensitif.",
  },
  {
    title: "Masih terbuka untuk pengembangan",
    description:
      "Modul penting yang belum dibawa, seperti generate rapot, tetap dipisah jelas agar tidak mengganggu fungsi inti saat ini.",
  },
];

const commitmentItems = [
  "Diskusi kebutuhan sekolah bisa menyesuaikan jumlah siswa, pola ujian, dan ritme operasional yang sudah berjalan.",
  "Sekolah yang belum aktif tetap bisa masuk dengan akses terbatas sambil melihat informasi aktivasi dan promosi yang berjalan.",
];

const parityModules = [
  "Bank soal, paket soal, dan import Excel untuk siswa maupun soal.",
  "Ujian online, attempt management, autosave, hasil ujian, dan export data.",
  "Tutor area, siswa area, SEB download, absensi, tugas sekolah, dan referral.",
  "Scheduler, recovery, dan modul operasional lain yang dipakai sekolah setiap hari.",
];

const accessCards = [
  {
    title: "Login admin, tutor, atau siswa",
    description:
      "Masuk ke dashboard sesuai peran untuk mengelola modul sekolah yang memang dibutuhkan tiap hari.",
    href: "/login",
    label: "Buka login",
  },
  {
    title: "Daftarkan sekolah baru",
    description:
      "Buat akun admin sekolah, aktifkan masa coba awal, lalu siapkan data inti untuk mulai dipakai.",
    href: "/register",
    label: "Buka register",
  },
  {
    title: "Reset password",
    description:
      "User lama yang lupa password tetap bisa masuk lagi lewat alur reset yang sudah tersedia di versi ini.",
    href: "/forgot-password",
    label: "Lupa password",
  },
];

export function LandingPage() {
  const [stats, setStats] = useState<LandingStats | null>(null);
  const [contact, setContact] = useState<ContactFormState>(defaultForm);
  const [demo, setDemo] = useState<ContactFormState>(defaultForm);
  const [contactMessage, setContactMessage] = useState<string | null>(null);
  const [demoMessage, setDemoMessage] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<LandingStats>("/api/landing/stats")
      .then(setStats)
      .catch(() => undefined);
  }, []);

  const statCards = useMemo(
    () => [
      {
        label: "Sekolah terpercaya",
        value: stats?.schools,
      },
      {
        label: "Ujian berhasil",
        value: stats?.exams,
      },
      {
        label: "Soal terkelola",
        value: stats?.questions,
      },
      {
        label: "Hasil ujian",
        value: stats?.exam_results,
      },
    ],
    [stats],
  );

  const jsonLd = useMemo(
    () => ({
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: "Exam Kelas Privat",
      applicationCategory: "EducationalApplication",
      operatingSystem: "Web",
      description:
        "Platform untuk ujian online, absensi, tugas sekolah, bank soal, import Excel, dan operasional kelas privat.",
      provider: {
        "@type": "Organization",
        name: "Exam Kelas Privat",
      },
    }),
    [],
  );

  const formatStat = (value: number | undefined) =>
    typeof value === "number" ? new Intl.NumberFormat("id-ID").format(value) : "...";

  const submitForm = async (
    endpoint: string,
    payload: ContactFormState,
    setter: (message: string) => void,
    reset: () => void,
  ) => {
    try {
      const response = await apiFetch<{ message?: string }>(endpoint, {
        method: "POST",
        body: JSON.stringify(payload),
      });
      setter(response.message ?? "Permintaan berhasil dikirim.");
      reset();
    } catch (error) {
      setter(error instanceof Error ? error.message : "Permintaan gagal dikirim.");
    }
  };

  const onContactSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    await submitForm("/api/landing/contact", contact, setContactMessage, () =>
      setContact(defaultForm),
    );
  };

  const onDemoSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    await submitForm("/api/landing/demo-request", demo, setDemoMessage, () =>
      setDemo(defaultForm),
    );
  };

  return (
    <div className="landing-page">
      <Script
        id="landing-jsonld"
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <header className="landing-header">
        <div className="landing-container landing-nav">
          <Link href="/" className="brand-mark">
            Exam Kelas Privat
          </Link>
          <nav className="landing-links" aria-label="Navigasi utama">
            <a href="#fitur">Fitur</a>
            <a href="#tampilan">Tampilan</a>
            <a href="#modul">Modul</a>
            <a href="#cara-kerja">Cara kerja</a>
            <a href="#komitmen">Komitmen</a>
            <a href="#kontak">Kontak</a>
            <Link href="/login" className="button-secondary">
              Login
            </Link>
            <Link href="/register" className="button">
              Mulai
            </Link>
          </nav>
        </div>
      </header>

      <main>
        <section className="landing-hero">
          <div className="landing-container landing-hero-grid">
            <div className="hero-copy">
              <span className="eyebrow">Sistem ujian online terpercaya untuk sekolah Indonesia</span>
              <h1>Ujian, absensi, tugas, dan operasional sekolah tetap terasa utuh dalam satu sistem.</h1>
              <p className="hero-lead">
                Exam Kelas Privat membantu admin, tutor, dan siswa menjalankan ujian digital,
                absensi, tugas sekolah, bank soal, import Excel, hasil ujian, dan monitoring kelas
                privat dari desktop, tablet, sampai mobile.
              </p>
              <div className="button-row">
                <Link href="/register" className="button">
                  Mulai sekarang
                </Link>
                <a href="#demo" className="button-secondary">
                  Minta demo
                </a>
                <Link href="/forgot-password" className="button-secondary">
                  Lupa password
                </Link>
              </div>
              <div className="hero-points" aria-label="Keunggulan utama">
                <span className="landing-chip">Keamanan ujian lebih terjaga</span>
                <span className="landing-chip">Import Excel siswa dan soal</span>
                <span className="landing-chip">Hasil ujian dan export data</span>
                <span className="landing-chip">Admin, tutor, dan siswa</span>
              </div>
            </div>

            <div className="hero-preview panel">
              <div className="preview-top">
                <span className="preview-dot" />
                <span className="preview-dot" />
                <span className="preview-dot" />
              </div>
              <div className="hero-showcase">
                <article className="preview-card accent">
                  <p className="muted">Dashboard guru</p>
                  <strong>24 ujian, 156 siswa</strong>
                  <span>Pantau ujian terbaru, hasil, dan kelas yang sedang diampu.</span>
                </article>
                <article className="preview-card">
                  <p className="muted">Dashboard siswa</p>
                  <strong>Ujian mendatang</strong>
                  <span>Lihat jadwal, hasil terbaru, dan tugas aktif dari satu portal siswa.</span>
                </article>
                <article className="preview-card">
                  <p className="muted">Interface ujian</p>
                  <strong>Autosave lebih stabil</strong>
                  <span>Pengerjaan soal pilihan ganda dan essay tetap tersimpan selama ujian berjalan.</span>
                </article>
                <article className="preview-card">
                  <p className="muted">Laporan dan analytics</p>
                  <strong>Ringkas dan siap export</strong>
                  <span>Nilai, catatan hasil, dan rekap evaluasi lebih cepat ditindaklanjuti.</span>
                </article>
              </div>
            </div>
          </div>
        </section>

        <section className="landing-stats" aria-label="Statistik platform">
          <div className="landing-container stats-grid">
            {statCards.map((item) => (
              <div key={item.label} className="stat-box">
                <strong>{formatStat(item.value)}</strong>
                <span>{item.label}</span>
              </div>
            ))}
          </div>
        </section>

        <section id="fitur" className="landing-section">
          <div className="landing-container">
            <div className="section-heading">
              <span className="eyebrow">Fitur utama</span>
              <h2>Fitur lengkap untuk kebutuhan ujian digital dan operasional sekolah.</h2>
              <p>
                Yang dipertahankan bukan hanya tampilan yang bersih, tetapi juga alur kerja penting
                yang sebelumnya memang dipakai setiap hari oleh sekolah.
              </p>
            </div>
            <div className="feature-grid">
              {featureCards.map((item) => (
                <article key={item.title} className="panel feature-card">
                  <div className="feature-icon">
                    <i className={item.icon} aria-hidden="true" />
                  </div>
                  <h3>{item.title}</h3>
                  <p>{item.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="tampilan" className="landing-section landing-section-muted">
          <div className="landing-container">
            <div className="section-heading">
              <span className="eyebrow">Tampilan aplikasi</span>
              <h2>Antarmuka yang lebih informatif untuk admin, tutor, dan siswa.</h2>
              <p>
                Area utama tetap dibuat ringkas, tetapi sekarang lebih jelas menjelaskan apa yang
                bisa dilakukan oleh tiap peran di dalam sistem.
              </p>
            </div>
            <div className="showcase-grid">
              {showcaseCards.map((item) => (
                <article key={item.title} className="panel showcase-card">
                  <div className="showcase-window">
                    <div className="preview-top">
                      <span className="preview-dot" />
                      <span className="preview-dot" />
                      <span className="preview-dot" />
                    </div>
                    <div className="showcase-pills">
                      {item.pills.map((pill) => (
                        <span key={pill} className="landing-chip">
                          {pill}
                        </span>
                      ))}
                    </div>
                    <div className="showcase-list">
                      {item.rows.map((row) => (
                        <div key={row} className="showcase-row">
                          <span>{row}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                  <h3>{item.title}</h3>
                  <p>{item.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="modul" className="landing-section landing-section-muted">
          <div className="landing-container">
            <div className="section-heading">
              <span className="eyebrow">Modul operasional</span>
              <h2>Bagian yang paling sering dipakai sekolah tetap dipertahankan.</h2>
              <p>
                Siswa, kelas, mapel, tutor, paket soal, soal, ujian, hasil ujian, absensi,
                tugas sekolah, referral, attempt management, sampai scheduler tetap ada dalam satu sistem.
              </p>
            </div>
            <div className="feature-grid">
              <article className="panel feature-card">
                <h3>Data sekolah</h3>
                <p>Kelola siswa, kelas, mapel, tutor, akun tutor, dan pengaturan sekolah.</p>
              </article>
              <article className="panel feature-card">
                <h3>Sistem ujian</h3>
                <p>Kelola paket soal, bank soal, assignment ujian, attempt, hasil ujian, dan export data.</p>
              </article>
              <article className="panel feature-card">
                <h3>Operasional harian</h3>
                <p>Absensi, tugas sekolah, referral & credit, download SEB, dan menu siswa tetap tersedia.</p>
              </article>
              <article className="panel feature-card">
                <h3>Status rapot</h3>
                <p>Generate rapot memang sedang dipisah dan akan dibangun ulang, jadi modul ini belum dibawa ke versi sekarang.</p>
              </article>
            </div>
          </div>
        </section>

        <section className="landing-section">
          <div className="landing-container two-column-section">
            <div className="section-heading left">
              <span className="eyebrow">Permukaan produk penuh</span>
              <h2>Bagian yang dulu dipakai di sistem lama tetap dijaga supaya tidak hilang diam-diam.</h2>
              <p>
                Fokus versi ini bukan hanya tampilan yang lebih modern, tetapi juga memastikan fitur
                inti sekolah tetap bisa ditemukan kembali oleh user lama.
              </p>
            </div>
            <div className="benefit-grid">
              {parityModules.map((item) => (
                <article key={item} className="panel feature-card benefit-card">
                  <h3>Fitur yang dipertahankan</h3>
                  <p>{item}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="peran" className="landing-section">
          <div className="landing-container">
            <div className="section-heading">
              <span className="eyebrow">Area pengguna</span>
              <h2>Setiap peran masuk ke menu yang memang mereka butuhkan.</h2>
            </div>
            <div className="steps-grid">
              {roleCards.map((item, index) => (
                <article key={item.title} className="panel step-card">
                  <span className="step-number">{index + 1}</span>
                  <h3>{item.title}</h3>
                  <p>{item.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="cara-kerja" className="landing-section landing-section-muted">
          <div className="landing-container">
            <div className="section-heading">
              <span className="eyebrow">Cara kerja</span>
              <h2>Alur implementasi yang mudah untuk tim sekolah.</h2>
              <p>Dalam empat langkah sederhana, sekolah sudah bisa menjalankan sistem secara penuh.</p>
            </div>
            <div className="steps-grid">
              {workflowSteps.map((item, index) => (
                <article key={item.title} className="panel step-card">
                  <span className="step-number">{index + 1}</span>
                  <h3>{item.title}</h3>
                  <p>{item.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="demo" className="landing-section">
          <div className="landing-container two-column-section">
            <div>
              <div className="section-heading left">
                <span className="eyebrow">Kenapa dipakai harian</span>
                <h2>Versi ini tetap terasa seperti aplikasi yang sama, hanya lebih rapi dan lebih stabil.</h2>
              </div>
              <div className="benefit-grid">
                {benefitItems.map((item) => (
                  <article key={item.title} className="panel feature-card benefit-card">
                    <h3>{item.title}</h3>
                    <p>{item.description}</p>
                  </article>
                ))}
              </div>
              <div className="button-row" style={{ marginTop: 16 }}>
                <Link href="/login" className="button-secondary">
                  Login
                </Link>
                <Link href="/register" className="button-secondary">
                  Register
                </Link>
              </div>
            </div>

            <form className="panel landing-form" onSubmit={onDemoSubmit}>
              <h3>Jadwalkan demo</h3>
              <label className="field">
                <span>Nama PIC</span>
                <input
                  value={demo.name}
                  onChange={(event) => setDemo((prev) => ({ ...prev, name: event.target.value }))}
                  required
                />
              </label>
              <label className="field">
                <span>Nama sekolah</span>
                <input
                  value={demo.school}
                  onChange={(event) =>
                    setDemo((prev) => ({ ...prev, school: event.target.value }))
                  }
                  required
                />
              </label>
              <label className="field">
                <span>Email</span>
                <input
                  type="email"
                  value={demo.email}
                  onChange={(event) => setDemo((prev) => ({ ...prev, email: event.target.value }))}
                  required
                />
              </label>
              <label className="field">
                <span>WhatsApp</span>
                <input
                  value={demo.phone}
                  onChange={(event) => setDemo((prev) => ({ ...prev, phone: event.target.value }))}
                  required
                />
              </label>
              <label className="field">
                <span>Kebutuhan utama</span>
                <textarea
                  rows={4}
                  value={demo.message}
                  onChange={(event) =>
                    setDemo((prev) => ({ ...prev, message: event.target.value }))
                  }
                />
              </label>
              <button type="submit" className="button">
                Kirim permintaan demo
              </button>
              {demoMessage ? <p className="muted">{demoMessage}</p> : null}
            </form>
          </div>
        </section>

        <section id="komitmen" className="landing-section landing-section-muted">
          <div className="landing-container two-column-section">
            <div className="section-heading left">
              <span className="eyebrow">Komitmen kami</span>
              <h2>Kami membantu sekolah menemukan pola penggunaan yang paling cocok.</h2>
              <p>
                Setiap sekolah punya kebutuhan, ritme belajar, dan kapasitas tim yang berbeda.
                Karena itu, implementasi dan aktivasi tetap dibuka untuk diskusi yang fleksibel.
              </p>
              <ul className="benefit-list">
                {commitmentItems.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
            <div className="panel landing-form commitment-card">
              <h3>Diskusi harga dan aktivasi</h3>
              <p className="muted">
                Tim kami siap membantu aktivasi sekolah, perpanjangan masa aktif, dan penyesuaian
                kebutuhan penggunaan untuk admin, tutor, dan siswa.
              </p>
              <div className="button-row">
                <a
                  className="button"
                  href="https://wa.me/6281211007449?text=Halo,%20saya%20ingin%20diskusi%20harga%20dan%20aktivasi%20Exam%20Kelas%20Privat"
                  target="_blank"
                  rel="noreferrer"
                >
                  <i className="fab fa-whatsapp" aria-hidden="true" />
                  Diskusi via WhatsApp
                </a>
                <a className="button-secondary" href="mailto:admin@kelasprivat.id">
                  <i className="fas fa-arrow-right" aria-hidden="true" />
                  Email admin
                </a>
              </div>
            </div>
          </div>
        </section>

        <section id="akses" className="landing-section">
          <div className="landing-container">
            <div className="section-heading">
              <span className="eyebrow">Akses user lama</span>
              <h2>Jalur masuk penting tetap tersedia untuk admin, tutor, dan siswa.</h2>
              <p>
                User tidak perlu bingung mencari pintu masuk utama. Login, daftar, dan reset password
                tetap dibuka dari permukaan publik.
              </p>
            </div>
            <div className="feature-grid">
              {accessCards.map((item) => (
                <article key={item.title} className="panel feature-card">
                  <h3>{item.title}</h3>
                  <p>{item.description}</p>
                  <Link href={item.href} className="button-secondary">
                    {item.label}
                  </Link>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="kontak" className="landing-section landing-section-muted">
          <div className="landing-container two-column-section">
            <div className="section-heading left">
              <span className="eyebrow">Hubungi kami</span>
              <h2>Ingin pengelolaan ujian, absensi, dan tugas sekolah lebih rapi?</h2>
              <p>
                Kami siap membantu menyesuaikan kebutuhan sekolah agar admin,
                tutor, dan siswa tetap nyaman menggunakan sistem setiap hari.
              </p>
            </div>

            <form className="panel landing-form" onSubmit={onContactSubmit}>
              <h3>Kirim pesan</h3>
              <label className="field">
                <span>Nama</span>
                <input
                  value={contact.name}
                  onChange={(event) =>
                    setContact((prev) => ({ ...prev, name: event.target.value }))
                  }
                  required
                />
              </label>
              <label className="field">
                <span>Nama sekolah</span>
                <input
                  value={contact.school}
                  onChange={(event) =>
                    setContact((prev) => ({ ...prev, school: event.target.value }))
                  }
                  required
                />
              </label>
              <label className="field">
                <span>Email</span>
                <input
                  type="email"
                  value={contact.email}
                  onChange={(event) =>
                    setContact((prev) => ({ ...prev, email: event.target.value }))
                  }
                  required
                />
              </label>
              <label className="field">
                <span>Nomor telepon</span>
                <input
                  value={contact.phone}
                  onChange={(event) =>
                    setContact((prev) => ({ ...prev, phone: event.target.value }))
                  }
                  required
                />
              </label>
              <label className="field">
                <span>Pesan</span>
                <textarea
                  rows={4}
                  value={contact.message}
                  onChange={(event) =>
                    setContact((prev) => ({ ...prev, message: event.target.value }))
                  }
                  required
                />
              </label>
              <button type="submit" className="button">
                Kirim pesan
              </button>
              <div className="button-row">
                <a
                  className="button-secondary"
                  href="https://wa.me/6281211007449?text=Halo,%20saya%20ingin%20info%20Exam%20Kelas%20Privat"
                  target="_blank"
                  rel="noreferrer"
                >
                  <i className="fab fa-whatsapp" aria-hidden="true" />
                  Hubungi WhatsApp
                </a>
                <a className="button-secondary" href="mailto:admin@kelasprivat.id">
                  <i className="fas fa-arrow-right" aria-hidden="true" />
                  Email admin
                </a>
              </div>
              {contactMessage ? <p className="muted">{contactMessage}</p> : null}
            </form>
          </div>
        </section>
      </main>

      <footer className="landing-footer">
        <div className="landing-container footer-grid">
          <div>
            <strong>Exam Kelas Privat</strong>
            <p>
              Platform operasional sekolah untuk ujian, absensi, tugas, dan kelas privat.
            </p>
          </div>
          <div>
            <strong>Navigasi</strong>
            <div className="footer-links">
              <a href="#fitur">Fitur</a>
              <a href="#tampilan">Tampilan</a>
              <a href="#modul">Modul</a>
              <a href="#peran">Peran</a>
              <a href="#demo">Demo</a>
              <a href="#cara-kerja">Cara kerja</a>
              <a href="#komitmen">Komitmen</a>
              <a href="#kontak">Kontak</a>
            </div>
          </div>
          <div>
            <strong>Akses</strong>
            <div className="footer-links">
              <Link href="/login">Login</Link>
              <Link href="/register">Register</Link>
              <Link href="/forgot-password">
                <i className="fas fa-key" aria-hidden="true" />
                Lupa password
              </Link>
              <span>
                <i className="fas fa-desktop" aria-hidden="true" /> Desktop, tablet, mobile
              </span>
              <span>
                <i className="fas fa-shield-alt" aria-hidden="true" /> Rapor disiapkan ulang terpisah
              </span>
            </div>
          </div>
        </div>
      </footer>

      <div className="floating-wa">
        <a
          href="https://wa.me/6281211007449?text=Halo,%20saya%20ingin%20info%20Exam%20Kelas%20Privat"
          target="_blank"
          rel="noreferrer"
          aria-label="Hubungi WhatsApp"
        >
          <i className="fab fa-whatsapp" aria-hidden="true" />
        </a>
      </div>
    </div>
  );
}
