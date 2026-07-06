#!/usr/bin/env bash
# 启动 new-api（幂等：已运行则不重复拉起）
set -euo pipefail

APP_DIR=/opt/new-api
BIN="$APP_DIR/bin/new-api"
ENV_FILE="$APP_DIR/config/new-api.env"
PID_FILE="$APP_DIR/run/new-api.pid"
LOG_FILE="$APP_DIR/logs/supervisor.log"

# 二进制检查
if [ ! -x "$BIN" ]; then
  echo "ERROR: 二进制不存在或不可执行: $BIN"
  echo "请先放置二进制：install -m 0755 <path> $BIN"
  exit 1
fi

# 已运行检测
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "new-api already running, pid=$(cat "$PID_FILE")"
  exit 0
fi
rm -f "$PID_FILE"

# 加载环境变量
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: 配置文件不存在: $ENV_FILE"
  exit 1
fi
# shellcheck source=/opt/new-api/config/new-api.env
set -a; . "$ENV_FILE"; set +a

# 默认值
: "${PORT:=3000}"
: "${HOST:=0.0.0.0}"
: "${TZ:=Asia/Shanghai}"
: "${LOG_DIR:=$APP_DIR/data/logs}"

mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"

cd "$APP_DIR"
# setsid + nohup 让进程脱离当前 shell，chroot 关闭后仍可存活
setsid nohup "$BIN" >>"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
# 给二进制一点时间初始化并监听端口
sleep 2

# 检查进程是否还存活（若因端口占用/配置错误立即 crash，此处会捕获）
if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "started new-api, pid=$(cat "$PID_FILE"), listen=$HOST:$PORT"
  echo "log: $LOG_FILE"
else
  echo "ERROR: 启动失败，查看日志: $LOG_FILE"
  tail -n 30 "$LOG_FILE" || true
  rm -f "$PID_FILE"
  exit 1
fi
