package config

import "os"

// 运行期可覆盖的路径与参数：OpenWrt 上用默认值，本地联调用环境变量指过去。
var (
	// WebRoot 前端静态文件根目录
	WebRoot = env("EP_WEBROOT", "/www/easyproxy")
	// PasswordFile 面板密码哈希文件（sha256 十六进制）
	PasswordFile = env("EP_PWFILE", "/etc/easyproxy/panel.pw")
	// SessionFile 会话表，每行 "token 过期时间戳"
	SessionFile = env("EP_SESSFILE", "/tmp/easyproxy-sessions")
	// CliPath easyproxy CLI，所有数据读写都走它，保证与 shell 实现行为一致
	CliPath = env("EP_CLI", "/usr/sbin/easyproxy")
	// ListenAddr 面板监听地址
	ListenAddr = env("EP_LISTEN", "0.0.0.0:8090")
	// LogPath 服务日志
	LogPath = env("EP_LOG", "/var/log/easyproxy-api.log")

	CookieName  = "ep_sess"
	SessionTTL  = int64(7 * 24 * 3600)
	MaxBodySize = int64(1 << 20)
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
