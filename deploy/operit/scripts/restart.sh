#!/usr/bin/env bash
# 重启 new-api
set -euo pipefail
/opt/new-api/scripts/stop.sh
# 等端口/句柄彻底释放，避免立即重启时 bind 失败
sleep 2
/opt/new-api/scripts/start.sh
