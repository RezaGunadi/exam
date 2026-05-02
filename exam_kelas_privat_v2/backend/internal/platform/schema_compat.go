package platform

import (
	"fmt"
	"strings"

	"gorm.io/gorm"
)

var laravelRequiredTables = []string{
	"users",
	"schools",
	"classes",
	"subjects",
	"question_packages",
	"questions",
	"exams",
	"exam_assignments",
	"exam_attempt_configs",
	"exam_results",
	"exam_result_temp_answers",
	"student_answers",
	"student_answer_recaps",
	"pg_answers",
	"report_configs",
	"raports",
	"subject_orders",
	"tutor_assignments",
	"school_tasks",
	"school_task_assignments",
	"student_school_tasks",
	"semesters",
	"school_absents",
	"user_absents",
	"referrals",
	"user_credit_transactions",
	"contact_demo_requests",
	"ads",
	"password_resets",
	"personal_access_tokens",
}

var laravelRequiredColumns = map[string][]string{
	"users": {
		"id", "name", "slug", "email", "password", "school_id", "role", "is_admin",
		"class_id", "token", "referral_token", "credit_balance", "is_coachmark_showing", "qr",
	},
	"schools": {
		"id", "name", "slug", "max_user", "total_user", "total_export", "max_total_export",
		"max_concurent_exam", "active_until", "last_paid", "subscription_type", "token_balance",
	},
	"questions":         {"id", "question_text", "slug", "options", "correct_answer", "essay_answer", "image", "video_url", "attachments", "created_by"},
	"question_packages": {"id", "name", "slug", "school_id", "subject_id", "total_questions"},
	"exams":             {"id", "title", "slug", "exam_type", "question_package_id", "start_time", "end_time", "duration", "status"},
	"exam_results": {
		"id", "slug", "exam_id", "user_id", "started_at", "completed_at", "status", "answers",
		"essay_scores", "cheating_note", "proctor_snapshots", "is_double_checker_running",
	},
	"exam_attempt_configs": {"id", "exam_assignment_id", "for_attempt_number", "mode", "custom_duration_minutes"},
	"raports": {
		"id", "school_id", "user_id", "class_id", "academic_year", "semester", "subjects_data",
		"overall_score", "overall_grade", "overall_passed", "status", "generated_at", "published_at",
	},
	"report_configs": {"id", "school_id", "config_type", "key", "value", "description", "metadata", "is_active"},
}

func ValidateLaravelSchema(db *gorm.DB) error {
	migrator := db.Migrator()
	var missing []string

	for _, table := range laravelRequiredTables {
		if !migrator.HasTable(table) {
			missing = append(missing, "table:"+table)
		}
	}

	for table, columns := range laravelRequiredColumns {
		if !migrator.HasTable(table) {
			continue
		}
		for _, column := range columns {
			if !migrator.HasColumn(table, column) {
				missing = append(missing, table+"."+column)
			}
		}
	}

	if len(missing) > 0 {
		return fmt.Errorf("schema DB belum kompatibel dengan migration Laravel: %s", strings.Join(missing, ", "))
	}
	return nil
}
