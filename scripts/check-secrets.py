#!/usr/bin/env python3
"""提交前敏感信息扫描。

拦住真正会泄露的东西：完整节点分享链接（host 不是文档保留网段）、
明文 method:password、真实邮箱账号、坚果云 WebDAV 地址。
放行语法说明与测试假数据（example.com / 10.0.0.0/8 / 198.51.100.x / 203.0.113.x / 192.0.2.x）。
"""
import os, re, subprocess, sys

LINK = re.compile(r'\b(?:ss|vmess|vless|trojan|hysteria2?|hy2)://([^@\s\'"<>]+)@([A-Za-z0-9.\-]+):(\d+)')
MAIL = re.compile(r'\b[0-9A-Za-z._%+\-]+@(qq|163|126|gmail|outlook|hotmail)\.com\b')
DAV = re.compile(r'jianguoyun\.com/dav/[A-Za-z]')
PLAINSS = re.compile(r'(aes-256-gcm|chacha20-ietf-poly1305|xchacha20-ietf-poly1305):([0-9a-zA-Z\-]{20,})')

RESERVED_HOST = re.compile(r'(^|\.)example\.com$|^localhost$')
RESERVED_NET = re.compile(r'^(10\.|127\.|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|1\.2\.3\.4$)')


def allowed_host(h):
    return bool(RESERVED_HOST.search(h) or RESERVED_NET.match(h))


def scan_line(line):
    out = []
    m = LINK.search(line)
    if m and not allowed_host(m.group(2)):
        out.append('完整节点分享链接 host=' + m.group(2))
    if MAIL.search(line):
        out.append('真实邮箱账号')
    if DAV.search(line):
        out.append('坚果云 WebDAV 地址')
    if PLAINSS.search(line):
        out.append('明文 method:password')
    return out


def main():
    files = sys.argv[1:]
    if not files:
        files = subprocess.run(['git', 'diff', '--cached', '--name-only', '--diff-filter=ACM'],
                               capture_output=True, text=True).stdout.split()
    hits = []
    for f in files:
        if not f or not os.path.isfile(f):
            continue
        try:
            with open(f, 'r', encoding='utf-8', errors='ignore') as fh:
                for i, line in enumerate(fh, 1):
                    for why in scan_line(line):
                        hits.append('%s:%d  %s' % (f, i, why))
        except OSError:
            continue
    if hits:
        sys.stderr.write('✗ 检测到疑似真实凭据，提交已阻断：\n')
        for h in hits:
            sys.stderr.write(h + '\n')
        sys.stderr.write('\n原型/文档里的节点示例请写成 ss://...@node.example.com:8388#示例节点JP\n')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
