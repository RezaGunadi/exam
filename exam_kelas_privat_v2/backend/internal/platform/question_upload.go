package platform

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/go-chi/render"
	"github.com/google/uuid"
)

const maxQuestionImageBytes = 5 << 20
const maxQuestionAttachmentBytes = 20 << 20

var sniffToExt = map[string]string{
	"image/jpeg": ".jpg",
	"image/png":  ".png",
	"image/gif":  ".gif",
	"image/webp": ".webp",
}

func (s *Server) uploadPathFromPublicURL(publicPath string) (string, error) {
	publicPath = strings.TrimSpace(publicPath)
	if publicPath == "" {
		return "", nil
	}
	rel := strings.TrimPrefix(publicPath, "/api/files/")
	rel = strings.TrimPrefix(rel, "/")
	if rel == "" || strings.Contains(rel, "..") {
		return "", fmt.Errorf("path tidak valid")
	}
	base := filepath.Clean(s.Config.UploadDir)
	target := filepath.Clean(filepath.Join(base, filepath.FromSlash(rel)))
	relFromBase, err := filepath.Rel(base, target)
	if err != nil || strings.HasPrefix(relFromBase, "..") {
		return "", fmt.Errorf("path tidak valid")
	}
	return target, nil
}

func (s *Server) removeQuestionImageFile(publicPath *string) {
	if publicPath == nil || *publicPath == "" {
		return
	}
	fsPath, err := s.uploadPathFromPublicURL(*publicPath)
	if err != nil || fsPath == "" {
		return
	}
	_ = os.Remove(fsPath)
}

func (s *Server) handleUploadQuestionImage(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var q Question
	if err := s.DB.Where("id = ? AND school_id = ?", id, user.SchoolID).First(&q).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "soal tidak ditemukan"})
		return
	}
	if err := r.ParseMultipartForm(maxQuestionImageBytes + (1 << 20)); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "gagal membaca form upload"})
		return
	}
	file, _, err := r.FormFile("file")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "field file wajib diisi"})
		return
	}
	defer file.Close()

	buf := make([]byte, 512)
	n, err := file.Read(buf)
	if err != nil && err != io.EOF {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "gagal membaca file"})
		return
	}
	if _, err := file.Seek(0, 0); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memproses file"})
		return
	}
	ct := http.DetectContentType(buf[:n])
	ext, ok := sniffToExt[ct]
	if !ok {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "hanya gambar JPEG, PNG, GIF, atau WebP"})
		return
	}

	limited := io.LimitReader(file, maxQuestionImageBytes+1)
	dir := filepath.Join(s.Config.UploadDir, "questions", fmt.Sprintf("%d", user.SchoolID))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyiapkan penyimpanan"})
		return
	}
	filename := uuid.NewString() + ext
	fsPath := filepath.Join(dir, filename)
	out, err := os.Create(fsPath)
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyimpan file"})
		return
	}
	written, err := io.Copy(out, limited)
	out.Close()
	if err != nil {
		_ = os.Remove(fsPath)
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menulis file"})
		return
	}
	if written > maxQuestionImageBytes {
		_ = os.Remove(fsPath)
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "ukuran gambar maksimal 5 MB"})
		return
	}

	publicURL := fmt.Sprintf("/api/files/questions/%d/%s", user.SchoolID, filename)
	s.removeQuestionImageFile(q.Image)
	if err := s.DB.Model(&q).Update("image", publicURL).Error; err != nil {
		_ = os.Remove(fsPath)
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui soal"})
		return
	}

	render.JSON(w, r, map[string]any{
		"message": "gambar soal diunggah",
		"image":   publicURL,
		"item":    map[string]any{"id": q.ID, "image": publicURL},
	})
}

func (s *Server) handleClearQuestionImage(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var q Question
	if err := s.DB.Where("id = ? AND school_id = ?", id, user.SchoolID).First(&q).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "soal tidak ditemukan"})
		return
	}
	s.removeQuestionImageFile(q.Image)
	if err := s.DB.Model(&q).Update("image", nil).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menghapus gambar"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "gambar soal dihapus"})
}

func (s *Server) questionAttachments(q Question) []map[string]any {
	var attachments []map[string]any
	if len(q.Attachments) > 0 {
		_ = json.Unmarshal(q.Attachments, &attachments)
	}
	return attachments
}

func sanitizeUploadFilename(name string) string {
	name = filepath.Base(strings.TrimSpace(name))
	if name == "." || name == "/" || name == "\\" || name == "" {
		return "attachment"
	}
	replacer := strings.NewReplacer("/", "-", "\\", "-", ":", "-", "*", "-", "?", "-", `"`, "-", "<", "-", ">", "-", "|", "-")
	return replacer.Replace(name)
}

func (s *Server) handleUploadQuestionAttachment(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var q Question
	if err := s.DB.Where("id = ? AND school_id = ?", id, user.SchoolID).First(&q).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "soal tidak ditemukan"})
		return
	}
	if err := r.ParseMultipartForm(maxQuestionAttachmentBytes + (1 << 20)); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "gagal membaca form upload"})
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "field file wajib diisi"})
		return
	}
	defer file.Close()
	label := strings.TrimSpace(r.FormValue("label"))
	if label == "" {
		label = sanitizeUploadFilename(header.Filename)
	}
	dir := filepath.Join(s.Config.UploadDir, "questions", fmt.Sprintf("%d", user.SchoolID), "attachments")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyiapkan penyimpanan"})
		return
	}
	filename := uuid.NewString() + "-" + sanitizeUploadFilename(header.Filename)
	fsPath := filepath.Join(dir, filename)
	out, err := os.Create(fsPath)
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menyimpan file"})
		return
	}
	written, err := io.Copy(out, io.LimitReader(file, maxQuestionAttachmentBytes+1))
	out.Close()
	if err != nil {
		_ = os.Remove(fsPath)
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menulis file"})
		return
	}
	if written > maxQuestionAttachmentBytes {
		_ = os.Remove(fsPath)
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "ukuran lampiran maksimal 20 MB"})
		return
	}
	publicURL := fmt.Sprintf("/api/files/questions/%d/attachments/%s", user.SchoolID, filename)
	attachments := s.questionAttachments(q)
	item := map[string]any{"label": label, "url": publicURL, "filename": sanitizeUploadFilename(header.Filename), "size": written}
	attachments = append(attachments, item)
	if err := s.DB.Model(&q).Update("attachments", upsertJSON(attachments)).Error; err != nil {
		_ = os.Remove(fsPath)
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal memperbarui lampiran soal"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "lampiran soal diunggah", "attachment": item, "attachments": attachments})
}

func (s *Server) handleDeleteQuestionAttachment(w http.ResponseWriter, r *http.Request) {
	user := s.currentUser(r)
	id, err := pathUint(r, "id")
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "id tidak valid"})
		return
	}
	var payload struct {
		URL string `json:"url"`
	}
	if err := parseJSONBody(r, &payload); err != nil || strings.TrimSpace(payload.URL) == "" {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, map[string]any{"message": "url lampiran wajib diisi"})
		return
	}
	var q Question
	if err := s.DB.Where("id = ? AND school_id = ?", id, user.SchoolID).First(&q).Error; err != nil {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "soal tidak ditemukan"})
		return
	}
	attachments := s.questionAttachments(q)
	next := make([]map[string]any, 0, len(attachments))
	removed := false
	for _, item := range attachments {
		if fmt.Sprint(item["url"]) == payload.URL {
			removed = true
			continue
		}
		next = append(next, item)
	}
	if !removed {
		render.Status(r, http.StatusNotFound)
		render.JSON(w, r, map[string]any{"message": "lampiran tidak ditemukan"})
		return
	}
	if fsPath, err := s.uploadPathFromPublicURL(payload.URL); err == nil && fsPath != "" {
		_ = os.Remove(fsPath)
	}
	if err := s.DB.Model(&q).Update("attachments", upsertJSON(next)).Error; err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, map[string]any{"message": "gagal menghapus lampiran"})
		return
	}
	render.JSON(w, r, map[string]any{"message": "lampiran soal dihapus", "attachments": next})
}
