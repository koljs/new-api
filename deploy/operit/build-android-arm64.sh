#!/usr/bin/env bash
# 本地交叉编译 Android arm64 二进制（用于 Operit Ubuntu chroot 部署）
#
# 用法：
#   ./deploy/operit/build-android-arm64.sh              # 用 git describe 作为版本号
#   ./deploy/operit/build-android-arm64.sh v1.2.3       # 指定版本号
#
# 产物：仓库根目录的 new-api-android-arm64
# 依赖：go >= 1.25.1, bun
#
# 注意：main.go 用 go:embed 同时嵌入 web/default/dist 和 web/classic/dist，
# 两个前端都必须构建，否则 go build 会因 embed 找不到文件而失败。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(git describe --tags 2>/dev/null || echo "dev-$(git rev-parse --short HEAD)")"
fi

echo "==> Repository: $REPO_ROOT"
echo "==> Version:    $VERSION"

# ---------- 前端 (default + classic 都必须构建, main.go 用 go:embed 嵌入两者) ----------
echo "==> [1/4] Building frontend (default)..."
(
  cd web
  bun install --frozen-lockfile
  cd default
  CI="" DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION="$VERSION" bun run build
)

echo "==> [2/4] Building frontend (classic)..."
(
  cd web
  bun install --filter ./classic --frozen-lockfile
  cd classic
  CI="" VITE_REACT_APP_VERSION="$VERSION" bun run build
)

# ---------- 后端 ----------
echo "==> [3/4] Building backend (linux/arm64, CGO disabled)..."
export GOOS=linux
export GOARCH=arm64
export CGO_ENABLED=0
# glebarez/sqlite 是纯 Go 实现,无需 CGO 和交叉编译器
go mod download
go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION'" \
  -o new-api-android-arm64

echo "==> [4/4] Verify..."
file new-api-android-arm64
ls -lh new-api-android-arm64
sha256sum new-api-android-arm64 | tee new-api-android-arm64.sha256

echo ""
echo "==> Done. Binary: $REPO_ROOT/new-api-android-arm64"
echo "==> Push to phone:"
echo "      adb push new-api-android-arm64 /sdcard/Download/"
echo "    Then in Operit Ubuntu terminal:"
echo "      install -m 0755 /sdcard/Download/new-api-android-arm64 /opt/new-api/bin/new-api"
