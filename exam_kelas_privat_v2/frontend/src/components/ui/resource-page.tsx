"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { Database, FileSpreadsheet, Inbox, Pencil, Plus, Save, Sparkles, Trash2, X } from "lucide-react";
import { apiFetch } from "@/lib/api";

type ResourcePageProps = {
  endpoint: string;
  title: string;
  description: string;
  createHint?: Record<string, unknown>;
};

type ResourceRecord = Record<string, unknown> & {
  id?: number;
};

export function ResourcePage({
  endpoint,
  title,
  description,
  createHint,
}: ResourcePageProps) {
  const [items, setItems] = useState<ResourceRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingItem, setEditingItem] = useState<ResourceRecord | null>(null);
  const [saving, setSaving] = useState(false);
  const [formValues, setFormValues] = useState<Record<string, unknown>>({});

  const formFields = useMemo(() => Object.keys(createHint ?? {}), [createHint]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiFetch<{ items?: ResourceRecord[] }>(endpoint);
      setItems(data.items ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat data");
    } finally {
      setLoading(false);
    }
  }, [endpoint]);

  useEffect(() => {
    void load();
  }, [load]);

  const filteredItems = useMemo(() => {
    if (!search.trim()) {
      return items;
    }
    const keyword = search.toLowerCase();
    return items.filter((item) =>
      JSON.stringify(item).toLowerCase().includes(keyword),
    );
  }, [items, search]);

  function getDisplayRows(item: ResourceRecord) {
    return Object.entries(item)
      .filter(([, value]) => value !== null && value !== "" && typeof value !== "object")
      .filter(([key]) => !["id", "created_at", "updated_at", "deleted_at", "school_id"].includes(key))
      .slice(0, 6);
  }

  function normalizeFieldValue(key: string, value: unknown, record?: ResourceRecord) {
    const hint = createHint?.[key];
    const source = record?.[key] ?? value;
    if (Array.isArray(hint)) {
      if (Array.isArray(source)) {
        return source.join("\n");
      }
      return typeof source === "string" ? source : "";
    }
    if (typeof hint === "boolean") {
      return Boolean(source);
    }
    if (typeof hint === "number") {
      return typeof source === "number" ? source : source ? Number(source) : 0;
    }
    return typeof source === "string" ? source : source == null ? "" : String(source);
  }

  function openCreateForm() {
    const nextValues = Object.fromEntries(
      formFields.map((field) => [field, normalizeFieldValue(field, createHint?.[field])]),
    );
    setEditingItem(null);
    setFormValues(nextValues);
    setIsFormOpen(true);
    setMessage(null);
  }

  function openEditForm(item: ResourceRecord) {
    const nextValues = Object.fromEntries(
      formFields.map((field) => [field, normalizeFieldValue(field, createHint?.[field], item)]),
    );
    if ("password" in nextValues) {
      nextValues.password = "";
    }
    setEditingItem(item);
    setFormValues(nextValues);
    setIsFormOpen(true);
    setMessage(null);
  }

  function closeForm() {
    setEditingItem(null);
    setFormValues({});
    setIsFormOpen(false);
  }

  function buildPayload() {
    const payload: Record<string, unknown> = {};
    for (const field of formFields) {
      const hint = createHint?.[field];
      const rawValue = formValues[field];
      if (Array.isArray(hint)) {
        const text = String(rawValue ?? "").trim();
        payload[field] = text ? text.split(/\r?\n|,/).map((item) => item.trim()).filter(Boolean) : [];
        continue;
      }
      if (typeof hint === "boolean") {
        payload[field] = Boolean(rawValue);
        continue;
      }
      if (typeof hint === "number") {
        payload[field] = rawValue === "" || rawValue == null ? 0 : Number(rawValue);
        continue;
      }
      const text = String(rawValue ?? "").trim();
      if (field === "password" && editingItem && !text) {
        continue;
      }
      payload[field] = text;
    }
    return payload;
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const payload = buildPayload();
      if (editingItem?.id) {
        await apiFetch(`${endpoint}/${editingItem.id}`, {
          method: "PUT",
          body: JSON.stringify(payload),
        });
        setMessage("Data berhasil diperbarui.");
      } else {
        await apiFetch(endpoint, {
          method: "POST",
          body: JSON.stringify(payload),
        });
        setMessage("Data berhasil ditambahkan.");
      }
      closeForm();
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan data");
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(item: ResourceRecord) {
    if (!item.id) {
      return;
    }
    const confirmed = window.confirm("Hapus data ini?");
    if (!confirmed) {
      return;
    }
    setError(null);
    setMessage(null);
    try {
      await apiFetch(`${endpoint}/${item.id}`, { method: "DELETE" });
      setMessage("Data berhasil dihapus.");
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus data");
    }
  }

  function renderField(field: string) {
    const hint = createHint?.[field];
    const value = formValues[field];
    const label = field.replaceAll("_", " ");

    if (typeof hint === "boolean") {
      return (
        <label key={field} className="field checkbox-field">
          <span>{label}</span>
          <input
            type="checkbox"
            checked={Boolean(value)}
            onChange={(event) =>
              setFormValues((prev) => ({ ...prev, [field]: event.target.checked }))
            }
          />
        </label>
      );
    }

    if (Array.isArray(hint)) {
      return (
        <label key={field} className="field">
          <span>{label}</span>
          <textarea
            rows={4}
            value={String(value ?? "")}
            onChange={(event) =>
              setFormValues((prev) => ({ ...prev, [field]: event.target.value }))
            }
            placeholder="Pisahkan dengan enter atau koma"
          />
        </label>
      );
    }

    const inputType =
      field.includes("password") ? "password" : typeof hint === "number" ? "number" : "text";

    return (
      <label key={field} className="field">
        <span>{label}</span>
        <input
          type={inputType}
          value={String(value ?? "")}
          onChange={(event) =>
            setFormValues((prev) => ({
              ...prev,
              [field]: typeof hint === "number" ? Number(event.target.value) : event.target.value,
            }))
          }
        />
      </label>
    );
  }

  return (
    <div className="data-card panel resource-surface">
      <div className="resource-hero">
        <div>
          <div className="section-kicker">
            <Sparkles size={16} />
            Data Utama
          </div>
          <h2>{title}</h2>
          <p className="muted">{description}</p>
        </div>
        <div className="resource-hero-actions">
          {createHint ? (
            <button className="button" onClick={openCreateForm} type="button">
              <Plus size={16} />
              Tambah data
            </button>
          ) : null}
          <button className="button-secondary" onClick={() => void load()}>
            Refresh data
          </button>
        </div>
      </div>

      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="card-grid">
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon blue">
            <Database size={18} />
          </div>
          <div className="muted">Total item</div>
          <div className="stat-value">{filteredItems.length}</div>
        </div>
        <div className="panel stat-card stat-card-soft">
          <div className="stat-icon purple">
            <FileSpreadsheet size={18} />
          </div>
          <div className="muted">Pengelolaan</div>
          <div className="stat-value stat-value-sm">
            {createHint ? "Tambah, edit, dan hapus data dari halaman ini" : "Gunakan menu sesuai kebutuhan"}
          </div>
        </div>
      </div>

      {createHint && isFormOpen ? (
        <form className="panel data-card resource-form-card" onSubmit={handleSubmit}>
          <div className="section-heading-inline">
            <div>
              <h3>{editingItem ? "Edit data" : "Tambah data baru"}</h3>
              <p className="muted">
                {editingItem
                  ? "Perbarui data yang sudah ada lalu simpan perubahan."
                  : "Isi data utama pada modul ini lalu simpan."}
              </p>
            </div>
            <button className="button-secondary" type="button" onClick={closeForm}>
              <X size={16} />
              Tutup
            </button>
          </div>
          <div className="resource-form-grid">{formFields.map((field) => renderField(field))}</div>
          <div className="button-row">
            <button className="button" disabled={saving} type="submit">
              <Save size={16} />
              {saving ? "Menyimpan..." : editingItem ? "Simpan perubahan" : "Tambah data"}
            </button>
          </div>
        </form>
      ) : null}

      <div className="panel data-card">
        <div className="section-heading-inline">
          <div>
            <h3>Daftar data</h3>
            <p className="muted">Lihat data yang sudah tersedia pada menu ini.</p>
          </div>
          <label className="field resource-search">
            <span>Pencarian</span>
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Cari nama, email, kode, atau judul"
            />
          </label>
        </div>

        {loading ? (
          <div className="empty-state">Memuat data...</div>
        ) : filteredItems.length === 0 ? (
          <div className="empty-state resource-empty">
            <Inbox size={24} />
            <span>Belum ada data yang tersedia di modul ini.</span>
          </div>
        ) : (
          <div className="resource-list">
            {filteredItems.map((item, index) => {
              const rows = getDisplayRows(item);
              const titleValue =
                String(
                  item.name ??
                    item.title ??
                    item.email ??
                    item.code ??
                    `Item ${index + 1}`,
                ) || `Item ${index + 1}`;
              return (
                <article key={item.id ?? index} className="resource-card">
                  <div className="resource-card-top">
                    <div>
                      <h4>{titleValue}</h4>
                      <span className="badge">#{item.id ?? index + 1}</span>
                    </div>
                    <div className="button-row">
                      {createHint ? (
                        <button
                          className="button-secondary resource-card-button"
                          type="button"
                          onClick={() => openEditForm(item)}
                        >
                          <Pencil size={14} />
                          Edit
                        </button>
                      ) : null}
                      {createHint ? (
                        <button
                          className="button-danger resource-card-button"
                          type="button"
                          onClick={() => void handleDelete(item)}
                        >
                          <Trash2 size={14} />
                          Hapus
                        </button>
                      ) : null}
                    </div>
                  </div>
                  <div className="resource-meta">
                    {rows.length > 0 ? (
                      rows.map(([key, value]) => (
                        <div key={key} className="resource-meta-row">
                          <span className="resource-meta-key">{key.replaceAll("_", " ")}</span>
                          <span className="resource-meta-value">{String(value)}</span>
                        </div>
                      ))
                    ) : (
                      <div className="muted">Detail data belum tersedia.</div>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
