package api

import (
	"crypto/tls"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// clashBase 取 mihomo 控制接口地址；uci 没配就退回 127.0.0.1:9090。
// 与 api.sh 一致：配的是裸地址就补 http://，已带 http 前缀直接用。
func (s *Server) clashBase() string {
	c := execText("uci", "get", "easyproxy.mihomo.controller")
	c = strings.TrimSpace(c)
	if c == "" || strings.Contains(c, "not found") || strings.Contains(c, "Entry not found") {
		c = "127.0.0.1:9090"
	}
	if strings.HasPrefix(c, "http") {
		return strings.TrimRight(c, "/")
	}
	return "http://" + strings.TrimRight(c, "/")
}

// clashSecret 读 uci 里配置的控制接口密钥；没配或为空时返回空串。
// mihomo 开了 secret 就必须带 Authorization: Bearer，否则 401。
func (s *Server) clashSecret() string {
	v := strings.TrimSpace(execText("uci", "get", "easyproxy.mihomo.secret"))
	if strings.Contains(v, "not found") || strings.Contains(v, "Entry not found") {
		return ""
	}
	return v
}

// clashGet 调用 Clash 控制接口，返回原始 JSON 文本（与 api.sh 的透传口径一致）。
func (s *Server) clashGet(path string, timeout time.Duration) (string, error) {
	req, err := http.NewRequest(http.MethodGet, s.clashBase()+path, nil)
	if err != nil {
		return "", err
	}
	if sec := s.clashSecret(); sec != "" {
		req.Header.Set("Authorization", "Bearer "+sec)
	}
	client := &http.Client{Timeout: timeout}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return "", err
	}
	text := strings.TrimSpace(string(body))
	if text == "" || !strings.HasPrefix(text, "{") {
		return "", errors.New("Clash API 返回异常")
	}
	return text, nil
}

// mixedPort 取 mihomo 的混合代理端口；uci 没配就退回 7890。
// 探测必须走这个端口，测出来才是"经过代理"的数字。
func (s *Server) mixedPort() string {
	p := strings.TrimSpace(execText("uci", "get", "easyproxy.mihomo.mixed_port"))
	if p == "" || strings.Contains(p, "not found") || strings.Contains(p, "Entry not found") {
		p = "7890"
	}
	return p
}

// siteResult 单个站点的探测结果。level 为 green / yellow / red。
type siteResult struct {
	Name  string `json:"name"`
	Host  string `json:"host"`
	Code  string `json:"code"`
	Time  string `json:"time"`
	Ms    int64  `json:"ms"`
	Level string `json:"level"`
	Via   string `json:"via"`
}

// probeSite 经本地代理出口请求一个目标地址，返回状态码、耗时与分级。
// 判定：连不上（000）或超过 2s 记 red；≤800ms 记 green；其余 yellow。
// 4xx 也算"通"（OpenAI 未带 key 会返回 401，能连上就说明线路没问题）。
func probeSite(name, target string, client *http.Client, via string) siteResult {
	start := time.Now()
	resp, err := client.Get(target)
	code := "000"
	if err == nil {
		code = itoa64(int64(resp.StatusCode))
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<16))
		_ = resp.Body.Close()
	}
	ms := time.Since(start).Milliseconds()

	level := "red"
	if code != "000" {
		switch {
		case ms <= 800:
			level = "green"
		case ms <= 2000:
			level = "yellow"
		default:
			level = "red"
		}
	}

	host := target
	if u, e := url.Parse(target); e == nil && u.Host != "" {
		host = u.Host
	}

	return siteResult{
		Name:  name,
		Host:  host,
		Code:  code,
		Time:  itoa64(ms) + " ms",
		Ms:    ms,
		Level: level,
		Via:   via,
	}
}

// newProbeClient 生成走本地代理端口的 HTTP 客户端。
func (s *Server) newProbeClient() *http.Client {
	proxyURL, _ := url.Parse("http://127.0.0.1:" + s.mixedPort())
	return &http.Client{
		Timeout: 8 * time.Second,
		Transport: &http.Transport{
			Proxy:           http.ProxyURL(proxyURL),
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
			DialContext: (&net.Dialer{
				Timeout: 5 * time.Second,
			}).DialContext,
		},
	}
}
