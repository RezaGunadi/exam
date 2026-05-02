"use client";

import { useEffect, useState } from "react";
import { CalendarDays, CheckCircle2, Clock3, Download, Paperclip, School, Trash2, UserRound } from "lucide-react";
import { AppShell } from "@/components/layout/app-shell";
import { apiFetch, apiFetchForm, downloadApiFile } from "@/lib/api";

type DayItem = {
  date: string;
  present_count: number;
};

type ClassItem = {
  class: { id: number; name: string };
  total_students: number;
  present_count: number;
};

type StudentItem = {
  student: { id: number; name: string };
  status: string;
  detail?: Record<string, unknown>;
};

export default function AttendancePage() {
  const [days, setDays] = useState<DayItem[]>([]);
  const [selectedDate, setSelectedDate] = useState("");
  const [classes, setClasses] = useState<ClassItem[]>([]);
  const [selectedClass, setSelectedClass] = useState<number | null>(null);
  const [students, setStudents] = useState<StudentItem[]>([]);
  const [selectedStudent, setSelectedStudent] = useState<number | null>(null);
  const [studentDetail, setStudentDetail] = useState<Record<string, unknown> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<{ items: DayItem[] }>("/api/admin/attendance/school-days")
      .then((data) => {
        setDays(data.items);
        if (data.items[0]?.date) {
          setSelectedDate(data.items[0].date);
        }
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat absensi"));
  }, []);

  useEffect(() => {
    if (!selectedDate) {
      return;
    }
    apiFetch<{ items: ClassItem[] }>(`/api/admin/attendance/by-date/${selectedDate}`)
      .then((data) => {
        setClasses(data.items);
        setSelectedClass(data.items[0]?.class.id ?? null);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat kelas"));
  }, [selectedDate]);

  useEffect(() => {
    if (!selectedDate || !selectedClass) {
      return;
    }
    apiFetch<{ items: StudentItem[] }>(
      `/api/admin/attendance/by-date/${selectedDate}/class/${selectedClass}`,
    )
      .then((data) => {
        setStudents(data.items);
        setSelectedStudent(data.items[0]?.student.id ?? null);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat siswa"));
  }, [selectedClass, selectedDate]);

  useEffect(() => {
    if (!selectedDate || !selectedStudent) {
      return;
    }
    apiFetch<{ detail: Record<string, unknown> }>(
      `/api/admin/attendance/student/${selectedStudent}/date/${selectedDate}`,
    )
      .then((data) => setStudentDetail(data.detail))
      .catch((err) => setError(err instanceof Error ? err.message : "Gagal memuat detail siswa"));
  }, [selectedDate, selectedStudent]);

  async function refreshStudentDetail() {
    if (!selectedDate || !selectedStudent) {
      return;
    }
    const data = await apiFetch<{ detail: Record<string, unknown> }>(
      `/api/admin/attendance/student/${selectedStudent}/date/${selectedDate}`,
    );
    setStudentDetail(data.detail);
  }

  async function uploadAttachment(file?: File) {
    if (!file || !selectedDate || !selectedStudent) {
      return;
    }
    setError(null);
    setMessage(null);
    try {
      const formData = new FormData();
      formData.append("file", file);
      await apiFetchForm(
        `/api/admin/attendance/upload-attachment/${selectedDate}/${selectedStudent}`,
        formData,
        { method: "POST" },
      );
      setMessage("Lampiran absensi berhasil diunggah.");
      await refreshStudentDetail();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal mengunggah lampiran");
    }
  }

  async function removeAttachment() {
    if (!selectedDate || !selectedStudent) {
      return;
    }
    setError(null);
    setMessage(null);
    try {
      await apiFetch(`/api/admin/attendance/remove-attachment/${selectedDate}/${selectedStudent}`, {
        method: "POST",
        body: JSON.stringify({}),
      });
      setMessage("Lampiran absensi dihapus.");
      await refreshStudentDetail();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menghapus lampiran");
    }
  }

  return (
    <AppShell
      title="Absensi"
      description="Pilih tanggal, lihat kelas, lalu buka detail absensi siswa."
    >
      {error ? <div className="inline-alert danger">{error}</div> : null}
      {message ? <div className="inline-alert">{message}</div> : null}

      <div className="attendance-grid">
        <div className="panel data-card">
          <div className="section-kicker">
            <CalendarDays size={16} />
            Langkah 1
          </div>
          <h2>Pilih tanggal sekolah</h2>
          <div className="compact-list">
            {days.map((day) => (
              <button
                key={day.date}
                className={`attendance-day-button ${selectedDate === day.date ? "active" : ""}`}
                onClick={() => setSelectedDate(day.date)}
              >
                <strong>{day.date}</strong>
                <span className="muted">Hadir {day.present_count} siswa</span>
              </button>
            ))}
          </div>
        </div>

        <div className="panel data-card">
          <div className="section-kicker">
            <School size={16} />
            Langkah 2
          </div>
          <h2>Kelas pada {selectedDate || "-"}</h2>
          <div className="compact-list">
            {classes.map((item) => (
              <button
                key={item.class.id}
                className={`attendance-class-button ${selectedClass === item.class.id ? "active" : ""}`}
                onClick={() => setSelectedClass(item.class.id)}
              >
                <strong>{item.class.name}</strong>
                <span className="muted">
                  {item.present_count}/{item.total_students} hadir
                </span>
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="attendance-detail-grid">
        <div className="panel data-card">
          <div className="section-kicker">
            <UserRound size={16} />
            Langkah 3
          </div>
          <h2>Daftar siswa</h2>
          <div className="compact-list">
            {students.map((item) => (
              <button
                key={item.student.id}
                className={`attendance-student-button ${selectedStudent === item.student.id ? "active" : ""}`}
                onClick={() => setSelectedStudent(item.student.id)}
              >
                <strong>{item.student.name}</strong>
                <span
                  className={`status-pill ${
                    item.status === "present"
                      ? "success"
                      : item.status === "late"
                        ? "warning"
                        : "danger"
                  }`}
                >
                  {item.status}
                </span>
              </button>
            ))}
          </div>
        </div>

        <div className="panel data-card student-detail-card">
          <div className="section-kicker">
            <CheckCircle2 size={16} />
            Langkah 4
          </div>
          <h2>Detail siswa di tanggal terpilih</h2>
          {studentDetail ? (
            <>
              <div className="meta-row">
                <span className="meta-key">Tanggal</span>
                <span className="meta-value">{String(studentDetail.date ?? selectedDate ?? "-")}</span>
              </div>
              <div className="meta-row">
                <span className="meta-key">Status</span>
                <span className="meta-value">
                  <span
                    className={`status-pill ${
                      String(studentDetail.status ?? "") === "present"
                        ? "success"
                        : String(studentDetail.status ?? "") === "late"
                          ? "warning"
                          : "danger"
                    }`}
                  >
                    {String(studentDetail.status ?? "-")}
                  </span>
                </span>
              </div>
              <div className="meta-row">
                <span className="meta-key">Jam masuk</span>
                <span className="meta-value">{String(studentDetail.time ?? studentDetail.check_in_time ?? "-")}</span>
              </div>
              <div className="meta-row">
                <span className="meta-key">Catatan</span>
                <span className="meta-value">{String(studentDetail.note ?? studentDetail.notes ?? "-")}</span>
              </div>
              <div className="meta-row">
                <span className="meta-key">Lampiran</span>
                <span className="meta-value">{String(studentDetail.attachment ?? studentDetail.image ?? "-")}</span>
              </div>
              <div className="button-row" style={{ marginTop: 12 }}>
                <label className="button-secondary">
                  <Paperclip size={16} />
                  Unggah lampiran
                  <input
                    type="file"
                    hidden
                    onChange={(event) => void uploadAttachment(event.target.files?.[0])}
                  />
                </label>
                {studentDetail.attachment ? (
                  <button className="button-danger" type="button" onClick={() => void removeAttachment()}>
                    <Trash2 size={16} />
                    Hapus lampiran
                  </button>
                ) : null}
                {selectedStudent ? (
                  <button
                    className="button"
                    type="button"
                    onClick={() =>
                      void downloadApiFile(
                        `/api/admin/attendance/generate-card/${selectedStudent}`,
                        `kartu-absensi-${selectedStudent}.pdf`,
                      )
                    }
                  >
                    <Download size={16} />
                    Unduh kartu
                  </button>
                ) : null}
              </div>
              <div className="inline-alert">
                <div className="button-row">
                  <Clock3 size={16} />
                  Detail absensi ditampilkan sesuai tanggal dan siswa yang dipilih.
                </div>
              </div>
            </>
          ) : (
            <div className="empty-state">Pilih siswa untuk melihat detail tanggal itu.</div>
          )}
        </div>
      </div>
    </AppShell>
  );
}
