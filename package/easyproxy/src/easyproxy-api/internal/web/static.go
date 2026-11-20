package web

import (
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// Handler 静态文件托管：从 root 目录提供前端文件，禁止目录穿越。
// 带 ?v= 的资源可长缓存（版本号变了 URL 就变），HTML 一律 no-cache。
func Handler(root string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		upath := r.URL.Path
		if !strings.HasPrefix(upath, "/") {
			upath = "/" + upath
		}
		clean := path.Clean(upath)
		if clean == "/" || clean == "" {
			clean = "/index.html"
		}
		// 只允许单层目录层级，拒绝 .. 与绝对跳转
		if strings.Contains(clean, "..") {
			http.NotFound(w, r)
			return
		}

		name := filepath.Join(root, filepath.FromSlash(clean))
		st, err := os.Stat(name)
		if err != nil || st.IsDir() {
			http.NotFound(w, r)
			return
		}

		// 条件请求：ETag 用大小+修改时间，省掉重复传输
		etag := `"` + itoa(st.Size()) + "-" + itoa(st.ModTime().UnixNano()) + `"`
		w.Header().Set("ETag", etag)
		if inm := r.Header.Get("If-None-Match"); inm != "" && inm == etag {
			w.WriteHeader(http.StatusNotModified)
			return
		}

		if hasVersionQuery(r) {
			w.Header().Set("Cache-Control", "public, max-age=86400")
		} else {
			w.Header().Set("Cache-Control", "no-cache")
		}
		w.Header().Set("X-Content-Type-Options", "nosniff")
		http.ServeFile(w, r, name)
	})
}

func hasVersionQuery(r *http.Request) bool {
	return r.URL.Query().Get("v") != ""
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
