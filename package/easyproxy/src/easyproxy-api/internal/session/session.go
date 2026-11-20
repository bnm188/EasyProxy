package session

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"strings"
	"sync"
	"time"
)

// Store 面板会话：密码哈希存盘、token 列表存文件，格式与 api.sh 完全一致，
// 两套实现可以互相读写同一个文件，切换后端不丢登录态。
type Store struct {
	PwPath   string
	SessPath string
	TTL      int64
	mu       sync.Mutex
}

func New(pwPath, sessPath string, ttl int64) *Store {
	return &Store{PwPath: pwPath, SessPath: sessPath, TTL: ttl}
}

// Hash 密码哈希：sha256 十六进制小写，与 shell 的 sha256sum 一致。
func Hash(pw string) string {
	sum := sha256.Sum256([]byte(pw))
	return hex.EncodeToString(sum[:])
}

// HasPassword 是否已经设置过管理密码。
func (s *Store) HasPassword() bool {
	st, err := os.Stat(s.PwPath)
	return err == nil && st.Size() > 0
}

// Check 校验明文密码。
func (s *Store) Check(pw string) bool {
	b, err := os.ReadFile(s.PwPath)
	if err != nil {
		return false
	}
	want := strings.TrimSpace(string(b))
	return want != "" && want == Hash(pw)
}

// SetPassword 写入新密码哈希，权限 600。
func (s *Store) SetPassword(pw string) error {
	if err := os.MkdirAll(dirOf(s.PwPath), 0o755); err != nil {
		return err
	}
	tmp := s.PwPath + ".tmp"
	if err := os.WriteFile(tmp, []byte(Hash(pw)+"\n"), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.PwPath)
}

// Issue 签发新会话，返回 token。
func (s *Store) Issue(remote string) (string, error) {
	now := time.Now().Unix()
	tok := issueToken(now, remote)
	s.mu.Lock()
	defer s.mu.Unlock()

	live, _ := s.readLines()
	live = filterAlive(live, now)

	f, err := os.OpenFile(s.SessPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return "", err
	}
	defer f.Close()
	for _, l := range live {
		if _, err := f.WriteString(l + "\n"); err != nil {
			return "", err
		}
	}
	if _, err := f.WriteString(tok + " " + itoa(now+s.TTL) + "\n"); err != nil {
		return "", err
	}
	return tok, nil
}

// Valid 校验 token 是否有效且未过期。
func (s *Store) Valid(tok string) bool {
	if tok == "" {
		return false
	}
	now := time.Now().Unix()
	s.mu.Lock()
	lines, _ := s.readLines()
	s.mu.Unlock()
	for _, l := range lines {
		parts := strings.Fields(l)
		if len(parts) != 2 || parts[0] != tok {
			continue
		}
		exp := atoi(parts[1])
		return exp > now
	}
	return false
}

// Revoke 退出登录：删掉该 token 行。
func (s *Store) Revoke(tok string) error {
	if tok == "" {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	lines, _ := s.readLines()
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		parts := strings.Fields(l)
		if len(parts) == 2 && parts[0] == tok {
			continue
		}
		out = append(out, l)
	}
	return s.writeLines(out)
}

// ClearAll 改密码时清空全部会话。
func (s *Store) ClearAll() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.writeLines(nil)
}

func (s *Store) readLines() ([]string, error) {
	b, err := os.ReadFile(s.SessPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	raw := strings.Split(strings.ReplaceAll(string(b), "\r\n", "\n"), "\n")
	out := make([]string, 0, len(raw))
	for _, l := range raw {
		if strings.TrimSpace(l) != "" {
			out = append(out, strings.TrimSpace(l))
		}
	}
	return out, nil
}

func (s *Store) writeLines(lines []string) error {
	var b strings.Builder
	for _, l := range lines {
		b.WriteString(l)
		b.WriteString("\n")
	}
	tmp := s.SessPath + ".tmp"
	if err := os.WriteFile(tmp, []byte(b.String()), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.SessPath)
}

func filterAlive(lines []string, now int64) []string {
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		parts := strings.Fields(l)
		if len(parts) != 2 {
			continue
		}
		if atoi(parts[1]) > now {
			out = append(out, l)
		}
	}
	return out
}

// issueToken 生成 40 字符 token；与 shell 版同为 sha256 前缀，只求唯一，不求同值。
func issueToken(now int64, remote string) string {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		buf = []byte(itoa(now))
	}
	sum := sha256.Sum256([]byte(itoa(now) + "|" + remote + "|" + hex.EncodeToString(buf)))
	return hex.EncodeToString(sum[:])[:40]
}

func dirOf(p string) string {
	if i := strings.LastIndex(p, "/"); i > 0 {
		return p[:i]
	}
	return "."
}

func itoa(v int64) string {
	if v == 0 {
		return "0"
	}
	neg := v < 0
	if neg {
		v = -v
	}
	var b []byte
	for v > 0 {
		b = append([]byte{byte('0' + v%10)}, b...)
		v /= 10
	}
	if neg {
		b = append([]byte{'-'}, b...)
	}
	return string(b)
}

func atoi(s string) int64 {
	var v int64
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0
		}
		v = v*10 + int64(c-'0')
	}
	return v
}
