package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"strings"

	"easyproxy-api/internal/cli"
	"easyproxy-api/internal/session"
)

// Server 面板 API 服务：对外只暴露 /cgi-bin/api.sh 一个入口，
// 与旧 CGI 的 URL、参数、响应结构保持一致，前端无需改动。
type Server struct {
	Store *session.Store
	Cli   *cli.Runner
}

func New(store *session.Store, cliRunner *cli.Runner) *Server {
	return &Server{Store: store, Cli: cliRunner}
}

// Handler 组装路由：API 前缀 + 静态兜底。
func (s *Server) Handler(static http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/cgi-bin/api.sh", s.handleAPI)
	mux.Handle("/", static)
	return mux
}

func (s *Server) handleAPI(w http.ResponseWriter, r *http.Request) {
	cmd, body := parseRequest(r)

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	// 未登录也可用的命令
	switch cmd {
	case "state":
		s.handleState(w, r)
		return
	case "setup":
		s.handleSetup(w, r, body)
		return
	case "login":
		s.handleLogin(w, r, body)
		return
	case "logout":
		s.handleLogout(w, r)
		return
	case "":
		fail(w, "未知命令")
		return
	}

	// 以下全部需要有效会话
	if !s.Store.Valid(cookieToken(r)) {
		fail(w, "未登录或会话已失效")
		return
	}

	switch cmd {
	// 账号与系统
	case "passwd":
		s.handlePasswd(w, r, body)
	case "status":
		s.handleStatus(w, r)
	case "diag":
		s.handleDiag(w, r)

	// 只读端点
	case "clash-proxies":
		s.handleClashProxies(w, r)
	case "clash-conns":
		s.handleClashConns(w, r)
	case "conn":
		s.handleConn(w, r)
	case "nodes":
		s.handleNodes(w, r)
	case "group":
		s.handleGroup(w, r)
	case "policy-list":
		s.handlePolicyList(w, r)
	case "policy-show":
		s.handlePolicyShow(w, r, body)
	case "logs":
		s.handleLogs(w, r, body)
	case "sites":
		s.handleSites(w, r)
	case "dns":
		s.handleDNS(w, r)
	case "engines":
		s.handleEngines(w, r)

	default:
		fail(w, "命令尚未迁移："+cmd)
	}
}

// parseRequest 取 cmd：query 优先，其次请求体 JSON 的 cmd 字段（与 api.sh 顺序一致）。
func parseRequest(r *http.Request) (string, map[string]interface{}) {
	body := map[string]interface{}{}
	cmd := r.URL.Query().Get("cmd")

	if r.Method == http.MethodPost && r.Body != nil {
		dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
		_ = dec.Decode(&body)
		if cmd == "" {
			if v, ok := body["cmd"].(string); ok {
				cmd = v
			}
		}
	}
	return strings.TrimSpace(cmd), body
}

func cookieToken(r *http.Request) string {
	c, err := r.Cookie("ep_sess")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(c.Value)
}

// ---------------- 响应约定 ----------------
// 与 api.sh 一致：HTTP 恒定 200，业务成败看 ok 字段。

func writeJSON(w http.ResponseWriter, v interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	buf := &bytes.Buffer{}
	enc := json.NewEncoder(buf)
	// 与旧 CGI 的 jesc 对齐：不转义 < > &，保持日志等纯文本原样输出
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":false,"error":"响应编码失败"}`))
		return
	}
	_, _ = w.Write(buf.Bytes())
}

func ok(w http.ResponseWriter, fields map[string]interface{}) {
	out := map[string]interface{}{"ok": true}
	for k, v := range fields {
		out[k] = v
	}
	writeJSON(w, out)
}

func fail(w http.ResponseWriter, msg string) {
	writeJSON(w, map[string]interface{}{"ok": false, "error": msg})
}

func str(body map[string]interface{}, key string) string {
	if v, ok := body[key].(string); ok {
		return strings.TrimSpace(v)
	}
	return ""
}
