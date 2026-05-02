"use client";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export function apiUrl(path: string) {
  return `${API_URL}${path}`;
}

export function getToken() {
  if (typeof window === "undefined") {
    return null;
  }
  return window.localStorage.getItem("exam_kelas_privat_v2_token");
}

export function setToken(token: string) {
  if (typeof window === "undefined") {
    return;
  }
  window.localStorage.setItem("exam_kelas_privat_v2_token", token);
}

export function clearToken() {
  if (typeof window === "undefined") {
    return;
  }
  window.localStorage.removeItem("exam_kelas_privat_v2_token");
}

function buildHeaders(init?: RequestInit, contentType = "application/json") {
  const token = getToken();
  const headers = new Headers(init?.headers ?? {});
  if (contentType && !headers.has("Content-Type")) {
    headers.set("Content-Type", contentType);
  }
  if (token && !headers.has("Authorization")) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  return headers;
}

export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const hasFormData = typeof FormData !== "undefined" && init?.body instanceof FormData;
  const response = await fetch(apiUrl(path), {
    ...init,
    headers: buildHeaders(init, hasFormData ? "" : "application/json"),
    cache: "no-store",
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.message ?? "Terjadi kesalahan pada API");
  }
  return data as T;
}

export async function apiFetchForm<T>(path: string, formData: FormData, init?: RequestInit) {
  return apiFetch<T>(path, {
    ...init,
    body: formData,
  });
}

export async function downloadApiFile(path: string, fallbackFilename: string) {
  const response = await fetch(apiUrl(path), {
    method: "GET",
    headers: buildHeaders(undefined, ""),
    cache: "no-store",
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    throw new Error(data.message ?? "Gagal mengunduh file");
  }

  const blob = await response.blob();
  const downloadUrl = window.URL.createObjectURL(blob);
  const link = document.createElement("a");
  const disposition = response.headers.get("Content-Disposition");
  const filenameMatch = disposition?.match(/filename="?([^"]+)"?/i);
  link.href = downloadUrl;
  link.download = filenameMatch?.[1] ?? fallbackFilename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(downloadUrl);
}
