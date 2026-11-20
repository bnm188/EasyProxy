package api

import (
	"net/http"
	"os"
	"strings"

	"easyproxy-api/internal/config"
)

// handleState 面板启动时的状态探测：是否需要初始化密码、是否已登录。
func (s *Server) handleState(w http.ResponseWriter, r *http.Request) {
	needSetup := 0
	if !s.Store.HasPassword() {
		needSetup = 1
	}
	loggedIn := 0
	if s.Store.Valid(cookieToken(r)) {
		loggedIn = 1
	}
	ok(w, map[string]interface{}{
		"need_setup": needSetup,
		"logged_in":  loggedIn,
		"version":    s.version(),
		"host":       hostname(),
	})
}

// handleSetup 首次设置管理密码。
func (s *Server) handleSetup(w http.ResponseWriter, r *http.Request, body map[string]interface{}) {
	if s.Store.HasPassword() {
		fail(w, "已经设置过密码")
		return
	}
	pw := str(body, "password")
	if pw == "" {
		fail(w, "密码不能为空")
		return
	}
	if len([]rune(pw)) < 6 {
		fail(w, "密码至少 6 位")
		return
	}
	if err := s.Store.SetPassword(pw); err != nil {
		fail(w, "密码保存失败")
		return
	}
	s.issueCookie(w, r)
	ok(w, nil)
}

// handleLogin 校验密码并签发会话。
func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request, body map[string]interface{}) {
	if !s.Store.HasPassword() {
		fail(w, "尚未设置密码")
		return
	}
	pw := str(body, "password")
	if pw == "" {
		fail(w, "密码不能为空")
		return
	}
	if !s.Store.Check(pw) {
		fail(w, "密码错误")
		return
	}
	s.issueCookie(w, r)
	ok(w, nil)
}

// handleLogout 删除当前会话并清 cookie。
func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	_ = s.Store.Revoke(cookieToken(r))
	http.SetCookie(w, &http.Cookie{
		Name:     config.CookieName,
		Value:    "",
		Path:     "/",
		MaxAge:   0,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
	ok(w, nil)
}

// handlePasswd 修改密码：校验旧密码、写新哈希、清空所有会话。
func (s *Server) handlePasswd(w http.ResponseWriter, r *http.Request, body map[string]interface{}) {
	oldPw := str(body, "old")
	newPw := str(body, "new")
	if newPw == "" {
		fail(w, "新密码不能为空")
		return
	}
	if len([]rune(newPw)) < 6 {
		fail(w, "新密码至少 6 位")
		return
	}
	if !s.Store.Check(oldPw) {
		fail(w, "当前密码不正确")
		return
	}
	if err := s.Store.SetPassword(newPw); err != nil {
		fail(w, "密码保存失败")
		return
	}
	_ = s.Store.ClearAll()
	http.SetCookie(w, &http.Cookie{
		Name:     config.CookieName,
		Value:    "",
		Path:     "/",
		MaxAge:   0,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
	ok(w, nil)
}

func (s *Server) issueCookie(w http.ResponseWriter, r *http.Request) {
	tok, err := s.Store.Issue(clientIP(r))
	if err != nil {
		fail(w, "会话创建失败")
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name:     config.CookieName,
		Value:    tok,
		Path:     "/",
		MaxAge:   int(config.SessionTTL),
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

func (s *Server) version() string {
	v := s.Cli.FirstLine("version")
	if v == "" {
		return "unknown"
	}
	return v
}

func clientIP(r *http.Request) string {
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if i := strings.Index(fwd, ","); i > 0 {
			return strings.TrimSpace(fwd[:i])
		}
		return strings.TrimSpace(fwd)
	}
	if host, _, err := splitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

func splitHostPort(addr string) (string, string, error) {
	i := strings.LastIndex(addr, ":")
	if i < 0 {
		return addr, "", nil
	}
	return addr[:i], addr[i+1:], nil
}

func hostname() string {
	b, err := os.ReadFile("/proc/sys/kernel/hostname")
	if err != nil {
		return "—"
	}
	return strings.TrimSpace(string(b))
}
