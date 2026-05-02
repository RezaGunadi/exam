package platform

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"github.com/google/uuid"
	"github.com/jung-kurt/gofpdf/v2"
	"github.com/xuri/excelize/v2"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func (s *Server) handleStaticPage(w http.ResponseWriter, r *http.Request) {
	slug := strings.TrimSpace(chi.URLParam(r, "slug"))
	pages := map[string]map[string]string{
		"about": {
			"title": "Tentang Exam Kelas Privat",
			"body":  "Platform ujian, bank soal, absensi, tugas, laporan, dan rapor untuk sekolah/kelas privat.",
		},
		"contact": {
			"title": "Kontak",
			"body":  "Hubungi tim Exam Kelas Privat melalui form kontak atau demo request.",
		},
		"privacy-policy": {
			"title": "Privacy Policy",
			"body":  "Data pengguna dipakai untuk operasional ujian, laporan, absensi, dan layanan sekolah.",
		},
		"terms": {
			"title": "Terms",
			"body":  "Penggunaan layanan mengikuti aturan sekolah dan kebijakan Exam Kelas Privat.",
		},
	}
	page, ok := pages[slug]
	if !ok {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "halaman tidak ditemukan"})
		return
	}
	render.JSON(w, r, map[string]any{"page": page})
}

func (s *Server) handleDismissOnboarding(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	if user == nil {
		render.Status(r, http.StatusUnauthorized)
		render.JSON(w, r, map[string]any{"message": "unauthorized"})
		return
	}
	if err := s.DB.Model(&User{}).Where("id = ?", user.ID).Update("is_coachmark_showing", true).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyimpan onboarding"})
		return
	}
	user.IsCoachmarkShowing = true
	render.JSON(w, r, map[string]any{"message": "onboarding ditutup", "user": user})
}

func (s *Server) handleListSubjectKKM(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var subjects []Subject
	s.DB.Where("school_id = ?", user.SchoolID).Order("name ASC").Find(&subjects)
	render.JSON(w, r, map[string]any{"items": subjects})
}

func (s *Server) handleUpdateSubjectKKM(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id mapel tidak valid"})
		return
	}
	var payload struct {
		KKM int `json:"kkm"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.KKM < 0 || payload.KKM > 100 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "kkm harus 0-100"})
		return
	}
	if err := s.DB.Model(&Subject{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Update("kkm", payload.KKM).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui KKM"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "KKM diperbarui"})
}

func (s *Server) handleUpdateMultipleSubjectKKM(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		Items []struct {
			ID  uint `json:"id"`
			KKM int  `json:"kkm"`
		} `json:"items"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	updated := 0
	err := s.withTx(func(tx *gorm.DB) error {
		for _, item := range payload.Items {
			if item.ID == 0 || item.KKM < 0 || item.KKM > 100 {
				continue
			}
			result := tx.Model(&Subject{}).Where("id = ? AND school_id = ?", item.ID, user.SchoolID).Update("kkm", item.KKM)
			if result.Error != nil {
				return result.Error
			}
			updated += int(result.RowsAffected)
		}
		return nil
	})
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui KKM"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "KKM massal diperbarui", "updated": updated})
}

func (s *Server) handleResetSubjectKKM(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	defaultKKM := 75
	var payload struct {
		KKM *int `json:"kkm"`
	}
	_ = parseJSONBody(r, &payload)
	if payload.KKM != nil {
		defaultKKM = *payload.KKM
	}
	result := s.DB.Model(&Subject{}).Where("school_id = ?", user.SchoolID).Update("kkm", defaultKKM)
	if result.Error != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal reset KKM"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "KKM direset", "updated": result.RowsAffected})
}

func (s *Server) handleExportExamResultsExcel(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []ExamResult
	s.DB.Joins("JOIN exams ON exams.id = exam_results.exam_id").
		Where("exams.school_id = ?", user.SchoolID).
		Order("exam_results.created_at DESC").
		Find(&items)

	book := excelize.NewFile()
	sheet := book.GetSheetName(0)
	headers := []string{"ID", "ExamID", "UserID", "Status", "Score", "PGScore", "EssayScore", "CompletedAt"}
	for idx, header := range headers {
		cell, _ := excelize.CoordinatesToCellName(idx+1, 1)
		book.SetCellValue(sheet, cell, header)
	}
	for row, item := range items {
		completedAt := ""
		if item.CompletedAt != nil {
			completedAt = item.CompletedAt.Format(time.RFC3339)
		}
		values := []any{item.ID, item.ExamID, item.UserID, item.Status, item.Score, item.PGScore, item.EssayScore, completedAt}
		for col, value := range values {
			cell, _ := excelize.CoordinatesToCellName(col+1, row+2)
			book.SetCellValue(sheet, cell, value)
		}
	}
	if err := writeExcelWorkbook(w, "exam-results.xlsx", book); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal membuat excel"})
	}
}

func (s *Server) handleMarkExamResultFinished(w http.ResponseWriter, r *http.Request) {
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id result tidak valid"})
		return
	}
	now := time.Now()
	if err := s.DB.Model(&ExamResult{}).Where("id = ?", id).Updates(map[string]any{
		"status":       "completed",
		"completed_at": now,
	}).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menandai selesai"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "hasil ujian ditandai selesai"})
}

func (s *Server) handleMarkMultipleExamResultsFinished(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		IDs []uint `json:"ids"`
	}
	if err := parseJSONBody(r, &payload); err != nil || len(payload.IDs) == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "ids wajib diisi"})
		return
	}
	now := time.Now()
	result := s.DB.Model(&ExamResult{}).Where("id IN ?", payload.IDs).Updates(map[string]any{
		"status":       "completed",
		"completed_at": now,
	})
	if result.Error != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menandai selesai"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "hasil ujian ditandai selesai", "updated": result.RowsAffected})
}

const maxAttendanceAttachmentBytes = 10 << 20

func (s *Server) handleAttendanceUploadAttachment(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	dateValue := chi.URLParam(r, "date")
	userID, err := pathUint(r, "userId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id siswa tidak valid"})
		return
	}
	parsedDate, err := time.Parse("2006-01-02", dateValue)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "tanggal tidak valid"})
		return
	}
	if err := r.ParseMultipartForm(maxAttendanceAttachmentBytes + (1 << 20)); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "gagal membaca upload"})
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "field file wajib diisi"})
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext == "" {
		ext = ".bin"
	}
	dir := filepath.Join(s.Config.UploadDir, "attendance", fmt.Sprintf("%d", user.SchoolID), dateValue, fmt.Sprintf("%d", userID))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyiapkan folder lampiran"})
		return
	}
	filename := uuid.NewString() + ext
	fsPath := filepath.Join(dir, filename)
	out, err := os.Create(fsPath)
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyimpan lampiran"})
		return
	}
	written, err := io.Copy(out, io.LimitReader(file, maxAttendanceAttachmentBytes+1))
	out.Close()
	if err != nil || written > maxAttendanceAttachmentBytes {
		_ = os.Remove(fsPath)
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "lampiran maksimal 10 MB"})
		return
	}

	publicURL := fmt.Sprintf("/api/files/attendance/%d/%s/%d/%s", user.SchoolID, dateValue, userID, filename)
	record := UserAbsent{
		UserID:     userID,
		SchoolID:   user.SchoolID,
		Date:       parsedDate,
		Status:     "excused",
		Attachment: &publicURL,
	}
	if err := s.DB.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "user_id"}, {Name: "date"}},
		DoUpdates: clause.AssignmentColumns([]string{"attachment", "status", "updated_at"}),
	}).Create(&record).Error; err != nil {
		_ = os.Remove(fsPath)
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyimpan data lampiran"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "lampiran absensi diunggah", "attachment": publicURL})
}

func (s *Server) handleAttendanceRemoveAttachment(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	dateValue := chi.URLParam(r, "date")
	userID, err := pathUint(r, "userId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id siswa tidak valid"})
		return
	}
	parsedDate, err := time.Parse("2006-01-02", dateValue)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "tanggal tidak valid"})
		return
	}
	var record UserAbsent
	if err := s.DB.Where("school_id = ? AND user_id = ? AND date = ?", user.SchoolID, userID, parsedDate).First(&record).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "absensi tidak ditemukan"})
		return
	}
	if record.Attachment != nil && *record.Attachment != "" {
		if fsPath, err := s.uploadPathFromPublicURL(*record.Attachment); err == nil {
			_ = os.Remove(fsPath)
		}
	}
	if err := s.DB.Model(&record).Update("attachment", nil).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menghapus lampiran"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "lampiran absensi dihapus"})
}

func (s *Server) handleAttendanceGenerateCard(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	userID, err := pathUint(r, "userId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id siswa tidak valid"})
		return
	}
	var student User
	if err := s.DB.Preload("School").Preload("ClassRoom").Where("school_id = ?", user.SchoolID).First(&student, userID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "siswa tidak ditemukan"})
		return
	}

	pdf := gofpdf.New("L", "mm", "A6", "")
	pdf.AddPage()
	pdf.SetFillColor(12, 41, 71)
	pdf.Rect(0, 0, 148, 105, "F")
	pdf.SetTextColor(245, 178, 60)
	pdf.SetFont("Arial", "B", 16)
	pdf.SetXY(10, 10)
	pdf.Cell(0, 8, "Kartu Absensi")
	pdf.SetTextColor(255, 255, 255)
	pdf.SetFont("Arial", "", 11)
	pdf.SetXY(10, 28)
	pdf.Cell(0, 7, "Nama: "+student.Name)
	pdf.SetXY(10, 38)
	pdf.Cell(0, 7, "Email: "+student.Email)
	className := "-"
	if student.ClassRoom != nil {
		className = student.ClassRoom.Name
	}
	pdf.SetXY(10, 48)
	pdf.Cell(0, 7, "Kelas: "+className)
	pdf.SetXY(10, 58)
	pdf.Cell(0, 7, fmt.Sprintf("Token QR: %s", strings.TrimSpace(valueOrDash(student.QR))))
	pdf.SetXY(10, 78)
	pdf.SetFont("Arial", "B", 10)
	pdf.Cell(0, 7, "Exam Kelas Privat")

	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"kartu-absensi-%d.pdf\"", student.ID))
	if err := pdf.Output(w); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal membuat kartu"})
	}
}

func valueOrDash(value *string) string {
	if value == nil || strings.TrimSpace(*value) == "" {
		return "-"
	}
	return *value
}

func (s *Server) handleStudentExamMarkDisconnected(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	now := time.Now()
	if err := s.DB.Model(&ExamResult{}).
		Where("exam_id = ? AND user_id = ? AND status IN ?", examID, user.ID, []string{"in_progress", "disconnected"}).
		Updates(map[string]any{"status": "disconnected", "last_activity_at": now}).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menandai disconnected"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "status disconnected tersimpan"})
}

func (s *Server) handleStudentExamProctorUpload(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	var payload map[string]any
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	var result ExamResult
	if err := s.DB.Where("exam_id = ? AND user_id = ? AND status IN ?", examID, user.ID, []string{"in_progress", "disconnected"}).
		Order("created_at DESC").
		First(&result).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "attempt aktif tidak ditemukan"})
		return
	}
	var snapshots []map[string]any
	if len(result.ProctorSnapshots) > 0 {
		_ = json.Unmarshal(result.ProctorSnapshots, &snapshots)
	}
	payload["captured_at"] = time.Now().Format(time.RFC3339)
	snapshots = append(snapshots, payload)
	if err := s.DB.Model(&result).Updates(map[string]any{
		"proctor_snapshots": upsertJSON(snapshots),
		"last_activity_at":  time.Now(),
	}).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyimpan proctoring"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "snapshot proctoring tersimpan", "total": len(snapshots)})
}

func (s *Server) handleStudentExamRecordCheating(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	var payload struct {
		Event string `json:"event"`
		Note  string `json:"note"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	entry := fmt.Sprintf("%s - %s %s", time.Now().Format(time.RFC3339), strings.TrimSpace(payload.Event), strings.TrimSpace(payload.Note))
	if err := s.DB.Model(&ExamResult{}).
		Where("exam_id = ? AND user_id = ? AND status IN ?", examID, user.ID, []string{"in_progress", "disconnected"}).
		Update("cheating_note", gorm.Expr("CONCAT(COALESCE(cheating_note, ''), ?)", "\n"+entry)).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyimpan catatan kecurangan"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "catatan kecurangan tersimpan"})
}

func (s *Server) handleSendAnswerSheetsEmail(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		Email string `json:"email"`
		IDs   []uint `json:"ids"`
	}
	if err := parseJSONBody(r, &payload); err != nil || strings.TrimSpace(payload.Email) == "" || len(payload.IDs) == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "email dan ids wajib diisi"})
		return
	}
	attachments := make([]mailAttachment, 0, len(payload.IDs))
	for _, id := range payload.IDs {
		var result ExamResult
		if err := s.DB.Joins("JOIN exams ON exams.id = exam_results.exam_id").
			Where("exams.school_id = ? AND exam_results.id = ?", user.SchoolID, id).
			First(&result).Error; err != nil {
			render.Status(r, http.StatusNotFound)
			render.JSON(w, r, map[string]any{"message": fmt.Sprintf("hasil ujian #%d tidak ditemukan", id)})
			return
		}
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
		data, filename, err := s.buildExamAnswerSheetPDF(&result, true)
		if err != nil {
			render.Status(r, http.StatusInternalServerError)
			render.JSON(w, r, map[string]any{"message": err.Error()})
			return
		}
		attachments = append(attachments, mailAttachment{
			Filename:    filename,
			ContentType: "application/pdf",
			Data:        data,
		})
	}
	if err := s.sendAnswerSheetEmail(payload.Email, payload.IDs, attachments); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "gagal mengirim email", "mail_status": err.Error()})
		return
	}
	render.JSON(w, r, map[string]any{"message": "email lembar jawaban dikirim", "sent": len(payload.IDs)})
}

func (s *Server) handleFixAIGradedData(w http.ResponseWriter, r *http.Request) {
	result := s.DB.Model(&StudentAnswer{}).
		Where("question_type = ? AND is_ai_scheduler = ? AND is_graded = ?", "essay", true, false).
		Updates(map[string]any{"is_graded": true, "ai_type": "fixed"})
	if result.Error != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbaiki data AI"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "data AI diperbaiki", "updated": result.RowsAffected})
}

func (s *Server) handleUpdateIndividualEssayScore(w http.ResponseWriter, r *http.Request) {
	resultID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id result tidak valid"})
		return
	}
	var payload struct {
		QuestionID uint `json:"question_id"`
		Score      int  `json:"score"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.QuestionID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "question_id wajib diisi"})
		return
	}
	if err := s.withTx(func(tx *gorm.DB) error {
		if err := tx.Model(&StudentAnswer{}).
			Where("exam_result_id = ? AND question_id = ?", resultID, payload.QuestionID).
			Updates(map[string]any{
				"points_earned":   payload.Score,
				"score":           payload.Score,
				"is_graded":       true,
				"is_ai_scheduler": true,
				"ai_type":         "manual",
				"is_correct":      payload.Score > 0,
			}).Error; err != nil {
			return err
		}
		var answers []StudentAnswer
		if err := tx.Where("exam_result_id = ? AND question_type = ?", resultID, "essay").Find(&answers).Error; err != nil {
			return err
		}
		totalEssay := 0
		scoreMap := map[string]int{}
		for _, answer := range answers {
			totalEssay += answer.Score
			scoreMap[strconv.Itoa(int(answer.QuestionID))] = answer.Score
		}
		return tx.Model(&ExamResult{}).Where("id = ?", resultID).Updates(map[string]any{
			"essay_score":  totalEssay,
			"score":        gorm.Expr("pg_score + ?", totalEssay),
			"essay_scores": upsertJSON(scoreMap),
		}).Error
	}); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui skor essay"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "skor essay diperbarui"})
}

func (s *Server) handleListReports(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	query := s.reportExamQuery(user.SchoolID, r)
	var exams []Exam
	query.Order("start_time DESC").Find(&exams)
	items := make([]map[string]any, 0, len(exams))
	for _, exam := range exams {
		stats := s.examReportStats(exam.ID)
		items = append(items, map[string]any{
			"id":             exam.ID,
			"title":          exam.Title,
			"exam_type":      exam.ExamType,
			"status":         exam.Status,
			"start_time":     exam.StartTime,
			"total_students": stats["total_students"],
			"average_score":  stats["average_score"],
			"passed":         stats["passed"],
			"pass_rate":      stats["pass_rate"],
		})
	}
	render.JSON(w, r, map[string]any{"items": items, "stats": s.reportStatistics(user.SchoolID, r)})
}

func (s *Server) handleShowReport(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	var exam Exam
	if err := s.DB.Where("school_id = ?", user.SchoolID).First(&exam, examID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "ujian tidak ditemukan"})
		return
	}
	var results []ExamResult
	s.DB.Where("exam_id = ?", examID).Order("score DESC").Find(&results)
	render.JSON(w, r, map[string]any{"exam": exam, "results": results, "stats": s.examReportStats(examID)})
}

func (s *Server) handleStudentReport(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	idParam := chi.URLParam(r, "studentId")
	if idParam == "" {
		idParam = chi.URLParam(r, "id")
	}
	studentID, err := strconv.ParseUint(idParam, 10, 64)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id siswa tidak valid"})
		return
	}
	var student User
	if err := s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "student").First(&student, uint(studentID)).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "siswa tidak ditemukan"})
		return
	}
	var results []ExamResult
	s.DB.Joins("JOIN exams ON exams.id = exam_results.exam_id").
		Where("exams.school_id = ? AND exam_results.user_id = ?", user.SchoolID, student.ID).
		Order("exam_results.created_at DESC").
		Find(&results)
	render.JSON(w, r, map[string]any{"student": student, "results": results})
}

func (s *Server) handleExportReports(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var school School
	if err := s.DB.First(&school, user.SchoolID).Error; err == nil {
		if !s.consumeExportQuota(&school) {
			render.Status(r, http.StatusTooManyRequests)
			render.JSON(w, r, map[string]any{"message": "kuota export sekolah sudah habis"})
			return
		}
	}
	records := [][]string{{"ExamID", "Title", "Type", "Status", "Students", "Average", "Passed", "PassRate"}}
	var exams []Exam
	s.reportExamQuery(user.SchoolID, r).Order("start_time DESC").Find(&exams)
	for _, exam := range exams {
		stats := s.examReportStats(exam.ID)
		records = append(records, []string{
			strconv.Itoa(int(exam.ID)),
			exam.Title,
			exam.ExamType,
			exam.Status,
			fmt.Sprint(stats["total_students"]),
			fmt.Sprintf("%.2f", stats["average_score"]),
			fmt.Sprint(stats["passed"]),
			fmt.Sprintf("%.2f", stats["pass_rate"]),
		})
	}
	if err := writeCSV(w, "reports.csv", records); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal membuat laporan"})
	}
}

func (s *Server) reportExamQuery(schoolID uint, r *http.Request) *gorm.DB {
	query := s.DB.Model(&Exam{}).Where("school_id = ? AND status = ?", schoolID, "completed")
	if examType := r.URL.Query().Get("exam_type"); examType != "" && examType != "all" {
		query = query.Where("exam_type = ?", examType)
	}
	if subjectID := r.URL.Query().Get("subject_id"); subjectID != "" && subjectID != "all" {
		query = query.Joins("JOIN question_packages ON question_packages.id = exams.question_package_id").Where("question_packages.subject_id = ?", subjectID)
	}
	if dateFrom := r.URL.Query().Get("date_from"); dateFrom != "" {
		query = query.Where("DATE(start_time) >= ?", dateFrom)
	}
	if dateTo := r.URL.Query().Get("date_to"); dateTo != "" {
		query = query.Where("DATE(start_time) <= ?", dateTo)
	}
	return query
}

func (s *Server) reportStatistics(schoolID uint, r *http.Request) map[string]any {
	var examIDs []uint
	s.reportExamQuery(schoolID, r).Pluck("id", &examIDs)
	stats := map[string]any{
		"total_exams":    len(examIDs),
		"total_students": int64(0),
		"total_results":  int64(0),
		"passed_results": int64(0),
		"failed_results": int64(0),
		"pass_rate":      float64(0),
		"average_score":  float64(0),
	}
	if len(examIDs) == 0 {
		return stats
	}
	var totalStudents, totalResults, passedResults int64
	var avg float64
	s.DB.Model(&ExamResult{}).Where("exam_id IN ?", examIDs).Distinct("user_id").Count(&totalStudents)
	s.DB.Model(&ExamResult{}).Where("exam_id IN ?", examIDs).Count(&totalResults)
	s.DB.Model(&ExamResult{}).Where("exam_id IN ? AND is_passed = ?", examIDs, true).Count(&passedResults)
	s.DB.Model(&ExamResult{}).Where("exam_id IN ? AND status = ?", examIDs, "completed").Select("COALESCE(AVG(score), 0)").Scan(&avg)
	passRate := float64(0)
	if totalResults > 0 {
		passRate = float64(passedResults) / float64(totalResults) * 100
	}
	stats["total_students"] = totalStudents
	stats["total_results"] = totalResults
	stats["passed_results"] = passedResults
	stats["failed_results"] = totalResults - passedResults
	stats["pass_rate"] = passRate
	stats["average_score"] = avg
	stats["exam_type_stats"] = s.examTypeReportStats(examIDs)
	return stats
}

func (s *Server) examReportStats(examID uint) map[string]any {
	var total, passed int64
	var avg float64
	s.DB.Model(&ExamResult{}).Where("exam_id = ?", examID).Count(&total)
	s.DB.Model(&ExamResult{}).Where("exam_id = ? AND is_passed = ?", examID, true).Count(&passed)
	s.DB.Model(&ExamResult{}).Where("exam_id = ? AND status = ?", examID, "completed").Select("COALESCE(AVG(score), 0)").Scan(&avg)
	passRate := float64(0)
	if total > 0 {
		passRate = float64(passed) / float64(total) * 100
	}
	return map[string]any{"total_students": total, "average_score": avg, "passed": passed, "pass_rate": passRate}
}

func (s *Server) examTypeReportStats(examIDs []uint) map[string]any {
	rows := []struct {
		ExamType string
		Count    int64
		Average  float64
	}{}
	s.DB.Model(&Exam{}).
		Select("exams.exam_type, COUNT(DISTINCT exams.id) as count, COALESCE(AVG(exam_results.score), 0) as average").
		Joins("LEFT JOIN exam_results ON exam_results.exam_id = exams.id").
		Where("exams.id IN ?", examIDs).
		Group("exams.exam_type").
		Scan(&rows)
	out := map[string]any{}
	for _, row := range rows {
		out[row.ExamType] = map[string]any{"count": row.Count, "average_score": row.Average}
	}
	return out
}

func (s *Server) handleReportConfigIndex(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []ReportConfig
	s.DB.Where("school_id = ?", user.SchoolID).Order("config_type ASC, `key` ASC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) upsertReportConfig(user *User, key string, value any) error {
	config := ReportConfig{
		SchoolID:   user.SchoolID,
		ConfigType: key,
		Key:        "payload",
		Metadata:   upsertJSON(value),
		IsActive:   true,
	}
	return s.DB.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "school_id"}, {Name: "config_type"}, {Name: "key"}},
		DoUpdates: clause.AssignmentColumns([]string{"metadata", "is_active", "updated_at"}),
	}).Create(&config).Error
}

func (s *Server) handleUpdateExamTypePercentages(w http.ResponseWriter, r *http.Request) {
	s.handleReportConfigUpdate(w, r, "exam_type_percentages")
}

func (s *Server) handleUpdateGradeThresholds(w http.ResponseWriter, r *http.Request) {
	s.handleReportConfigUpdate(w, r, "grade_thresholds")
}

func (s *Server) handleUpdateReportSettings(w http.ResponseWriter, r *http.Request) {
	s.handleReportConfigUpdate(w, r, "report_settings")
}

func (s *Server) handleReportConfigUpdate(w http.ResponseWriter, r *http.Request, key string) {
	user := s.currentUser(r)
	var payload map[string]any
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	if err := s.upsertReportConfig(user, key, payload); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyimpan konfigurasi"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "konfigurasi laporan disimpan"})
}

func (s *Server) handleResetReportConfig(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	defaults := map[string]any{
		"exam_type_percentages": map[string]any{"tugas_harian": 10, "ulangan_harian": 15, "tugas_besar": 15, "uts": 25, "uas": 35},
		"grade_thresholds":      map[string]any{"A": 90, "B": 80, "C": 70, "D": 60, "E": 0},
		"report_settings":       map[string]any{"kkm": 75, "show_rank": true},
	}
	for key, value := range defaults {
		if err := s.upsertReportConfig(user, key, value); err != nil {
			render.Status(r, http.StatusInternalServerError)
			render.JSON(w, r, map[string]any{"message": "gagal reset konfigurasi"})
			return
		}
	}
	render.JSON(w, r, map[string]any{"message": "konfigurasi laporan direset"})
}

func (s *Server) handleListRaports(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []Raport
	s.DB.Where("school_id = ?", user.SchoolID).Order("created_at DESC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleShowRaport(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id raport tidak valid"})
		return
	}
	var raport Raport
	if err := s.DB.Where("school_id = ?", user.SchoolID).First(&raport, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "raport tidak ditemukan"})
		return
	}
	render.JSON(w, r, map[string]any{"item": raport})
}

func (s *Server) handlePrintRaport(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id raport tidak valid"})
		return
	}
	var raport Raport
	if err := s.DB.Where("school_id = ?", user.SchoolID).First(&raport, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "raport tidak ditemukan"})
		return
	}
	var school School
	if err := s.DB.First(&school, user.SchoolID).Error; err == nil && !s.consumeExportQuota(&school) {
		render.Status(r, http.StatusTooManyRequests)
		render.JSON(w, r, map[string]any{"message": "kuota export sekolah sudah habis"})
		return
	}
	s.writeRaportPDF(w, r, &raport)
}

func (s *Server) handleStudentRaports(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []Raport
	s.DB.Where("school_id = ? AND user_id = ? AND status = ?", user.SchoolID, user.ID, "published").
		Order("academic_year DESC, semester ASC, created_at DESC").
		Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleStudentRaport(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id raport tidak valid"})
		return
	}
	var raport Raport
	if err := s.DB.Where("school_id = ? AND user_id = ? AND status = ?", user.SchoolID, user.ID, "published").First(&raport, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "raport tidak ditemukan"})
		return
	}
	render.JSON(w, r, map[string]any{"item": raport})
}

func (s *Server) handleStudentRaportPrint(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id raport tidak valid"})
		return
	}
	var raport Raport
	if err := s.DB.Where("school_id = ? AND user_id = ? AND status = ?", user.SchoolID, user.ID, "published").First(&raport, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "raport tidak ditemukan"})
		return
	}
	s.writeRaportPDF(w, r, &raport)
}

func (s *Server) writeRaportPDF(w http.ResponseWriter, r *http.Request, raport *Raport) {
	var student User
	if err := s.DB.First(&student, raport.UserID).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memuat siswa"})
		return
	}
	var school School
	if err := s.DB.First(&school, raport.SchoolID).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memuat sekolah"})
		return
	}
	var subjects []map[string]any
	if len(raport.SubjectsData) > 0 {
		_ = json.Unmarshal(raport.SubjectsData, &subjects)
	}

	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.SetTitle(pdfASCII(fmt.Sprintf("Raport %s %s", student.Name, raport.AcademicYear), 120), false)
	pdf.AddPage()
	pdf.SetFont("Arial", "B", 15)
	pdf.Cell(0, 8, "RAPORT SISWA")
	pdf.Ln(10)
	pdf.SetFont("Arial", "", 10)
	line := func(label, value string) {
		pdf.SetFont("Arial", "B", 10)
		pdf.Cell(42, 6, pdfASCII(label, 80))
		pdf.SetFont("Arial", "", 10)
		pdf.MultiCell(0, 6, pdfASCII(value, 300), "", "L", false)
	}
	line("Sekolah", school.Name)
	line("Siswa", student.Name)
	line("Email", student.Email)
	line("Tahun/Semester", raport.AcademicYear+" / "+raport.Semester)
	line("Status", raport.Status)
	line("Nilai akhir", fmt.Sprintf("%.2f (%s)", raport.OverallScore, raport.OverallGrade))
	if raport.OverallPassed {
		line("Ketuntasan", "Tuntas")
	} else {
		line("Ketuntasan", "Belum tuntas")
	}
	pdf.Ln(4)
	pdf.SetFont("Arial", "B", 11)
	pdf.Cell(0, 8, "Rincian Mapel")
	pdf.Ln(8)
	if len(subjects) == 0 {
		pdf.SetFont("Arial", "I", 10)
		pdf.MultiCell(0, 6, "Belum ada rincian mapel pada raport ini.", "", "L", false)
	} else {
		pdf.SetFont("Arial", "B", 9)
		pdf.CellFormat(70, 7, "Mapel", "1", 0, "L", false, 0, "")
		pdf.CellFormat(25, 7, "KKM", "1", 0, "C", false, 0, "")
		pdf.CellFormat(30, 7, "Nilai", "1", 0, "C", false, 0, "")
		pdf.CellFormat(25, 7, "Grade", "1", 0, "C", false, 0, "")
		pdf.CellFormat(35, 7, "Status", "1", 1, "C", false, 0, "")
		pdf.SetFont("Arial", "", 9)
		for _, subject := range subjects {
			score, _ := subject["score"].(float64)
			kkm := fmt.Sprint(subject["kkm"])
			name := fmt.Sprint(subject["name"])
			grade := fmt.Sprint(subject["grade"])
			status := "Belum tuntas"
			if passed, _ := subject["is_passed"].(bool); passed {
				status = "Tuntas"
			}
			pdf.CellFormat(70, 7, pdfASCII(name, 70), "1", 0, "L", false, 0, "")
			pdf.CellFormat(25, 7, pdfASCII(kkm, 12), "1", 0, "C", false, 0, "")
			pdf.CellFormat(30, 7, fmt.Sprintf("%.2f", score), "1", 0, "C", false, 0, "")
			pdf.CellFormat(25, 7, pdfASCII(grade, 10), "1", 0, "C", false, 0, "")
			pdf.CellFormat(35, 7, status, "1", 1, "C", false, 0, "")
		}
	}
	pdf.Ln(12)
	pdf.SetFont("Arial", "", 10)
	pdf.CellFormat(95, 6, "Catatan sekolah:", "", 0, "L", false, 0, "")
	pdf.CellFormat(95, 6, fmt.Sprintf("%s, %s", pdfASCII(school.Name, 40), time.Now().Format("02 Jan 2006")), "", 1, "L", false, 0, "")
	pdf.SetFont("Arial", "I", 9)
	pdf.MultiCell(90, 5, "Raport ini dihasilkan dari hasil ujian yang sudah selesai dan konfigurasi bobot sekolah.", "", "L", false)
	pdf.SetXY(115, pdf.GetY()-10)
	pdf.SetFont("Arial", "", 10)
	pdf.CellFormat(70, 6, "Kepala Sekolah", "", 1, "C", false, 0, "")
	pdf.Ln(18)
	pdf.SetX(115)
	principal := strings.TrimSpace(derefString(school.PrincipalName))
	if principal == "" {
		principal = "-"
	}
	pdf.CellFormat(70, 6, pdfASCII(principal, 80), "T", 1, "C", false, 0, "")
	filename := fmt.Sprintf("raport-%d-%s.pdf", raport.ID, pdfFilenamePart(student.Name))
	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", `attachment; filename="`+filename+`"`)
	_ = pdf.Output(w)
}

func (s *Server) handleUpdateRaport(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id raport tidak valid"})
		return
	}
	var payload map[string]any
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	delete(payload, "school_id")
	if err := s.DB.Model(&Raport{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Updates(payload).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui raport"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "raport diperbarui"})
}

func (s *Server) handleRaportGenerateForm(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var classes []ClassRoom
	var students []User
	s.DB.Where("school_id = ?", user.SchoolID).Order("name ASC").Find(&classes)
	s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "student").Order("name ASC").Find(&students)
	render.JSON(w, r, map[string]any{"classes": classes, "students": students})
}

func (s *Server) handleGenerateStudentRaport(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		UserID       uint   `json:"user_id"`
		AcademicYear string `json:"academic_year"`
		Semester     string `json:"semester"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.UserID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "user_id wajib diisi"})
		return
	}
	raport, err := s.generateRaportForStudent(user.SchoolID, payload.UserID, payload.AcademicYear, payload.Semester)
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal generate raport"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "raport siswa dibuat", "item": raport})
}

func (s *Server) handleGenerateClassRaports(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		ClassID      uint   `json:"class_id"`
		AcademicYear string `json:"academic_year"`
		Semester     string `json:"semester"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.ClassID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "class_id wajib diisi"})
		return
	}
	var students []User
	s.DB.Where("school_id = ? AND class_id = ? AND role = ?", user.SchoolID, payload.ClassID, "student").Find(&students)
	created := 0
	for _, student := range students {
		if _, err := s.generateRaportForStudent(user.SchoolID, student.ID, payload.AcademicYear, payload.Semester); err == nil {
			created++
		}
	}
	render.JSON(w, r, map[string]any{"message": "raport kelas dibuat", "created": created})
}

func (s *Server) handleGenerateSchoolRaports(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		AcademicYear string `json:"academic_year"`
		Semester     string `json:"semester"`
	}
	_ = parseJSONBody(r, &payload)
	var students []User
	s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "student").Find(&students)
	created := 0
	for _, student := range students {
		if _, err := s.generateRaportForStudent(user.SchoolID, student.ID, payload.AcademicYear, payload.Semester); err == nil {
			created++
		}
	}
	render.JSON(w, r, map[string]any{"message": "raport sekolah dibuat", "created": created})
}

func (s *Server) generateRaportForStudent(schoolID, userID uint, academicYear, semester string) (*Raport, error) {
	if strings.TrimSpace(academicYear) == "" {
		year := time.Now().Year()
		academicYear = fmt.Sprintf("%d/%d", year, year+1)
	}
	if strings.TrimSpace(semester) == "" {
		semester = "ganjil"
	}
	var student User
	if err := s.DB.Where("school_id = ? AND role = ?", schoolID, "student").First(&student, userID).Error; err != nil {
		return nil, err
	}
	subjectsData, avg := s.studentRaportSubjectsData(schoolID, userID)
	grade := gradeFromScore(avg)
	now := time.Now()
	raport := Raport{
		SchoolID:        schoolID,
		UserID:          userID,
		ClassID:         student.ClassID,
		AcademicYear:    academicYear,
		Semester:        semester,
		Grade:           grade,
		CalculatedScore: avg,
		FinalScore:      avg,
		OverallScore:    avg,
		OverallGrade:    grade,
		OverallPassed:   avg >= 75,
		Status:          "draft",
		IsPassed:        avg >= 75,
		GeneratedAt:     &now,
		SubjectsData:    upsertJSON(subjectsData),
		Data:            upsertJSON(map[string]any{"source": "weighted_subject_exam_results", "subjects_count": len(subjectsData)}),
	}
	err := s.DB.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "school_id"}, {Name: "user_id"}, {Name: "academic_year"}, {Name: "semester"}},
		DoUpdates: clause.AssignmentColumns([]string{"class_id", "grade", "calculated_score", "final_score", "overall_score", "overall_grade", "overall_passed", "is_passed", "generated_at", "subjects_data", "data", "updated_at"}),
	}).Create(&raport).Error
	return &raport, err
}

func (s *Server) studentRaportSubjectsData(schoolID, userID uint) ([]map[string]any, float64) {
	rows := []struct {
		SubjectID   uint
		SubjectName string
		KKM         *int
		ExamType    string
		Average     float64
		Count       int64
	}{}
	s.DB.Model(&ExamResult{}).
		Select("subjects.id as subject_id, subjects.name as subject_name, subjects.kkm, exams.exam_type, COALESCE(AVG(exam_results.score), 0) as average, COUNT(exam_results.id) as count").
		Joins("JOIN exams ON exams.id = exam_results.exam_id").
		Joins("JOIN question_packages ON question_packages.id = exams.question_package_id").
		Joins("JOIN subjects ON subjects.id = question_packages.subject_id").
		Where("exams.school_id = ? AND exam_results.user_id = ? AND exam_results.status = ?", schoolID, userID, "completed").
		Group("subjects.id, subjects.name, subjects.kkm, exams.exam_type").
		Scan(&rows)

	weights := s.reportExamTypeWeights(schoolID)
	type subjectAccumulator struct {
		name      string
		kkm       int
		total     float64
		weightSum float64
		breakdown map[string]any
	}
	subjects := map[uint]*subjectAccumulator{}
	for _, row := range rows {
		kkm := 75
		if row.KKM != nil {
			kkm = *row.KKM
		}
		acc := subjects[row.SubjectID]
		if acc == nil {
			acc = &subjectAccumulator{name: row.SubjectName, kkm: kkm, breakdown: map[string]any{}}
			subjects[row.SubjectID] = acc
		}
		weight := weights[row.ExamType]
		if weight <= 0 {
			weight = 1
		}
		acc.total += row.Average * weight
		acc.weightSum += weight
		acc.breakdown[row.ExamType] = map[string]any{"average": row.Average, "count": row.Count, "weight": weight}
	}

	out := make([]map[string]any, 0, len(subjects))
	var overall float64
	for subjectID, acc := range subjects {
		score := float64(0)
		if acc.weightSum > 0 {
			score = acc.total / acc.weightSum
		}
		overall += score
		out = append(out, map[string]any{
			"subject_id": subjectID,
			"name":       acc.name,
			"kkm":        acc.kkm,
			"score":      score,
			"grade":      gradeFromScore(score),
			"is_passed":  score >= float64(acc.kkm),
			"breakdown":  acc.breakdown,
		})
	}
	if len(out) > 0 {
		overall = overall / float64(len(out))
	}
	return out, overall
}

func (s *Server) reportExamTypeWeights(schoolID uint) map[string]float64 {
	defaults := map[string]float64{
		"tugas_harian":   10,
		"ulangan_harian": 15,
		"tugas_besar":    15,
		"uts":            25,
		"uas":            35,
		"un":             0,
		"lainnya":        0,
	}
	var configs []ReportConfig
	s.DB.Where("school_id = ? AND config_type = ? AND is_active = ?", schoolID, "exam_type_percentages", true).Find(&configs)
	for _, config := range configs {
		if config.Value != nil && config.Key != "payload" {
			defaults[config.Key] = *config.Value
		}
		if config.Key == "payload" && len(config.Metadata) > 0 {
			var payload map[string]float64
			if err := json.Unmarshal(config.Metadata, &payload); err == nil {
				for key, value := range payload {
					defaults[key] = value
				}
			}
		}
	}
	return defaults
}

func gradeFromScore(score float64) string {
	switch {
	case score >= 90:
		return "A"
	case score >= 80:
		return "B"
	case score >= 70:
		return "C"
	case score >= 60:
		return "D"
	default:
		return "E"
	}
}

func (s *Server) handlePublishRaport(w http.ResponseWriter, r *http.Request) {
	s.handleRaportStatus(w, r, "published")
}

func (s *Server) handleArchiveRaport(w http.ResponseWriter, r *http.Request) {
	s.handleRaportStatus(w, r, "archived")
}

func (s *Server) handleRaportStatus(w http.ResponseWriter, r *http.Request, status string) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id raport tidak valid"})
		return
	}
	updates := map[string]any{"status": status}
	if status == "published" {
		updates["published_at"] = time.Now()
	}
	if err := s.DB.Model(&Raport{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Updates(updates).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui status raport"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "status raport diperbarui", "status": status})
}

func (s *Server) handleAIScoringIndex(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []StudentAnswer
	s.DB.Joins("JOIN exams ON exams.id = student_answers.exam_id").
		Where("exams.school_id = ? AND student_answers.question_type = ?", user.SchoolID, "essay").
		Order("student_answers.updated_at DESC").
		Limit(100).
		Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleAIScoringStats(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var total, pending, graded int64
	base := s.DB.Model(&StudentAnswer{}).
		Joins("JOIN exams ON exams.id = student_answers.exam_id").
		Where("exams.school_id = ? AND student_answers.question_type = ?", user.SchoolID, "essay")
	base.Count(&total)
	base.Where("student_answers.is_graded = ?", false).Count(&pending)
	base.Where("student_answers.is_graded = ?", true).Count(&graded)
	render.JSON(w, r, map[string]any{"total": total, "pending": pending, "graded": graded})
}

func (s *Server) handleScoreEssay(w http.ResponseWriter, r *http.Request) {
	essayID, err := pathUint(r, "essayId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id essay tidak valid"})
		return
	}
	var answer StudentAnswer
	if err := s.DB.First(&answer, essayID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "essay tidak ditemukan"})
		return
	}
	result, err := s.scoreEssayWithAI(answer)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	if err := s.DB.Transaction(func(tx *gorm.DB) error {
		return s.applyAIScore(tx, answer, result)
	}); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal scoring essay"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "essay discoring", "suggested_score": result.Score, "ai_type": result.Model})
}

func (s *Server) handleScoreMultipleEssays(w http.ResponseWriter, r *http.Request) {
	processed, err := s.runAIScoring()
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menjalankan AI scoring"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "AI scoring diproses", "processed": processed})
}

func (s *Server) handleResetEssayScoring(w http.ResponseWriter, r *http.Request) {
	essayID, err := pathUint(r, "essayId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id essay tidak valid"})
		return
	}
	if err := s.DB.Model(&StudentAnswer{}).Where("id = ?", essayID).Updates(map[string]any{
		"is_ai_scheduler":    false,
		"is_graded":          false,
		"ai_score_suggested": 0,
		"ai_type":            nil,
		"points_earned":      0,
		"additional_data":    upsertJSON(map[string]any{"ai_scoring_audit": []map[string]any{{"at": time.Now().Format(time.RFC3339), "source": "manual_reset", "score": 0}}}),
	}).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal reset scoring"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "scoring essay direset"})
}
