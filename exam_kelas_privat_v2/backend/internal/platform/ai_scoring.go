package platform

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gorm.io/gorm"
)

type aiScoreResult struct {
	Score int
	Model string
}

func (s *Server) buildScoringPrompt(question, studentAnswer, correctAnswer, studentClass string, maxScore int) string {
	if strings.TrimSpace(studentClass) == "" {
		studentClass = "Unknown"
	}
	return fmt.Sprintf(`Anda adalah seorang guru yang ahli dalam menilai jawaban essay siswa.

SOAL: %s

JAWABAN YANG BENAR: %s

JAWABAN SISWA: %s

KELAS SISWA: %s

TUGAS: Berikan skor untuk jawaban siswa berdasarkan:
1. Akurasi konten (kesesuaian dengan jawaban yang benar)
2. Kelengkapan jawaban
3. Kualitas bahasa dan struktur
4. Tingkat kesulitan sesuai kelas %s

RANGE SKOR: 0 - %d

Berikan hanya angka skor (contoh: 3.5) tanpa penjelasan tambahan.`, question, correctAnswer, studentAnswer, studentClass, studentClass, maxScore)
}

func (s *Server) scoreEssayWithAI(answer StudentAnswer) (*aiScoreResult, error) {
	var question Question
	if err := s.DB.First(&question, answer.QuestionID).Error; err != nil {
		return nil, err
	}
	var student User
	_ = s.DB.Preload("ClassRoom").First(&student, answer.UserID).Error

	maxScore := question.Points
	if maxScore <= 0 {
		maxScore = answer.MaxPoints
	}
	if maxScore <= 0 {
		maxScore = 1
	}

	className := "Unknown"
	if student.ClassRoom != nil {
		className = student.ClassRoom.Name
	}
	prompt := s.buildScoringPrompt(question.QuestionText, answer.AnswerValue, derefString(question.EssayAnswer), className, maxScore)

	if result, err := s.scoreWithGemini(prompt, maxScore); err == nil && result != nil {
		return result, nil
	}
	if result, err := s.scoreWithGroq(prompt, maxScore); err == nil && result != nil {
		return result, nil
	}
	return nil, fmt.Errorf("AI scoring provider belum menghasilkan skor")
}

func (s *Server) scoreWithGemini(prompt string, maxScore int) (*aiScoreResult, error) {
	if strings.TrimSpace(s.Config.GeminiAPIKey) == "" {
		return nil, fmt.Errorf("Gemini API key kosong")
	}
	client := http.Client{Timeout: 30 * time.Second}
	for _, model := range s.Config.GeminiModels {
		payload := map[string]any{
			"contents": []map[string]any{{
				"parts": []map[string]string{{"text": prompt}},
			}},
			"generationConfig": map[string]any{"temperature": 0.1, "maxOutputTokens": 10},
		}
		raw, _ := json.Marshal(payload)
		url := strings.TrimRight(s.Config.GeminiBaseURL, "/") + "/models/" + model + ":generateContent"
		req, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("x-goog-api-key", s.Config.GeminiAPIKey)
		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			continue
		}
		score := extractAIScore(string(body), maxScore)
		if score != nil {
			return &aiScoreResult{Score: *score, Model: "gemini-" + model}, nil
		}
	}
	return nil, fmt.Errorf("Gemini gagal memberi skor")
}

func (s *Server) scoreWithGroq(prompt string, maxScore int) (*aiScoreResult, error) {
	if strings.TrimSpace(s.Config.GroqAPIKey) == "" {
		return nil, fmt.Errorf("Groq API key kosong")
	}
	client := http.Client{Timeout: 30 * time.Second}
	for _, model := range s.Config.GroqModels {
		payload := map[string]any{
			"model":       model,
			"temperature": 0.1,
			"max_tokens":  10,
			"messages": []map[string]string{
				{"role": "user", "content": prompt},
			},
		}
		raw, _ := json.Marshal(payload)
		req, _ := http.NewRequest(http.MethodPost, s.Config.GroqURL, bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+s.Config.GroqAPIKey)
		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			continue
		}
		score := extractAIScore(string(body), maxScore)
		if score != nil {
			return &aiScoreResult{Score: *score, Model: "groq-" + model}, nil
		}
	}
	return nil, fmt.Errorf("Groq gagal memberi skor")
}

func extractAIScore(text string, maxScore int) *int {
	re := regexp.MustCompile(`[-+]?\d+(\.\d+)?`)
	matches := re.FindAllString(text, -1)
	for _, match := range matches {
		value, err := strconv.ParseFloat(match, 64)
		if err != nil {
			continue
		}
		if value < 0 || value > float64(maxScore) {
			continue
		}
		score := int(math.Round(value))
		if score < 0 {
			score = 0
		}
		if score > maxScore {
			score = maxScore
		}
		return &score
	}
	return nil
}

func derefString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func (s *Server) applyAIScore(tx *gorm.DB, answer StudentAnswer, result *aiScoreResult) error {
	if result == nil {
		return fmt.Errorf("hasil AI kosong")
	}
	additionalData := map[string]any{}
	if len(answer.AdditionalData) > 0 {
		_ = json.Unmarshal(answer.AdditionalData, &additionalData)
	}
	audit, _ := additionalData["ai_scoring_audit"].([]any)
	audit = append(audit, map[string]any{
		"at":     time.Now().Format(time.RFC3339),
		"model":  result.Model,
		"score":  result.Score,
		"source": "admin_or_worker",
	})
	additionalData["ai_scoring_audit"] = audit
	if err := tx.Model(&StudentAnswer{}).Where("id = ? AND is_graded = ?", answer.ID, false).Updates(map[string]any{
		"is_ai_scheduler":    true,
		"is_graded":          true,
		"ai_score_suggested": result.Score,
		"ai_type":            result.Model,
		"score":              result.Score,
		"points_earned":      result.Score,
		"is_correct":         result.Score != 0,
		"additional_data":    upsertJSON(additionalData),
	}).Error; err != nil {
		return err
	}
	var exam Exam
	if err := tx.First(&exam, answer.ExamID).Error; err != nil {
		return err
	}
	var examResult ExamResult
	if err := tx.First(&examResult, answer.ExamResultID).Error; err != nil {
		return err
	}
	scoreData, err := s.calculateExamScore(tx, exam, &examResult)
	if err != nil {
		return err
	}
	return tx.Model(&ExamResult{}).Where("id = ?", answer.ExamResultID).Updates(map[string]any{
		"score":              scoreData["score"],
		"total_score":        scoreData["total_score"],
		"correct_answers":    scoreData["correct_answers"],
		"wrong_answers":      scoreData["wrong_answers"],
		"pg_score":           scoreData["pg_score"],
		"essay_score":        scoreData["essay_score"],
		"total_pg_points":    scoreData["total_pg_points"],
		"total_essay_points": scoreData["total_essay_points"],
	}).Error
}
