package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime/debug"
	"syscall"
	"time"

	"easyproxy-api/internal/api"
	"easyproxy-api/internal/cli"
	"easyproxy-api/internal/config"
	"easyproxy-api/internal/session"
	"easyproxy-api/internal/web"
)

func main() {
	addr := flag.String("listen", config.ListenAddr, "监听地址，默认 0.0.0.0:8090")
	root := flag.String("web", config.WebRoot, "前端静态目录")
	pw := flag.String("pwfile", config.PasswordFile, "密码哈希文件")
	sess := flag.String("sessfile", config.SessionFile, "会话文件")
	bin := flag.String("cli", config.CliPath, "easyproxy CLI 路径")
	logPath := flag.String("log", config.LogPath, "日志文件")
	flag.Parse()

	// 内存上限：路由器上必须锁住，常驻目标 12–20MB
	debug.SetMemoryLimit(24 << 20)
	debug.SetGCPercent(60)

	closeLog := setupLog(*logPath)
	defer closeLog()

	store := session.New(*pw, *sess, config.SessionTTL)
	runner := cli.New(*bin)
	srv := api.New(store, runner)

	h := srv.Handler(web.Handler(*root))
	httpSrv := &http.Server{
		Addr:              *addr,
		Handler:           h,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	log.Printf("easyproxy-api 启动，监听 %s，前端 %s", *addr, *root)

	errCh := make(chan error, 1)
	go func() {
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-errCh:
		log.Printf("监听失败：%v", err)
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	case <-stop:
		log.Printf("收到退出信号，正在关闭")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(ctx)
}

// setupLog 日志写到文件，失败则退回标准输出；返回关闭函数。
func setupLog(path string) func() {
	if path == "" {
		return func() {}
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		log.SetOutput(os.Stderr)
		return func() {}
	}
	log.SetOutput(io.MultiWriter(os.Stderr, f))
	return func() { _ = f.Close() }
}
