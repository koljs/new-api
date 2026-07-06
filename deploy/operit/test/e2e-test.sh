#!/usr/bin/env bash
# 端到端测试 deploy/operit 全套脚本
# 用 mock 二进制模拟 new-api，避免等真实 go build
set -uo pipefail

TEST_PORT=3999
TEST_ROOT=/tmp/operit-e2e
MOCK_BIN="$TEST_ROOT/mock-new-api"
MOCK_V2="$TEST_ROOT/mock-new-api-v2"

# 清理上次残留（用端口精准定位，不用 pkill -f 避免自杀）
rm -rf "$TEST_ROOT" /opt/new-api /sdcard/new-api-backup
if command -v ss >/dev/null; then
  OLD_PID=$(ss -tlnp 2>/dev/null | grep ":$TEST_PORT " | grep -oP 'pid=\K[0-9]+' | head -1)
  [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 1
fi
mkdir -p "$TEST_ROOT" /sdcard

# mock 二进制 v1（纯 python 单进程，准确模拟 Go 单二进制）
cat > "$MOCK_BIN" <<'MOCK'
#!/usr/bin/env python3
import sys, os, json, socketserver, http.server
if '--version' in sys.argv:
    print('mock v1.0.0'); sys.exit(0)
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header('C','application/json'); self.end_headers()
        self.wfile.write(json.dumps({'data':{'version':'v1'}}).encode())
    def log_message(self,*a): pass
socketserver.TCPServer.allow_reuse_address=True
http.server.HTTPServer(('0.0.0.0', int(os.environ.get('PORT','3999'))), H).serve_forever()
MOCK
chmod +x "$MOCK_BIN"

# mock v2
cat > "$MOCK_V2" <<'MOCK'
#!/usr/bin/env python3
import sys, os, json, socketserver, http.server
if '--version' in sys.argv:
    print('mock v2.0.0-updated'); sys.exit(0)
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header('C','application/json'); self.end_headers()
        self.wfile.write(json.dumps({'data':{'version':'v2-updated'}}).encode())
    def log_message(self,*a): pass
socketserver.TCPServer.allow_reuse_address=True
http.server.HTTPServer(('0.0.0.0', int(os.environ.get('PORT','3999'))), H).serve_forever()
MOCK
chmod +x "$MOCK_V2"

cp -r /workspace/deploy/operit "$TEST_ROOT/deploy"

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILED=1; }
FAILED=0

echo "=== 1. install ==="
bash "$TEST_ROOT/deploy/install.sh" "$MOCK_BIN" >/dev/null 2>&1
[ -x /opt/new-api/bin/new-api ] && pass "二进制已安装" || fail "二进制未安装"
[ -f /opt/new-api/config/new-api.env ] && pass "配置已生成" || fail "配置未生成"
[ -x /opt/new-api/scripts/start.sh ] && pass "脚本已安装" || fail "脚本未安装"

echo ""
echo "=== 2. 改配置 ==="
sed -i 's/请改成你自己的32位以上随机字符串/test-secret-1234567890abcdef1234567890ab/' /opt/new-api/config/new-api.env
sed -i "s/^PORT=.*/PORT=$TEST_PORT/" /opt/new-api/config/new-api.env
grep "^PORT=" /opt/new-api/config/new-api.env | sed 's/^/  /'
grep "^SESSION_SECRET=" /opt/new-api/config/new-api.env | sed 's/^/  /'

echo ""
echo "=== 3. start ==="
/opt/new-api/scripts/start.sh 2>&1 | sed 's/^/  /'
sleep 1

echo ""
echo "=== 4. status ==="
/opt/new-api/scripts/status.sh 2>&1 | sed 's/^/  /'

echo ""
echo "=== 5. curl /api/status ==="
RESP=$(curl -sS http://127.0.0.1:$TEST_PORT/api/status 2>&1)
echo "  $RESP"
echo "$RESP" | grep -q "v1" && pass "curl 返回 v1" || fail "curl 失败"

echo ""
echo "=== 6. 幂等 start ==="
OUT=$(/opt/new-api/scripts/start.sh 2>&1)
echo "$OUT" | grep -q "already running" && pass "重复 start 被识别" || fail "幂等失败: $OUT"

echo ""
echo "=== 7. restart ==="
/opt/new-api/scripts/restart.sh 2>&1 | sed 's/^/  /'
sleep 1
RESP=$(curl -sS http://127.0.0.1:$TEST_PORT/api/status 2>&1)
echo "  restart 后 curl: $RESP"
echo "$RESP" | grep -q "v1" && pass "restart 后服务正常" || fail "restart 后服务异常"

echo ""
echo "=== 8. backup ==="
echo "log" > /opt/new-api/data/test.log
/opt/new-api/scripts/backup.sh 2>&1 | sed 's/^/  /'
[ -d /sdcard/new-api-backup ] && pass "备份目录已创建" || fail "备份目录未创建"
ls /sdcard/new-api-backup/*/test.log >/dev/null 2>&1 && pass "数据已备份" || fail "数据未备份"

echo ""
echo "=== 9. update ==="
/opt/new-api/scripts/update.sh "$MOCK_V2" 2>&1 | sed 's/^/  /'
sleep 1
VER=$(/opt/new-api/bin/new-api --version 2>&1)
echo "  --version: $VER"
[ "$VER" = "mock v2.0.0-updated" ] && pass "二进制已更新" || fail "版本未更新: $VER"
RESP=$(curl -sS http://127.0.0.1:$TEST_PORT/api/status 2>&1)
echo "$RESP" | grep -q "v2-updated" && pass "服务已用新版本运行" || fail "服务未切到新版本: $RESP"
[ -f /opt/new-api/bin/new-api.bak ] && pass "旧版本已备份" || fail "旧版本未备份"

echo ""
echo "=== 10. backup 保留 7 份 ==="
for i in $(seq 1 8); do
  mkdir -p "/sdcard/new-api-backup/2025010$i-0000"
  echo "old $i" > "/sdcard/new-api-backup/2025010$i-0000/marker"
done
BEFORE=$(ls -1d /sdcard/new-api-backup/*/ 2>/dev/null | wc -l)
/opt/new-api/scripts/backup.sh >/dev/null 2>&1
AFTER=$(ls -1d /sdcard/new-api-backup/*/ 2>/dev/null | wc -l)
echo "  清理前: $BEFORE, 清理后: $AFTER"
[ "$AFTER" -eq 7 ] && pass "保留 7 份" || fail "保留份数异常: $AFTER"

echo ""
echo "=== 11. stop ==="
/opt/new-api/scripts/stop.sh 2>&1 | sed 's/^/  /'
sleep 1
/opt/new-api/scripts/status.sh 2>&1 | sed 's/^/  /' && fail "stop 后仍 running" || pass "已停止"

echo ""
echo "=== 12. 幂等 stop ==="
OUT=$(/opt/new-api/scripts/stop.sh 2>&1)
echo "$OUT" | grep -q "not running" && pass "幂等 stop 正常" || fail "幂等 stop 失败: $OUT"

echo ""
echo "=== 13. uninstall ==="
echo "YES
n" | /opt/new-api/scripts/uninstall.sh 2>&1 | tail -2 | sed 's/^/  /'
[ -d /opt/new-api ] && fail "/opt/new-api 仍存在" || pass "/opt/new-api 已删除"

# 清理残留进程
if command -v ss >/dev/null; then
  P=$(ss -tlnp 2>/dev/null | grep ":$TEST_PORT " | grep -oP 'pid=\K[0-9]+' | head -1)
  [ -n "$P" ] && kill "$P" 2>/dev/null
fi
rm -rf "$TEST_ROOT" /sdcard/new-api-backup

echo ""
if [ "$FAILED" = "0" ]; then
  echo "========== ALL E2E TESTS PASSED =========="
else
  echo "========== SOME TESTS FAILED =========="
  exit 1
fi
