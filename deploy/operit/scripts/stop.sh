#!/usr/bin/env bash
# 停止 new-api（先 SIGTERM，10 秒未退出则 SIGKILL）
set -euo pipefail

PID_FILE=/opt/new-api/run/new-api.pid
TIMEOUT=10

if [ ! -f "$PID_FILE" ]; then
  echo "not running (no pid file)"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if ! kill -0 "$PID" 2>/dev/null; then
  echo "not running (stale pid file)"
  rm -f "$PID_FILE"
  exit 0
fi

echo "stopping pid=$PID ..."
kill -TERM "$PID" 2>/dev/null || true

for _ in $(seq 1 "$TIMEOUT"); do
  if ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "stopped (term)"
    exit 0
  fi
  sleep 1
done

echo "force killing ..."
kill -KILL "$PID" 2>/dev/null || true
rm -f "$PID_FILE"
echo "stopped (kill)"
