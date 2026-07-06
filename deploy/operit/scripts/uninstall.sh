#!/usr/bin/env bash
# 卸载 new-api（含数据，不可恢复）
set -euo pipefail

APP_DIR=/opt/new-api

if [ "$(id -u)" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo "将完全删除 $APP_DIR 及其下所有数据，不可恢复。"
read -rp "确认卸载？请输入 YES 继续: " ans
if [ "$ans" != "YES" ]; then
  echo "已取消"
  exit 0
fi

read -rp "是否先备份到 /sdcard/new-api-backup-$(date +%F)？[y/N] " bk
if [ "$bk" = "y" ] || [ "$bk" = "Y" ]; then
  BK="/sdcard/new-api-backup-$(date +%F)"
  mkdir -p "$BK"
  cp -a "$APP_DIR/data/." "$BK/" 2>/dev/null || true
  echo "已备份到 $BK"
fi

# 停止进程
if [ -x "$APP_DIR/scripts/stop.sh" ]; then
  "$APP_DIR/scripts/stop.sh" 2>/dev/null || true
fi

rm -rf "$APP_DIR"
echo "==> 已卸载: $APP_DIR"
echo "    （Magisk/Operit 工作流自启任务需手动关闭）"
