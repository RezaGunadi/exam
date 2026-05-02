import "bootstrap/dist/css/bootstrap.min.css";
import "@fortawesome/fontawesome-free/css/all.min.css";
import "./globals.css";
import type { Metadata } from "next";
import { ReactNode } from "react";

export const metadata: Metadata = {
  metadataBase: new URL("https://examkelasprivat.id"),
  title: {
    default: "KelasPrivat",
    template: "%s | KelasPrivat",
  },
  description:
    "Platform ujian, absensi, tugas sekolah, bank soal, import Excel, hasil ujian, referral, scheduler, dan monitoring kelas privat untuk sekolah yang butuh proses lebih cepat, rapi, dan mudah diawasi.",
  applicationName: "KelasPrivat",
  keywords: [
    "ujian online sekolah",
    "aplikasi absensi sekolah",
    "kelas privat",
    "manajemen ujian",
    "bank soal sekolah",
    "import excel siswa",
    "tugas sekolah",
    "dashboard tutor",
    "hasil ujian sekolah",
    "scheduler sekolah",
    "referral sekolah",
  ],
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    locale: "id_ID",
    url: "/",
    title: "KelasPrivat",
    description:
      "Kelola ujian, absensi, tugas sekolah, bank soal, hasil ujian, referral, scheduler, dan operasional kelas privat dalam satu platform yang responsif dan siap dipakai sekolah.",
    siteName: "KelasPrivat",
  },
  twitter: {
    card: "summary_large_image",
    title: "KelasPrivat",
    description:
      "Satu platform untuk ujian online, absensi, tugas sekolah, bank soal, hasil ujian, referral, dan pemantauan kelas privat.",
  },
  robots: {
    index: true,
    follow: true,
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="id">
      <body>{children}</body>
    </html>
  );
}
