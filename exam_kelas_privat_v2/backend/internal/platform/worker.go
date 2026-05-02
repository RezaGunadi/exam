package platform

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/robfig/cron/v3"
	"gorm.io/gorm"
)

var workerJobLocks sync.Map

func (s *Server) StartWorker() *cron.Cron {
	c := cron.New(cron.WithSeconds())

	c.AddFunc("0 * * * * *", func() { s.runLockedJob("ai:score-essays", func() error { _, err := s.runAIScoring(); return err }) })
	c.AddFunc("0 */5 * * * *", func() { s.runLockedJob("exams:cleanup-expired", s.cleanupExpiredExams) })
	c.AddFunc("0 * * * * *", func() {
		s.runLockedJob("double-checker:run", func() error { _, err := s.runDoubleChecker(); return err })
	})
	c.AddFunc("0 * * * * *", func() { s.runLockedJob("exam-results:mark-completed", s.markCompletedExamResults) })
	c.AddFunc("0 * * * * *", func() { s.runLockedJob("exam-results:mark-disconnected-inactive", s.markDisconnectedInactive) })
	c.AddFunc("0 */10 * * * *", func() { s.runLockedJob("exam-results:complete-ended", s.completeEndedExamResults) })
	c.AddFunc("0 * * * * *", func() { s.runLockedJob("exam-results:reset-double-checker-no-pg", s.resetDoubleCheckerNoPG) })
	c.AddFunc("0 0 1 * * *", func() { s.runLockedJob("users:generate-qr", s.generateUserQRs) })
	c.AddFunc("0 0 1 * * *", func() { s.runLockedJob("users:generate-referral-tokens", s.generateReferralTokens) })
	c.AddFunc("0 0 1 * * *", func() { s.runLockedJob("schools:cap-concurrent-expired", s.capConcurrentExpiredSchools) })
	c.AddFunc("0 0 1 * * *", func() { s.runLockedJob("schools:sync-concurrent-when-active", s.syncConcurrentActiveSchools) })
	c.AddFunc("0 0 1 1 1 *", func() { s.runLockedJob("semester:sync", s.syncSemesterYearly) })
	c.AddFunc("0 15 2 * * *", func() { s.runLockedJob("sitemap:generate", s.generateSitemap) })

	c.Start()
	return c
}

func (s *Server) runLockedJob(name string, fn func() error) {
	lock, _ := workerJobLocks.LoadOrStore(name, &sync.Mutex{})
	mutex := lock.(*sync.Mutex)
	if !mutex.TryLock() {
		return
	}
	defer mutex.Unlock()
	_ = fn()
}

func (s *Server) runAIScoring() (int64, error) {
	var answers []StudentAnswer
	if err := s.DB.
		Joins("JOIN users ON users.id = student_answers.user_id").
		Joins("JOIN schools ON schools.id = users.school_id").
		Where("student_answers.question_type = ? AND student_answers.is_graded = ?", "essay", false).
		Where("student_answers.is_ai_scheduler = ?", false).
		Where("student_answers.answer IS NOT NULL AND student_answers.answer <> ''").
		Where("schools.active_until IS NOT NULL AND schools.active_until >= ?", time.Now()).
		Limit(10).
		Find(&answers).Error; err != nil {
		return 0, err
	}
	var processed int64
	for _, answer := range answers {
		result, err := s.scoreEssayWithAI(answer)
		if err != nil {
			_ = s.DB.Model(&StudentAnswer{}).Where("id = ?", answer.ID).Updates(map[string]any{
				"is_ai_scheduler":    true,
				"ai_type":            "pending_review",
				"ai_score_suggested": 0,
			}).Error
			continue
		}
		if err := s.DB.Transaction(func(tx *gorm.DB) error {
			return s.applyAIScore(tx, answer, result)
		}); err == nil {
			processed++
		}
		time.Sleep(2 * time.Second)
	}
	return processed, nil
}

func (s *Server) cleanupExpiredExams() error {
	var results []ExamResult
	if err := s.DB.
		Preload("Exam").
		Where("status = ? AND started_at IS NOT NULL", "in_progress").
		Where("exam_id IN (?)", s.DB.Model(&Exam{}).Select("id").Where("status = ?", "published")).
		Find(&results).Error; err != nil {
		return err
	}
	now := time.Now()
	for _, result := range results {
		var exam Exam
		if err := s.DB.First(&exam, result.ExamID).Error; err != nil {
			return err
		}
		if result.StartedAt == nil {
			continue
		}
		timeSpent := int(now.Sub(*result.StartedAt).Minutes())
		if timeSpent < exam.Duration {
			continue
		}
		notes := map[string]any{
			"reason":     "timeout",
			"message":    "Ujian berakhir karena waktu habis (auto-cleanup)",
			"cleaned_at": now.Format(time.RFC3339),
		}
		if err := s.DB.Model(&ExamResult{}).Where("id = ? AND status = ?", result.ID, "in_progress").Updates(map[string]any{
			"status":       "timeout",
			"completed_at": now,
			"time_taken":   timeSpent,
			"notes":        upsertJSON(notes),
		}).Error; err != nil {
			return err
		}
	}
	return nil
}

func (s *Server) markCompletedExamResults() error {
	cutoff := time.Now().Add(-24 * time.Hour)
	var results []ExamResult
	if err := s.DB.
		Where("status = ?", "in_progress").
		Where(s.DB.
			Where("last_activity_at IS NOT NULL AND last_activity_at <= ?", cutoff).
			Or("last_activity_at IS NULL AND started_at IS NOT NULL AND started_at <= ?", cutoff)).
		Find(&results).Error; err != nil {
		return err
	}
	for _, result := range results {
		hasAnswers := len(result.Answers) > 0 && string(result.Answers) != "null" && string(result.Answers) != "{}"
		updates := map[string]any{"status": "not_started", "completed_at": nil}
		if hasAnswers {
			updates["status"] = "completed"
			if result.CompletedAt == nil {
				updates["completed_at"] = time.Now()
			}
		}
		if err := s.DB.Model(&ExamResult{}).Where("id = ? AND status = ?", result.ID, "in_progress").Updates(updates).Error; err != nil {
			return err
		}
	}
	return nil
}

func (s *Server) markDisconnectedInactive() error {
	cutoff := time.Now().Add(-610 * time.Second)
	return s.DB.Model(&ExamResult{}).
		Where("status = ?", "in_progress").
		Where(s.DB.
			Where("last_activity_at IS NOT NULL AND last_activity_at <= ?", cutoff).
			Or("last_activity_at IS NULL AND updated_at IS NOT NULL AND updated_at <= ?", cutoff).
			Or("last_activity_at IS NULL AND updated_at IS NULL AND started_at IS NOT NULL AND started_at <= ?", cutoff)).
		Update("status", "disconnected").Error
}

func (s *Server) completeEndedExamResults() error {
	now := time.Now()
	var results []ExamResult
	if err := s.DB.
		Where("status IN ?", []string{"in_progress", "disconnected"}).
		Where("exam_id IN (?)", s.DB.Model(&Exam{}).Select("id").Where("end_time <= ?", now)).
		Find(&results).Error; err != nil {
		return err
	}
	for _, result := range results {
		updates := map[string]any{
			"status":                    "completed",
			"is_double_checker_running": 0,
		}
		if result.CompletedAt == nil {
			updates["completed_at"] = now
		}
		if result.TimeTaken == 0 && result.StartedAt != nil {
			updates["time_taken"] = maxInt(0, int(now.Sub(*result.StartedAt).Minutes()))
		}
		if err := s.DB.Model(&ExamResult{}).Where("id = ? AND status IN ?", result.ID, []string{"in_progress", "disconnected"}).Updates(updates).Error; err != nil {
			return err
		}
	}
	return nil
}

func (s *Server) resetDoubleCheckerNoPG() error {
	return s.DB.Model(&ExamResult{}).
		Where("(total_pg_points = 0 OR total_pg_points IS NULL)").
		Where("(total_essay_points = 0 OR total_essay_points IS NULL)").
		Where("is_double_checker_running <> 0").
		Update("is_double_checker_running", 0).Error
}

func (s *Server) generateUserQRs() error {
	var users []User
	if err := s.DB.Where("qr IS NULL OR qr = ''").Find(&users).Error; err != nil {
		return err
	}
	for _, user := range users {
		qr := fmt.Sprintf("%d%s", user.ID, randomAlphaNumeric(150))
		s.DB.Model(&User{}).Where("id = ?", user.ID).Update("qr", qr)
	}
	return nil
}

func (s *Server) generateReferralTokens() error {
	var users []User
	if err := s.DB.Where("referral_token IS NULL OR referral_token = ''").Find(&users).Error; err != nil {
		return err
	}
	for _, user := range users {
		token, err := s.generateUniqueReferralToken()
		if err != nil {
			return err
		}
		s.DB.Model(&User{}).Where("id = ?", user.ID).Update("referral_token", token)
	}
	return nil
}

func (s *Server) capConcurrentExpiredSchools() error {
	return s.DB.Model(&School{}).
		Where("(active_until IS NOT NULL AND active_until < ?) OR active_until IS NULL", time.Now()).
		Where("max_concurent_exam > ?", 5).
		Update("max_concurent_exam", 5).Error
}

func (s *Server) syncConcurrentActiveSchools() error {
	return s.DB.Model(&School{}).
		Where("active_until IS NOT NULL AND active_until >= ?", time.Now()).
		Update("max_concurent_exam", gorm.Expr("total_user")).Error
}

func (s *Server) syncSemesterYearly() error {
	baseYear := time.Now().Year()
	ganjil := Semester{
		Type:         "ganjil",
		AcademicYear: fmt.Sprintf("%d/%d", baseYear, baseYear+1),
		StartDate:    time.Date(baseYear, 7, 1, 0, 0, 0, 0, time.UTC),
		EndDate:      time.Date(baseYear, 12, 31, 0, 0, 0, 0, time.UTC),
	}
	genap := Semester{
		Type:         "genap",
		AcademicYear: fmt.Sprintf("%d/%d", baseYear, baseYear+1),
		StartDate:    time.Date(baseYear+1, 1, 1, 0, 0, 0, 0, time.UTC),
		EndDate:      time.Date(baseYear+1, 6, 30, 0, 0, 0, 0, time.UTC),
	}
	s.DB.Where(Semester{Type: ganjil.Type, AcademicYear: ganjil.AcademicYear}).Assign(ganjil).FirstOrCreate(&ganjil)
	s.DB.Where(Semester{Type: genap.Type, AcademicYear: genap.AcademicYear}).Assign(genap).FirstOrCreate(&genap)
	return nil
}

func (s *Server) generateSitemap() error {
	appURL := strings.TrimRight(s.Config.AppURL, "/")
	if appURL == "" {
		appURL = "https://examkelasprivat.id"
	}
	urls := []string{
		"/",
		"/about",
		"/contact",
		"/privacy-policy",
		"/terms",
		"/login",
		"/register",
	}
	var sitemap strings.Builder
	sitemap.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	sitemap.WriteString(`<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">` + "\n")
	for _, path := range urls {
		sitemap.WriteString("  <url><loc>" + appURL + path + "</loc></url>\n")
	}
	sitemap.WriteString("</urlset>\n")

	publicDir := filepath.Join("..", "frontend", "public")
	_ = os.MkdirAll(publicDir, 0o755)
	if err := os.WriteFile(filepath.Join(publicDir, "sitemap.xml"), []byte(sitemap.String()), 0o644); err != nil {
		return err
	}
	robots := "User-agent: *\nAllow: /\nSitemap: " + appURL + "/sitemap.xml\n"
	return os.WriteFile(filepath.Join(publicDir, "robots.txt"), []byte(robots), 0o644)
}

func (s *Server) generateUniqueReferralToken() (string, error) {
	for i := 0; i < 10; i++ {
		token := strings.ToUpper(strings.ReplaceAll(uuid.NewString(), "-", ""))[:16]
		var count int64
		if err := s.DB.Model(&User{}).Where("referral_token = ?", token).Count(&count).Error; err != nil {
			return "", err
		}
		if count == 0 {
			return token, nil
		}
	}
	return "", fmt.Errorf("gagal membuat referral token unik")
}

func randomAlphaNumeric(length int) string {
	raw := strings.ToUpper(strings.ReplaceAll(uuid.NewString()+uuid.NewString()+uuid.NewString()+uuid.NewString(), "-", ""))
	if len(raw) >= length {
		return raw[:length]
	}
	return raw
}

func (s *Server) runDoubleChecker() (int64, error) {
	var results []ExamResult
	if err := s.DB.Where("is_double_checker_running = ? AND status IN ?", 0, []string{"completed", "disconnected", "timeout"}).Limit(1000).Find(&results).Error; err != nil {
		return 0, err
	}
	var processed int64
	for _, result := range results {
		if err := s.DB.Transaction(func(tx *gorm.DB) error {
			if err := tx.Model(&ExamResult{}).Where("id = ?", result.ID).Update("is_double_checker_running", 1).Error; err != nil {
				return err
			}
			var exam Exam
			if err := tx.First(&exam, result.ExamID).Error; err != nil {
				return err
			}
			scoreData, err := s.calculateExamScore(tx, exam, &result)
			if err != nil {
				return err
			}
			return tx.Model(&ExamResult{}).Where("id = ?", result.ID).Updates(map[string]any{
				"score":                     scoreData["score"],
				"total_score":               scoreData["total_score"],
				"correct_answers":           scoreData["correct_answers"],
				"wrong_answers":             scoreData["wrong_answers"],
				"pg_score":                  scoreData["pg_score"],
				"essay_score":               scoreData["essay_score"],
				"total_pg_points":           scoreData["total_pg_points"],
				"total_essay_points":        scoreData["total_essay_points"],
				"is_double_checker_running": 2,
			}).Error
		}); err == nil {
			processed++
		} else {
			s.DB.Model(&ExamResult{}).Where("id = ?", result.ID).Update("is_double_checker_running", 0)
		}
	}
	return processed, nil
}

func (s *Server) runExamRecovery() error {
	return s.DB.Model(&ExamResult{}).
		Where("status = ? AND answers IS NOT NULL", "disconnected").
		Updates(map[string]any{
			"status":           "in_progress",
			"last_activity_at": time.Now(),
		}).Error
}
