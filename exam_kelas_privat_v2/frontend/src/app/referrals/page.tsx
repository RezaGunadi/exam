"use client";

import { useEffect, useState } from "react";
import { Coins, Gift, Wallet } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch } from "@/lib/api";

type ReferralData = {
  user: {
    referral_token?: string;
    credit_balance: number;
  };
  referrals: unknown[];
  transactions: unknown[];
  can_withdraw: boolean;
};

export default function ReferralsPage() {
  const [data, setData] = useState<ReferralData | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<ReferralData>("/api/referrals")
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat referral"));
  }, []);

  return (
    <AppShell
      title="Referral"
      description="Lihat kode referral, saldo credit, dan riwayat transaksi."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon purple">
            <Gift size={18} />
          </div>
          <div className="muted">Kode referral</div>
          <div className="stat-value" style={{ fontSize: 18 }}>
            {data?.user.referral_token ?? "-"}
          </div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon green">
            <Wallet size={18} />
          </div>
          <div className="muted">Saldo credit</div>
          <div className="stat-value">{data?.user.credit_balance ?? 0}</div>
        </div>
      </div>

      <div className="results-grid">
        <div className="panel data-card">
          <div className="button-row">
            <div className="stat-icon blue">
              <Gift size={18} />
            </div>
            <div>
              <h2>Referral masuk</h2>
              <p className="muted">Lihat daftar referral yang sudah masuk.</p>
            </div>
          </div>
          <div className="compact-list">
            {(data?.referrals ?? []).map((item, index) => {
              const row = item as Record<string, unknown>;
              return (
                <div key={index} className="compact-list-item">
                  <strong>{String(row.status ?? `Referral ${index + 1}`)}</strong>
                  <div className="meta-row">
                    <span className="meta-key">Sekolah</span>
                    <span className="meta-value">{String(row.school_id ?? "-")}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Kontributor</span>
                    <span className="meta-value">{String(row.user_contributor_id ?? "-")}</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
        <div className="panel data-card">
          <div className="button-row">
            <div className="stat-icon orange">
              <Coins size={18} />
            </div>
            <div>
              <h2>Transaksi credit</h2>
              <p className="muted">Lihat riwayat penambahan dan penggunaan credit.</p>
            </div>
          </div>
          <div className="compact-list">
            {(data?.transactions ?? []).map((item, index) => {
              const row = item as Record<string, unknown>;
              return (
                <div key={index} className="compact-list-item">
                  <strong>{String(row.type ?? `Transaksi ${index + 1}`)}</strong>
                  <div className="meta-row">
                    <span className="meta-key">Jumlah</span>
                    <span className="meta-value">{String(row.amount ?? "-")}</span>
                  </div>
                  <div className="meta-row">
                    <span className="meta-key">Referensi</span>
                    <span className="meta-value">{String(row.reference_key ?? "-")}</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </AppShell>
  );
}
