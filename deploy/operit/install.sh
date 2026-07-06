#!/usr/bin/env bash
# Operit Ubuntu chroot 一键安装脚本
# 用法：在 Operit Ubuntu 终端内执行
#   bash install.sh [path-to-new-api-binary]
#
# 若未提供二进制路径，则提示用户手动放置。

set -euo pipefail

APP_DIR=/opt/new-api
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 若不是 root，尝试 sudo
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo bash "$0" "$@"
  else
    echo "需要 root 权限执行"; exit 1
  fi
fi

echo "==> 创建目录结构 $APP_DIR"
mkdir -p "$APP_DIR"/{bin,config,data/logs,run,logs,scripts}

# 安装脚本
echo "==> 安装管理脚本到 $APP_DIR/scripts/"
cp -v "$SCRIPT_DIR/scripts/"*.sh "$APP_DIR/scripts/"
chmod +x "$APP_DIR/scripts/"*.sh

# 安装配置示例
if [ ! -f "$APP_DIR/config/new-api.env" ]; then
  cp -v "$SCRIPT_DIR/config/new-api.env.example" "$APP_DIR/config/new-api.env"
  chmod 600 "$APP_DIR/config/new-api.env"
  echo "    已生成配置文件 $APP_DIR/config/new-api.env"
  echo "    >>> 请编辑此文件，至少修改 SESSION_SECRET <<<"
else
  echo "    配置文件已存在，跳过"
fi

# 安装二进制
BIN_SRC="${1:-}"
if [ -n "$BIN_SRC" ] && [ -f "$BIN_SRC" ]; then
  install -m 0755 "$BIN_SRC" "$APP_DIR/bin/new-api"
  echo "==> 已安装二进制 $APP_DIR/bin/new-api"
else
  echo "==> 未提供二进制路径"
  echo "    请将编译好的 new-api-android-arm64 放到 $APP_DIR/bin/new-api"
  echo "    示例: install -m 0755 ~/new-api-arm64 $APP_DIR/bin/new-api"
fi

# 修正属主为当前调用 sudo 的用户
REAL_USER="${SUDO_USER:-root}"
chown -R "$REAL_USER":"$REAL_USER" "$APP_DIR" 2>/dev/null || true

cat <<EOF

==> 安装完成

  目录:     $APP_DIR
  二进制:   $APP_DIR/bin/new-api
  配置:     $APP_DIR/config/new-api.env
  数据:     $APP_DIR/data/
  脚本:     $APP_DIR/scripts/

下一步:
  1. 编辑配置:   nano $APP_DIR/config/new-api.env
  2. 启动:       $APP_DIR/scripts/start.sh
  3. 状态:       $APP_DIR/scripts/status.sh
  4. 访问:       http://127.0.0.1:3000  (默认 root/123456, 登录后立即改密)

EOF
