import type { Metadata } from "next";
import { LandingPage } from "@/components/landing/landing-page";

export const metadata: Metadata = {
  title: "Ujian, Absensi, Tugas, Bank Soal, dan Operasional Sekolah",
  description:
    "Exam Kelas Privat membantu sekolah mengelola ujian online, absensi harian, tugas sekolah, bank soal, import Excel, hasil ujian, scheduler, referral, dan monitoring tutor dalam satu sistem.",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title: "Exam Kelas Privat | Operasional Sekolah dalam Satu Sistem",
    description:
      "Platform operasional sekolah untuk ujian online, absensi, tugas sekolah, bank soal, hasil ujian, import Excel, referral, scheduler, dan kontrol kelas privat yang lebih cepat dan mudah diawasi.",
    url: "/",
  },
  twitter: {
    title: "Exam Kelas Privat",
    description:
      "Kelola ujian, absensi, tugas sekolah, bank soal, import Excel, hasil ujian, dan kelas privat dalam satu dashboard yang responsif.",
  },
};

export default function HomePage() {
  return <LandingPage />;
}
