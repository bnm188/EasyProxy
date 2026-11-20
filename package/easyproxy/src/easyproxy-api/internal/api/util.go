package api

import (
	"context"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// execText 执行外部命令（uci 等），返回拼接后的输出；失败也返回已有输出，
// 由调用方判断 "not found" 之类文案。
func execText(name string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, _ := exec.CommandContext(ctx, name, args...).CombinedOutput()
	return strings.TrimSpace(string(out))
}

func itoa64(v int64) string {
	return strconv.FormatInt(v, 10)
}

// writeRaw 直接写出已经校验过的 JSON 文本（CLI 输出的完整响应体）。
func writeRaw(w http.ResponseWriter, body string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	_, _ = w.Write([]byte(body + "\n"))
}
