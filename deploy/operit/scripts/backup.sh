#!/usr/bin/env bash
# 备份 new-api 数据到 Android /sdcard 用户存储（防 chroot 重置丢失）
set -euo pipefail

APP_DIR=/opt/new-api
BACKUP_ROOT=/sdcard/new-api-backup
TS="$(date +%Y%m%d-%H%M)"
DEST="$BACKUP_ROOT/$TS"
KEEP=7

if [ ! -d "$APP_DIR/data" ]; then
  echo "ERROR: 数据目录不存在: $APP_DIR/data"
  exit 1
fi

mkdir -p "$DEST"
echo "==> 备份到 $DEST"
cp -a "$APP_DIR/data/." "$DEST/"

# 仅保留最近 $KEEP 份（用 find 处理带特殊字符的目录名更安全）
find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | awk -v keep="$KEEP" 'NR>keep {sub(/^[^ ]+ /,""); print}' \
  | while IFS= read -r old; do
      echo "    清理旧备份: $old"
      rm -rf "${old:?}"
    done

echo "==> 完成"
du -sh "$DEST" 2>/dev/null || true
