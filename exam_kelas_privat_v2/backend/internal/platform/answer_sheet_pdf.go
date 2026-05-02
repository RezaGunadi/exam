package platform

import (
	"bytes"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/render"
	"github.com/jung-kurt/gofpdf/v2"
)

func pdfASCII(s string, maxRunes int) string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, "\r", "\n")
	var b strings.Builder
	n := 0
	for _, r := range s {
		if n >= maxRunes {
			b.WriteString("...")
			break
		}
		if r == '\n' {
			b.WriteString(" ")
			n++
			continue
		}
		if r < 32 || r > 126 {
			b.WriteRune('?')
		} else {
			b.WriteRune(r)
		}
		n++
	}
	return b.String()
}

func pdfFilenamePart(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return "exam"
	}
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == ' ', r == '-', r == '_':
			b.WriteRune('-')
		default:
			b.WriteRune('-')
		}
	}
	out := strings.Trim(b.String(), "-")
	for strings.Contains(out, "--") {
		out = strings.ReplaceAll(out, "--", "-")
	}
	if out == "" {
		return "exam"
	}
	if utf8.RuneCountInString(out) > 40 {
		out = string([]rune(out)[:40])
	}
	return out
}

func (s *Server) handleAdminExamResultAnswerSheetPDF(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id result tidak valid"})
		return
	}
	var result ExamResult
	if err := s.DB.Joins("JOIN exams ON exams.id = exam_results.exam_id").
		Where("exams.school_id = ? AND exam_results.id = ?", user.SchoolID, id).
		First(&result).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "hasil ujian tidak ditemukan"})
		return
	}
	s.writeExamAnswerSheetPDF(w, r, &result, true)
}

func (s *Server) handleStudentExamResultAnswerSheetPDF(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id result tidak valid"})
		return
	}
	var result ExamResult
	if err := s.DB.Where("user_id = ? AND id = ?", user.ID, id).First(&result).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "hasil ujian tidak ditemukan"})
		return
	}
	s.writeExamAnswerSheetPDF(w, r, &result, false)
}

func (s *Server) writeExamAnswerSheetPDF(w http.ResponseWriter, r *http.Request, result *ExamResult, includeAnswerKey bool) {
	if includeAnswerKey {
		var exam Exam
		if err := s.DB.First(&exam, result.ExamID).Error; err != nil {
			render.Status(r, http.StatusInternalServerError)
			render.JSON(w, r, map[string]any{"message": "gagal memuat data ujian"})
			return
		}
		var school School
		if err := s.DB.First(&school, exam.SchoolID).Error; err != nil {
			render.Status(r, http.StatusInternalServerError)
			render.JSON(w, r, map[string]any{"message": "gagal memuat data sekolah"})
			return
		}
		if !s.consumeExportQuota(&school) {
			render.Status(r, http.StatusTooManyRequests)
			render.JSON(w, r, map[string]any{"message": "kuota export sekolah sudah habis"})
			return
		}
	}
	data, filename, err := s.buildExamAnswerSheetPDF(result, includeAnswerKey)
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", `attachment; filename="`+filename+`"`)
	_, _ = w.Write(data)
}

func (s *Server) buildExamAnswerSheetPDF(result *ExamResult, includeAnswerKey bool) ([]byte, string, error) {
	var exam Exam
	if err := s.DB.First(&exam, result.ExamID).Error; err != nil {
		return nil, "", fmt.Errorf("gagal memuat data ujian")
	}
	var student User
	if err := s.DB.First(&student, result.UserID).Error; err != nil {
		return nil, "", fmt.Errorf("gagal memuat data siswa")
	}
	var school School
	if err := s.DB.First(&school, exam.SchoolID).Error; err != nil {
		return nil, "", fmt.Errorf("gagal memuat data sekolah")
	}

	var answers []StudentAnswer
	if err := s.DB.Where("exam_result_id = ?", result.ID).Order("question_id ASC").Find(&answers).Error; err != nil {
		return nil, "", fmt.Errorf("gagal memuat jawaban")
	}

	ids := make([]uint, 0, len(answers))
	for _, a := range answers {
		ids = append(ids, a.QuestionID)
	}
	qmap := make(map[uint]Question)
	if len(ids) > 0 {
		var qs []Question
		if err := s.DB.Where("id IN ?", ids).Find(&qs).Error; err != nil {
			return nil, "", fmt.Errorf("gagal memuat bank soal")
		}
		for _, q := range qs {
			qmap[q.ID] = q
		}
	}

	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.SetTitle(pdfASCII(exam.Title, 120), false)
	pdf.AddPage()
	pdf.SetFont("Arial", "B", 14)
	pdf.Cell(0, 8, "LEMBAR JAWABAN (ANSWER SHEET)")
	pdf.Ln(10)

	pdf.SetFont("Arial", "", 10)
	line := func(label, value string) {
		pdf.SetFont("Arial", "B", 10)
		pdf.Cell(40, 6, pdfASCII(label, 80))
		pdf.SetFont("Arial", "", 10)
		pdf.MultiCell(0, 6, pdfASCII(value, 500), "", "L", false)
	}

	line("Sekolah", school.Name)
	line("Ujian", exam.Title)
	line("Siswa", student.Name)
	line("Email", student.Email)
	line("Result ID", strconv.FormatUint(uint64(result.ID), 10))
	line("Status", result.Status)
	line("Skor", fmt.Sprintf("%d / %d (PG %d, Essay %d)", result.Score, result.TotalScore, result.PGScore, result.EssayScore))
	completed := "-"
	if result.CompletedAt != nil {
		completed = result.CompletedAt.Format(time.RFC3339)
	}
	line("Selesai", completed)
	if result.Notes != nil && strings.TrimSpace(*result.Notes) != "" {
		line("Catatan", *result.Notes)
	}
	pdf.Ln(4)

	pdf.SetFont("Arial", "B", 11)
	pdf.Cell(0, 8, "Rincian jawaban")
	pdf.Ln(8)

	if len(answers) == 0 {
		pdf.SetFont("Arial", "I", 10)
		pdf.MultiCell(0, 6, "Belum ada baris jawaban yang tersimpan untuk result ini.", "", "L", false)
	} else {
		for i, a := range answers {
			q := qmap[a.QuestionID]
			title := fmt.Sprintf("Soal %d (ID %d) - %s", i+1, a.QuestionID, a.QuestionType)
			pdf.SetFont("Arial", "B", 10)
			pdf.MultiCell(0, 6, pdfASCII(title, 200), "", "L", false)
			pdf.SetFont("Arial", "", 9)
			if strings.TrimSpace(q.QuestionText) != "" {
				pdf.MultiCell(0, 5, "Teks: "+pdfASCII(q.QuestionText, 800), "", "L", false)
			}
			studentAns := strings.TrimSpace(a.StudentAnswer)
			if studentAns == "" {
				studentAns = strings.TrimSpace(a.Answer)
			}
			pdf.MultiCell(0, 5, "Jawaban siswa: "+pdfASCII(studentAns, 2000), "", "L", false)
			if includeAnswerKey && strings.TrimSpace(a.CorrectAnswer) != "" {
				pdf.MultiCell(0, 5, "Acuan/kunci: "+pdfASCII(a.CorrectAnswer, 2000), "", "L", false)
			}
			pdf.MultiCell(0, 5, fmt.Sprintf("Poin: %d / %d (dinilai: %v)", a.PointsEarned, a.MaxPoints, a.IsGraded), "", "L", false)
			pdf.Ln(2)
		}
	}

	fn := fmt.Sprintf("answer-sheet-result-%d-%s.pdf", result.ID, pdfFilenamePart(exam.Title))
	var out bytes.Buffer
	if err := pdf.Output(&out); err != nil {
		return nil, "", fmt.Errorf("gagal membuat PDF")
	}
	return out.Bytes(), fn, nil
}
