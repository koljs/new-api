#!/usr/bin/env bash
# 升级 new-api 二进制
# 用法: update.sh <path-to-new-binary>
set -euo pipefail

APP_DIR=/opt/new-api
NEW_BIN="${1:-}"

if [ -z "$NEW_BIN" ]; then
  echo "usage: $0 <path-to-new-binary>"
  echo "  例: $0 ~/new-api-android-arm64"
  exit 1
fi
if [ ! -f "$NEW_BIN" ]; then
  echo "ERROR: 文件不存在: $NEW_BIN"
  exit 1
fi

echo "==> 停止旧进程 ..."
/opt/new-api/scripts/stop.sh

# 备份当前二进制
if [ -f "$APP_DIR/bin/new-api" ]; then
  cp -a "$APP_DIR/bin/new-api" "$APP_DIR/bin/new-api.bak"
  echo "    旧版本已备份为 new-api.bak"
fi

echo "==> 安装新二进制 ..."
install -m 0755 "$NEW_BIN" "$APP_DIR/bin/new-api"

echo "==> 启动 ..."
/opt/new-api/scripts/start.sh

sleep 2
echo ""
echo "==> 升级完成"
echo "    版本信息:"
/opt/new-api/bin/new-api --version 2>&1 | head -n 5 || true
