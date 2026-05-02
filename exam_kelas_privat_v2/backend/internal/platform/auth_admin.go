package platform

import (
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/render"
	"github.com/google/uuid"
	"github.com/xuri/excelize/v2"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type registerRequest struct {
	Name                 string `json:"name"`
	Email                string `json:"email"`
	Phone                string `json:"phone"`
	Password             string `json:"password"`
	PasswordConfirmation string `json:"password_confirmation"`
	SchoolName           string `json:"school_name"`
	TotalSiswa           int    `json:"total_siswa"`
	ReferralCode         string `json:"referral_code"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := parseJSONBody(r, &req); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}

	var user User
	if err := s.DB.Preload("School").Where("LOWER(email) = ?", strings.ToLower(req.Email)).First(&user).Error; err != nil {
		render.Status(r, http.StatusUnauthorized)
		render.JSON(w, r, map[string]any{"message": "email atau password salah"})
		return
	}
	if err := comparePassword(user.Password, req.Password); err != nil {
		render.Status(r, http.StatusUnauthorized)
		render.JSON(w, r, map[string]any{"message": "email atau password salah"})
		return
	}

	token, err := s.issueToken(user)
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal membuat token"})
		return
	}

	render.JSON(w, r, map[string]any{
		"token":         token,
		"user":          user,
		"school_active": s.isSchoolActive(&user.School),
		"home":          s.roleHome(user.Role),
	})
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := parseJSONBody(r, &req); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	if req.Name == "" || req.Email == "" || req.Phone == "" || req.Password == "" || req.SchoolName == "" || req.TotalSiswa < 1 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "field wajib belum lengkap"})
		return
	}
	if req.Password != req.PasswordConfirmation {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "konfirmasi password tidak cocok"})
		return
	}

	var existing int64
	s.DB.Model(&User{}).Where("LOWER(email) = ?", strings.ToLower(req.Email)).Count(&existing)
	if existing > 0 {
		render.Status(r, http.StatusConflict)
		render.JSON(w, r, map[string]any{"message": "email sudah terdaftar"})
		return
	}

	hashed, err := hashPassword(req.Password)
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memproses password"})
		return
	}

	var createdUser User
	err = s.withTx(func(tx *gorm.DB) error {
		school := School{
			Name:             req.SchoolName,
			MaxUser:          req.TotalSiswa,
			TotalUser:        0,
			MaxConcurentExam: req.TotalSiswa,
		}

		if strings.TrimSpace(req.ReferralCode) != "" {
			var referrer User
			if err := tx.Where("referral_token = ?", strings.TrimSpace(req.ReferralCode)).First(&referrer).Error; err != nil {
				return errors.New("kode referral tidak valid")
			}
			activeUntil := time.Now().AddDate(0, 1, 0)
			school.ActiveUntil = &activeUntil
		}

		if err := tx.Create(&school).Error; err != nil {
			return err
		}

		token := s.randomToken("usr")
		referralToken := strings.ToUpper(strings.ReplaceAll(uuid.NewString(), "-", ""))[:16]
		createdUser = User{
			Name:          req.Name,
			Email:         strings.ToLower(req.Email),
			Phone:         ptr(req.Phone),
			Password:      hashed,
			SchoolID:      school.ID,
			Role:          "admin",
			IsAdmin:       true,
			Token:         &token,
			ReferralToken: &referralToken,
		}
		if err := tx.Create(&createdUser).Error; err != nil {
			return err
		}

		if strings.TrimSpace(req.ReferralCode) != "" {
			var referrer User
			if err := tx.Where("referral_token = ?", strings.TrimSpace(req.ReferralCode)).First(&referrer).Error; err != nil {
				return err
			}
			now := time.Now()
			ref := Referral{
				UserID:            referrer.ID,
				UserContributorID: createdUser.ID,
				SchoolID:          school.ID,
				Status:            "registered",
				ReferredAt:        &now,
			}
			if err := tx.Create(&ref).Error; err != nil {
				return err
			}
			referenceKey := fmt.Sprintf("referral_signup_%d_%d", createdUser.ID, school.ID)
			tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&UserCreditTransaction{
				UserID:       referrer.ID,
				Amount:       200,
				Type:         "referral_signup_bonus",
				ReferenceKey: &referenceKey,
				Meta:         upsertJSON(map[string]any{"school_id": school.ID, "school_name": school.Name, "user_contributor_id": createdUser.ID}),
			})
			tx.Model(&User{}).Where("id = ?", referrer.ID).UpdateColumn("credit_balance", gorm.Expr("credit_balance + ?", 200))
		}

		return nil
	})
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}

	token, _ := s.issueToken(createdUser)
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{
		"token":         token,
		"user":          createdUser,
		"school_active": strings.TrimSpace(req.ReferralCode) != "",
		"home":          "/admin/dashboard",
	})
}

func (s *Server) handleForgotPassword(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Email string `json:"email"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.Email == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "email wajib diisi"})
		return
	}

	token := s.randomToken("reset")
	record := PasswordReset{
		Email:     strings.ToLower(payload.Email),
		Token:     token,
		CreatedAt: time.Now(),
	}
	s.DB.Clauses(clause.OnConflict{UpdateAll: true}).Create(&record)
	response := map[string]any{"message": "jika email terdaftar, link reset password akan dikirim"}
	if err := s.sendPasswordResetEmail(record.Email, token); err != nil {
		response["mail_status"] = err.Error()
		if s.Config.EmailDebugToken {
			response["reset_token"] = token
		}
	} else {
		response["mail_status"] = "sent"
	}
	render.JSON(w, r, response)
}

func (s *Server) handleResetPassword(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Token                string `json:"token"`
		Email                string `json:"email"`
		Password             string `json:"password"`
		PasswordConfirmation string `json:"password_confirmation"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	if payload.Password == "" || payload.Password != payload.PasswordConfirmation {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "password tidak valid"})
		return
	}

	var reset PasswordReset
	if err := s.DB.Where("email = ? AND token = ?", strings.ToLower(payload.Email), payload.Token).First(&reset).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "token reset tidak ditemukan"})
		return
	}

	hashed, _ := hashPassword(payload.Password)
	s.DB.Model(&User{}).Where("LOWER(email) = ?", strings.ToLower(payload.Email)).Update("password", hashed)
	s.DB.Delete(&reset)
	render.JSON(w, r, map[string]any{"message": "password berhasil diubah"})
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	render.JSON(w, r, map[string]any{"user": s.currentUser(r)})
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	render.JSON(w, r, map[string]any{"message": "logout berhasil"})
}

func (s *Server) handleCurrentAd(w http.ResponseWriter, r *http.Request) {
	var ad Ad
	if err := s.DB.Where("is_active = ?", true).Order("updated_at DESC").First(&ad).Error; err != nil {
		render.JSON(w, r, map[string]any{"item": nil})
		return
	}
	render.JSON(w, r, map[string]any{"item": ad})
}

func (s *Server) handleLandingStats(w http.ResponseWriter, r *http.Request) {
	var schools, exams, questions, examResults int64
	s.DB.Model(&School{}).Count(&schools)
	s.DB.Model(&Exam{}).Count(&exams)
	s.DB.Model(&Question{}).Count(&questions)
	s.DB.Model(&ExamResult{}).Count(&examResults)
	render.JSON(w, r, map[string]any{
		"schools":      schools,
		"exams":        exams,
		"questions":    questions,
		"exam_results": examResults,
	})
}

func (s *Server) handleContactDemo(w http.ResponseWriter, r *http.Request) {
	var payload ContactDemoRequest
	if err := parseJSONBody(r, &payload); err != nil || payload.Name == "" || payload.Email == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "nama dan email wajib"})
		return
	}
	s.DB.Create(&payload)
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"message": "permintaan berhasil dikirim"})
}

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	response := map[string]any{"user": user}

	switch user.Role {
	case "admin", "tutor":
		var students, classes, subjects, exams, results, tasks int64
		var draftExams, publishedExams, cancelledExams, packages, questions, tutorAccounts int64
		s.DB.Model(&User{}).Where("school_id = ? AND role = ?", user.SchoolID, "student").Count(&students)
		s.DB.Model(&ClassRoom{}).Where("school_id = ? AND is_active = ?", user.SchoolID, true).Count(&classes)
		s.DB.Model(&Subject{}).Where("school_id = ? AND is_active = ?", user.SchoolID, true).Count(&subjects)
		s.DB.Model(&Exam{}).Where("school_id = ?", user.SchoolID).Count(&exams)
		s.DB.Model(&ExamResult{}).Joins("JOIN exams ON exams.id = exam_results.exam_id").Where("exams.school_id = ?", user.SchoolID).Count(&results)
		s.DB.Model(&SchoolTask{}).Where("school_id = ?", user.SchoolID).Count(&tasks)
		s.DB.Model(&Exam{}).Where("school_id = ? AND status = ?", user.SchoolID, "draft").Count(&draftExams)
		s.DB.Model(&Exam{}).Where("school_id = ? AND status = ?", user.SchoolID, "published").Count(&publishedExams)
		s.DB.Model(&Exam{}).Where("school_id = ? AND status = ?", user.SchoolID, "cancelled").Count(&cancelledExams)
		s.DB.Model(&QuestionPackage{}).Where("school_id = ?", user.SchoolID).Count(&packages)
		s.DB.Model(&Question{}).Where("school_id = ?", user.SchoolID).Count(&questions)
		s.DB.Model(&User{}).Where("school_id = ? AND role = ?", user.SchoolID, "tutor").Count(&tutorAccounts)
		response["stats"] = map[string]any{
			"students":          students,
			"classes":           classes,
			"subjects":          subjects,
			"exams":             exams,
			"draft_exams":       draftExams,
			"published_exams":   publishedExams,
			"cancelled_exams":   cancelledExams,
			"question_packages": packages,
			"questions":         questions,
			"tutor_accounts":    tutorAccounts,
			"results":           results,
			"tasks":             tasks,
		}
		if user.Role == "tutor" {
			var tutorSlots int64
			s.DB.Model(&TutorAssignment{}).Where("tutor_id = ?", user.ID).Count(&tutorSlots)
			response["tutor"] = map[string]any{
				"assignments": tutorSlots,
			}
		}
		response["trends"] = map[string]any{
			"exam_results_7d": s.dashboardExamResultTrend(user, false),
		}
	default:
		var assignments, results, activeTasks, publishedAssigned, completedExams, submittedTasks, gradedTasks, publishedRaports int64
		s.DB.Model(&ExamAssignment{}).Where("user_id = ?", user.ID).Count(&assignments)
		s.DB.Model(&ExamResult{}).Where("user_id = ?", user.ID).Count(&results)
		s.DB.Model(&SchoolTaskAssignment{}).Where("user_id = ? AND is_active = ?", user.ID, true).Count(&activeTasks)
		s.DB.Model(&StudentSchoolTask{}).Where("user_id = ?", user.ID).Count(&submittedTasks)
		s.DB.Model(&StudentSchoolTask{}).Where("user_id = ? AND nilai IS NOT NULL", user.ID).Count(&gradedTasks)
		s.DB.Model(&Raport{}).Where("user_id = ? AND status = ?", user.ID, "published").Count(&publishedRaports)
		s.DB.Model(&Exam{}).
			Joins("JOIN exam_assignments ON exam_assignments.exam_id = exams.id").
			Where("exam_assignments.user_id = ? AND exams.status = ?", user.ID, "published").
			Count(&publishedAssigned)
		s.DB.Model(&ExamResult{}).Where("user_id = ? AND status = ?", user.ID, "completed").Count(&completedExams)
		response["stats"] = map[string]any{
			"assignments":     assignments,
			"published_exams": publishedAssigned,
			"results":         results,
			"completed_exams": completedExams,
			"tasks":           activeTasks,
			"submitted_tasks": submittedTasks,
			"graded_tasks":    gradedTasks,
			"raports":         publishedRaports,
		}
		response["trends"] = map[string]any{
			"exam_results_7d": s.dashboardExamResultTrend(user, true),
		}
	}

	render.JSON(w, r, response)
}

func (s *Server) dashboardExamResultTrend(user *User, studentOnly bool) []map[string]any {
	start := time.Now().AddDate(0, 0, -6)
	var rows []ExamResult
	query := s.DB.Model(&ExamResult{}).
		Joins("JOIN exams ON exams.id = exam_results.exam_id").
		Where("exams.school_id = ? AND exam_results.created_at >= ?", user.SchoolID, time.Date(start.Year(), start.Month(), start.Day(), 0, 0, 0, 0, start.Location()))
	if studentOnly {
		query = query.Where("exam_results.user_id = ?", user.ID)
	}
	query.Find(&rows)
	counts := map[string]int{}
	for _, row := range rows {
		key := row.CreatedAt.Format("2006-01-02")
		counts[key]++
	}
	out := make([]map[string]any, 0, 7)
	for i := 0; i < 7; i++ {
		day := start.AddDate(0, 0, i)
		key := day.Format("2006-01-02")
		out = append(out, map[string]any{
			"date":  key,
			"label": day.Format("02 Jan"),
			"count": counts[key],
		})
	}
	return out
}

func (s *Server) handleProfile(w http.ResponseWriter, r *http.Request) {
	render.JSON(w, r, map[string]any{"user": s.currentUser(r)})
}

func (s *Server) handleUpdateProfile(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		Name      string  `json:"name"`
		Email     string  `json:"email"`
		Phone     *string `json:"phone"`
		Address   *string `json:"address"`
		Gender    *string `json:"gender"`
		ClassID   *uint   `json:"class_id"`
		BirthDate *string `json:"birth_date"`
	}
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}

	updates := map[string]any{
		"name":     payload.Name,
		"email":    strings.ToLower(payload.Email),
		"phone":    payload.Phone,
		"address":  payload.Address,
		"gender":   payload.Gender,
		"class_id": payload.ClassID,
	}
	if payload.BirthDate != nil && *payload.BirthDate != "" {
		if t, err := time.Parse("2006-01-02", *payload.BirthDate); err == nil {
			updates["birth_date"] = t
		}
	}
	if err := s.DB.Model(&User{}).Where("id = ?", user.ID).Updates(updates).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui profil"})
		return
	}
	s.DB.Preload("School").Preload("ClassRoom").First(user, user.ID)
	render.JSON(w, r, map[string]any{"message": "profil berhasil diperbarui", "user": user})
}

func (s *Server) handleUpdatePassword(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.NewPassword == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	if err := comparePassword(user.Password, payload.CurrentPassword); err != nil {
		render.Status(r, http.StatusUnauthorized)
		render.JSON(w, r, map[string]any{"message": "password lama salah"})
		return
	}
	hashed, _ := hashPassword(payload.NewPassword)
	s.DB.Model(&User{}).Where("id = ?", user.ID).Update("password", hashed)
	render.JSON(w, r, map[string]any{"message": "password berhasil diperbarui"})
}

func (s *Server) handleUpdateAvatar(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		Avatar string `json:"avatar"`
	}
	if err := parseJSONBody(r, &payload); err != nil || strings.TrimSpace(payload.Avatar) == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "avatar wajib diisi"})
		return
	}
	avatar := strings.TrimSpace(payload.Avatar)
	if err := s.DB.Model(&User{}).Where("id = ?", user.ID).Update("avatar", avatar).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui avatar"})
		return
	}
	user.Avatar = &avatar
	render.JSON(w, r, map[string]any{"message": "avatar berhasil diperbarui", "user": user})
}

func (s *Server) handleSchool(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var school School
	if err := s.DB.First(&school, user.SchoolID).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "sekolah tidak ditemukan"})
		return
	}
	render.JSON(w, r, map[string]any{"school": school})
}

func (s *Server) handleUpdateSchool(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload map[string]any
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	if err := s.DB.Model(&School{}).Where("id = ?", user.SchoolID).Updates(payload).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui sekolah"})
		return
	}
	s.handleSchool(w, r)
}

func (s *Server) handleListStudents(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	query := s.DB.Model(&User{}).Where("school_id = ? AND role = ?", user.SchoolID, "student")
	if search := strings.TrimSpace(r.URL.Query().Get("search")); search != "" {
		query = query.Where("name LIKE ? OR email LIKE ?", "%"+search+"%", "%"+search+"%")
	}
	if classID := r.URL.Query().Get("class_id"); classID != "" {
		query = query.Where("class_id = ?", classID)
	}
	var students []User
	query.Order("created_at DESC").Find(&students)
	render.JSON(w, r, map[string]any{"items": students})
}

func (s *Server) handleCreateStudent(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		Name     string  `json:"name"`
		Email    string  `json:"email"`
		Password string  `json:"password"`
		ClassID  *uint   `json:"class_id"`
		Gender   *string `json:"gender"`
		Phone    *string `json:"phone"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.Name == "" || payload.Email == "" || payload.Password == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "data siswa tidak lengkap"})
		return
	}
	hashed, _ := hashPassword(payload.Password)
	token := s.randomToken("usr")
	referralToken := strings.ToUpper(strings.ReplaceAll(uuid.NewString(), "-", ""))[:16]
	student := User{
		Name:          payload.Name,
		Email:         strings.ToLower(payload.Email),
		Password:      hashed,
		SchoolID:      user.SchoolID,
		Role:          "student",
		ClassID:       payload.ClassID,
		Gender:        payload.Gender,
		Phone:         payload.Phone,
		Token:         &token,
		ReferralToken: &referralToken,
	}
	if err := s.withTx(func(tx *gorm.DB) error {
		var school School
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&school, user.SchoolID).Error; err != nil {
			return err
		}
		if school.TotalUser >= school.MaxUser {
			return errors.New("kapasitas siswa sekolah sudah penuh")
		}
		if err := tx.Create(&student).Error; err != nil {
			return err
		}
		return tx.Model(&school).UpdateColumn("total_user", gorm.Expr("total_user + ?", 1)).Error
	}); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": student})
}

func (s *Server) handleUpdateStudent(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var student User
	if err := s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "student").First(&student, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "siswa tidak ditemukan"})
		return
	}
	var payload map[string]any
	if err := parseJSONBody(r, &payload); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload tidak valid"})
		return
	}
	delete(payload, "school_id")
	delete(payload, "role")
	if password, ok := payload["password"].(string); ok && password != "" {
		hashed, _ := hashPassword(password)
		payload["password"] = hashed
	} else {
		delete(payload, "password")
	}
	s.DB.Model(&student).Updates(payload)
	render.JSON(w, r, map[string]any{"item": student})
}

func (s *Server) handleDeleteStudent(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var student User
	if err := s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "student").First(&student, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "siswa tidak ditemukan"})
		return
	}

	_ = s.withTx(func(tx *gorm.DB) error {
		suffix := fmt.Sprintf("_deleted_%d", time.Now().Unix())
		updates := map[string]any{"name": student.Name + suffix}
		if student.Email != "" {
			updates["email"] = student.Email + suffix
		}
		if student.Phone != nil && *student.Phone != "" {
			updates["phone"] = *student.Phone + suffix
		}
		if err := tx.Model(&student).Updates(updates).Error; err != nil {
			return err
		}
		if err := tx.Delete(&student).Error; err != nil {
			return err
		}
		return tx.Model(&School{}).Where("id = ? AND total_user > 0", user.SchoolID).UpdateColumn("total_user", gorm.Expr("total_user - ?", 1)).Error
	})
	render.JSON(w, r, map[string]any{"message": "siswa berhasil dihapus"})
}

func writeExcelWorkbook(w http.ResponseWriter, filename string, book *excelize.File) error {
	w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filename))
	return book.Write(w)
}

func (s *Server) handleDownloadStudentImportTemplate(w http.ResponseWriter, r *http.Request) {
	book := excelize.NewFile()
	sheet := book.GetSheetName(0)
	headers := []string{"name", "email", "gender", "password"}
	samples := [][]string{
		{"Budi Santoso", "budi@example.com", "L", "password123"},
		{"Cinta Santoso", "cinta@example.com", "P", "password123"},
	}
	for idx, header := range headers {
		cell, _ := excelize.CoordinatesToCellName(idx+1, 1)
		book.SetCellValue(sheet, cell, header)
	}
	for rowIdx, row := range samples {
		for colIdx, value := range row {
			cell, _ := excelize.CoordinatesToCellName(colIdx+1, rowIdx+2)
			book.SetCellValue(sheet, cell, value)
		}
	}
	if err := writeExcelWorkbook(w, "template-import-siswa.xlsx", book); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal membuat template import siswa"})
	}
}

func (s *Server) handleImportStudents(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "gagal membaca form upload"})
		return
	}
	classID, _ := strconv.ParseUint(r.FormValue("class_id"), 10, 64)
	file, _, err := r.FormFile("file")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "file wajib diisi"})
		return
	}
	defer file.Close()

	book, err := excelize.OpenReader(file)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "file excel tidak valid"})
		return
	}
	sheet := book.GetSheetName(0)
	rows, err := book.GetRows(sheet)
	if err != nil || len(rows) < 2 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "baris data tidak ditemukan"})
		return
	}

	success, failed := 0, 0
	failures := make([]map[string]any, 0)
	for idx, row := range rows[1:] {
		if len(row) < 4 {
			failed++
			failures = append(failures, map[string]any{"row": idx + 2, "reason": "kolom minimal name,email,gender,password"})
			continue
		}
		payload := struct {
			Name     string
			Email    string
			Gender   string
			Password string
		}{
			Name:     strings.TrimSpace(row[0]),
			Email:    strings.TrimSpace(row[1]),
			Gender:   strings.TrimSpace(row[2]),
			Password: strings.TrimSpace(row[3]),
		}
		if payload.Name == "" || payload.Email == "" || payload.Password == "" {
			failed++
			failures = append(failures, map[string]any{"row": idx + 2, "reason": "field wajib kosong"})
			continue
		}
		hashed, _ := hashPassword(payload.Password)
		token := s.randomToken("usr")
		referralToken := strings.ToUpper(strings.ReplaceAll(uuid.NewString(), "-", ""))[:16]
		student := User{
			Name:          payload.Name,
			Email:         strings.ToLower(payload.Email),
			Password:      hashed,
			SchoolID:      user.SchoolID,
			Role:          "student",
			ClassID:       ptr(uint(classID)),
			Gender:        ptr(strings.ToLower(payload.Gender)),
			Token:         &token,
			ReferralToken: &referralToken,
		}
		if err := s.DB.Create(&student).Error; err != nil {
			failed++
			failures = append(failures, map[string]any{"row": idx + 2, "reason": err.Error(), "email": payload.Email})
			continue
		}
		s.DB.Model(&School{}).Where("id = ?", user.SchoolID).UpdateColumn("total_user", gorm.Expr("total_user + ?", 1))
		success++
	}
	render.JSON(w, r, map[string]any{"success": success, "failed": failed, "failures": failures})
}

func (s *Server) handleDownloadBulkPasswordTemplate(w http.ResponseWriter, r *http.Request) {
	book := excelize.NewFile()
	sheet := book.GetSheetName(0)
	headers := []string{"email", "new_password"}
	samples := [][]string{{"siswa@example.com", "PasswordBaru123"}}
	for idx, header := range headers {
		cell, _ := excelize.CoordinatesToCellName(idx+1, 1)
		book.SetCellValue(sheet, cell, header)
	}
	for rowIdx, row := range samples {
		for colIdx, value := range row {
			cell, _ := excelize.CoordinatesToCellName(colIdx+1, rowIdx+2)
			book.SetCellValue(sheet, cell, value)
		}
	}
	if err := writeExcelWorkbook(w, "template-bulk-password-siswa.xlsx", book); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal membuat template bulk password"})
	}
}

func (s *Server) handleBulkPassword(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	if strings.Contains(r.Header.Get("Content-Type"), "multipart/form-data") {
		if err := r.ParseMultipartForm(32 << 20); err != nil {
			render.Status(r, http.StatusBadRequest)
			render.JSON(w, r, map[string]any{"message": "gagal membaca form upload"})
			return
		}
		file, _, err := r.FormFile("file")
		if err != nil {
			render.Status(r, http.StatusBadRequest)
			render.JSON(w, r, map[string]any{"message": "file wajib diisi"})
			return
		}
		defer file.Close()
		book, err := excelize.OpenReader(file)
		if err != nil {
			render.Status(r, http.StatusBadRequest)
			render.JSON(w, r, map[string]any{"message": "file excel tidak valid"})
			return
		}
		sheet := book.GetSheetName(0)
		rows, err := book.GetRows(sheet)
		if err != nil || len(rows) < 2 {
			render.Status(r, http.StatusBadRequest)
			render.JSON(w, r, map[string]any{"message": "baris data tidak ditemukan"})
			return
		}

		updated, failed := 0, 0
		failures := make([]map[string]any, 0)
		for idx, row := range rows[1:] {
			if len(row) < 2 {
				failed++
				failures = append(failures, map[string]any{"row": idx + 2, "reason": "kolom minimal email,new_password"})
				continue
			}
			email := strings.TrimSpace(row[0])
			newPassword := strings.TrimSpace(row[1])
			if email == "" || newPassword == "" {
				failed++
				failures = append(failures, map[string]any{"row": idx + 2, "email": email, "reason": "field wajib kosong"})
				continue
			}
			hash, _ := hashPassword(newPassword)
			result := s.DB.Model(&User{}).
				Where("school_id = ? AND role = ? AND LOWER(email) = ?", user.SchoolID, "student", strings.ToLower(email)).
				Update("password", hash)
			if result.RowsAffected == 0 {
				failed++
				failures = append(failures, map[string]any{"row": idx + 2, "email": email, "reason": "email siswa tidak ditemukan"})
				continue
			}
			updated++
		}
		render.JSON(w, r, map[string]any{"updated": updated, "failed": failed, "failures": failures})
		return
	}

	var payload struct {
		Items []struct {
			Email       string `json:"email"`
			NewPassword string `json:"new_password"`
		} `json:"items"`
	}
	if err := parseJSONBody(r, &payload); err != nil || len(payload.Items) == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "items wajib diisi"})
		return
	}
	updated := 0
	for _, item := range payload.Items {
		if item.Email == "" || item.NewPassword == "" {
			continue
		}
		hash, _ := hashPassword(item.NewPassword)
		result := s.DB.Model(&User{}).
			Where("school_id = ? AND role = ? AND LOWER(email) = ?", user.SchoolID, "student", strings.ToLower(item.Email)).
			Update("password", hash)
		if result.RowsAffected > 0 {
			updated++
		}
	}
	render.JSON(w, r, map[string]any{"updated": updated})
}

func (s *Server) handleListClasses(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var classes []ClassRoom
	s.DB.Where("school_id = ?", user.SchoolID).Order("name ASC").Find(&classes)
	render.JSON(w, r, map[string]any{"items": classes})
}

func (s *Server) handleTutorMyClasses(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var assignments []TutorAssignment
	s.DB.Where("school_id = ? AND tutor_id = ?", user.SchoolID, user.ID).Find(&assignments)
	if len(assignments) == 0 {
		render.JSON(w, r, map[string]any{"items": []map[string]any{}})
		return
	}
	classIDs := make([]uint, 0, len(assignments))
	seen := make(map[uint]struct{}, len(assignments))
	for _, item := range assignments {
		if _, ok := seen[item.ClassID]; ok {
			continue
		}
		seen[item.ClassID] = struct{}{}
		classIDs = append(classIDs, item.ClassID)
	}
	var classes []ClassRoom
	s.DB.Where("school_id = ? AND id IN ?", user.SchoolID, classIDs).Order("name ASC").Find(&classes)
	items := make([]map[string]any, 0, len(classes))
	for _, classItem := range classes {
		var totalStudents int64
		var totalSubjects int64
		s.DB.Model(&User{}).Where("school_id = ? AND role = ? AND class_id = ?", user.SchoolID, "student", classItem.ID).Count(&totalStudents)
		s.DB.Model(&TutorAssignment{}).Where("school_id = ? AND tutor_id = ? AND class_id = ?", user.SchoolID, user.ID, classItem.ID).Distinct("subject_id").Count(&totalSubjects)
		items = append(items, map[string]any{
			"class":          classItem,
			"total_students": totalStudents,
			"total_subjects": totalSubjects,
		})
	}
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleCreateClass(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		Name     string `json:"name"`
		IsActive *bool  `json:"is_active"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.Name == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "nama kelas wajib"})
		return
	}
	isActive := true
	if payload.IsActive != nil {
		isActive = *payload.IsActive
	}
	item := ClassRoom{SchoolID: user.SchoolID, Name: payload.Name, IsActive: isActive}
	s.DB.Create(&item)
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": item})
}

func (s *Server) handleUpdateClass(w http.ResponseWriter, r *http.Request) {
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
	s.DB.Model(&ClassRoom{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Updates(payload)
	render.JSON(w, r, map[string]any{"message": "kelas diperbarui"})
}

func (s *Server) handleDeleteClass(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	s.DB.Model(&User{}).Where("school_id = ? AND class_id = ?", user.SchoolID, id).Update("class_id", nil)
	s.DB.Where("school_id = ?", user.SchoolID).Delete(&ClassRoom{}, id)
	render.JSON(w, r, map[string]any{"message": "kelas dihapus"})
}

func (s *Server) handleListSubjects(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []Subject
	s.DB.Where("school_id = ?", user.SchoolID).Order("name ASC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleTutorMyStudents(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var assignments []TutorAssignment
	s.DB.Where("school_id = ? AND tutor_id = ?", user.SchoolID, user.ID).Find(&assignments)
	if len(assignments) == 0 {
		render.JSON(w, r, map[string]any{"items": []User{}})
		return
	}
	classIDs := make([]uint, 0, len(assignments))
	seen := make(map[uint]struct{}, len(assignments))
	for _, item := range assignments {
		if _, ok := seen[item.ClassID]; ok {
			continue
		}
		seen[item.ClassID] = struct{}{}
		classIDs = append(classIDs, item.ClassID)
	}
	query := s.DB.Model(&User{}).
		Preload("ClassRoom").
		Where("school_id = ? AND role = ? AND class_id IN ?", user.SchoolID, "student", classIDs)
	if search := strings.TrimSpace(r.URL.Query().Get("search")); search != "" {
		query = query.Where("name LIKE ? OR email LIKE ?", "%"+search+"%", "%"+search+"%")
	}
	if classID := r.URL.Query().Get("class_id"); classID != "" {
		query = query.Where("class_id = ?", classID)
	}
	var students []User
	query.Order("name ASC").Find(&students)
	render.JSON(w, r, map[string]any{"items": students})
}

func (s *Server) handleCreateSubject(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload Subject
	if err := parseJSONBody(r, &payload); err != nil || payload.Name == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "nama mapel wajib"})
		return
	}
	payload.SchoolID = user.SchoolID
	if !payload.IsActive {
		payload.IsActive = true
	}
	s.DB.Create(&payload)
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": payload})
}

func (s *Server) handleUpdateSubject(w http.ResponseWriter, r *http.Request) {
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
	s.DB.Model(&Subject{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Updates(payload)
	render.JSON(w, r, map[string]any{"message": "mapel diperbarui"})
}

func (s *Server) handleDeleteSubject(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	s.DB.Where("school_id = ?", user.SchoolID).Delete(&Subject{}, id)
	render.JSON(w, r, map[string]any{"message": "mapel dihapus"})
}

func (s *Server) handleListSubjectOrders(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var subjects []Subject
	var orders []SubjectOrder
	s.DB.Where("school_id = ?", user.SchoolID).Order("name ASC").Find(&subjects)
	s.DB.Where("school_id = ?", user.SchoolID).Find(&orders)

	orderMap := make(map[uint]int, len(orders))
	for _, item := range orders {
		orderMap[item.SubjectID] = item.Order
	}

	items := make([]map[string]any, 0, len(subjects))
	for index, subject := range subjects {
		order := index + 1
		if saved, ok := orderMap[subject.ID]; ok && saved > 0 {
			order = saved
		}
		items = append(items, map[string]any{
			"subject_id": subject.ID,
			"name":       subject.Name,
			"code":       subject.Code,
			"kkm":        subject.KKM,
			"order":      order,
			"is_active":  subject.IsActive,
		})
	}

	sort.Slice(items, func(i, j int) bool {
		left := items[i]["order"].(int)
		right := items[j]["order"].(int)
		if left == right {
			return fmt.Sprint(items[i]["name"]) < fmt.Sprint(items[j]["name"])
		}
		return left < right
	})

	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleUpdateSubjectOrders(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		Items []struct {
			SubjectID uint `json:"subject_id"`
			Order     int  `json:"order"`
		} `json:"items"`
	}
	if err := parseJSONBody(r, &payload); err != nil || len(payload.Items) == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "payload urutan mapel tidak valid"})
		return
	}

	if err := s.withTx(func(tx *gorm.DB) error {
		if err := tx.Where("school_id = ?", user.SchoolID).Delete(&SubjectOrder{}).Error; err != nil {
			return err
		}
		for _, item := range payload.Items {
			if item.SubjectID == 0 || item.Order <= 0 {
				continue
			}
			if err := tx.Create(&SubjectOrder{
				SchoolID:  user.SchoolID,
				SubjectID: item.SubjectID,
				Order:     item.Order,
			}).Error; err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui urutan mapel"})
		return
	}

	render.JSON(w, r, map[string]any{"message": "urutan mapel diperbarui"})
}

func (s *Server) handleListQuestionPackages(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []QuestionPackage
	query := s.DB.Where("school_id = ?", user.SchoolID)
	if subjectID := r.URL.Query().Get("subject_id"); subjectID != "" {
		query = query.Where("subject_id = ?", subjectID)
	}
	query.Order("created_at DESC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleCreateQuestionPackage(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload QuestionPackage
	if err := parseJSONBody(r, &payload); err != nil || payload.Name == "" || payload.SubjectID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "paket soal tidak valid"})
		return
	}
	payload.SchoolID = user.SchoolID
	payload.IsActive = true
	s.DB.Create(&payload)
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": payload})
}

func (s *Server) handleUpdateQuestionPackage(w http.ResponseWriter, r *http.Request) {
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
	s.DB.Model(&QuestionPackage{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Updates(payload)
	render.JSON(w, r, map[string]any{"message": "paket soal diperbarui"})
}

func (s *Server) handleDeleteQuestionPackage(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	s.DB.Where("school_id = ?", user.SchoolID).Delete(&QuestionPackage{}, id)
	render.JSON(w, r, map[string]any{"message": "paket soal dihapus"})
}

func (s *Server) handleDownloadQuestionImportTemplate(w http.ResponseWriter, r *http.Request) {
	book := excelize.NewFile()
	sheet := book.GetSheetName(0)
	headers := []string{"type", "question_text", "option_a", "option_b", "option_c", "option_d", "option_e", "points", "correct_answer", "essay_answer"}
	samples := [][]string{
		{"multiple_choice", "Siapakah proklamator kemerdekaan Indonesia?", "Soekarno", "Moh. Hatta", "Soekarno dan Moh. Hatta", "Sutan Sjahrir", "", "1", "C", ""},
		{"essay", "Jelaskan singkat makna Proklamasi bagi bangsa Indonesia.", "", "", "", "", "", "2", "", "Proklamasi menandai kemerdekaan Indonesia dan kedaulatan bangsa."},
	}
	for idx, header := range headers {
		cell, _ := excelize.CoordinatesToCellName(idx+1, 1)
		book.SetCellValue(sheet, cell, header)
	}
	for rowIdx, row := range samples {
		for colIdx, value := range row {
			cell, _ := excelize.CoordinatesToCellName(colIdx+1, rowIdx+2)
			book.SetCellValue(sheet, cell, value)
		}
	}
	if err := writeExcelWorkbook(w, "template-import-soal.xlsx", book); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal membuat template import soal"})
	}
}

func (s *Server) handleListQuestions(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []Question
	query := s.DB.Where("school_id = ?", user.SchoolID)
	if packageID := r.URL.Query().Get("question_package_id"); packageID != "" {
		query = query.Where("question_package_id = ?", packageID)
	}
	if subjectID := r.URL.Query().Get("subject_id"); subjectID != "" {
		query = query.Where("subject_id = ?", subjectID)
	}
	query.Order("`order` ASC, id ASC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func normalizeOptions(input []string) map[string]string {
	options := make(map[string]string)
	labels := []string{"A", "B", "C", "D", "E"}
	for idx, option := range input {
		if idx >= len(labels) {
			break
		}
		if strings.TrimSpace(option) != "" {
			options[labels[idx]] = option
		}
	}
	return options
}

func (s *Server) handleImportQuestions(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	packageID, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id paket soal tidak valid"})
		return
	}
	var questionPackage QuestionPackage
	if err := s.DB.Where("id = ? AND school_id = ?", packageID, user.SchoolID).First(&questionPackage).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "paket soal tidak ditemukan"})
		return
	}
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "gagal membaca form upload"})
		return
	}
	file, _, err := r.FormFile("file")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "file wajib diisi"})
		return
	}
	defer file.Close()
	book, err := excelize.OpenReader(file)
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "file excel tidak valid"})
		return
	}
	rows, err := book.GetRows(book.GetSheetName(0))
	if err != nil || len(rows) < 2 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "baris data tidak ditemukan"})
		return
	}

	success, failed := 0, 0
	failures := make([]map[string]any, 0)
	for idx, row := range rows[1:] {
		getCol := func(i int) string {
			if i >= len(row) {
				return ""
			}
			return strings.TrimSpace(row[i])
		}
		rowNum := idx + 2
		qType := strings.ToLower(getCol(0))
		questionText := getCol(1)
		points, _ := strconv.Atoi(getCol(7))
		if qType == "" || questionText == "" || points < 1 {
			failed++
			failures = append(failures, map[string]any{"row": rowNum, "reason": "type, question_text, dan points wajib valid"})
			continue
		}
		if qType != "multiple_choice" && qType != "essay" {
			failed++
			failures = append(failures, map[string]any{"row": rowNum, "reason": "type harus multiple_choice atau essay"})
			continue
		}

		item := Question{
			SchoolID:          user.SchoolID,
			SubjectID:         questionPackage.SubjectID,
			QuestionPackageID: questionPackage.ID,
			Type:              qType,
			QuestionText:      questionText,
			Points:            points,
			Order:             0,
			IsActive:          true,
			CreatedBy:         ptr(user.ID),
		}
		if qType == "multiple_choice" {
			options := normalizeOptions([]string{getCol(2), getCol(3), getCol(4), getCol(5), getCol(6)})
			correctAnswer := strings.ToUpper(getCol(8))
			if len(options) < 4 || (correctAnswer != "A" && correctAnswer != "B" && correctAnswer != "C" && correctAnswer != "D" && correctAnswer != "E") {
				failed++
				failures = append(failures, map[string]any{"row": rowNum, "reason": "opsi A-D dan correct_answer wajib valid untuk PG"})
				continue
			}
			item.Options = upsertJSON(options)
			item.CorrectAnswer = ptr(correctAnswer)
		} else {
			essayAnswer := getCol(9)
			if essayAnswer == "" {
				failed++
				failures = append(failures, map[string]any{"row": rowNum, "reason": "essay_answer wajib diisi untuk tipe essay"})
				continue
			}
			item.EssayAnswer = ptr(essayAnswer)
		}
		if err := s.DB.Create(&item).Error; err != nil {
			failed++
			failures = append(failures, map[string]any{"row": rowNum, "reason": err.Error()})
			continue
		}
		success++
	}
	s.DB.Model(&QuestionPackage{}).Where("id = ?", questionPackage.ID).Update("total_questions", gorm.Expr("total_questions + ?", success))
	render.JSON(w, r, map[string]any{"success": success, "failed": failed, "failures": failures})
}

func (s *Server) handleCreateQuestion(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		SubjectID         uint             `json:"subject_id"`
		QuestionPackageID uint             `json:"question_package_id"`
		Type              string           `json:"type"`
		QuestionText      string           `json:"question_text"`
		Options           []string         `json:"options"`
		CorrectAnswer     *string          `json:"correct_answer"`
		EssayAnswer       *string          `json:"essay_answer"`
		VideoURL          *string          `json:"video_url"`
		Attachments       []map[string]any `json:"attachments"`
		Points            int              `json:"points"`
		Order             int              `json:"order"`
		IsActive          *bool            `json:"is_active"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.SubjectID == 0 || payload.QuestionPackageID == 0 || payload.Type == "" || payload.QuestionText == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "data soal tidak valid"})
		return
	}
	isActive := true
	if payload.IsActive != nil {
		isActive = *payload.IsActive
	}
	item := Question{
		SchoolID:          user.SchoolID,
		SubjectID:         payload.SubjectID,
		QuestionPackageID: payload.QuestionPackageID,
		Type:              payload.Type,
		QuestionText:      payload.QuestionText,
		Options:           upsertJSON(normalizeOptions(payload.Options)),
		CorrectAnswer:     payload.CorrectAnswer,
		EssayAnswer:       payload.EssayAnswer,
		VideoURL:          payload.VideoURL,
		Attachments:       upsertJSON(payload.Attachments),
		Points:            payload.Points,
		Order:             payload.Order,
		IsActive:          isActive,
		CreatedBy:         ptr(user.ID),
	}
	s.DB.Create(&item)
	s.DB.Model(&QuestionPackage{}).Where("id = ?", payload.QuestionPackageID).Update("total_questions", gorm.Expr("total_questions + ?", 1))
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": item})
}

func (s *Server) handleUpdateQuestion(w http.ResponseWriter, r *http.Request) {
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
	if rawOptions, ok := payload["options"].([]any); ok {
		opts := make([]string, 0, len(rawOptions))
		for _, value := range rawOptions {
			opts = append(opts, fmt.Sprint(value))
		}
		payload["options"] = upsertJSON(normalizeOptions(opts))
	}
	if rawAttachments, ok := payload["attachments"].([]any); ok {
		attachments := make([]map[string]any, 0, len(rawAttachments))
		for _, value := range rawAttachments {
			if item, ok := value.(map[string]any); ok {
				attachments = append(attachments, item)
			}
		}
		payload["attachments"] = upsertJSON(attachments)
	}
	s.DB.Model(&Question{}).Where("id = ? AND school_id = ?", id, user.SchoolID).Updates(payload)
	render.JSON(w, r, map[string]any{"message": "soal diperbarui"})
}

func (s *Server) handleDeleteQuestion(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var question Question
	if err := s.DB.Where("school_id = ?", user.SchoolID).First(&question, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "soal tidak ditemukan"})
		return
	}
	s.removeQuestionImageFile(question.Image)
	s.DB.Delete(&question)
	s.DB.Model(&QuestionPackage{}).Where("id = ? AND total_questions > 0", question.QuestionPackageID).UpdateColumn("total_questions", gorm.Expr("total_questions - ?", 1))
	render.JSON(w, r, map[string]any{"message": "soal dihapus"})
}

func (s *Server) handleReferralOverview(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var referrals []Referral
	var transactions []UserCreditTransaction
	s.DB.Where("user_id = ?", user.ID).Order("referred_at DESC").Find(&referrals)
	s.DB.Where("user_id = ?", user.ID).Order("created_at DESC").Limit(50).Find(&transactions)
	render.JSON(w, r, map[string]any{
		"user":         user,
		"referrals":    referrals,
		"transactions": transactions,
		"can_withdraw": user.CreditBalance >= 10000,
	})
}

func (s *Server) handleUpdateBank(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		BankName          string `json:"bank_name"`
		BankAccountName   string `json:"bank_account_name"`
		BankAccountNumber string `json:"bank_account_number"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.BankName == "" || payload.BankAccountName == "" || payload.BankAccountNumber == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "data bank tidak lengkap"})
		return
	}
	s.DB.Model(&User{}).Where("id = ?", user.ID).Updates(map[string]any{
		"bank_name":           payload.BankName,
		"bank_account_name":   payload.BankAccountName,
		"bank_account_number": payload.BankAccountNumber,
	})
	render.JSON(w, r, map[string]any{"message": "data bank diperbarui"})
}

func (s *Server) handleWithdraw(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	if user.CreditBalance < 10000 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "saldo minimal 10.000 credit"})
		return
	}
	if user.BankName == nil || user.BankAccountName == nil || user.BankAccountNumber == nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "lengkapi data rekening terlebih dahulu"})
		return
	}
	amount := user.CreditBalance
	refKey := s.randomToken("withdraw")
	if err := s.withTx(func(tx *gorm.DB) error {
		if err := tx.Model(&User{}).Where("id = ?", user.ID).Update("credit_balance", 0).Error; err != nil {
			return err
		}
		return tx.Create(&UserCreditTransaction{
			UserID:       user.ID,
			Amount:       -amount,
			Type:         "withdrawal",
			ReferenceKey: &refKey,
			Meta: upsertJSON(map[string]any{
				"bank_name":           user.BankName,
				"bank_account_name":   user.BankAccountName,
				"bank_account_number": user.BankAccountNumber,
			}),
		}).Error
	}); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memproses withdrawal"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "withdrawal berhasil dibuat"})
}

func (s *Server) handleTutorOverview(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var tutors []User
	var assignments []TutorAssignment
	s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "tutor").Find(&tutors)
	s.DB.Where("school_id = ?", user.SchoolID).Find(&assignments)
	render.JSON(w, r, map[string]any{"tutors": tutors, "assignments": assignments})
}

func (s *Server) handleCreateTutorUser(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload struct {
		Name     string  `json:"name"`
		Email    string  `json:"email"`
		Password string  `json:"password"`
		Phone    *string `json:"phone"`
	}
	if err := parseJSONBody(r, &payload); err != nil || payload.Name == "" || payload.Email == "" || payload.Password == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "data tutor user tidak lengkap"})
		return
	}
	hash, _ := hashPassword(payload.Password)
	token := s.randomToken("usr")
	referralToken := strings.ToUpper(strings.ReplaceAll(uuid.NewString(), "-", ""))[:16]
	item := User{
		Name:          payload.Name,
		Email:         strings.ToLower(payload.Email),
		Password:      hash,
		SchoolID:      user.SchoolID,
		Role:          "tutor",
		IsAdmin:       false,
		Phone:         payload.Phone,
		Token:         &token,
		ReferralToken: &referralToken,
	}
	if err := s.DB.Create(&item).Error; err != nil {
		render.Status(r, http.StatusConflict)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	s.DB.Model(&School{}).Where("id = ?", user.SchoolID).UpdateColumn("total_user", gorm.Expr("total_user + ?", 1))
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": item})
}

func (s *Server) handleListTutorUsers(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var items []User
	s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "tutor").Order("name ASC").Find(&items)
	render.JSON(w, r, map[string]any{"items": items})
}

func (s *Server) handleUpdateTutorUser(w http.ResponseWriter, r *http.Request) {
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
	if password, ok := payload["password"].(string); ok && password != "" {
		hash, _ := hashPassword(password)
		payload["password"] = hash
	} else {
		delete(payload, "password")
	}
	s.DB.Model(&User{}).Where("id = ? AND school_id = ? AND role = ?", id, user.SchoolID, "tutor").Updates(payload)
	render.JSON(w, r, map[string]any{"message": "tutor user diperbarui"})
}

func (s *Server) handleDeleteTutorUser(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var tutor User
	if err := s.DB.Where("school_id = ? AND role = ?", user.SchoolID, "tutor").First(&tutor, id).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "tutor user tidak ditemukan"})
		return
	}
	suffix := fmt.Sprintf("_deleted_%d", time.Now().Unix())
	updates := map[string]any{"name": tutor.Name + suffix, "email": tutor.Email + suffix}
	if tutor.Phone != nil {
		updates["phone"] = *tutor.Phone + suffix
	}
	s.DB.Model(&tutor).Updates(updates)
	s.DB.Delete(&tutor)
	s.DB.Model(&School{}).Where("id = ? AND total_user > 0", user.SchoolID).UpdateColumn("total_user", gorm.Expr("total_user - ?", 1))
	render.JSON(w, r, map[string]any{"message": "tutor user dihapus"})
}

func (s *Server) handleCreateTutorAssignment(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	var payload TutorAssignment
	if err := parseJSONBody(r, &payload); err != nil || payload.TutorID == 0 || payload.ClassID == 0 || payload.SubjectID == 0 {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "assignment tutor tidak valid"})
		return
	}
	payload.SchoolID = user.SchoolID
	if err := s.DB.Clauses(clause.OnConflict{DoNothing: true}).Create(&payload).Error; err != nil {
		render.Status(r, http.StatusConflict)
		render.JSON(w, r, map[string]any{"message": err.Error()})
		return
	}
	render.Status(r, http.StatusCreated)
	render.JSON(w, r, map[string]any{"item": payload})
}

func (s *Server) handleDeleteTutorAssignment(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	s.DB.Where("school_id = ?", user.SchoolID).Delete(&TutorAssignment{}, id)
	render.JSON(w, r, map[string]any{"message": "assignment tutor dihapus"})
}
