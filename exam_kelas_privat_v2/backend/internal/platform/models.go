package platform

import (
	"time"

	"gorm.io/datatypes"
	"gorm.io/gorm"
)

type User struct {
	ID                 uint           `gorm:"primaryKey" json:"id"`
	CreatedAt          time.Time      `json:"created_at"`
	UpdatedAt          time.Time      `json:"updated_at"`
	DeletedAt          gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	Name               string         `json:"name"`
	Slug               *string        `gorm:"uniqueIndex" json:"slug,omitempty"`
	Email              string         `gorm:"uniqueIndex" json:"email"`
	NISN               *string        `json:"nisn,omitempty"`
	Password           string         `json:"-"`
	SchoolID           uint           `gorm:"index" json:"school_id"`
	Role               string         `gorm:"index" json:"role"`
	IsAdmin            bool           `gorm:"column:is_admin" json:"is_admin"`
	ClassID            *uint          `gorm:"index" json:"class_id,omitempty"`
	Phone              *string        `json:"phone,omitempty"`
	Address            *string        `json:"address,omitempty"`
	BirthDate          *time.Time     `json:"birth_date,omitempty"`
	Gender             *string        `json:"gender,omitempty"`
	Bio                *string        `json:"bio,omitempty"`
	Avatar             *string        `json:"avatar,omitempty"`
	Token              *string        `json:"token,omitempty"`
	ReferralToken      *string        `gorm:"uniqueIndex" json:"referral_token,omitempty"`
	CreditBalance      int64          `gorm:"default:0" json:"credit_balance"`
	BankName           *string        `json:"bank_name,omitempty"`
	BankAccountName    *string        `json:"bank_account_name,omitempty"`
	BankAccountNumber  *string        `json:"bank_account_number,omitempty"`
	IsCoachmarkShowing bool           `gorm:"column:is_coachmark_showing;default:false" json:"is_coachmark_showing"`
	QR                 *string        `json:"qr,omitempty"`

	School    School     `json:"school,omitempty"`
	ClassRoom *ClassRoom `gorm:"foreignKey:ClassID" json:"class_room,omitempty"`
}

func (User) TableName() string { return "users" }

type School struct {
	ID               uint           `gorm:"primaryKey" json:"id"`
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	Name             string         `json:"name"`
	Slug             *string        `gorm:"uniqueIndex" json:"slug,omitempty"`
	Address          *string        `json:"address,omitempty"`
	Phone            *string        `json:"phone,omitempty"`
	Email            *string        `json:"email,omitempty"`
	Website          *string        `json:"website,omitempty"`
	Logo             *string        `json:"logo,omitempty"`
	Description      *string        `json:"description,omitempty"`
	PrincipalName    *string        `json:"principal_name,omitempty"`
	PrincipalPhone   *string        `json:"principal_phone,omitempty"`
	PrincipalEmail   *string        `json:"principal_email,omitempty"`
	SignatureImage   *string        `json:"signature_image,omitempty"`
	MaxUser          int            `json:"max_user"`
	TotalUser        int            `json:"total_user"`
	TotalExport      int            `json:"total_export"`
	MaxTotalExport   int            `json:"max_total_export"`
	MaxConcurentExam int            `json:"max_concurent_exam"`
	ActiveUntil      *time.Time     `json:"active_until,omitempty"`
	LastPaid         *time.Time     `json:"last_paid,omitempty"`
	SubscriptionType *string        `gorm:"size:32;default:token_based" json:"subscription_type,omitempty"`
	TokenBalance     uint           `gorm:"default:500" json:"token_balance"`
}

func (School) TableName() string { return "schools" }

type ClassRoom struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID  uint           `gorm:"index" json:"school_id"`
	Name      string         `json:"name"`
	IsActive  bool           `gorm:"default:true" json:"is_active"`
}

func (ClassRoom) TableName() string { return "classes" }

type Subject struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID  uint           `gorm:"index" json:"school_id"`
	Name      string         `json:"name"`
	Code      *string        `json:"code,omitempty"`
	KKM       *int           `json:"kkm,omitempty"`
	IsActive  bool           `gorm:"default:true" json:"is_active"`
}

func (Subject) TableName() string { return "subjects" }

type QuestionPackage struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID       uint           `gorm:"index" json:"school_id"`
	SubjectID      uint           `gorm:"index" json:"subject_id"`
	Name           string         `json:"name"`
	Slug           *string        `gorm:"uniqueIndex" json:"slug,omitempty"`
	Description    *string        `json:"description,omitempty"`
	TotalQuestions int            `json:"total_questions"`
	IsActive       bool           `gorm:"default:true" json:"is_active"`
}

func (QuestionPackage) TableName() string { return "question_packages" }

type Question struct {
	ID                uint           `gorm:"primaryKey" json:"id"`
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID          uint           `gorm:"index" json:"school_id"`
	SubjectID         uint           `gorm:"index" json:"subject_id"`
	QuestionPackageID uint           `gorm:"index" json:"question_package_id"`
	Type              string         `json:"type"`
	QuestionText      string         `gorm:"type:longtext" json:"question_text"`
	Slug              *string        `gorm:"uniqueIndex" json:"slug,omitempty"`
	Options           datatypes.JSON `gorm:"type:json" json:"options,omitempty"`
	CorrectAnswer     *string        `json:"correct_answer,omitempty"`
	EssayAnswer       *string        `gorm:"type:longtext" json:"essay_answer,omitempty"`
	Points            int            `json:"points"`
	Order             int            `json:"order"`
	IsActive          bool           `gorm:"default:true" json:"is_active"`
	Image             *string        `json:"image,omitempty"`
	VideoURL          *string        `json:"video_url,omitempty"`
	Attachments       datatypes.JSON `gorm:"type:json" json:"attachments,omitempty"`
	CreatedBy         *uint          `json:"created_by,omitempty"`
}

func (Question) TableName() string { return "questions" }

type Exam struct {
	ID                uint           `gorm:"primaryKey" json:"id"`
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID          uint           `gorm:"index" json:"school_id"`
	QuestionPackageID uint           `gorm:"index" json:"question_package_id"`
	Title             string         `json:"title"`
	Slug              *string        `gorm:"uniqueIndex" json:"slug,omitempty"`
	ExamType          string         `json:"exam_type"`
	Description       *string        `gorm:"type:text" json:"description,omitempty"`
	StartTime         time.Time      `json:"start_time"`
	EndTime           time.Time      `json:"end_time"`
	Duration          int            `json:"duration"`
	TotalQuestions    int            `json:"total_questions"`
	PassingScore      int            `json:"passing_score"`
	Status            string         `json:"status"`
	ShuffleQuestions  bool           `json:"shuffle_questions"`
	ShowResults       bool           `json:"show_results"`
}

func (Exam) TableName() string { return "exams" }

type ExamAssignment struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	ExamID         uint           `gorm:"index" json:"exam_id"`
	UserID         uint           `gorm:"index" json:"user_id"`
	ClassID        *uint          `gorm:"index" json:"class_id,omitempty"`
	AssignmentType string         `json:"assignment_type"`
	IsActive       bool           `gorm:"default:true" json:"is_active"`
	Attempt        int            `gorm:"default:0" json:"attempt"`
	TotalAttempt   int            `gorm:"default:1" json:"total_attempt"`
}

func (ExamAssignment) TableName() string { return "exam_assignments" }

type ExamAttemptConfig struct {
	ID                    uint      `gorm:"primaryKey" json:"id"`
	CreatedAt             time.Time `json:"created_at"`
	UpdatedAt             time.Time `json:"updated_at"`
	ExamAssignmentID      uint      `gorm:"uniqueIndex:eac_assign_attempt_unique" json:"exam_assignment_id"`
	ForAttemptNumber      uint      `gorm:"uniqueIndex:eac_assign_attempt_unique" json:"for_attempt_number"`
	Mode                  string    `gorm:"default:auto" json:"mode"`
	CustomDurationMinutes *uint     `json:"custom_duration_minutes,omitempty"`
}

func (ExamAttemptConfig) TableName() string { return "exam_attempt_configs" }

type ExamResult struct {
	ID                     uint           `gorm:"primaryKey" json:"id"`
	Slug                   *string        `gorm:"uniqueIndex" json:"slug,omitempty"`
	CreatedAt              time.Time      `json:"created_at"`
	UpdatedAt              time.Time      `json:"updated_at"`
	DeletedAt              gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	ExamID                 uint           `gorm:"index" json:"exam_id"`
	UserID                 uint           `gorm:"index" json:"user_id"`
	StartedAt              *time.Time     `json:"started_at,omitempty"`
	CompletedAt            *time.Time     `json:"completed_at,omitempty"`
	Score                  int            `json:"score"`
	TotalScore             int            `json:"total_score"`
	CorrectAnswers         int            `json:"correct_answers"`
	WrongAnswers           int            `json:"wrong_answers"`
	TimeTaken              int            `json:"time_taken"`
	Status                 string         `gorm:"index" json:"status"`
	CurrentQuestion        *int           `json:"current_question,omitempty"`
	LastActivityAt         *time.Time     `json:"last_activity_at,omitempty"`
	IsPassed               *bool          `json:"is_passed,omitempty"`
	Answers                datatypes.JSON `gorm:"type:json" json:"answers,omitempty"`
	EssayScores            datatypes.JSON `gorm:"type:json" json:"essay_scores,omitempty"`
	PGScore                int            `gorm:"column:pg_score" json:"pg_score"`
	EssayScore             int            `json:"essay_score"`
	IsDoubleCheckerRunning int            `json:"is_double_checker_running"`
	TotalPGPoints          int            `gorm:"column:total_pg_points" json:"total_pg_points"`
	TotalEssayPoints       int            `json:"total_essay_points"`
	Notes                  *string        `gorm:"type:text" json:"notes,omitempty"`
	CheatingNote           *string        `gorm:"type:longtext" json:"cheating_note,omitempty"`
	ProctorSnapshots       datatypes.JSON `gorm:"type:json" json:"proctor_snapshots,omitempty"`
}

func (ExamResult) TableName() string { return "exam_results" }

type ExamResultTempAnswer struct {
	ID              uint           `gorm:"primaryKey" json:"id"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	ExamResultID    uint           `gorm:"uniqueIndex" json:"exam_result_id"`
	ExamID          uint           `gorm:"index" json:"exam_id"`
	UserID          uint           `gorm:"index" json:"user_id"`
	Answers         datatypes.JSON `gorm:"type:json" json:"answers"`
	PGAnswers       datatypes.JSON `gorm:"type:json" json:"pg_answers"`
	CurrentQuestion *int           `json:"current_question,omitempty"`
	LastSavedAt     *time.Time     `json:"last_saved_at,omitempty"`
}

func (ExamResultTempAnswer) TableName() string { return "exam_result_temp_answers" }

type StudentAnswer struct {
	ID                uint           `gorm:"primaryKey" json:"id"`
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	ExamID            uint           `gorm:"index" json:"exam_id"`
	ExamResultID      uint           `gorm:"index" json:"exam_result_id"`
	UserID            uint           `gorm:"index" json:"user_id"`
	QuestionID        uint           `gorm:"index" json:"question_id"`
	QuestionPackageID uint           `gorm:"index" json:"question_package_id"`
	QuestionType      string         `json:"question_type"`
	Key               *string        `json:"key,omitempty"`
	Answer            string         `gorm:"type:longtext" json:"answer"`
	AnswerValue       string         `gorm:"type:longtext" json:"answer_value"`
	StudentAnswer     string         `gorm:"type:longtext" json:"student_answer"`
	CorrectAnswer     string         `gorm:"type:longtext" json:"correct_answer"`
	IsCorrect         bool           `json:"is_correct"`
	PointsEarned      int            `json:"points_earned"`
	MaxPoints         int            `json:"max_points"`
	Score             int            `json:"score"`
	AdditionalData    datatypes.JSON `gorm:"type:json" json:"additional_data,omitempty"`
	IsGraded          bool           `json:"is_graded"`
	IsAIScheduler     bool           `gorm:"column:is_ai_scheduler" json:"is_ai_scheduler"`
	AIScoreSuggested  int            `json:"ai_score_suggested"`
	AIType            *string        `json:"ai_type,omitempty"`
}

func (StudentAnswer) TableName() string { return "student_answers" }

type PgAnswer struct {
	ID            uint           `gorm:"primaryKey" json:"id"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	ExamResultID  uint           `gorm:"index" json:"exam_result_id"`
	QuestionID    uint           `gorm:"index" json:"question_id"`
	StudentAnswer *string        `gorm:"column:student_answer" json:"student_answer,omitempty"`
	CorrectAnswer *string        `json:"correct_answer,omitempty"`
	IsCorrect     bool           `json:"is_correct"`
	Points        int            `json:"points"`
}

func (PgAnswer) TableName() string { return "pg_answers" }

type UserAbsent struct {
	ID         uint           `gorm:"primaryKey" json:"id"`
	CreatedAt  time.Time      `json:"created_at"`
	UpdatedAt  time.Time      `json:"updated_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	UserID     uint           `gorm:"uniqueIndex:idx_user_absent" json:"user_id"`
	SchoolID   uint           `gorm:"index" json:"school_id"`
	Date       time.Time      `gorm:"type:date;uniqueIndex:idx_user_absent" json:"date"`
	Time       *string        `json:"time,omitempty"`
	EndTime    *string        `json:"end_time,omitempty"`
	Attachment *string        `json:"attachment,omitempty"`
	Status     string         `json:"status"`
}

func (UserAbsent) TableName() string { return "user_absents" }

type SchoolAbsent struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID  uint           `gorm:"uniqueIndex:idx_school_absent" json:"school_id"`
	Date      time.Time      `gorm:"type:date;uniqueIndex:idx_school_absent" json:"date"`
}

func (SchoolAbsent) TableName() string { return "school_absents" }

type SchoolTask struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID    uint           `gorm:"index" json:"school_id"`
	ClassID     uint           `gorm:"index" json:"class_id"`
	Title       string         `json:"title"`
	Description *string        `gorm:"type:text" json:"description,omitempty"`
	CreatedBy   uint           `gorm:"index" json:"created_by"`
	Files       datatypes.JSON `gorm:"type:json" json:"files,omitempty"`
}

func (SchoolTask) TableName() string { return "school_tasks" }

type SchoolTaskAssignment struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolTaskID   uint           `gorm:"index" json:"school_task_id"`
	SchoolID       uint           `gorm:"index" json:"school_id"`
	ClassID        uint           `gorm:"index" json:"class_id"`
	UserID         *uint          `gorm:"index" json:"user_id,omitempty"`
	AssignmentType string         `json:"assignment_type"`
	IsActive       bool           `gorm:"default:true" json:"is_active"`
}

func (SchoolTaskAssignment) TableName() string { return "school_task_assignments" }

type StudentSchoolTask struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	UserID       uint           `gorm:"index" json:"user_id"`
	SchoolID     uint           `gorm:"index" json:"school_id"`
	ClassID      uint           `gorm:"index" json:"class_id"`
	SchoolTaskID uint           `gorm:"index" json:"school_task_id"`
	Text         *string        `gorm:"type:longtext" json:"text,omitempty"`
	Files        datatypes.JSON `gorm:"type:json" json:"files,omitempty"`
	Nilai        *int           `json:"nilai,omitempty"`
	Note         *string        `gorm:"type:text" json:"note,omitempty"`
}

func (StudentSchoolTask) TableName() string { return "student_school_tasks" }

type TutorAssignment struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	TutorID   uint           `gorm:"uniqueIndex:idx_tutor_assignment" json:"tutor_id"`
	ClassID   uint           `gorm:"uniqueIndex:idx_tutor_assignment" json:"class_id"`
	SubjectID uint           `gorm:"uniqueIndex:idx_tutor_assignment" json:"subject_id"`
	SchoolID  uint           `gorm:"index" json:"school_id"`
}

func (TutorAssignment) TableName() string { return "tutor_assignments" }

type Referral struct {
	ID                uint           `gorm:"primaryKey" json:"id"`
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	UserID            uint           `gorm:"index" json:"user_id"`
	UserContributorID uint           `gorm:"index" json:"user_contributor_id"`
	SchoolID          uint           `gorm:"index" json:"school_id"`
	Status            string         `json:"status"`
	ReferredAt        *time.Time     `json:"referred_at,omitempty"`
}

func (Referral) TableName() string { return "referrals" }

type UserCreditTransaction struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	UserID       uint           `gorm:"index" json:"user_id"`
	Amount       int64          `json:"amount"`
	Type         string         `json:"type"`
	ReferenceKey *string        `gorm:"uniqueIndex" json:"reference_key,omitempty"`
	Meta         datatypes.JSON `gorm:"type:json" json:"meta,omitempty"`
}

func (UserCreditTransaction) TableName() string { return "user_credit_transactions" }

type Semester struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID     *uint          `gorm:"index" json:"school_id,omitempty"`
	Type         string         `json:"type"`
	AcademicYear string         `json:"academic_year"`
	StartDate    time.Time      `gorm:"type:date" json:"start_date"`
	EndDate      time.Time      `gorm:"type:date" json:"end_date"`
}

func (Semester) TableName() string { return "semesters" }

type ReportConfig struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID    uint           `gorm:"uniqueIndex:idx_report_config" json:"school_id"`
	ConfigType  string         `gorm:"uniqueIndex:idx_report_config" json:"config_type"`
	Key         string         `gorm:"uniqueIndex:idx_report_config" json:"key"`
	Value       *float64       `gorm:"type:decimal(5,2)" json:"value,omitempty"`
	Description *string        `gorm:"type:text" json:"description,omitempty"`
	Metadata    datatypes.JSON `gorm:"type:json" json:"metadata,omitempty"`
	IsActive    bool           `gorm:"default:true" json:"is_active"`
}

func (ReportConfig) TableName() string { return "report_configs" }

type Raport struct {
	ID                  uint           `gorm:"primaryKey" json:"id"`
	CreatedAt           time.Time      `json:"created_at"`
	UpdatedAt           time.Time      `json:"updated_at"`
	DeletedAt           gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID            uint           `gorm:"index:raports_school_year_idx;uniqueIndex:raports_unique_key" json:"school_id"`
	UserID              uint           `gorm:"index:raports_user_year_idx;uniqueIndex:raports_unique_key" json:"user_id"`
	ClassID             *uint          `gorm:"index" json:"class_id,omitempty"`
	SemesterID          *uint          `gorm:"index" json:"semester_id,omitempty"`
	AcademicYear        string         `gorm:"index:raports_school_year_idx;index:raports_user_year_idx;uniqueIndex:raports_unique_key" json:"academic_year"`
	Semester            string         `gorm:"index:raports_school_year_idx;index:raports_user_year_idx;uniqueIndex:raports_unique_key" json:"semester"`
	Grade               string         `json:"grade"`
	TugasHarianScore    float64        `gorm:"type:decimal(5,2);default:0" json:"tugas_harian_score"`
	UlanganHarianScore  float64        `gorm:"type:decimal(5,2);default:0" json:"ulangan_harian_score"`
	TugasBesarScore     float64        `gorm:"type:decimal(5,2);default:0" json:"tugas_besar_score"`
	UtsScore            float64        `gorm:"type:decimal(5,2);default:0" json:"uts_score"`
	UasScore            float64        `gorm:"type:decimal(5,2);default:0" json:"uas_score"`
	UnScore             float64        `gorm:"type:decimal(5,2);default:0" json:"un_score"`
	LainnyaScore        float64        `gorm:"type:decimal(5,2);default:0" json:"lainnya_score"`
	CalculatedScore     float64        `gorm:"type:decimal(5,2);default:0" json:"calculated_score"`
	FinalScore          float64        `gorm:"type:decimal(5,2);default:0" json:"final_score"`
	OverallScore        float64        `gorm:"type:decimal(5,2);default:0" json:"overall_score"`
	OverallGrade        string         `gorm:"default:E" json:"overall_grade"`
	OverallPassed       bool           `gorm:"default:false" json:"overall_passed"`
	IsEdited            bool           `gorm:"default:false" json:"is_edited"`
	EditNotes           *string        `gorm:"type:text" json:"edit_notes,omitempty"`
	ExamTypePercentages datatypes.JSON `gorm:"type:json" json:"exam_type_percentages,omitempty"`
	ExamScoresBreakdown datatypes.JSON `gorm:"type:json" json:"exam_scores_breakdown,omitempty"`
	GradeThresholds     datatypes.JSON `gorm:"type:json" json:"grade_thresholds,omitempty"`
	SubjectsData        datatypes.JSON `gorm:"type:json" json:"subjects_data,omitempty"`
	Status              string         `gorm:"default:draft" json:"status"`
	IsPassed            bool           `gorm:"default:false" json:"is_passed"`
	GeneratedAt         *time.Time     `json:"generated_at,omitempty"`
	PublishedAt         *time.Time     `json:"published_at,omitempty"`
	Data                datatypes.JSON `gorm:"type:json" json:"data,omitempty"`
}

func (Raport) TableName() string { return "raports" }

type SubjectOrder struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	SchoolID  uint           `gorm:"index" json:"school_id"`
	SubjectID uint           `gorm:"index" json:"subject_id"`
	Order     int            `json:"order"`
}

func (SubjectOrder) TableName() string { return "subject_orders" }

type StudentAnswerRecap struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	ExamResultID uint           `gorm:"index" json:"exam_result_id"`
	UserID       uint           `gorm:"index" json:"user_id"`
	Payload      datatypes.JSON `gorm:"type:json" json:"payload,omitempty"`
}

func (StudentAnswerRecap) TableName() string { return "student_answer_recaps" }

type ContactDemoRequest struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	Name      string         `json:"name"`
	Email     string         `json:"email"`
	Phone     *string        `json:"phone,omitempty"`
	School    *string        `json:"school,omitempty"`
	Message   *string        `gorm:"type:text" json:"message,omitempty"`
}

func (ContactDemoRequest) TableName() string { return "contact_demo_requests" }

type Ad struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	Title     string         `json:"title"`
	Body      *string        `gorm:"type:text" json:"body,omitempty"`
	Image     *string        `json:"image,omitempty"`
	IsActive  bool           `gorm:"default:true" json:"is_active"`
}

func (Ad) TableName() string { return "ads" }

type PasswordReset struct {
	Email     string    `gorm:"primaryKey" json:"email"`
	Token     string    `json:"token"`
	CreatedAt time.Time `json:"created_at"`
}

func (PasswordReset) TableName() string { return "password_resets" }

type FailedJob struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UUID       string    `gorm:"uniqueIndex" json:"uuid"`
	Connection string    `json:"connection"`
	Queue      string    `json:"queue"`
	Payload    string    `gorm:"type:longtext" json:"payload"`
	Exception  string    `gorm:"type:longtext" json:"exception"`
	FailedAt   time.Time `json:"failed_at"`
}

func (FailedJob) TableName() string { return "failed_jobs" }

type PersonalAccessToken struct {
	ID            uint           `gorm:"primaryKey" json:"id"`
	TokenableType string         `json:"tokenable_type"`
	TokenableID   uint           `gorm:"index" json:"tokenable_id"`
	Name          string         `json:"name"`
	Token         string         `gorm:"uniqueIndex" json:"token"`
	Abilities     datatypes.JSON `gorm:"type:json" json:"abilities,omitempty"`
	LastUsedAt    *time.Time     `json:"last_used_at,omitempty"`
	ExpiresAt     *time.Time     `json:"expires_at,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
}

func (PersonalAccessToken) TableName() string { return "personal_access_tokens" }

type PotentialCustomer struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	Name      string         `json:"name"`
	Phone     *string        `json:"phone,omitempty"`
	Email     *string        `json:"email,omitempty"`
	Source    *string        `json:"source,omitempty"`
	Notes     *string        `gorm:"type:text" json:"notes,omitempty"`
}

func (PotentialCustomer) TableName() string { return "potential_customers" }

type WaSendLog struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	Phone     string         `json:"phone"`
	Message   string         `gorm:"type:text" json:"message"`
	Status    string         `json:"status"`
	Response  *string        `gorm:"type:text" json:"response,omitempty"`
}

func (WaSendLog) TableName() string { return "wa_send_logs" }

type MessageTemplate struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	Name      string         `json:"name"`
	Category  *string        `json:"category,omitempty"`
	Content   string         `gorm:"type:text" json:"content"`
	IsActive  bool           `gorm:"default:true" json:"is_active"`
}

func (MessageTemplate) TableName() string { return "message_templates" }

type BotOwner struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	UserID    *uint          `gorm:"index" json:"user_id,omitempty"`
	Phone     string         `json:"phone"`
	Role      *string        `json:"role,omitempty"`
}

func (BotOwner) TableName() string { return "bot_owners" }

type PendingMessage struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	Phone     string         `json:"phone"`
	Message   string         `gorm:"type:text" json:"message"`
	Status    string         `json:"status"`
}

func (PendingMessage) TableName() string { return "pending_messages" }

type BotConfig struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	ConfigKey string         `gorm:"uniqueIndex" json:"config_key"`
	ConfigVal *string        `gorm:"type:text" json:"config_val,omitempty"`
}

func (BotConfig) TableName() string { return "bot_config" }

func AutoMigrateModels() []any {
	return []any{
		&School{},
		&ClassRoom{},
		&User{},
		&Subject{},
		&QuestionPackage{},
		&Question{},
		&Exam{},
		&ExamAssignment{},
		&ExamAttemptConfig{},
		&ExamResult{},
		&ExamResultTempAnswer{},
		&PgAnswer{},
		&StudentAnswer{},
		&StudentAnswerRecap{},
		&SchoolAbsent{},
		&UserAbsent{},
		&SchoolTask{},
		&SchoolTaskAssignment{},
		&StudentSchoolTask{},
		&TutorAssignment{},
		&Referral{},
		&UserCreditTransaction{},
		&Semester{},
		&ReportConfig{},
		&Raport{},
		&SubjectOrder{},
		&ContactDemoRequest{},
		&Ad{},
		&PasswordReset{},
		&FailedJob{},
		&PersonalAccessToken{},
		&PotentialCustomer{},
		&WaSendLog{},
		&MessageTemplate{},
		&BotOwner{},
		&PendingMessage{},
		&BotConfig{},
	}
}
