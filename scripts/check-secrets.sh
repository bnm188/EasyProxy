#!/bin/sh
# 兼容入口：转发到 check-secrets.py
exec python3 "$(git rev-parse --show-toplevel)/scripts/check-secrets.py" "$@"
