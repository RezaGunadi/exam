"use client";

import { useState } from "react";
import { RotateCcw } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { ResourcePage } from "@/components/ui/resource-page";
import { apiFetch } from "@/lib/api";

export default function AdminReportsConfigPage() {
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function resetConfig() {
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/admin/reports-config/reset", { method: "POST", body: JSON.stringify({}) });
      setMessage("Konfigurasi laporan direset ke default.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal reset konfigurasi");
    }
  }

  return (
    <AppShell
      title="Konfigurasi Laporan"
      description="Kelola bobot tipe ujian, threshold nilai, dan pengaturan laporan."
    >
      {message ? <div className="inline-alert">{message}</div> : null}
      {error ? <div className="inline-alert danger">{error}</div> : null}
      <div className="button-row" style={{ marginBottom: 16 }}>
        <button className="button-secondary" type="button" onClick={() => void resetConfig()}>
          <RotateCcw size={16} />
          Reset default
        </button>
      </div>
      <ResourcePage
        endpoint="/api/admin/reports-config"
        title="Konfigurasi aktif"
        description="Daftar konfigurasi laporan yang tersimpan untuk sekolah ini."
      />
    </AppShell>
  );
}
