package platform

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/rand"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func decodeJSONMap(data []byte) map[string]string {
	if len(data) == 0 {
		return map[string]string{}
	}
	var out map[string]string
	if err := json.Unmarshal(data, &out); err != nil {
		return map[string]string{}
	}
	return out
}

func decodeJSONIntMap(data []byte) map[string]int {
	if len(data) == 0 {
		return map[string]int{}
	}
	var out map[string]int
	if err := json.Unmarshal(data, &out); err != nil {
		return map[string]int{}
	}
	return out
}

const questionIDsMetaKey = "__question_ids_v1"

func parseCommaUintList(input string) []uint {
	input = strings.TrimSpace(input)
	if input == "" {
		return nil
	}
	parts := strings.Split(input, ",")
	out := make([]uint, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		v, err := strconv.ParseUint(p, 10, 64)
		if err != nil {
			continue
		}
		out = append(out, uint(v))
	}
	return out
}

func decodeQuestionOptions(data []byte) map[string]string {
	if len(data) == 0 {
		return map[string]string{}
	}
	var out map[string]string
	_ = json.Unmarshal(data, &out)
	return out
}

func (s *Server) handleListExams(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var exams []Exam
	query := s.DB.Where("school_id = ?", user.SchoolID)
	if status := r.URL.Query().Get("status"); status != "" {
		query = query.Where("status = ?", status)
	}
	if examType := r.URL.Query().Get("exam_type"); examType != "" {
		query = query.Where("exam_type = ?", examType)
	}
	query.Order("created_at DESC").Find(&exams)
	render.JSON(w, r, map[string]any{"items": exams})
}

func (s *Server) handleCreateExam(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload Exam
	if err := parseJSONBody(r, &payload); err != nil || payload.QuestionPackageID == 0 || payload.Title == "" || payload.ExamType == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "data ujian tidak valid"})
		return
	}
	payload.SchoolID = user.SchoolID
	if payload.Status == "" {
		payload.Status = "draft"
	}
	s.DB.Create(&payload)
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": payload})
}

func (s *Server) handleUpdateExam(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var payload map[string]any
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	s.DB.Model(&Exam{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Updates(payload)
	render.JSON(w, r, map[string]any{"message": "ujian diperbarui"})
}

func (s *Server) handleDeleteExam(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	s.DB.Where("school_id = ?", user.SchoolID).Delete(&Exam{}, id)
	render.JSON(w, r, map[string]any{"message": "ujian dihapus"})
}

func (s *Server) handlePublishExam(w http.ResponseWriter, r *http.Request) {
	s.handleExamStatusUpdate(w, r, "published")
}

func (s *Server) handleCancelExam(w http.ResponseWriter, r *http.Request) {
	s.handleExamStatusUpdate(w, r, "cancelled")
}

func (s *Server) handleExamStatusUpdate(w http.ResponseWriter, r *http.Request, status string) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	s.DB.Model(&Exam{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Update("status", status)
	render.JSON(w, r, map[string]any{"message": "status ujian diperbarui", "status": status})
}

func (s *Server) handleRepickExam(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}

	var payload struct {
		UserIDs         []uint `json:"user_ids"`
		ResetAttempt    *bool  `json:"reset_attempt"`
		PreserveHistory *bool  `json:"preserve_history"`
	}
	_ = parseJSONBody(r, &payload)

	var exam Exam
	if err := s.DB.Where("id = ? AND school_id = ?", examID, user.SchoolID).First(&exam).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "ujian tidak ditemukan"})
		return
	}

	resetAttempt := true
	if payload.ResetAttempt != nil {
		resetAttempt = *payload.ResetAttempt
	}
	preserveHistory := false
	if payload.PreserveHistory != nil {
		preserveHistory = *payload.PreserveHistory
	}

	affectedUsers := make([]uint, 0)
	affectedResults := int64(0)
	affectedAssignments := int64(0)
	err = s.withTx(func(tx *gorm.DB) error {
		assignQuery := tx.Where("exam_id = ?", examID)
		if len(payload.UserIDs) > 0 {
			assignQuery = assignQuery.Where("user_id IN ?", payload.UserIDs)
		}

		var assignments []ExamAssignment
		if err := assignQuery.
			Clauses(clause.Locking{Strength: "UPDATE"}).
			Find(&assignments).Error; err != nil {
			return err
		}
		if len(assignments) == 0 {
			return fmt.Errorf("tidak ada assignment untuk repick")
		}
		userSet := make(map[uint]struct{}, len(assignments))
		for _, a := range assignments {
			userSet[a.UserID] = struct{}{}
		}
		for uid := range userSet {
			affectedUsers = append(affectedUsers, uid)
		}
		sort.Slice(affectedUsers, func(i, j int) bool { return affectedUsers[i] < affectedUsers[j] })

		var resultIDs []uint
		var existingResults []ExamResult
		if err := tx.Where("exam_id = ? AND user_id IN ?", examID, affectedUsers).Find(&existingResults).Error; err != nil {
			return err
		}
		for _, item := range existingResults {
			resultIDs = append(resultIDs, item.ID)
		}
		affectedResults = int64(len(resultIDs))

		if preserveHistory {
			if len(resultIDs) > 0 {
				if err := tx.Model(&ExamResult{}).Where("id IN ?", resultIDs).Updates(map[string]any{
					"status":           "repicked_archived",
					"last_activity_at": time.Now(),
					"notes":            gorm.Expr("CONCAT(COALESCE(notes, ''), ?)", "\nDiarsipkan karena repick soal."),
				}).Error; err != nil {
					return err
				}
			}
		} else {
			if len(resultIDs) > 0 {
				if err := tx.Where("exam_result_id IN ?", resultIDs).Delete(&PgAnswer{}).Error; err != nil {
					return err
				}
			}
			if err := tx.Where("exam_id = ? AND user_id IN ?", examID, affectedUsers).Delete(&StudentAnswer{}).Error; err != nil {
				return err
			}
			if err := tx.Where("exam_id = ? AND user_id IN ?", examID, affectedUsers).Delete(&ExamResult{}).Error; err != nil {
				return err
			}
		}
		if err := tx.Where("exam_id = ? AND user_id IN ?", examID, affectedUsers).Delete(&ExamResultTempAnswer{}).Error; err != nil {
			return err
		}

		if resetAttempt {
			result := tx.Model(&ExamAssignment{}).
				Where("exam_id = ? AND user_id IN ?", examID, affectedUsers).
				Updates(map[string]any{
					"attempt":   0,
					"is_active": true,
				})
			if result.Error != nil {
				return result.Error
			}
			affectedAssignments = result.RowsAffected
		}
		return nil
	})
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}

	render.JSON(w, r, map[string]any{
		"message":               "repick ujian berhasil dijadwalkan ulang",
		"exam_id":               exam.ID,
		"affected_user_count":   len(affectedUsers),
		"affected_result_count": affectedResults,
		"reset_attempt":         resetAttempt,
		"preserve_history":      preserveHistory,
		"reset_assignment_rows": affectedAssignments,
	})
}

func (s *Server) handleListExamAssignments(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	var items []ExamAssignment
	s.DB.Where("exam_id = ?", examID).Find(&items)
	var exam Exam
	s.DB.Where("school_id = ?", user.SchoolID).First(&exam, examID)
	render.JSON(w, r, map[string]any{"exam": exam, "items": items})
}

func (s *Server) handleAssignExam(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	var payload struct {
		AssignmentType string `json:"assignment_type"`
		UserIDs        []uint `json:"user_ids"`
		ClassIDs       []uint `json:"class_ids"`
		TotalAttempt   int    `json:"total_attempt"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.AssignmentType == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	if payload.TotalAttempt <= 0 {
		payload.TotalAttempt = 1
	}

	var studentIDs []uint
	if payload.AssignmentType == "individual" {
		studentIDs = payload.UserIDs
	} else {
		var students []User
		s.DB.Where("school_id = ? AND role = ? AND class_id IN ?", user.SchoolID, "student", payload.ClassIDs).Find(&students)
		studentIDs = make([]uint, 0, len(students))
		for _, student := range students {
			studentIDs = append(studentIDs, student.ID)
		}
	}

	for _, studentID := range studentIDs {
		item := ExamAssignment{
			ExamID:         examID,
			UserID:         studentID,
			AssignmentType: "individual",
			IsActive:       true,
			TotalAttempt:   payload.TotalAttempt,
		}
		s.DB.Clauses(clause.OnConflict{DoNothing: true}).Create(&item)
	}

	render.JSON(w, r, map[string]any{"message": "assignment ujian diperbarui", "count": len(studentIDs)})
}

func (s *Server) handleDeleteExamAssignment(w http.ResponseWriter, r *http.Request) {
	assignmentID, err := pathUint(r, "assignmentId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id assignment tidak valid"})
		return
	}
	s.DB.Delete(&ExamAssignment{}, assignmentID)
	render.JSON(w, r, map[string]any{"message": "assignment dihapus"})
}

func (s *Server) handleAttemptManagement(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	query := s.DB.
		Model(&ExamAssignment{}).
		Preload("Exam").
		Preload("User").
		Preload("ClassRoom").
		Joins("JOIN exams ON exams.id = exam_assignments.exam_id").
		Joins("JOIN users ON users.id = exam_assignments.user_id").
		Where("exams.school_id = ?", user.SchoolID).
		Where("users.school_id = ? AND users.role = ?", user.SchoolID, "student")
	if search := strings.TrimSpace(r.URL.Query().Get("search")); search != "" {
		like := "%" + search + "%"
		query = query.Where("users.name LIKE ? OR users.email LIKE ?", like, like)
	}
	if examID := strings.TrimSpace(r.URL.Query().Get("exam_id")); examID != "" {
		query = query.Where("exam_assignments.exam_id = ?", examID)
	}
	if userID := strings.TrimSpace(r.URL.Query().Get("user_id")); userID != "" {
		query = query.Where("exam_assignments.user_id = ?", userID)
	}
	if classID := strings.TrimSpace(r.URL.Query().Get("class_id")); classID != "" {
		query = query.Where("users.class_id = ?", classID)
	}
	if assignmentType := strings.TrimSpace(r.URL.Query().Get("assignment_type")); assignmentType != "" {
		query = query.Where("exam_assignments.assignment_type = ?", assignmentType)
	}
	if active := strings.TrimSpace(r.URL.Query().Get("is_active")); active != "" {
		query = query.Where("exam_assignments.is_active = ?", active == "true" || active == "1")
	}
	var items []ExamAssignment
	query.Order("exam_assignments.updated_at DESC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleResetAttempt(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		AssignmentID uint `json:"assignment_id"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.AssignmentID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "assignment_id wajib"})
		return
	}
	s.DB.Model(&ExamAssignment{}).Where("id = ?", payload.AssignmentID).Updates(map[string]any{"attempt": 0, "is_active": true})
	render.JSON(w, r, map[string]any{"message": "attempt direset"})
}

func (s *Server) handleAddUserAttempt(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		UserID                uint   `json:"user_id"`
		ExamID                uint   `json:"exam_id"`
		ExtraAttempts         int    `json:"extra_attempts"`
		Confirmed             bool   `json:"confirmed"`
		Mode                  string `json:"mode"`
		CustomDurationMinutes *uint  `json:"custom_duration_minutes"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.UserID == 0 || payload.ExamID == 0 || payload.ExtraAttempts < 1 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	var student User
	if err := s.DB.Where("id = ? AND school_id = ? AND role = ?", payload.UserID, user.SchoolID, "student").First(&student).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "siswa tidak ditemukan"})
		return
	}
	var exam Exam
	if err := s.DB.Where("id = ? AND school_id = ?", payload.ExamID, user.SchoolID).First(&exam).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "ujian tidak ditemukan"})
		return
	}
	var existing ExamAssignment
	if err := s.DB.Where("user_id = ? AND exam_id = ?", payload.UserID, payload.ExamID).First(&existing).Error; err == nil && !payload.Confirmed {
		details, detailsErr := s.attemptDetailsFor(s.DB, user.SchoolID, existing.ID)
		if detailsErr == nil {
			render.Status(r, http.StatusConflict)
			render.JSON(w, r, map[string]any{
				"message":             "siswa ini sudah memiliki assignment. kirim confirmed=true untuk menambah attempt.",
				"needs_confirmation":  true,
				"existing_assignment": details,
			})
			return
		}
	}
	if err := s.withTx(func(tx *gorm.DB) error {
		var assignment ExamAssignment
		err := tx.Where("user_id = ? AND exam_id = ?", payload.UserID, payload.ExamID).First(&assignment).Error
		if err == nil {
			oldTotal := assignment.TotalAttempt
			if err := tx.Model(&ExamAssignment{}).Where("id = ?", assignment.ID).Updates(map[string]any{
				"total_attempt": gorm.Expr("total_attempt + ?", payload.ExtraAttempts),
				"is_active":     true,
			}).Error; err != nil {
				return err
			}
			return s.ensureAttemptConfigs(tx, assignment.ID, oldTotal+1, oldTotal+payload.ExtraAttempts, payload.Mode, payload.CustomDurationMinutes)
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		item := ExamAssignment{
			ExamID:         payload.ExamID,
			UserID:         payload.UserID,
			ClassID:        student.ClassID,
			AssignmentType: "individual",
			IsActive:       true,
			Attempt:        0,
			TotalAttempt:   payload.ExtraAttempts,
		}
		if err := tx.Create(&item).Error; err != nil {
			return err
		}
		return s.ensureAttemptConfigs(tx, item.ID, 1, payload.ExtraAttempts, payload.Mode, payload.CustomDurationMinutes)
	}); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "gagal menambah attempt"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "attempt siswa berhasil diperbarui"})
}

func (s *Server) handleAddClassAttempt(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		ClassID               uint   `json:"class_id"`
		ExamID                uint   `json:"exam_id"`
		ExtraAttempts         int    `json:"extra_attempts"`
		Confirmed             bool   `json:"confirmed"`
		Mode                  string `json:"mode"`
		CustomDurationMinutes *uint  `json:"custom_duration_minutes"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.ClassID == 0 || payload.ExamID == 0 || payload.ExtraAttempts < 1 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	var students []User
	s.DB.Where("school_id = ? AND role = ? AND class_id = ?", user.SchoolID, "student", payload.ClassID).Find(&students)
	if len(students) == 0 {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "tidak ada siswa pada kelas tersebut"})
		return
	}

	var existing []map[string]any
	for _, student := range students {
		var assignment ExamAssignment
		if err := s.DB.Where("user_id = ? AND exam_id = ?", student.ID, payload.ExamID).First(&assignment).Error; err == nil {
			details, detailsErr := s.attemptDetailsFor(s.DB, user.SchoolID, assignment.ID)
			if detailsErr == nil {
				existing = append(existing, details)
			}
		}
	}
	if len(existing) > 0 && !payload.Confirmed {
		render.Status(r, http.StatusConflict)
		render.JSON(w, r, map[string]any{
			"message":              "sebagian siswa sudah memiliki assignment. kirim confirmed=true untuk menambah attempt.",
			"needs_confirmation":   true,
			"existing_assignments": existing,
		})
		return
	}

	if err := s.withTx(func(tx *gorm.DB) error {
		for _, student := range students {
			var assignment ExamAssignment
			err := tx.Where("user_id = ? AND exam_id = ?", student.ID, payload.ExamID).First(&assignment).Error
			if err == nil {
				oldTotal := assignment.TotalAttempt
				if err := tx.Model(&ExamAssignment{}).Where("id = ?", assignment.ID).Updates(map[string]any{
					"total_attempt": gorm.Expr("total_attempt + ?", payload.ExtraAttempts),
					"is_active":     true,
				}).Error; err != nil {
					return err
				}
				if err := s.ensureAttemptConfigs(tx, assignment.ID, oldTotal+1, oldTotal+payload.ExtraAttempts, payload.Mode, payload.CustomDurationMinutes); err != nil {
					return err
				}
				continue
			}
			if !errors.Is(err, gorm.ErrRecordNotFound) {
				return err
			}
			item := ExamAssignment{
				ExamID:         payload.ExamID,
				UserID:         student.ID,
				ClassID:        student.ClassID,
				AssignmentType: "class",
				IsActive:       true,
				Attempt:        0,
				TotalAttempt:   payload.ExtraAttempts,
			}
			if err := tx.Create(&item).Error; err != nil {
				return err
			}
			if err := s.ensureAttemptConfigs(tx, item.ID, 1, payload.ExtraAttempts, payload.Mode, payload.CustomDurationMinutes); err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menambah attempt kelas"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "attempt kelas berhasil diperbarui", "count": len(students)})
}

func (s *Server) ensureAttemptConfigs(tx *gorm.DB, assignmentID uint, startAttempt, endAttempt int, mode string, customDuration *uint) error {
	if mode == "" {
		mode = "auto"
	}
	allowed := map[string]bool{
		"auto":               true,
		"fresh_start":        true,
		"continue_remaining": true,
		"full_time":          true,
		"custom_duration":    true,
	}
	if !allowed[mode] {
		mode = "auto"
	}
	for attempt := startAttempt; attempt <= endAttempt; attempt++ {
		config := ExamAttemptConfig{
			ExamAssignmentID:      assignmentID,
			ForAttemptNumber:      uint(attempt),
			Mode:                  mode,
			CustomDurationMinutes: customDuration,
		}
		if err := tx.Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "exam_assignment_id"}, {Name: "for_attempt_number"}},
			DoUpdates: clause.AssignmentColumns([]string{"mode", "custom_duration_minutes", "updated_at"}),
		}).Create(&config).Error; err != nil {
			return err
		}
	}
	return nil
}

func (s *Server) handleResetUserAttempt(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		UserID uint `json:"user_id"`
		ExamID uint `json:"exam_id"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.UserID == 0 || payload.ExamID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	res := s.DB.Model(&ExamAssignment{}).
		Joins("JOIN exams ON exams.id = exam_assignments.exam_id").
		Where("exam_assignments.user_id = ? AND exam_assignments.exam_id = ? AND exams.school_id = ?", payload.UserID, payload.ExamID, user.SchoolID).
		Updates(map[string]any{"attempt": 0, "is_active": true})
	if res.RowsAffected == 0 {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "assignment tidak ditemukan"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "attempt siswa berhasil direset"})
}

func (s *Server) handleResetClassAttempt(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		ClassID uint `json:"class_id"`
		ExamID  uint `json:"exam_id"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.ClassID == 0 || payload.ExamID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	var studentIDs []uint
	s.DB.Model(&User{}).Where("school_id = ? AND role = ? AND class_id = ?", user.SchoolID, "student", payload.ClassID).Pluck("id", &studentIDs)
	if len(studentIDs) == 0 {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "tidak ada siswa pada kelas tersebut"})
		return
	}
	res := s.DB.Model(&ExamAssignment{}).Where("exam_id = ? AND user_id IN ?", payload.ExamID, studentIDs).Updates(map[string]any{"attempt": 0, "is_active": true})
	render.JSON(w, r, map[string]any{"message": "attempt kelas berhasil direset", "count": res.RowsAffected})
}

func (s *Server) handleDeleteAttemptAssignment(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		AssignmentID uint `json:"assignment_id"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.AssignmentID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "assignment_id wajib"})
		return
	}
	res := s.DB.
		Joins("JOIN exams ON exams.id = exam_assignments.exam_id").
		Where("exam_assignments.id = ? AND exams.school_id = ?", payload.AssignmentID, user.SchoolID).
		Delete(&ExamAssignment{})
	if res.RowsAffected == 0 {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "assignment tidak ditemukan"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "assignment berhasil dihapus"})
}

func (s *Server) handleToggleAttemptActive(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id assignment tidak valid"})
		return
	}
	var assignment ExamAssignment
	if err := s.DB.Preload("Exam").
		Joins("JOIN exams ON exams.id = exam_assignments.exam_id").
		Where("exam_assignments.id = ? AND exams.school_id = ?", id, user.SchoolID).
		First(&assignment).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "assignment tidak ditemukan"})
		return
	}
	nextActive := !assignment.IsActive
	s.DB.Model(&ExamAssignment{}).Where("id = ?", assignment.ID).Update("is_active", nextActive)
	render.JSON(w, r, map[string]any{"message": "status assignment diperbarui", "is_active": nextActive})
}

func (s *Server) handleAttemptDetails(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id assignment tidak valid"})
		return
	}
	details, err := s.attemptDetailsFor(s.DB, user.SchoolID, id)
	if err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "detail assignment tidak ditemukan"})
		return
	}
	render.JSON(w, r, details)
}

func (s *Server) attemptDetailsFor(db *gorm.DB, schoolID uint, assignmentID uint) (map[string]any, error) {
	var assignment ExamAssignment
	if err := db.
		Preload("Exam").
		Preload("User").
		Preload("ClassRoom").
		Joins("JOIN exams ON exams.id = exam_assignments.exam_id").
		Where("exam_assignments.id = ? AND exams.school_id = ?", assignmentID, schoolID).
		First(&assignment).Error; err != nil {
		return nil, err
	}
	var results []ExamResult
	if err := db.Where("exam_id = ? AND user_id = ?", assignment.ExamID, assignment.UserID).Order("created_at DESC").Find(&results).Error; err != nil {
		return nil, err
	}
	return map[string]any{
		"assignment":        assignment,
		"remaining_attempt": maxInt(0, assignment.TotalAttempt-assignment.Attempt),
		"cheating_history":  buildCheatingHistory(results),
		"exam_results":      results,
	}, nil
}

func buildCheatingHistory(results []ExamResult) []map[string]any {
	history := make([]map[string]any, 0, len(results))
	for _, result := range results {
		entry := map[string]any{
			"exam_result_id":    result.ID,
			"status":            result.Status,
			"started_at":        result.StartedAt,
			"completed_at":      result.CompletedAt,
			"created_at":        result.CreatedAt,
			"cheating_note_raw": result.CheatingNote,
			"cheating_entries":  []map[string]any{},
		}
		if result.CheatingNote != nil && strings.TrimSpace(*result.CheatingNote) != "" {
			var raw map[string]any
			if json.Unmarshal([]byte(*result.CheatingNote), &raw) == nil {
				if violations, ok := raw["violations"].([]any); ok {
					items := make([]map[string]any, 0, len(violations))
					for _, violation := range violations {
						if row, ok := violation.(map[string]any); ok {
							items = append(items, map[string]any{
								"timestamp":   row["timestamp"],
								"type":        row["type"],
								"description": coalesceAny(row["description"], row["message"]),
								"details":     row["details"],
							})
						}
					}
					entry["cheating_entries"] = items
				}
			}
		}
		history = append(history, entry)
	}
	return history
}

func coalesceAny(values ...any) any {
	for _, value := range values {
		if value != nil {
			return value
		}
	}
	return nil
}

func maxInt(a int, b int) int {
	if a > b {
		return a
	}
	return b
}

func (s *Server) handleListExamResults(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	items := []ExamResult{}
	query := s.DB.Joins("JOIN exams ON exams.id = exam_results.exam_id").Where("exams.school_id = ?", user.SchoolID)
	query = s.scopeExamResultsForUser(query, user)
	if status := r.URL.Query().Get("status"); status != "" {
		query = query.Where("exam_results.status = ?", status)
	}
	if examID := r.URL.Query().Get("exam_id"); examID != "" {
		query = query.Where("exam_results.exam_id = ?", examID)
	}
	if userID := r.URL.Query().Get("user_id"); userID != "" {
		query = query.Where("exam_results.user_id = ?", userID)
	}
	query.Order("exam_results.created_at DESC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleGetExamResult(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id result tidak valid"})
		return
	}
	var item ExamResult
	query := s.DB.Joins("JOIN exams ON exams.id = exam_results.exam_id").Where("exams.school_id = ?", user.SchoolID)
	query = s.scopeExamResultsForUser(query, user)
	if err := query.First(&item, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "hasil ujian tidak ditemukan"})
		return
	}
	var answers []StudentAnswer
	s.DB.Where("exam_result_id = ?", item.ID).Order("question_id ASC").Find(&answers)
	render.JSON(w, r, map[string]any{"item": item, "answers": answers})
}

func (s *Server) scopeExamResultsForUser(query *gorm.DB, user *User) *gorm.DB {
	if user == nil || user.Role != "tutor" {
		return query
	}
	return query.
		Joins("JOIN question_packages tutor_qp_scope ON tutor_qp_scope.id = exams.question_package_id").
		Joins("JOIN users tutor_student_scope ON tutor_student_scope.id = exam_results.user_id").
		Joins("JOIN tutor_assignments tutor_scope ON tutor_scope.school_id = exams.school_id AND tutor_scope.subject_id = tutor_qp_scope.subject_id AND tutor_scope.class_id = tutor_student_scope.class_id").
		Where("tutor_scope.tutor_id = ?", user.ID)
}

func (s *Server) handleUpdateExamResultNotes(w http.ResponseWriter, r *http.Request) {
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id result tidak valid"})
		return
	}
	var payload struct {
		Notes string `json:"notes"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	s.DB.Model(&ExamResult{}).Where("id = ?", id).Update("notes", payload.Notes)
	render.JSON(w, r, map[string]any{"message": "catatan diperbarui"})
}

func (s *Server) handleUpdateEssayScores(w http.ResponseWriter, r *http.Request) {
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id result tidak valid"})
		return
	}
	var payload struct {
		Scores map[string]int `json:"essay_scores"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	if err := s.withTx(func(tx *gorm.DB) error {
		var result ExamResult
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&result, id).Error; err != nil {
			return err
		}
		totalEssay := 0
		for qID, score := range payload.Scores {
			totalEssay += score
			tx.Model(&StudentAnswer{}).
				Where("exam_result_id = ? AND question_id = ?", id, qID).
				Updates(map[string]any{
					"points_earned":   score,
					"score":           score,
					"is_graded":       true,
					"is_ai_scheduler": true,
					"ai_type":         "manual",
					"is_correct":      score > 0,
				})
		}
		result.EssayScore = totalEssay
		result.Score = result.PGScore + totalEssay
		result.EssayScores = upsertJSON(payload.Scores)
		return tx.Save(&result).Error
	}); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui nilai essay"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "nilai essay diperbarui"})
}

func (s *Server) handleExportExamResultsCSV(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []ExamResult
	s.DB.Joins("JOIN exams ON exams.id = exam_results.exam_id").Where("exams.school_id = ?", user.SchoolID).Order("exam_results.created_at DESC").Find(&items)
	records := [][]string{{"ID", "ExamID", "UserID", "Status", "Score", "PGScore", "EssayScore", "CompletedAt"}}
	for _, item := range items {
		completedAt := ""
		if item.CompletedAt != nil {
			completedAt = item.CompletedAt.Format(time.RFC3339)
		}
		records = append(records, []string{
			strconv.Itoa(int(item.ID)),
			strconv.Itoa(int(item.ExamID)),
			strconv.Itoa(int(item.UserID)),
			item.Status,
			strconv.Itoa(item.Score),
			strconv.Itoa(item.PGScore),
			strconv.Itoa(item.EssayScore),
			completedAt,
		})
	}
	if err := writeCSV(w, "exam-results.csv", records); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal membuat csv"})
	}
}

func (s *Server) handleStudentExams(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var assignments []ExamAssignment
	s.DB.Where("user_id = ? AND is_active = ?", user.ID, true).Order("created_at DESC").Find(&assignments)
	var examIDs []uint
	for _, assignment := range assignments {
		examIDs = append(examIDs, assignment.ExamID)
	}
	var exams []Exam
	if len(examIDs) > 0 {
		s.DB.Where("id IN ?", examIDs).Find(&exams)
	}
	render.JSON(w, r, map[string]any{"assignments": assignments, "exams": exams})
}

func (s *Server) handleStudentExamDetail(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	var exam Exam
	if err := s.DB.First(&exam, examID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "ujian tidak ditemukan"})
		return
	}
	var assignment ExamAssignment
	if err := s.DB.Where("exam_id = ? AND user_id = ?", examID, user.ID).First(&assignment).Error; err != nil {
		render.Status(r, http.StatusForbidden)
		render.JSON(w, r, map[string]any{"message": "ujian tidak diassign"})
		return
	}
	render.JSON(w, r, map[string]any{"exam": exam, "assignment": assignment})
}

func (s *Server) handleStudentExamStart(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}

	var exam Exam
	if err := s.DB.First(&exam, examID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "ujian tidak ditemukan"})
		return
	}
	if time.Now().Before(exam.StartTime) || time.Now().After(exam.EndTime) {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "ujian tidak dalam waktu yang diizinkan"})
		return
	}

	var assignment ExamAssignment
	if err := s.DB.Where("exam_id = ? AND user_id = ? AND is_active = ?", examID, user.ID, true).First(&assignment).Error; err != nil {
		render.Status(r, http.StatusForbidden)
		render.JSON(w, r, map[string]any{"message": "ujian tidak diassign"})
		return
	}

	// If user already consumed all attempts, still allow "resume" when there is an active exam_result.
	if assignment.Attempt >= assignment.TotalAttempt {
		var existing ExamResult
		err := s.DB.Where("exam_id = ? AND user_id = ? AND status IN ?", examID, user.ID, []string{"in_progress", "disconnected"}).First(&existing).Error
		if err != nil {
			render.Status(r, http.StatusBadRequest)
			render.JSON(w, r, map[string]any{"message": "attempt ujian sudah habis"})
			return
		}
	}

	var questions []Question
	var examResult *ExamResult
	timeLimit := exam.Duration * 60
	if err := s.withTx(func(tx *gorm.DB) error {
		lockedAssignment := ExamAssignment{}
		if err := tx.Where("exam_id = ? AND user_id = ? AND is_active = ?", examID, user.ID, true).
			Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&lockedAssignment).Error; err != nil {
			return err
		}

		result, created, err := s.getOrCreateActiveExamResult(tx, examID, user.ID)
		if err != nil {
			return err
		}
		examResult = result

		if created && lockedAssignment.Attempt >= lockedAssignment.TotalAttempt {
			return fmt.Errorf("attempt ujian sudah habis")
		}
		attemptNumber := lockedAssignment.Attempt
		if created {
			attemptNumber = lockedAssignment.Attempt + 1
		}
		timeLimit = s.effectiveAttemptTimeLimit(tx, exam, lockedAssignment.ID, attemptNumber, result)
		if created {
			if err := tx.Model(&lockedAssignment).UpdateColumn("attempt", gorm.Expr("attempt + ?", 1)).Error; err != nil {
				return err
			}
		}

		meta := decodeJSONMap(result.Answers)
		selectedIDs := parseCommaUintList(meta[questionIDsMetaKey])

		limit := exam.TotalQuestions
		if limit <= 0 {
			limit = 0
		}

		if len(selectedIDs) == 0 {
			var allQuestions []Question
			if err := tx.Where("question_package_id = ? AND is_active = ?", exam.QuestionPackageID, true).
				Order("`order` ASC, id ASC").
				Find(&allQuestions).Error; err != nil {
				return err
			}

			allIDs := make([]uint, 0, len(allQuestions))
			for _, q := range allQuestions {
				allIDs = append(allIDs, q.ID)
			}

			if limit <= 0 || limit > len(allIDs) {
				limit = len(allIDs)
			}

			if exam.ShuffleQuestions {
				seed := int64(result.ID) + int64(examID)*1000003
				rng := rand.New(rand.NewSource(seed))
				rng.Shuffle(len(allIDs), func(i, j int) {
					allIDs[i], allIDs[j] = allIDs[j], allIDs[i]
				})
			}

			selectedIDs = allIDs[:limit]

			metaParts := make([]string, 0, len(selectedIDs))
			for _, id := range selectedIDs {
				metaParts = append(metaParts, strconv.FormatUint(uint64(id), 10))
			}
			meta[questionIDsMetaKey] = strings.Join(metaParts, ",")
		}

		// Build questions in the same order as selectedIDs (so UI remains stable).
		if len(selectedIDs) > 0 {
			var chosen []Question
			if err := tx.Where("id IN ?", selectedIDs).Find(&chosen).Error; err != nil {
				return err
			}
			qMap := make(map[uint]Question, len(chosen))
			for _, q := range chosen {
				qMap[q.ID] = q
			}
			questions = make([]Question, 0, len(selectedIDs))
			for _, id := range selectedIDs {
				if q, ok := qMap[id]; ok {
					questions = append(questions, q)
				}
			}
		} else {
			questions = []Question{}
		}

		result.Answers = upsertJSON(meta)
		return tx.Save(result).Error
	}); err != nil {
		if err.Error() == "attempt ujian sudah habis" {
			render.Status(r, http.StatusBadRequest)
			render.JSON(w, r, map[string]any{"message": "attempt ujian sudah habis"})
			return
		}
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memulai ujian"})
		return
	}

	render.JSON(w, r, map[string]any{
		"exam":        exam,
		"exam_result": examResult,
		"questions":   questions,
		"time_limit":  timeLimit,
	})
}

func (s *Server) effectiveAttemptTimeLimit(tx *gorm.DB, exam Exam, assignmentID uint, attemptNumber int, result *ExamResult) int {
	minutes := exam.Duration
	var config ExamAttemptConfig
	if err := tx.Where("exam_assignment_id = ? AND for_attempt_number = ?", assignmentID, attemptNumber).First(&config).Error; err == nil {
		switch config.Mode {
		case "custom_duration":
			if config.CustomDurationMinutes != nil && *config.CustomDurationMinutes > 0 {
				minutes = int(*config.CustomDurationMinutes)
			}
		case "continue_remaining":
			if result != nil && result.StartedAt != nil {
				elapsed := int(time.Since(*result.StartedAt).Minutes())
				if elapsed > 0 && elapsed < minutes {
					minutes -= elapsed
				}
			}
		case "fresh_start", "full_time", "auto":
			minutes = exam.Duration
		}
	}
	if minutes < 1 {
		minutes = 1
	}
	return minutes * 60
}

func (s *Server) handleStudentExamHeartbeat(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, _ := pathUint(r, "id")
	var payload struct {
		ExamResultID    uint `json:"exam_result_id"`
		CurrentQuestion int  `json:"current_question"`
	}
	_ = parseJSONBody(r, &payload)
	query := s.DB.Model(&ExamResult{}).Where("exam_id = ? AND user_id = ?", examID, user.ID)
	if payload.ExamResultID > 0 {
		query = query.Where("id = ?", payload.ExamResultID)
	}
	now := time.Now()
	query.Updates(map[string]any{
		"status":           "in_progress",
		"last_activity_at": now,
		"current_question": payload.CurrentQuestion,
	})
	render.JSON(w, r, map[string]any{"message": "heartbeat tersimpan", "saved_at": now})
}

func (s *Server) handleStudentExamSync(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	var payload struct {
		ExamResultID    uint              `json:"exam_result_id"`
		Answers         map[string]string `json:"answers"`
		PGAnswers       map[string]string `json:"pg_answers"`
		CurrentQuestion int               `json:"current_question"`
		ClientVersion   int64             `json:"client_version"`
		SaveMode        string            `json:"save_mode"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}

	var synced ExamResult
	err = s.withTx(func(tx *gorm.DB) error {
		result, _, err := s.getOrCreateActiveExamResult(tx, examID, user.ID)
		if err != nil {
			return err
		}
		if payload.ExamResultID > 0 && result.ID != payload.ExamResultID {
			return fmt.Errorf("exam_result_id tidak cocok")
		}

		mergedAnswers := decodeJSONMap(result.Answers)
		for key, value := range payload.Answers {
			mergedAnswers[key] = value
		}
		for key, value := range payload.PGAnswers {
			mergedAnswers[key] = value
		}

		var questions []Question
		var questionIDs []uint
		for key := range payload.Answers {
			if questionID, err := strconv.ParseUint(key, 10, 64); err == nil {
				questionIDs = append(questionIDs, uint(questionID))
			}
		}
		for key := range payload.PGAnswers {
			if questionID, err := strconv.ParseUint(key, 10, 64); err == nil {
				questionIDs = append(questionIDs, uint(questionID))
			}
		}
		if len(questionIDs) > 0 {
			tx.Where("id IN ?", questionIDs).Find(&questions)
		}
		questionMap := make(map[uint]Question, len(questions))
		for _, question := range questions {
			questionMap[question.ID] = question
		}

		for key, answer := range payload.PGAnswers {
			questionID, _ := strconv.ParseUint(key, 10, 64)
			question := questionMap[uint(questionID)]
			tx.Clauses(clause.OnConflict{
				Columns:   []clause.Column{{Name: "exam_result_id"}, {Name: "question_id"}},
				DoUpdates: clause.AssignmentColumns([]string{"student_answer", "correct_answer", "is_correct", "points", "updated_at"}),
			}).Create(&PgAnswer{
				ExamResultID:  result.ID,
				QuestionID:    uint(questionID),
				StudentAnswer: ptr(answer),
				CorrectAnswer: question.CorrectAnswer,
				IsCorrect:     question.CorrectAnswer != nil && answer == *question.CorrectAnswer,
				Points:        question.Points,
			})
		}

		for key, answer := range payload.Answers {
			questionID, _ := strconv.ParseUint(key, 10, 64)
			question := questionMap[uint(questionID)]
			answerValue := answer
			tx.Clauses(clause.OnConflict{
				Columns:   []clause.Column{{Name: "exam_result_id"}, {Name: "question_id"}},
				DoUpdates: clause.AssignmentColumns([]string{"answer", "answer_value", "student_answer", "updated_at"}),
			}).Create(&StudentAnswer{
				ExamID:            examID,
				ExamResultID:      result.ID,
				UserID:            user.ID,
				QuestionID:        uint(questionID),
				QuestionPackageID: question.QuestionPackageID,
				QuestionType:      question.Type,
				Answer:            answerValue,
				AnswerValue:       answerValue,
				StudentAnswer:     answerValue,
				CorrectAnswer:     valueOrEmpty(question.EssayAnswer),
				MaxPoints:         question.Points,
				PointsEarned:      0,
				Score:             0,
			})
		}

		now := time.Now()
		result.Status = "in_progress"
		result.LastActivityAt = &now
		result.CurrentQuestion = ptr(payload.CurrentQuestion)
		result.Answers = upsertJSON(mergedAnswers)
		if err := tx.Save(result).Error; err != nil {
			return err
		}

		temp := ExamResultTempAnswer{
			ExamResultID:    result.ID,
			ExamID:          examID,
			UserID:          user.ID,
			Answers:         upsertJSON(payload.Answers),
			PGAnswers:       upsertJSON(payload.PGAnswers),
			CurrentQuestion: ptr(payload.CurrentQuestion),
			LastSavedAt:     &now,
		}
		if err := tx.Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "exam_result_id"}},
			DoUpdates: clause.AssignmentColumns([]string{"answers", "pg_answers", "current_question", "last_saved_at", "updated_at"}),
		}).Create(&temp).Error; err != nil {
			return err
		}

		synced = *result
		return nil
	})
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}

	render.JSON(w, r, map[string]any{
		"message":        "jawaban tersimpan",
		"exam_result":    synced,
		"saved_at":       time.Now(),
		"save_mode":      payload.SaveMode,
		"client_version": payload.ClientVersion,
	})
}

func valueOrEmpty(v *string) string {
	if v == nil {
		return ""
	}
	return *v
}

func (s *Server) calculateExamScore(tx *gorm.DB, exam Exam, result *ExamResult) (map[string]any, error) {
	var questions []Question
	if err := tx.Where("question_package_id = ?", exam.QuestionPackageID).Find(&questions).Error; err != nil {
		return nil, err
	}

	answers := decodeJSONMap(result.Answers)
	correct, wrong := 0, 0
	pgScore, essayScore := 0, 0
	totalPgPoints, totalEssayPoints := 0, 0
	essayScores := decodeJSONIntMap(result.EssayScores)

	for _, question := range questions {
		answer := answers[strconv.Itoa(int(question.ID))]
		if question.Type == "multiple_choice" {
			totalPgPoints += question.Points
			if question.CorrectAnswer != nil && answer == *question.CorrectAnswer {
				correct++
				pgScore += question.Points
			} else {
				wrong++
			}
		} else {
			totalEssayPoints += question.Points
			essayScore += essayScores[strconv.Itoa(int(question.ID))]
		}
	}

	totalPossible := totalPgPoints + totalEssayPoints
	totalScore := pgScore + essayScore
	return map[string]any{
		"score":              totalScore,
		"total_score":        totalPossible,
		"correct_answers":    correct,
		"wrong_answers":      wrong,
		"pg_score":           pgScore,
		"essay_score":        essayScore,
		"total_pg_points":    totalPgPoints,
		"total_essay_points": totalEssayPoints,
		"essay_scores":       essayScores,
	}, nil
}

func (s *Server) handleStudentExamSubmit(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id ujian tidak valid"})
		return
	}
	var payload struct {
		ExamResultID    uint              `json:"exam_result_id"`
		Answers         map[string]string `json:"answers"`
		PGAnswers       map[string]string `json:"pg_answers"`
		CurrentQuestion int               `json:"current_question"`
		Violations      []string          `json:"violations"`
		SubmitType      string            `json:"submit_type"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}

	var response map[string]any
	err = s.withTx(func(tx *gorm.DB) error {
		var exam Exam
		if err := tx.First(&exam, examID).Error; err != nil {
			return err
		}

		result, _, err := s.getOrCreateActiveExamResult(tx, examID, user.ID)
		if err != nil {
			return err
		}
		if payload.ExamResultID > 0 && result.ID != payload.ExamResultID {
			return fmt.Errorf("exam_result_id tidak cocok")
		}

		mergedAnswers := decodeJSONMap(result.Answers)
		for key, value := range payload.Answers {
			mergedAnswers[key] = value
		}
		for key, value := range payload.PGAnswers {
			mergedAnswers[key] = value
		}
		result.Answers = upsertJSON(mergedAnswers)
		result.CurrentQuestion = ptr(payload.CurrentQuestion)
		now := time.Now()
		result.LastActivityAt = &now

		var questions []Question
		var questionIDs []uint
		for key := range payload.Answers {
			if questionID, err := strconv.ParseUint(key, 10, 64); err == nil {
				questionIDs = append(questionIDs, uint(questionID))
			}
		}
		for key := range payload.PGAnswers {
			if questionID, err := strconv.ParseUint(key, 10, 64); err == nil {
				questionIDs = append(questionIDs, uint(questionID))
			}
		}
		if len(questionIDs) > 0 {
			tx.Where("id IN ?", questionIDs).Find(&questions)
		}
		questionMap := make(map[uint]Question, len(questions))
		for _, question := range questions {
			questionMap[question.ID] = question
		}
		for key, answer := range payload.PGAnswers {
			questionID, _ := strconv.ParseUint(key, 10, 64)
			question := questionMap[uint(questionID)]
			tx.Clauses(clause.OnConflict{
				Columns:   []clause.Column{{Name: "exam_result_id"}, {Name: "question_id"}},
				DoUpdates: clause.AssignmentColumns([]string{"student_answer", "correct_answer", "is_correct", "points", "updated_at"}),
			}).Create(&PgAnswer{
				ExamResultID:  result.ID,
				QuestionID:    uint(questionID),
				StudentAnswer: ptr(answer),
				CorrectAnswer: question.CorrectAnswer,
				IsCorrect:     question.CorrectAnswer != nil && answer == *question.CorrectAnswer,
				Points:        question.Points,
			})
		}
		for key, answer := range payload.Answers {
			questionID, _ := strconv.ParseUint(key, 10, 64)
			question := questionMap[uint(questionID)]
			tx.Clauses(clause.OnConflict{
				Columns:   []clause.Column{{Name: "exam_result_id"}, {Name: "question_id"}},
				DoUpdates: clause.AssignmentColumns([]string{"answer", "answer_value", "student_answer", "updated_at"}),
			}).Create(&StudentAnswer{
				ExamID:            examID,
				ExamResultID:      result.ID,
				UserID:            user.ID,
				QuestionID:        uint(questionID),
				QuestionPackageID: question.QuestionPackageID,
				QuestionType:      question.Type,
				Answer:            answer,
				AnswerValue:       answer,
				StudentAnswer:     answer,
				CorrectAnswer:     valueOrEmpty(question.EssayAnswer),
				MaxPoints:         question.Points,
			})
		}

		if err := tx.Save(result).Error; err != nil {
			return err
		}
		scoreData, err := s.calculateExamScore(tx, exam, result)
		if err != nil {
			return err
		}
		totalPossible := scoreData["total_score"].(int)
		percentage := 0.0
		if totalPossible > 0 {
			percentage = float64(scoreData["score"].(int)) / float64(totalPossible) * 100
		}
		isPassed := percentage >= float64(exam.PassingScore)
		cheatingNote := ""
		if len(payload.Violations) > 0 || payload.SubmitType != "" {
			raw, _ := json.Marshal(map[string]any{
				"violations":  payload.Violations,
				"submit_type": payload.SubmitType,
				"timestamp":   now.Format(time.RFC3339),
			})
			cheatingNote = string(raw)
		}
		timeTaken := 0
		if result.StartedAt != nil {
			timeTaken = int(now.Sub(*result.StartedAt).Minutes())
		}

		result.Status = "completed"
		result.CompletedAt = &now
		result.LastActivityAt = &now
		result.TimeTaken = timeTaken
		result.Score = scoreData["score"].(int)
		result.TotalScore = scoreData["total_score"].(int)
		result.CorrectAnswers = scoreData["correct_answers"].(int)
		result.WrongAnswers = scoreData["wrong_answers"].(int)
		result.PGScore = scoreData["pg_score"].(int)
		result.EssayScore = scoreData["essay_score"].(int)
		result.TotalPGPoints = scoreData["total_pg_points"].(int)
		result.TotalEssayPoints = scoreData["total_essay_points"].(int)
		result.EssayScores = upsertJSON(scoreData["essay_scores"])
		result.IsPassed = &isPassed
		if cheatingNote != "" {
			result.CheatingNote = &cheatingNote
		}
		if err := tx.Save(result).Error; err != nil {
			return err
		}

		response = map[string]any{
			"message":    "ujian berhasil diselesaikan",
			"result_id":  result.ID,
			"score":      result.Score,
			"is_passed":  isPassed,
			"time_taken": timeTaken,
		}
		return nil
	})
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}

	render.JSON(w, r, response)
}

func (s *Server) handleStudentExamTimeout(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, _ := pathUint(r, "id")
	now := time.Now()
	s.DB.Model(&ExamResult{}).
		Where("exam_id = ? AND user_id = ? AND status = ?", examID, user.ID, "in_progress").
		Updates(map[string]any{"status": "timeout", "completed_at": now, "last_activity_at": now})
	render.JSON(w, r, map[string]any{"message": "ujian diakhiri karena waktu habis"})
}

func (s *Server) handleStudentExamStatus(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	examID, _ := pathUint(r, "id")
	var exam Exam
	if err := s.DB.First(&exam, examID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "ujian tidak ditemukan"})
		return
	}
	var result ExamResult
	if err := s.DB.Where("exam_id = ? AND user_id = ? AND status IN ?", examID, user.ID, []string{"in_progress", "disconnected", "timeout", "completed"}).Order("created_at DESC").First(&result).Error; err != nil {
		render.JSON(w, r, map[string]any{"status": "not_started", "server_time": time.Now().Unix()})
		return
	}
	if result.Status == "timeout" || result.Status == "completed" {
		render.JSON(w, r, map[string]any{"status": result.Status, "server_time": time.Now().Unix(), "time_remaining": 0})
		return
	}
	if result.StartedAt == nil {
		render.JSON(w, r, map[string]any{"status": "not_started", "server_time": time.Now().Unix()})
		return
	}
	endTime := result.StartedAt.Add(time.Duration(exam.Duration) * time.Minute)
	remaining := int(time.Until(endTime).Seconds())
	if remaining <= 0 {
		now := time.Now()
		s.DB.Model(&result).Updates(map[string]any{"status": "timeout", "completed_at": now, "last_activity_at": now})
		render.JSON(w, r, map[string]any{"status": "timeout", "server_time": now.Unix(), "time_remaining": 0})
		return
	}
	render.JSON(w, r, map[string]any{"status": "in_progress", "server_time": time.Now().Unix(), "time_remaining": remaining, "exam_end_time": endTime.Unix()})
}

func (s *Server) handleServerTime(w http.ResponseWriter, r *http.Request) {
	now := time.Now()
	loc, _ := time.LoadLocation("Asia/Jakarta")
	wib := now.In(loc)
	render.JSON(w, r, map[string]any{
		"server_time":     now.Unix(),
		"server_time_iso": wib.Format(time.RFC3339),
		"timezone":        "Asia/Jakarta",
		"wib_timestamp":   wib.Unix(),
	})
}

func (s *Server) handleStudentResults(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []ExamResult
	s.DB.Where("user_id = ?", user.ID).Order("completed_at DESC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleStudentResult(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id result tidak valid"})
		return
	}
	var item ExamResult
	if err := s.DB.Where("user_id = ?", user.ID).First(&item, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "hasil ujian tidak ditemukan"})
		return
	}
	var answers []StudentAnswer
	s.DB.Where("exam_result_id = ?", item.ID).Find(&answers)
	render.JSON(w, r, map[string]any{"item": item, "answers": answers})
}

func (s *Server) handleAttendanceDays(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var days []SchoolAbsent
	s.DB.Where("school_id = ?", user.SchoolID).Order("date DESC").Find(&days)
	items := make([]map[string]any, 0, len(days))
	for _, day := range days {
		var present int64
		s.DB.Model(&UserAbsent{}).Where("school_id = ? AND date = ? AND status = ?", user.SchoolID, day.Date.Format("2006-01-02"), "hadir").Count(&present)
		items = append(items, map[string]any{
			"id":            day.ID,
			"date":          day.Date.Format("2006-01-02"),
			"present_count": present,
		})
	}
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleAttendanceByDate(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	dateText := chi.URLParam(r, "date")
	date, err := time.Parse("2006-01-02", dateText)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "format tanggal tidak valid"})
		return
	}
	var classes []ClassRoom
	s.DB.Where("school_id = ? AND is_active = ?", user.SchoolID, true).Order("name ASC").Find(&classes)
	items := make([]map[string]any, 0, len(classes))
	for _, class := range classes {
		var total, present int64
		s.DB.Model(&User{}).Where("school_id = ? AND role = ? AND class_id = ?", user.SchoolID, "student", class.ID).Count(&total)
		s.DB.Model(&UserAbsent{}).
			Joins("JOIN users ON users.id = user_absents.user_id").
			Where("user_absents.school_id = ? AND user_absents.date = ? AND users.class_id = ? AND user_absents.status = ?", user.SchoolID, date.Format("2006-01-02"), class.ID, "hadir").
			Count(&present)
		items = append(items, map[string]any{
			"class":          class,
			"total_students": total,
			"present_count":  present,
		})
	}
	render.JSON(w, r, map[string]any{"date": date.Format("2006-01-02"), "items": items})
}

func (s *Server) handleAttendanceByDateClass(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	dateText := chi.URLParam(r, "date")
	date, err := time.Parse("2006-01-02", dateText)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "format tanggal tidak valid"})
		return
	}
	classID, err := pathUint(r, "classId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "kelas tidak valid"})
		return
	}
	var students []User
	s.DB.Where("school_id = ? AND role = ? AND class_id = ?", user.SchoolID, "student", classID).Order("name ASC").Find(&students)
	var absents []UserAbsent
	s.DB.Where("school_id = ? AND date = ? AND user_id IN ?", user.SchoolID, date.Format("2006-01-02"), collectUserIDs(students)).Find(&absents)
	absentMap := make(map[uint]UserAbsent, len(absents))
	for _, item := range absents {
		absentMap[item.UserID] = item
	}
	items := make([]map[string]any, 0, len(students))
	for _, student := range students {
		status := "tidak_hadir"
		if absent, ok := absentMap[student.ID]; ok {
			status = absent.Status
		}
		items = append(items, map[string]any{
			"student": student,
			"status":  status,
			"detail":  absentMap[student.ID],
		})
	}
	render.JSON(w, r, map[string]any{"date": date.Format("2006-01-02"), "class_id": classID, "items": items})
}

func collectUserIDs(users []User) []uint {
	ids := make([]uint, 0, len(users))
	for _, user := range users {
		ids = append(ids, user.ID)
	}
	return ids
}

func (s *Server) handleAttendanceStudentDate(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	userID, err := pathUint(r, "userId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "user tidak valid"})
		return
	}
	dateText := chi.URLParam(r, "date")
	date, err := time.Parse("2006-01-02", dateText)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "format tanggal tidak valid"})
		return
	}
	var student User
	if err := s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "student").First(&student, userID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "siswa tidak ditemukan"})
		return
	}
	var detail UserAbsent
	err = s.DB.Where("school_id = ? AND user_id = ? AND date = ?", user.SchoolID, userID, date.Format("2006-01-02")).First(&detail).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal mengambil detail absensi"})
		return
	}
	render.JSON(w, r, map[string]any{"student": student, "date": date.Format("2006-01-02"), "detail": detail})
}

func (s *Server) handleAttendanceScan(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		QRCode string `json:"qr_code"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.QRCode == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "qr_code wajib"})
		return
	}
	var student User
	if err := s.DB.Where("school_id = ? AND role = ? AND qr = ?", user.SchoolID, "student", payload.QRCode).First(&student).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "QR Code tidak valid atau siswa tidak ditemukan"})
		return
	}
	now := time.Now()
	date := now.Format("2006-01-02")
	timeText := now.Format("15:04:05")
	record := UserAbsent{UserID: student.ID, SchoolID: user.SchoolID, Date: now, Time: &timeText, Status: "hadir"}
	s.DB.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "user_id"}, {Name: "date"}},
		DoUpdates: clause.Assignments(map[string]any{"status": "hadir", "end_time": timeText, "deleted_at": nil, "updated_at": now}),
	}).Create(&record)
	s.DB.Clauses(clause.OnConflict{DoNothing: true}).Create(&SchoolAbsent{SchoolID: user.SchoolID, Date: now})
	render.JSON(w, r, map[string]any{"message": fmt.Sprintf("%s telah hadir pada tanggal %s", student.Name, date), "user": student})
}

func (s *Server) handleAttendanceStatus(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	userID, err := pathUint(r, "userId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "user tidak valid"})
		return
	}
	dateText := chi.URLParam(r, "date")
	var payload struct {
		Status string `json:"status"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.Status == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "status wajib"})
		return
	}
	now := time.Now()
	timeText := now.Format("15:04:05")
	record := UserAbsent{UserID: userID, SchoolID: user.SchoolID, Date: now, Time: &timeText, Status: payload.Status}
	s.DB.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "user_id"}, {Name: "date"}},
		DoUpdates: clause.Assignments(map[string]any{"status": payload.Status, "deleted_at": nil, "updated_at": now}),
	}).Create(&record)
	s.DB.Clauses(clause.OnConflict{DoNothing: true}).Create(&SchoolAbsent{SchoolID: user.SchoolID, Date: now})
	render.JSON(w, r, map[string]any{"message": "status absensi diperbarui", "date": dateText})
}

func (s *Server) handleListTasks(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	query := s.DB.Where("school_id = ?", user.SchoolID)
	if user.Role == "tutor" {
		var classIDs []uint
		s.DB.Model(&TutorAssignment{}).Where("tutor_id = ?", user.ID).Distinct("class_id").Pluck("class_id", &classIDs)
		if len(classIDs) == 0 {
			render.JSON(w, r, map[string]any{"items": []SchoolTask{}})
			return
		}
		query = query.Where("class_id IN ?", classIDs)
	}
	var items []SchoolTask
	query.Order("created_at DESC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleCreateTask(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		ClassID     uint             `json:"class_id"`
		Title       string           `json:"title"`
		Description *string          `json:"description"`
		Files       []map[string]any `json:"files"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.ClassID == 0 || payload.Title == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "data tugas tidak valid"})
		return
	}
	item := SchoolTask{
		SchoolID:    user.SchoolID,
		ClassID:     payload.ClassID,
		Title:       payload.Title,
		Description: payload.Description,
		CreatedBy:   user.ID,
		Files:       upsertJSON(payload.Files),
	}
	s.DB.Create(&item)
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": item})
}

func (s *Server) handleGetTask(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tugas tidak valid"})
		return
	}
	var item SchoolTask
	if err := s.DB.Where("school_id = ?", user.SchoolID).First(&item, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "tugas tidak ditemukan"})
		return
	}
	var assignments []SchoolTaskAssignment
	var submissions []StudentSchoolTask
	s.DB.Where("school_task_id = ?", id).Find(&assignments)
	s.DB.Where("school_task_id = ?", id).Find(&submissions)
	render.JSON(w, r, map[string]any{"item": item, "assignments": assignments, "submissions": submissions})
}

func (s *Server) handleAssignTask(w http.ResponseWriter, r *http.Request) {
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tugas tidak valid"})
		return
	}
	var task SchoolTask
	if err := s.DB.First(&task, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "tugas tidak ditemukan"})
		return
	}
	var payload struct {
		AssignmentType string `json:"assignment_type"`
		UserIDs        []uint `json:"user_ids"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.AssignmentType == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	userIDs := payload.UserIDs
	if payload.AssignmentType == "class" {
		var students []User
		s.DB.Where("school_id = ? AND role = ? AND class_id = ?", task.SchoolID, "student", task.ClassID).Find(&students)
		userIDs = collectUserIDs(students)
	}
	for _, userID := range userIDs {
		item := SchoolTaskAssignment{
			SchoolTaskID:   task.ID,
			SchoolID:       task.SchoolID,
			ClassID:        task.ClassID,
			UserID:         ptr(userID),
			AssignmentType: payload.AssignmentType,
			IsActive:       true,
		}
		s.DB.Clauses(clause.OnConflict{DoNothing: true}).Create(&item)
	}
	render.JSON(w, r, map[string]any{"message": "assignment tugas diperbarui", "count": len(userIDs)})
}

func (s *Server) handleDeleteTaskAssignment(w http.ResponseWriter, r *http.Request) {
	assignmentID, err := pathUint(r, "assignmentId")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id assignment tidak valid"})
		return
	}
	s.DB.Delete(&SchoolTaskAssignment{}, assignmentID)
	render.JSON(w, r, map[string]any{"message": "assignment tugas dihapus"})
}

func (s *Server) handleTaskSubmissions(w http.ResponseWriter, r *http.Request) {
	taskID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tugas tidak valid"})
		return
	}
	var items []StudentSchoolTask
	s.DB.Where("school_task_id = ?", taskID).Order("updated_at DESC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleGradeTask(w http.ResponseWriter, r *http.Request) {
	taskID, _ := pathUint(r, "id")
	userID, _ := pathUint(r, "userId")
	var payload struct {
		Nilai int     `json:"nilai"`
		Note  *string `json:"note"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	var current StudentSchoolTask
	if err := s.DB.Where("school_task_id = ? AND user_id = ?", taskID, userID).Order("created_at DESC").First(&current).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "submission tidak ditemukan"})
		return
	}
	current.Nilai = &payload.Nilai
	current.Note = payload.Note
	s.DB.Save(&current)
	render.JSON(w, r, map[string]any{"message": "nilai tugas diperbarui"})
}

func (s *Server) handleDeleteTask(w http.ResponseWriter, r *http.Request) {
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tugas tidak valid"})
		return
	}
	s.DB.Delete(&SchoolTask{}, id)
	render.JSON(w, r, map[string]any{"message": "tugas dihapus"})
}

func (s *Server) handleStudentTasks(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var assignments []SchoolTaskAssignment
	s.DB.Where("user_id = ? AND is_active = ?", user.ID, true).Find(&assignments)
	var taskIDs []uint
	for _, item := range assignments {
		taskIDs = append(taskIDs, item.SchoolTaskID)
	}
	var tasks []SchoolTask
	if len(taskIDs) > 0 {
		s.DB.Where("id IN ?", taskIDs).Order("created_at DESC").Find(&tasks)
	}
	render.JSON(w, r, map[string]any{"assignments": assignments, "items": tasks})
}

func (s *Server) handleStudentTask(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tugas tidak valid"})
		return
	}
	var task SchoolTask
	if err := s.DB.First(&task, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "tugas tidak ditemukan"})
		return
	}
	var assignment SchoolTaskAssignment
	if err := s.DB.Where("school_task_id = ? AND user_id = ? AND is_active = ?", id, user.ID, true).First(&assignment).Error; err != nil {
		render.Status(r, http.StatusForbidden)
		render.JSON(w, r, map[string]any{"message": "tugas tidak diassign"})
		return
	}
	var submission StudentSchoolTask
	_ = s.DB.Where("school_task_id = ? AND user_id = ?", id, user.ID).Order("created_at DESC").First(&submission).Error
	render.JSON(w, r, map[string]any{"item": task, "assignment": assignment, "submission": submission})
}

func (s *Server) handleStudentTaskSubmit(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	taskID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tugas tidak valid"})
		return
	}
	var payload struct {
		Text  *string          `json:"text"`
		Files []map[string]any `json:"files"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	var task SchoolTask
	if err := s.DB.First(&task, taskID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "tugas tidak ditemukan"})
		return
	}
	var assignment SchoolTaskAssignment
	if err := s.DB.Where("school_task_id = ? AND user_id = ? AND is_active = ?", taskID, user.ID, true).First(&assignment).Error; err != nil {
		render.Status(r, http.StatusForbidden)
		render.JSON(w, r, map[string]any{"message": "tugas tidak diassign"})
		return
	}
	var existing StudentSchoolTask
	if err := s.DB.Where("school_task_id = ? AND user_id = ?", taskID, user.ID).Order("created_at DESC").First(&existing).Error; err == nil {
		s.DB.Delete(&existing)
	}
	item := StudentSchoolTask{
		UserID:       user.ID,
		SchoolID:     user.SchoolID,
		ClassID:      task.ClassID,
		SchoolTaskID: taskID,
		Text:         payload.Text,
		Files:        upsertJSON(payload.Files),
	}
	s.DB.Create(&item)
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"message": "tugas berhasil dikumpulkan", "item": item})
}

func (s *Server) handleSchedulerStatus(w http.ResponseWriter, r *http.Request) {
	render.JSON(w, r, map[string]any{
		"jobs": []map[string]any{
			{"name": "ai:score-essays", "schedule": "* * * * *"},
			{"name": "exams:cleanup-expired", "schedule": "*/5 * * * *"},
			{"name": "double-checker:run", "schedule": "* * * * *"},
			{"name": "exam-results:mark-completed", "schedule": "* * * * *"},
			{"name": "exam-results:mark-disconnected-inactive", "schedule": "* * * * *"},
			{"name": "exam-results:complete-ended", "schedule": "*/10 * * * *"},
			{"name": "exam-results:reset-double-checker-no-pg", "schedule": "* * * * *"},
			{"name": "users:generate-qr", "schedule": "0 1 * * *"},
			{"name": "users:generate-referral-tokens", "schedule": "0 1 * * *"},
			{"name": "schools:cap-concurrent-expired", "schedule": "0 1 * * *"},
			{"name": "schools:sync-concurrent-when-active", "schedule": "0 1 * * *"},
			{"name": "semester:sync", "schedule": "0 1 1 1 *"},
			{"name": "sitemap:generate", "schedule": "15 2 * * *"},
		},
	})
}

func (s *Server) handleRunAIScoring(w http.ResponseWriter, r *http.Request) {
	processed, err := s.runAIScoring()
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	render.JSON(w, r, map[string]any{"processed": processed})
}

func (s *Server) handleRunDoubleChecker(w http.ResponseWriter, r *http.Request) {
	processed, err := s.runDoubleChecker()
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	render.JSON(w, r, map[string]any{"processed": processed})
}

func (s *Server) handleSyncSemesters(w http.ResponseWriter, r *http.Request) {
	baseYear := time.Now().Year()
	var semesters = []Semester{
		{Type: "ganjil", AcademicYear: fmt.Sprintf("%d/%d", baseYear, baseYear+1), StartDate: time.Date(baseYear, 7, 1, 0, 0, 0, 0, time.UTC), EndDate: time.Date(baseYear, 12, 31, 0, 0, 0, 0, time.UTC)},
		{Type: "genap", AcademicYear: fmt.Sprintf("%d/%d", baseYear, baseYear+1), StartDate: time.Date(baseYear+1, 1, 1, 0, 0, 0, 0, time.UTC), EndDate: time.Date(baseYear+1, 6, 30, 0, 0, 0, 0, time.UTC)},
	}
	for _, semester := range semesters {
		s.DB.Where(Semester{Type: semester.Type, AcademicYear: semester.AcademicYear}).Assign(semester).FirstOrCreate(&semester)
	}
	render.JSON(w, r, map[string]any{"message": "semester tersinkronisasi", "year": baseYear})
}

func (s *Server) handleRunRecovery(w http.ResponseWriter, r *http.Request) {
	if err := s.runExamRecovery(); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	render.JSON(w, r, map[string]any{"message": "recovery selesai"})
}

func (s *Server) handleResetDoubleCheckerFlags(w http.ResponseWriter, r *http.Request) {
	result := s.DB.Model(&ExamResult{}).Where("is_double_checker_running <> 0").Update("is_double_checker_running", 0)
	if result.Error != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": result.Error.Error()})
		return
	}
	render.JSON(w, r, map[string]any{"message": "flag double checker direset", "updated": result.RowsAffected})
}

func (s *Server) handleRecoveryStatus(w http.ResponseWriter, r *http.Request) {
	var disconnected, recoverable int64
	s.DB.Model(&ExamResult{}).Where("status = ?", "disconnected").Count(&disconnected)
	s.DB.Model(&ExamResult{}).Where("status = ? AND answers IS NOT NULL", "disconnected").Count(&recoverable)
	render.JSON(w, r, map[string]any{"disconnected": disconnected, "recoverable": recoverable})
}

func (s *Server) handleResetRecoveryFlags(w http.ResponseWriter, r *http.Request) {
	result := s.DB.Model(&ExamResult{}).
		Where("status = ? AND is_double_checker_running <> 0", "disconnected").
		Update("is_double_checker_running", 0)
	if result.Error != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": result.Error.Error()})
		return
	}
	render.JSON(w, r, map[string]any{"message": "flag recovery direset", "updated": result.RowsAffected})
}

func (s *Server) handleValidateEssayScoresConsistency(w http.ResponseWriter, r *http.Request) {
	var inconsistent int64
	s.DB.Model(&ExamResult{}).
		Where("essay_scores IS NOT NULL AND (total_essay_points IS NULL OR total_essay_points = 0)").
		Count(&inconsistent)
	render.JSON(w, r, map[string]any{"message": "validasi selesai", "inconsistent": inconsistent})
}

func (s *Server) handleRecalculateTotalScore(w http.ResponseWriter, r *http.Request) {
	processed, err := s.runDoubleChecker()
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	render.JSON(w, r, map[string]any{"message": "recalculate total score selesai", "processed": processed})
}
