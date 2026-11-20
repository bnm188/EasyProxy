package cli

import (
	"bytes"
	"context"
	"errors"
	"os/exec"
	"strings"
	"time"
)

// Runner 统一封装对 easyproxy CLI 的调用。
// 第一期所有数据读写都走它，行为与 api.sh 完全一致；第二期再把热点子命令改为直读 uci。
type Runner struct {
	Path    string
	Timeout time.Duration
}

func New(path string) *Runner {
	return &Runner{Path: path, Timeout: 30 * time.Second}
}

// Run 执行 CLI，返回标准输出（已去掉尾部空白）。
func (r *Runner) Run(args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), r.Timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, r.Path, args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	text := strings.TrimRight(out.String(), " \t\r\n")
	if err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return text, errors.New("命令超时")
		}
		if text == "" {
			return text, err
		}
	}
	return text, nil
}

// FirstLine 取输出首行，用于 version 这类单值查询。
func (r *Runner) FirstLine(args ...string) string {
	out, _ := r.Run(args...)
	if i := strings.IndexAny(out, "\r\n"); i >= 0 {
		out = out[:i]
	}
	return strings.TrimSpace(out)
}
