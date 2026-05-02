"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Megaphone, MessageCircle, ShieldAlert } from "lucide-react";
import { apiFetch, clearToken } from "@/lib/api";
import { ApiUser } from "@/lib/types";

type AdItem = {
  title: string;
  body?: string | null;
  image?: string | null;
};

export default function AdsPage() {
  const router = useRouter();
  const [user, setUser] = useState<ApiUser | null>(null);
  const [ad, setAd] = useState<AdItem | null>(null);
  const [countdown, setCountdown] = useState(20);

  useEffect(() => {
    apiFetch<{ user: ApiUser }>("/api/auth/me")
      .then((data) => {
        const activeUntil = data.user.school?.active_until;
        const isSchoolActive = Boolean(activeUntil && new Date(activeUntil).getTime() > Date.now());
        if (isSchoolActive) {
          router.push("/dashboard");
          return;
        }
        setUser(data.user);
      })
      .catch(() => {
        clearToken();
        router.push("/login");
      });
  }, [router]);

  useEffect(() => {
    if (!user) {
      return;
    }

    const activeUntil = user.school?.active_until;
    const isSchoolActive = Boolean(activeUntil && new Date(activeUntil).getTime() > Date.now());
    if (isSchoolActive) {
      return;
    }

    const timer = window.setInterval(() => {
      setCountdown((current) => {
			return Math.max(current - 1, 0);
      });
    }, 1000);

    return () => window.clearInterval(timer);
	}, [user]);

	useEffect(() => {
		if (!user || countdown > 0) {
			return;
		}
		router.push("/dashboard");
	}, [countdown, router, user]);

  useEffect(() => {
    apiFetch<{ item: AdItem | null }>("/api/ads/current")
      .then((data) => setAd(data.item))
      .catch(() => undefined);
  }, []);

  return (
    <div className="centered-page">
      <div className="panel auth-card" style={{ width: "min(760px, 100%)" }}>
        <div className="button-row" style={{ justifyContent: "space-between", alignItems: "center" }}>
          <div className="page-heading-chip">
            <Megaphone size={14} />
            Informasi Sekolah
          </div>
          <button
            type="button"
            className="button-secondary"
            onClick={() => {
              clearToken();
              router.push("/login");
            }}
          >
            Logout
          </button>
        </div>

        <h1>Langganan sekolah belum aktif</h1>
        <p className="muted">
          {user?.school?.name
            ? `${user.school.name} perlu aktivasi langganan agar akses penuh bisa dipakai kembali.`
            : "Sekolah perlu aktivasi langganan agar akses penuh bisa dipakai kembali."}
        </p>

        <div style={{ marginBottom: 20 }}>
          <div
            className="button-row"
            style={{ justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}
          >
            <strong>Masuk dashboard dalam {countdown} detik</strong>
            <span className="muted">Akses tetap dibuka dengan batasan informasi aktivasi</span>
          </div>
          <div
            style={{
              height: 8,
              borderRadius: 999,
              background: "rgba(148, 163, 184, 0.18)",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                width: `${(countdown / 20) * 100}%`,
                height: "100%",
                background: "linear-gradient(90deg, #2563eb, #1d4ed8)",
                transition: "width 1s linear",
              }}
            />
          </div>
        </div>

        <div className="inline-alert">
          <div className="button-row">
            <div className="stat-icon orange">
              <ShieldAlert size={18} />
            </div>
            <div>
              <strong>Akses tidak diblokir total</strong>
              <p className="muted">
                Halaman ini hanya interstitial informasi. Setelah countdown selesai, Anda akan
                diarahkan kembali ke dashboard dan tetap bisa masuk dengan akses terbatas.
              </p>
            </div>
          </div>
        </div>

        <div className="panel data-card">
          <div className="section-heading-inline">
            <div>
              <h3>{ad?.title ?? "Informasi penting"}</h3>
              <p className="muted">
                {ad?.body ??
                  "Aktivasi sekolah membantu membuka akses penuh ke ujian, absensi, tugas sekolah, dan menu operasional lainnya."}
              </p>
            </div>
          </div>
          {ad?.image ? (
            // eslint-disable-next-line @next/next/no-img-element -- URL gambar iklan dinamis dari API tanpa whitelist domain tetap
            <img
              src={ad.image}
              alt={ad.title ?? "Informasi sekolah"}
              style={{
                width: "100%",
                borderRadius: 16,
                border: "1px solid rgba(148, 163, 184, 0.2)",
                marginBottom: 16,
              }}
            />
          ) : null}
          <div className="button-row">
            <a
              className="button"
              href="https://wa.me/6281211007449?text=Halo,%20saya%20ingin%20aktivasi%20langganan%20Exam%20Kelas%20Privat"
              target="_blank"
              rel="noreferrer"
            >
              <MessageCircle size={16} />
              Hubungi WhatsApp
            </a>
            <button type="button" className="button-secondary" onClick={() => router.push("/dashboard")}>
              Masuk dashboard sekarang
            </button>
            <Link className="button-secondary" href="/">
              Lihat beranda
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
}
