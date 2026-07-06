#!/usr/bin/env bash
# 查看 new-api 运行状态
set -euo pipefail

APP_DIR=/opt/new-api
PID_FILE="$APP_DIR/run/new-api.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  PID="$(cat "$PID_FILE")"
  echo "running, pid=$PID"
  # 检查端口监听
  if command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | grep -E ":(3000|${PORT:-3000})\b" || true
  fi
  # CPU/内存
  ps -o pid,rss,%cpu,etime,cmd -p "$PID" 2>/dev/null || true
  exit 0
fi

echo "not running"
exit 1
