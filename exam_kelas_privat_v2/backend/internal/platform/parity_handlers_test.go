package platform

import "testing"

func TestGradeFromScore(t *testing.T) {
	tests := []struct {
		score float64
		want  string
	}{
		{95, "A"},
		{85, "B"},
		{75, "C"},
		{65, "D"},
		{59, "E"},
	}

	for _, tt := range tests {
		if got := gradeFromScore(tt.score); got != tt.want {
			t.Fatalf("gradeFromScore(%v) = %s, want %s", tt.score, got, tt.want)
		}
	}
}

func TestLaravelSchemaContractIncludesCriticalParityColumns(t *testing.T) {
	required := map[string][]string{
		"users":                {"slug", "is_coachmark_showing"},
		"schools":              {"slug", "subscription_type", "token_balance"},
		"exam_results":         {"slug", "proctor_snapshots"},
		"exam_attempt_configs": {"exam_assignment_id", "for_attempt_number", "mode"},
		"report_configs":       {"config_type", "key", "metadata"},
	}

	for table, columns := range required {
		available := make(map[string]struct{})
		for _, column := range laravelRequiredColumns[table] {
			available[column] = struct{}{}
		}
		for _, column := range columns {
			if _, ok := available[column]; !ok {
				t.Fatalf("schema contract missing %s.%s", table, column)
			}
		}
	}
}
