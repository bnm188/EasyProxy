package api

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// ---------------- 只读端点（P0 迁移） ----------------

func (s *Server) handleClashProxies(w http.ResponseWriter, r *http.Request) {
	raw, err := s.clashGet("/proxies", 8*time.Second)
	if err != nil {
		fail(w, "Clash API 不可用（引擎可能未运行）")
		return
	}
	ok(w, map[string]interface{}{"data": json.RawMessage(raw)})
}

func (s *Server) handleClashConns(w http.ResponseWriter, r *http.Request) {
	raw, err := s.clashGet("/connections", 8*time.Second)
	if err != nil {
		fail(w, "Clash API 不可用（引擎可能未运行）")
		return
	}
	ok(w, map[string]interface{}{"data": json.RawMessage(raw)})
}

func (s *Server) handleConn(w http.ResponseWriter, r *http.Request) {
	c, _ := s.Cli.Run("connections", "--json")
	c = strings.TrimSpace(c)
	if !json.Valid([]byte(c)) || c == "" {
		c = `{"connections":[]}`
	}
	ok(w, map[string]interface{}{"data": json.RawMessage(c)})
}

func (s *Server) handleNodes(w http.ResponseWriter, r *http.Request) {
	n, _ := s.Cli.Run("node", "list", "--json")
	n = strings.TrimSpace(n)
	if !json.Valid([]byte(n)) || n == "" {
		fail(w, "node list 调用失败")
		return
	}
	ok(w, map[string]interface{}{"data": json.RawMessage(n)})
}

func (s *Server) handleGroup(w http.ResponseWriter, r *http.Request) {
	g, _ := s.Cli.Run("group", "list", "--json")
	g = strings.TrimSpace(g)
	if !json.Valid([]byte(g)) || g == "" {
		fail(w, "group list 调用失败")
		return
	}
	ok(w, map[string]interface{}{"data": json.RawMessage(g)})
}

// policy-list CLI 输出的就是完整响应体，与 api.sh 一样直接透传。
func (s *Server) handlePolicyList(w http.ResponseWriter, r *http.Request) {
	p, _ := s.Cli.Run("policy", "list", "--json")
	p = strings.TrimSpace(p)
	if !json.Valid([]byte(p)) || p == "" {
		fail(w, "policy list 调用失败")
		return
	}
	writeRaw(w, p)
}

func (s *Server) handlePolicyShow(w http.ResponseWriter, r *http.Request, body map[string]interface{}) {
	key := str(body, "key")
	if key == "" {
		fail(w, "缺少 key")
		return
	}
	out, _ := s.Cli.Run("policy", "show", key, "--json")
	out = strings.TrimSpace(out)
	if !json.Valid([]byte(out)) || out == "" {
		msg := compact(out)
		if msg == "" {
			msg = "policy show 失败"
		}
		fail(w, msg)
		return
	}
	writeRaw(w, out)
}

// logs 读面板/引擎日志尾部，默认 120 行，上限 400 行，与 api.sh 一致。
func (s *Server) handleLogs(w http.ResponseWriter, r *http.Request, body map[string]interface{}) {
	n := intParam(body, "lines", 120)
	if n <= 0 {
		n = 120
	}
	if n > 400 {
		n = 400
	}
	lines := tailLines("/var/log/easyproxy.log", n)
	if lines == nil {
		lines = []string{}
	}
	ok(w, map[string]interface{}{"lines": lines})
}

// probeTargets 五项探测：百度看直连、Google/YouTube/OpenAI/Telegram 看代理那几路。
var probeTargets = []struct {
	Name string
	URL  string
}{
	{"百度", "https://www.baidu.com"},
	{"Google", "https://www.google.com/generate_204"},
	{"YouTube", "https://www.youtube.com/generate_204"},
	{"OpenAI", "https://api.openai.com/v1/models"},
	{"Telegram", "https://api.telegram.org/"},
}

// sites 经本地混合代理端口并发探测，返回每项的状态、耗时与绿黄红分级。
func (s *Server) handleSites(w http.ResponseWriter, r *http.Request) {
	port := s.mixedPort()
	via := "mihomo " + port
	client := s.newProbeClient()

	results := make([]siteResult, len(probeTargets))
	var wg sync.WaitGroup
	for i, t := range probeTargets {
		wg.Add(1)
		go func(idx int, name, target string) {
			defer wg.Done()
			results[idx] = probeSite(name, target, client, via)
		}(i, t.Name, t.URL)
	}
	wg.Wait()

	summary := map[string]int{"green": 0, "yellow": 0, "red": 0}
	for _, v := range results {
		summary[v.Level]++
	}

	ok(w, map[string]interface{}{
		"mode":    "经 " + port + " 出口",
		"data":    results,
		"summary": summary,
	})
}

// dns 汇总 uci 配置与引擎上报的 dns_mode。
func (s *Server) handleDNS(w http.ResponseWriter, r *http.Request) {
	loc := dash(execText("uci", "get", "easyproxy.routing.dns_local_server"))
	rem := dash(execText("uci", "get", "easyproxy.routing.dns_remote_server"))
	rsd := dash(execText("uci", "get", "easyproxy.routing.rule_set_dir"))

	dmode := "—"
	if st, err := s.Cli.Run("status", "--json"); err == nil && json.Valid([]byte(st)) {
		var m map[string]interface{}
		if json.Unmarshal([]byte(st), &m) == nil {
			if v, okv := m["dns_mode"].(string); okv && v != "" {
				dmode = v
			}
		}
	}

	ok(w, map[string]interface{}{
		"data": map[string]interface{}{
			"dns_local":   loc,
			"dns_remote":  rem,
			"dns_mode":    dmode,
			"fakeip":      "未启用",
			"cache":       1,
			"ruleset_dir": rsd,
		},
	})
}

// engines 列出三个引擎的二进制路径与是否可执行。
func (s *Server) handleEngines(w http.ResponseWriter, r *http.Request) {
	type engine struct {
		Name      string `json:"name"`
		Binary    string `json:"binary"`
		Installed int    `json:"installed"`
	}
	defs := []struct{ name, key string }{
		{"sing-box", "sing_box"},
		{"mihomo", "mihomo"},
		{"dae", "dae"},
	}
	out := make([]engine, 0, len(defs))
	for _, d := range defs {
		bin := strings.TrimSpace(execText("uci", "get", "easyproxy."+d.key+".binary"))
		installed := 0
		if bin != "" && isExecutable(bin) {
			installed = 1
		}
		out = append(out, engine{Name: d.name, Binary: bin, Installed: installed})
	}
	ok(w, map[string]interface{}{"data": out})
}

// ---------------- 小工具 ----------------

func dash(s string) string {
	s = strings.TrimSpace(s)
	if s == "" || strings.Contains(s, "not found") {
		return "—"
	}
	return s
}

func isExecutable(path string) bool {
	st, err := os.Stat(path)
	if err != nil {
		return false
	}
	return st.Mode()&0o111 != 0
}

func intParam(body map[string]interface{}, key string, def int) int {
	if v, okv := body[key]; okv {
		switch t := v.(type) {
		case float64:
			return int(t)
		case string:
			n := 0
			for _, c := range t {
				if c < '0' || c > '9' {
					return def
				}
				n = n*10 + int(c-'0')
			}
			if n == 0 {
				return def
			}
			return n
		}
	}
	return def
}

// tailLines 从文件尾部取最后 n 行；文件不存在返回 nil。
func tailLines(path string, n int) []string {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	raw := strings.Split(strings.ReplaceAll(string(b), "\r\n", "\n"), "\n")
	// 去掉末尾空行
	for len(raw) > 0 && strings.TrimSpace(raw[len(raw)-1]) == "" {
		raw = raw[:len(raw)-1]
	}
	if len(raw) <= n {
		return raw
	}
	return raw[len(raw)-n:]
}
