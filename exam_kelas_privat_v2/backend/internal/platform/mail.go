package platform

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"mime/multipart"
	"net/smtp"
	"net/textproto"
	"strings"
)

type mailAttachment struct {
	Filename    string
	ContentType string
	Data        []byte
}

func (s *Server) sendMail(to, subject, body string) error {
	return s.sendMailWithAttachments(to, subject, body, nil)
}

func (s *Server) sendMailWithAttachments(to, subject, body string, attachments []mailAttachment) error {
	to = strings.TrimSpace(to)
	if to == "" {
		return fmt.Errorf("email tujuan kosong")
	}
	if strings.TrimSpace(s.Config.SMTPHost) == "" {
		return fmt.Errorf("SMTP belum dikonfigurasi")
	}

	addr := s.Config.SMTPHost + ":" + s.Config.SMTPPort
	from := strings.TrimSpace(s.Config.SMTPFrom)
	if from == "" {
		from = s.Config.SMTPUsername
	}

	var auth smtp.Auth
	if s.Config.SMTPUsername != "" || s.Config.SMTPPassword != "" {
		auth = smtp.PlainAuth("", s.Config.SMTPUsername, s.Config.SMTPPassword, s.Config.SMTPHost)
	}

	if len(attachments) > 0 {
		var bodyBuf bytes.Buffer
		writer := multipart.NewWriter(&bodyBuf)
		textHeaders := textproto.MIMEHeader{}
		textHeaders.Set("Content-Type", "text/plain; charset=UTF-8")
		textPart, err := writer.CreatePart(textHeaders)
		if err != nil {
			return err
		}
		if _, err := textPart.Write([]byte(body)); err != nil {
			return err
		}
		for _, attachment := range attachments {
			filename := strings.TrimSpace(attachment.Filename)
			if filename == "" {
				filename = "attachment.bin"
			}
			contentType := strings.TrimSpace(attachment.ContentType)
			if contentType == "" {
				contentType = "application/octet-stream"
			}
			headers := textproto.MIMEHeader{}
			headers.Set("Content-Type", contentType)
			headers.Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, strings.ReplaceAll(filename, `"`, "")))
			headers.Set("Content-Transfer-Encoding", "base64")
			part, err := writer.CreatePart(headers)
			if err != nil {
				return err
			}
			encoded := base64.StdEncoding.EncodeToString(attachment.Data)
			for len(encoded) > 76 {
				if _, err := part.Write([]byte(encoded[:76] + "\r\n")); err != nil {
					return err
				}
				encoded = encoded[76:]
			}
			if _, err := part.Write([]byte(encoded + "\r\n")); err != nil {
				return err
			}
		}
		if err := writer.Close(); err != nil {
			return err
		}
		message := strings.Join([]string{
			"From: " + from,
			"To: " + to,
			"Subject: " + subject,
			"MIME-Version: 1.0",
			"Content-Type: multipart/mixed; boundary=" + writer.Boundary(),
			"",
			bodyBuf.String(),
		}, "\r\n")
		return smtp.SendMail(addr, auth, from, []string{to}, []byte(message))
	}

	message := strings.Join([]string{
		"From: " + from,
		"To: " + to,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
		"",
		body,
	}, "\r\n")

	return smtp.SendMail(addr, auth, from, []string{to}, []byte(message))
}

func (s *Server) sendPasswordResetEmail(to, token string) error {
	link := strings.TrimRight(s.Config.AppURL, "/") + "/reset-password?token=" + token + "&email=" + to
	body := "Halo,\n\nKlik link berikut untuk reset password Exam Kelas Privat:\n" + link + "\n\nJika Anda tidak meminta reset password, abaikan email ini."
	return s.sendMail(to, "Reset Password Exam Kelas Privat", body)
}

func (s *Server) sendAnswerSheetEmail(to string, ids []uint, attachments []mailAttachment) error {
	parts := make([]string, 0, len(ids))
	for _, id := range ids {
		parts = append(parts, fmt.Sprintf("#%d", id))
	}
	body := "Halo,\n\nPermintaan lembar jawaban untuk hasil ujian berikut sudah diterima:\n" + strings.Join(parts, ", ") + "\n\nPDF lembar jawaban terlampir di email ini."
	return s.sendMailWithAttachments(to, "Lembar Jawaban Exam Kelas Privat", body, attachments)
}
