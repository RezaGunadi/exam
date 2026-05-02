package platform

import (
	"context"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/cors"
	"github.com/go-chi/render"
	mysqlDriver "github.com/go-sql-driver/mysql"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/datatypes"
	gormmysql "gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type Config struct {
	Port            string
	DSN             string
	AppURL          string
	JWTSecret       string
	SchedulerToken  string
	UploadDir       string
	AutoMigrate     bool
	StrictSchema    bool
	SMTPHost        string
	SMTPPort        string
	SMTPUsername    string
	SMTPPassword    string
	SMTPFrom        string
	EmailDebugToken bool
	GeminiAPIKey    string
	GeminiBaseURL   string
	GeminiModels    []string
	GroqAPIKey      string
	GroqURL         string
	GroqModels      []string
}

type Server struct {
	DB     *gorm.DB
	Config Config
}

type Claims struct {
	UserID uint   `json:"user_id"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

type ctxKey string

const userCtxKey ctxKey = "auth_user"

func LoadConfig() Config {
	return Config{
		Port:            env("APP_PORT", "8080"),
		DSN:             loadMySQLDSN(),
		AppURL:          env("APP_URL", "http://localhost:8080"),
		JWTSecret:       env("JWT_SECRET", "exam-kelas-privat-v2-secret"),
		SchedulerToken:  env("SCHEDULER_TOKEN", "scheduler-secret"),
		UploadDir:       env("UPLOAD_DIR", "data/uploads"),
		AutoMigrate:     envBool("AUTO_MIGRATE", true),
		StrictSchema:    envBool("STRICT_SCHEMA_CHECK", false),
		SMTPHost:        env("SMTP_HOST", ""),
		SMTPPort:        env("SMTP_PORT", "587"),
		SMTPUsername:    env("SMTP_USERNAME", ""),
		SMTPPassword:    env("SMTP_PASSWORD", ""),
		SMTPFrom:        env("SMTP_FROM", "no-reply@examkelasprivat.id"),
		EmailDebugToken: envBool("EMAIL_DEBUG_TOKEN", false),
		GeminiAPIKey:    env("GEMINI_API_KEY", ""),
		GeminiBaseURL:   env("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1"),
		GeminiModels:    envCSV("GEMINI_MODELS", "gemini-2.5-flash-lite"),
		GroqAPIKey:      env("GROQ_API_KEY", ""),
		GroqURL:         env("GROQ_URL", "https://api.groq.com/openai/v1/chat/completions"),
		GroqModels:      envCSV("GROQ_MODELS", "llama-3.1-8b-instant"),
	}
}

func NewServer(cfg Config) (*Server, error) {
	if err := ensureDatabaseExists(cfg.DSN); err != nil {
		return nil, err
	}

	db, err := gorm.Open(gormmysql.Open(cfg.DSN), &gorm.Config{})
	if err != nil {
		return nil, err
	}
	if cfg.AutoMigrate {
		if err := db.AutoMigrate(AutoMigrateModels()...); err != nil {
			return nil, fmt.Errorf("gagal menjalankan automigrate: %w", err)
		}
	}
	if cfg.StrictSchema {
		if err := ValidateLaravelSchema(db); err != nil {
			return nil, err
		}
	}

	if err := os.MkdirAll(cfg.UploadDir, 0o755); err != nil {
		return nil, fmt.Errorf("gagal membuat direktori upload: %w", err)
	}

	return &Server{
		DB:     db,
		Config: cfg,
	}, nil
}

func (s *Server) Router() http.Handler {
	r := chi.NewRouter()
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	if strings.TrimSpace(s.Config.UploadDir) != "" {
		uploadRoot := http.FileServer(http.Dir(filepath.Clean(s.Config.UploadDir)))
		r.Handle("/api/files/*", http.StripPrefix("/api/files/", uploadRoot))
	}

	r.With(render.SetContentType(render.ContentTypeJSON)).Get("/healthz", s.handleHealth)

	r.Route("/api", func(api chi.Router) {
		api.Use(render.SetContentType(render.ContentTypeJSON))
		api.Post("/auth/login", s.handleLogin)
		api.Post("/auth/register", s.handleRegister)
		api.Post("/auth/forgot-password", s.handleForgotPassword)
		api.Post("/auth/reset-password", s.handleResetPassword)
		api.Get("/pages/{slug}", s.handleStaticPage)
		api.Get("/landing/stats", s.handleLandingStats)
		api.Post("/landing/contact", s.handleContactDemo)
		api.Post("/landing/demo-request", s.handleContactDemo)
		api.Get("/scheduler/double-checker", s.schedulerTokenHandler(s.handleRunDoubleChecker))
		api.Get("/scheduler/status", s.schedulerTokenHandler(s.handleSchedulerStatus))
		api.Post("/scheduler/reset", s.schedulerTokenHandler(s.handleResetDoubleCheckerFlags))
		api.Get("/scheduler/sync-semesters", s.schedulerTokenHandler(s.handleSyncSemesters))
		api.Get("/scheduler/recover-student-result-from-exam-result", s.schedulerTokenHandler(s.handleRunRecovery))
		api.Get("/scheduler/recovery-status", s.schedulerTokenHandler(s.handleRecoveryStatus))
		api.Post("/scheduler/reset-recovery-flags", s.schedulerTokenHandler(s.handleResetRecoveryFlags))
		api.Get("/scheduler/validate-essay-scores-consistency", s.schedulerTokenHandler(s.handleValidateEssayScoresConsistency))
		api.Get("/scheduler/recalculate-total-score", s.schedulerTokenHandler(s.handleRecalculateTotalScore))

		api.Group(func(protected chi.Router) {
			protected.Use(s.authMiddleware)
			protected.Get("/auth/me", s.handleMe)
			protected.Post("/auth/logout", s.handleLogout)
			protected.Get("/ads/current", s.handleCurrentAd)

			protected.Get("/dashboard", s.handleDashboard)
			protected.Get("/profile", s.handleProfile)
			protected.Put("/profile", s.handleUpdateProfile)
			protected.Put("/profile/password", s.handleUpdatePassword)
			protected.Put("/profile/avatar", s.handleUpdateAvatar)

			protected.Get("/referrals", s.handleReferralOverview)
			protected.Put("/referrals/bank", s.handleUpdateBank)
			protected.Post("/referrals/withdraw", s.handleWithdraw)
			protected.Post("/onboarding/dismiss", s.handleDismissOnboarding)

			protected.Route("/admin", func(admin chi.Router) {
				admin.Use(s.requireRoles("admin", "tutor"))
				admin.Use(s.adminTutorScopeMiddleware)
				admin.Get("/school", s.handleSchool)
				admin.Put("/school", s.handleUpdateSchool)
				admin.Get("/students", s.handleListStudents)
				admin.Post("/students", s.handleCreateStudent)
				admin.Put("/students/{id}", s.handleUpdateStudent)
				admin.Delete("/students/{id}", s.handleDeleteStudent)
				admin.Get("/students/import/template", s.handleDownloadStudentImportTemplate)
				admin.Post("/students/import", s.handleImportStudents)
				admin.Get("/students/bulk-password/template", s.handleDownloadBulkPasswordTemplate)
				admin.Post("/students/bulk-password", s.handleBulkPassword)
				admin.Get("/classes", s.handleListClasses)
				admin.Post("/classes", s.handleCreateClass)
				admin.Put("/classes/{id}", s.handleUpdateClass)
				admin.Delete("/classes/{id}", s.handleDeleteClass)
				admin.Get("/subjects", s.handleListSubjects)
				admin.Post("/subjects", s.handleCreateSubject)
				admin.Put("/subjects/{id}", s.handleUpdateSubject)
				admin.Delete("/subjects/{id}", s.handleDeleteSubject)
				admin.Get("/subject-orders", s.handleListSubjectOrders)
				admin.Put("/subject-orders", s.handleUpdateSubjectOrders)
				admin.Get("/subject-kkm", s.handleListSubjectKKM)
				admin.Put("/subject-kkm/{id}", s.handleUpdateSubjectKKM)
				admin.Post("/subject-kkm/update-multiple", s.handleUpdateMultipleSubjectKKM)
				admin.Post("/subject-kkm/reset-default", s.handleResetSubjectKKM)
				admin.Get("/question-packages", s.handleListQuestionPackages)
				admin.Post("/question-packages", s.handleCreateQuestionPackage)
				admin.Put("/question-packages/{id}", s.handleUpdateQuestionPackage)
				admin.Delete("/question-packages/{id}", s.handleDeleteQuestionPackage)
				admin.Get("/question-packages/import-template", s.handleDownloadQuestionImportTemplate)
				admin.Post("/question-packages/{id}/import-questions", s.handleImportQuestions)
				admin.Get("/questions", s.handleListQuestions)
				admin.Post("/questions", s.handleCreateQuestion)
				admin.Put("/questions/{id}", s.handleUpdateQuestion)
				admin.Delete("/questions/{id}", s.handleDeleteQuestion)
				admin.Post("/questions/{id}/image", s.handleUploadQuestionImage)
				admin.Delete("/questions/{id}/image", s.handleClearQuestionImage)
				admin.Post("/questions/{id}/attachments", s.handleUploadQuestionAttachment)
				admin.Delete("/questions/{id}/attachments", s.handleDeleteQuestionAttachment)
				admin.Get("/exams", s.handleListExams)
				admin.Post("/exams", s.handleCreateExam)
				admin.Put("/exams/{id}", s.handleUpdateExam)
				admin.Delete("/exams/{id}", s.handleDeleteExam)
				admin.Post("/exams/{id}/publish", s.handlePublishExam)
				admin.Post("/exams/{id}/cancel", s.handleCancelExam)
				admin.Post("/exams/{id}/repick", s.handleRepickExam)
				admin.Get("/exams/{id}/assignments", s.handleListExamAssignments)
				admin.Post("/exams/{id}/assignments", s.handleAssignExam)
				admin.Delete("/exams/{id}/assignments/{assignmentId}", s.handleDeleteExamAssignment)
				admin.Get("/attempt-management", s.handleAttemptManagement)
				admin.Post("/attempt-management/add-user", s.handleAddUserAttempt)
				admin.Post("/attempt-management/add-class", s.handleAddClassAttempt)
				admin.Post("/attempt-management/reset", s.handleResetAttempt)
				admin.Post("/attempt-management/reset-user", s.handleResetUserAttempt)
				admin.Post("/attempt-management/reset-class", s.handleResetClassAttempt)
				admin.Post("/attempt-management/delete", s.handleDeleteAttemptAssignment)
				admin.Post("/attempt-management/{id}/toggle-active", s.handleToggleAttemptActive)
				admin.Get("/attempt-management/{id}/details", s.handleAttemptDetails)
				admin.Get("/exam-results", s.handleListExamResults)
				admin.Get("/exam-results/export.csv", s.handleExportExamResultsCSV)
				admin.Get("/exam-results/export.xlsx", s.handleExportExamResultsExcel)
				admin.Get("/exam-results/{id}/answer-sheet.pdf", s.handleAdminExamResultAnswerSheetPDF)
				admin.Get("/exam-results/{id}", s.handleGetExamResult)
				admin.Put("/exam-results/{id}/notes", s.handleUpdateExamResultNotes)
				admin.Put("/exam-results/{id}/essay-scores", s.handleUpdateEssayScores)
				admin.Post("/exam-results/{id}/mark-as-finished", s.handleMarkExamResultFinished)
				admin.Post("/exam-results/mark-multiple-as-finished", s.handleMarkMultipleExamResultsFinished)
				admin.Post("/exam-results/send-answer-sheets-email", s.handleSendAnswerSheetsEmail)
				admin.Post("/exam-results/fix-ai-graded-data", s.handleFixAIGradedData)
				admin.Post("/exam-results/{id}/update-individual-essay-score", s.handleUpdateIndividualEssayScore)
				admin.Get("/reports", s.handleListReports)
				admin.Get("/reports/export.pdf", s.handleExportReports)
				admin.Get("/reports/student/{studentId}", s.handleStudentReport)
				admin.Get("/reports/{id}", s.handleShowReport)
				admin.Get("/reports-config", s.handleReportConfigIndex)
				admin.Post("/reports-config/exam-percentages", s.handleUpdateExamTypePercentages)
				admin.Post("/reports-config/grade-thresholds", s.handleUpdateGradeThresholds)
				admin.Post("/reports-config/report-settings", s.handleUpdateReportSettings)
				admin.Post("/reports-config/reset", s.handleResetReportConfig)
				admin.Get("/raports", s.handleListRaports)
				admin.Get("/raports/generate/form", s.handleRaportGenerateForm)
				admin.Post("/raports-generate/student", s.handleGenerateStudentRaport)
				admin.Post("/raports-generate/class", s.handleGenerateClassRaports)
				admin.Post("/raports-generate/school", s.handleGenerateSchoolRaports)
				admin.Get("/raports/{id}", s.handleShowRaport)
				admin.Get("/raports/{id}/print", s.handlePrintRaport)
				admin.Put("/raports/{id}", s.handleUpdateRaport)
				admin.Post("/raports/{id}/publish", s.handlePublishRaport)
				admin.Post("/raports/{id}/archive", s.handleArchiveRaport)
				admin.Get("/ai-scoring", s.handleAIScoringIndex)
				admin.Get("/ai-scoring/stats", s.handleAIScoringStats)
				admin.Post("/ai-scoring/score-essay/{essayId}", s.handleScoreEssay)
				admin.Post("/ai-scoring/score-multiple", s.handleScoreMultipleEssays)
				admin.Post("/ai-scoring/reset-scoring/{essayId}", s.handleResetEssayScoring)
				admin.Get("/attendance/school-days", s.handleAttendanceDays)
				admin.Get("/attendance/by-date/{date}", s.handleAttendanceByDate)
				admin.Get("/attendance/by-date/{date}/class/{classId}", s.handleAttendanceByDateClass)
				admin.Get("/attendance/student/{userId}/date/{date}", s.handleAttendanceStudentDate)
				admin.Post("/attendance/scan", s.handleAttendanceScan)
				admin.Post("/attendance/status/{date}/{userId}", s.handleAttendanceStatus)
				admin.Post("/attendance/upload-attachment/{date}/{userId}", s.handleAttendanceUploadAttachment)
				admin.Post("/attendance/remove-attachment/{date}/{userId}", s.handleAttendanceRemoveAttachment)
				admin.Get("/attendance/generate-card/{userId}", s.handleAttendanceGenerateCard)
				admin.Get("/tasks", s.handleListTasks)
				admin.Post("/tasks", s.handleCreateTask)
				admin.Get("/tasks/{id}", s.handleGetTask)
				admin.Post("/tasks/{id}/assignments", s.handleAssignTask)
				admin.Delete("/tasks/{id}/assignments/{assignmentId}", s.handleDeleteTaskAssignment)
				admin.Get("/tasks/{id}/submissions", s.handleTaskSubmissions)
				admin.Post("/tasks/{id}/grade/{userId}", s.handleGradeTask)
				admin.Delete("/tasks/{id}", s.handleDeleteTask)
				admin.Get("/tutors", s.handleTutorOverview)
				admin.Post("/tutors", s.handleCreateTutorAssignment)
				admin.Delete("/tutors/{id}", s.handleDeleteTutorAssignment)
				admin.Get("/tutor-users", s.handleListTutorUsers)
				admin.Post("/tutor-users", s.handleCreateTutorUser)
				admin.Put("/tutor-users/{id}", s.handleUpdateTutorUser)
				admin.Delete("/tutor-users/{id}", s.handleDeleteTutorUser)
			})

			protected.Route("/student", func(student chi.Router) {
				student.Use(s.requireRoles("student"))
				student.Get("/exams", s.handleStudentExams)
				student.Get("/exams/{id}", s.handleStudentExamDetail)
				student.Post("/exams/{id}/start", s.handleStudentExamStart)
				student.Post("/exams/{id}/sync", s.handleStudentExamSync)
				student.Post("/exams/{id}/autosave", s.handleStudentExamSync)
				student.Post("/exams/{id}/save-progress", s.handleStudentExamSync)
				student.Post("/exams/{id}/heartbeat", s.handleStudentExamHeartbeat)
				student.Post("/exams/{id}/mark-disconnected", s.handleStudentExamMarkDisconnected)
				student.Post("/exams/{id}/proctor-upload", s.handleStudentExamProctorUpload)
				student.Post("/exams/{id}/record-cheating", s.handleStudentExamRecordCheating)
				student.Post("/exams/{id}/submit", s.handleStudentExamSubmit)
				student.Post("/exams/{id}/timeout", s.handleStudentExamTimeout)
				student.Get("/exams/{id}/status", s.handleStudentExamStatus)
				student.Get("/server-time", s.handleServerTime)
				student.Get("/results", s.handleStudentResults)
				student.Get("/results/{id}/answer-sheet.pdf", s.handleStudentExamResultAnswerSheetPDF)
				student.Get("/results/{id}", s.handleStudentResult)
				student.Get("/raports", s.handleStudentRaports)
				student.Get("/raports/{id}", s.handleStudentRaport)
				student.Get("/raports/{id}/print", s.handleStudentRaportPrint)
				student.Get("/tasks", s.handleStudentTasks)
				student.Get("/tasks/{id}", s.handleStudentTask)
				student.Post("/tasks/{id}/submit", s.handleStudentTaskSubmit)
			})

			protected.Route("/tutor", func(tutor chi.Router) {
				tutor.Use(s.requireRoles("tutor"))
				tutor.Get("/classes", s.handleTutorMyClasses)
				tutor.Get("/students", s.handleTutorMyStudents)
				tutor.Get("/subjects", s.handleListSubjects)
				tutor.Get("/question-packages", s.handleListQuestionPackages)
				tutor.Get("/questions", s.handleListQuestions)
				tutor.Get("/exams", s.handleListExams)
				tutor.Get("/attempt-management", s.handleAttemptManagement)
				tutor.Get("/attempt-management/{id}/details", s.handleAttemptDetails)
				tutor.Get("/exam-results", s.handleListExamResults)
				tutor.Get("/exam-results/{id}", s.handleGetExamResult)
			})

			protected.Route("/scheduler", func(scheduler chi.Router) {
				scheduler.Use(s.requireRoles("admin", "tutor"))
				scheduler.Get("/status", s.handleSchedulerStatus)
				scheduler.Post("/run/ai-scoring", s.handleRunAIScoring)
				scheduler.Post("/run/double-checker", s.handleRunDoubleChecker)
				scheduler.Post("/run/sync-semesters", s.handleSyncSemesters)
				scheduler.Post("/run/recovery", s.handleRunRecovery)
			})
		})
	})

	return r
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	render.JSON(w, r, map[string]any{"ok": true, "service": "exam_kelas_privat_v2"})
}

func (s *Server) issueToken(user User) (string, error) {
	claims := Claims{
		UserID: user.ID,
		Role:   user.Role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Subject:   strconv.Itoa(int(user.ID)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(s.Config.JWTSecret))
}

func (s *Server) parseToken(tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(token *jwt.Token) (any, error) {
		return []byte(s.Config.JWTSecret), nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}

func (s *Server) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			render.Status(r, http.StatusUnauthorized)
			render.JSON(w, r, map[string]any{"message": "unauthorized"})
			return
		}

		claims, err := s.parseToken(strings.TrimPrefix(authHeader, "Bearer "))
		if err != nil {
			render.Status(r, http.StatusUnauthorized)
			render.JSON(w, r, map[string]any{"message": "invalid token"})
			return
		}

		var user User
		if err := s.DB.Preload("School").Preload("ClassRoom").First(&user, claims.UserID).Error; err != nil {
			render.Status(r, http.StatusUnauthorized)
			render.JSON(w, r, map[string]any{"message": "user not found"})
			return
		}

		ctx := context.WithValue(r.Context(), userCtxKey, &user)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *Server) requireRoles(roles ...string) func(http.Handler) http.Handler {
	roleSet := make(map[string]struct{}, len(roles))
	for _, role := range roles {
		roleSet[role] = struct{}{}
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			user := s.currentUser(r)
			if user == nil {
				render.Status(r, http.StatusUnauthorized)
				render.JSON(w, r, map[string]any{"message": "unauthorized"})
				return
			}
			if _, ok := roleSet[user.Role]; !ok {
				render.Status(r, http.StatusForbidden)
				render.JSON(w, r, map[string]any{"message": "forbidden"})
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func (s *Server) adminTutorScopeMiddleware(next http.Handler) http.Handler {
	tutorAllowedPrefixes := []string{
		"question-packages",
		"questions",
		"exams",
		"attempt-management",
		"exam-results",
		"attendance",
		"tasks",
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user := s.currentUser(r)
		if user == nil || user.Role != "tutor" {
			next.ServeHTTP(w, r)
			return
		}
		path := strings.TrimPrefix(r.URL.Path, "/api/admin/")
		for _, prefix := range tutorAllowedPrefixes {
			if path == prefix || strings.HasPrefix(path, prefix+"/") {
				next.ServeHTTP(w, r)
				return
			}
		}
		render.Status(r, http.StatusForbidden)
		render.JSON(w, r, map[string]any{"message": "forbidden"})
	})
}

func (s *Server) schedulerTokenHandler(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimSpace(r.URL.Query().Get("token"))
		if token == "" {
			token = strings.TrimSpace(r.Header.Get("X-Scheduler-Token"))
		}
		if token == "" {
			auth := strings.TrimSpace(r.Header.Get("Authorization"))
			token = strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
		}
		if token == s.Config.SchedulerToken {
			next(w, r)
			return
		}
		if token != "" {
			claims := &Claims{}
			parsed, err := jwt.ParseWithClaims(token, claims, func(token *jwt.Token) (any, error) {
				return []byte(s.Config.JWTSecret), nil
			})
			if err == nil && parsed.Valid && (claims.Role == "admin" || claims.Role == "tutor") {
				next(w, r)
				return
			}
		}
		if token == "" || token != s.Config.SchedulerToken {
			render.Status(r, http.StatusUnauthorized)
			render.JSON(w, r, map[string]any{"message": "scheduler token tidak valid"})
			return
		}
		next(w, r)
	}
}

func (s *Server) currentUser(r *http.Request) *User {
	user, _ := r.Context().Value(userCtxKey).(*User)
	return user
}

func (s *Server) isSchoolActive(school *School) bool {
	return school != nil && school.ActiveUntil != nil && school.ActiveUntil.After(time.Now())
}

func (s *Server) roleHome(role string) string {
	switch role {
	case "admin":
		return "/admin/dashboard"
	case "tutor":
		return "/tutor/dashboard"
	default:
		return "/student/dashboard"
	}
}

func (s *Server) randomToken(prefix string) string {
	return fmt.Sprintf("%s_%s", prefix, strings.ReplaceAll(uuid.NewString(), "-", ""))
}

func hashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

func comparePassword(hash string, password string) error {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func envAllowEmpty(key, fallback string) string {
	value, exists := os.LookupEnv(key)
	if !exists {
		return fallback
	}
	return value
}

func envBool(key string, fallback bool) bool {
	value, exists := os.LookupEnv(key)
	if !exists {
		return fallback
	}
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func envCSV(key, fallback string) []string {
	raw := env(key, fallback)
	parts := strings.Split(raw, ",")
	values := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			values = append(values, part)
		}
	}
	return values
}

func loadMySQLDSN() string {
	if dsn := strings.TrimSpace(os.Getenv("MYSQL_DSN")); dsn != "" {
		return dsn
	}

	host := env("DB_HOST", "127.0.0.1")
	port := env("DB_PORT", "3306")
	username := env("DB_USERNAME", "root")
	password := envAllowEmpty("DB_PASSWORD", "")
	name := env("DB_NAME", "exam_kelas_privat")
	params := env("DB_PARAMS", "parseTime=true")

	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?%s", username, password, host, port, name, params)
}

func ensureDatabaseExists(dsn string) error {
	cfg, err := mysqlDriver.ParseDSN(dsn)
	if err != nil {
		return fmt.Errorf("dsn mysql tidak valid: %w", err)
	}
	if strings.TrimSpace(cfg.DBName) == "" {
		return nil
	}

	targetDBName := cfg.DBName
	cfg.DBName = ""

	sqlDB, err := sql.Open("mysql", cfg.FormatDSN())
	if err != nil {
		return fmt.Errorf("gagal membuka koneksi mysql bootstrap: %w", err)
	}
	defer sqlDB.Close()

	if err := sqlDB.Ping(); err != nil {
		return fmt.Errorf("gagal konek mysql bootstrap: %w", err)
	}

	escapedDBName := strings.ReplaceAll(targetDBName, "`", "``")
	if _, err := sqlDB.Exec(fmt.Sprintf("CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", escapedDBName)); err != nil {
		return fmt.Errorf("gagal membuat database %s: %w", targetDBName, err)
	}

	return nil
}

func parseJSONBody[T any](r *http.Request, dst *T) error {
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(dst)
}

func pathUint(r *http.Request, key string) (uint, error) {
	id, err := strconv.ParseUint(chi.URLParam(r, key), 10, 64)
	if err != nil {
		return 0, err
	}
	return uint(id), nil
}

func ptr[T any](v T) *T { return &v }

func upsertJSON(value any) datatypes.JSON {
	raw, _ := json.Marshal(value)
	return datatypes.JSON(raw)
}

func writeCSV(w http.ResponseWriter, filename string, records [][]string) error {
	w.Header().Set("Content-Type", "text/csv")
	w.Header().Set("Content-Disposition", "attachment; filename="+filename)
	writer := csv.NewWriter(w)
	defer writer.Flush()
	return writer.WriteAll(records)
}

func (s *Server) consumeExportQuota(school *School) bool {
	if school == nil {
		return false
	}

	if school.ActiveUntil != nil && school.ActiveUntil.After(time.Now()) {
		s.DB.Model(school).UpdateColumn("total_export", gorm.Expr("total_export + ?", 1))
		return true
	}

	result := s.DB.Model(&School{}).
		Where("id = ?", school.ID).
		Where("max_total_export <= 0 OR total_export < max_total_export").
		UpdateColumn("total_export", gorm.Expr("total_export + ?", 1))

	return result.RowsAffected > 0
}

func (s *Server) withTx(fn func(tx *gorm.DB) error) error {
	return s.DB.Transaction(func(tx *gorm.DB) error {
		return fn(tx)
	})
}

func (s *Server) getOrCreateActiveExamResult(tx *gorm.DB, examID, userID uint) (*ExamResult, bool, error) {
	var result ExamResult
	err := tx.Where("exam_id = ? AND user_id = ? AND status IN ?", examID, userID, []string{"in_progress", "disconnected"}).
		Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&result).Error
	if err == nil {
		return &result, false, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, false, err
	}

	now := time.Now()
	result = ExamResult{
		ExamID:          examID,
		UserID:          userID,
		StartedAt:       &now,
		LastActivityAt:  &now,
		Status:          "in_progress",
		Answers:         upsertJSON(map[string]string{}),
		EssayScores:     upsertJSON(map[string]int{}),
		CurrentQuestion: ptr(1),
	}
	if err := tx.Create(&result).Error; err != nil {
		return nil, false, err
	}
	return &result, true, nil
}
