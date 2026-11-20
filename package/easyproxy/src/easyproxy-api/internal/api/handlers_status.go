package api

import (
	"encoding/json"
	"net/http"

	"easyproxy-api/internal/sysinfo"
)

// handleStatus 运行状态：CLI 的 status --json 原样透传，再补 CPU/内存/uptime，
// 结构与 api.sh 的 status 分支完全一致。
func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	raw, err := s.Cli.Run("status", "--json")
	if err != nil && raw == "" {
		fail(w, "status 调用失败")
		return
	}
	if !json.Valid([]byte(raw)) {
		fail(w, "status 返回异常")
		return
	}
	ok(w, map[string]interface{}{
		"status": json.RawMessage(raw),
		"cpu":    sysinfo.CPU(),
		"mem":    sysinfo.Mem(),
		"uptime": sysinfo.Uptime(),
	})
}

// handleDiag 运行自检，返回 CLI 的纯文本输出。
func (s *Server) handleDiag(w http.ResponseWriter, r *http.Request) {
	out, _ := s.Cli.Run("doctor")
	if out == "" {
		out = "（无输出）"
	}
	ok(w, map[string]interface{}{"text": compact(out)})
}

func compact(s string) string {
	out := make([]rune, 0, len(s))
	prevNL := false
	for _, c := range s {
		if c == '\n' || c == '\r' {
			if prevNL {
				continue
			}
			out = append(out, ' ')
			prevNL = true
			continue
		}
		prevNL = false
		out = append(out, c)
	}
	return string(out)
}
