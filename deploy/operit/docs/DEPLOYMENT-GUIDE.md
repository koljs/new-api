# new-api 部署到 Android (Operit) 完整指南

> **文档对象**：本地 AI agent（无前置对话上下文也可直接执行）
> **目标平台**：已 root 的 Android 手机，运行 Operit App（v1.12.0），使用其内置 Ubuntu 24 chroot 环境
> **部署对象**：[new-api](https://github.com/koljs/new-api) 项目（Go 后端 + 内嵌前端，单二进制）
> **最后验证**：GitHub Actions run #28809688357 全平台构建成功，产物 38.1MB arm64 二进制可运行

---

## 1. 部署架构概述

### 1.1 组件关系

```
Android 手机 (已 root)
  └── Operit App (v1.12.0, 已授 root)
      ├── 工作流引擎 (类 Tasker, 可触发 shell)
      └── 内置 Ubuntu 24 chroot 环境
          ├── /opt/new-api/          ← 部署根目录（所有文件集中此处）
          │   ├── bin/new-api        ← arm64 静态二进制
          │   ├── config/new-api.env ← 运行配置
          │   ├── data/               ← SQLite 库 + 日志（持久化）
          │   ├── run/new-api.pid    ← PID 文件
          │   ├── logs/supervisor.log ← 启动器日志
          │   └── scripts/*.sh       ← 生命周期管理脚本
          └── 监听 0.0.0.0:3000      ← 共享 Android 网络栈
```

### 1.2 关键设计决策

| 决策 | 原因 |
|---|---|
| 仅用 SQLite + 内存缓存 | 不在 chroot 装 MySQL/Redis，避免污染系统 |
| 所有文件集中 `/opt/new-api/` | 卸载只需 `rm -rf` 一个目录，不污染 `/usr/bin` `/etc` `/var` |
| `setsid + nohup` 启动 | 进程脱离 shell 会话，chroot 关闭后仍存活 |
| 幂等启动脚本 | 工作流可重复触发 `start.sh`，已运行则安全跳过 |
| 数据双保险 | 主数据在 chroot 内，定期备份到 `/sdcard` 防 chroot 重置丢失 |
| `CGO_ENABLED=0` 编译 | 项目用 `glebarez/sqlite`（纯 Go），无需交叉编译器，单二进制 |

---

## 2. 前置条件检查清单

执行部署前，逐项确认：

### 2.1 硬件/系统
- [ ] Android 手机已 root
- [ ] CPU 架构为 arm64-v8a（主流 64 位手机，2019 年后基本都是）
- [ ] 存储空间 ≥ 200MB（二进制 38MB + 数据增长空间）

### 2.2 软件环境
- [ ] 已安装 Operit App v1.12.0
- [ ] Operit 已授予 root 权限
- [ ] Operit 内置 Ubuntu 24 子系统已开启（设置 → 工具 → Ubuntu 子系统）
- [ ] Operit 已加入国产 ROM 电池优化白名单（关键，否则后台被杀）
  - MIUI/HyperOS：应用设置 → 应用管理 → Operit → 自启动:开；省电策略:无限制
  - ColorOS：电池 → 应用耗电管理 → Operit → 允许后台运行 + 允许自启
  - EMUI/鸿蒙：应用启动管理 → Operit → 手动管理 → 全开
  - 原生/Pixel：应用 → Operit → 电池 → 不受限

### 2.3 编译环境（二选一）
- [ ] **方式 A**：能访问 https://github.com/koljs/new-api/actions 的 GitHub 账号（workflow 手动触发）
- [ ] **方式 B**：本地有 Go ≥ 1.25.1 + Bun ≥ 1.2.x 的开发机

---

## 3. 仓库提供的资源清单

部署所需文件全部在仓库 `deploy/operit/` 目录下：

```
deploy/operit/
├── build-android-arm64.sh        # 本地交叉编译脚本
├── install.sh                    # 一键安装脚本（在 chroot 内执行）
├── config/
│   └── new-api.env.example       # 配置文件模板
├── scripts/
│   ├── start.sh                  # 启动（幂等）
│   ├── stop.sh                   # 停止（TERM→10s→KILL）
│   ├── restart.sh                # 重启
│   ├── status.sh                 # 状态查询
│   ├── update.sh                 # 升级二进制
│   ├── backup.sh                 # 备份到 /sdcard（保留 7 份）
│   └── uninstall.sh              # 卸载（含二次确认）
├── test/
│   └── e2e-test.sh               # 端到端测试（13 项，已全 PASS）
└── docs/
    ├── OPERIT-WORKFLOW-GUIDE.md  # Operit 工作流配置详细指引
    └── DEPLOYMENT-GUIDE.md       # 本文档
```

---

## 4. 部署步骤

### 阶段 A：获取 arm64 二进制（二选一）

#### A-1. 方式一：GitHub Actions 编译（推荐，无需本地环境）

1. 浏览器打开：https://github.com/koljs/new-api/actions/workflows/android-build.yml
2. 点击右上角 **"Run workflow"** 按钮
3. 选择分支 `main`，version 留空（自动用 git describe）
4. 点击绿色 **"Run workflow"** 确认
5. 等待约 2-3 分钟，运行完成（绿色对勾）
6. 点击进入本次 run，在页面底部 **Artifacts** 区域下载 `new-api-android-arm64-*`
7. 解压 zip 文件，得到 `new-api-android-arm64` 二进制

**验证点**：
```bash
file new-api-android-arm64
# 预期输出: ELF 64-bit LSB executable, ARM aarch64
ls -lh new-api-android-arm64
# 预期大小: 约 38MB
```

#### A-2. 方式二：本地交叉编译

在装有 Go ≥ 1.25.1 和 Bun ≥ 1.2.x 的开发机上：

```bash
git clone https://github.com/koljs/new-api.git
cd new-api
bash deploy/operit/build-android-arm64.sh
```

**脚本会自动完成 4 步**：
1. `bun install` + 构建 default 前端（React 19, Rsbuild）
2. `bun install` + 构建 classic 前端（**必须构建**，main.go 用 go:embed 嵌入两者）
3. `GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build`（纯 Go，无需交叉编译器）
4. 生成 `new-api-android-arm64` + sha256 校验文件

**验证点**：
```bash
file new-api-android-arm64
# 预期: ELF 64-bit LSB executable, ARM aarch64
sha256sum -c new-api-android-arm64.sha256
# 预期: OK
```

> **注意**：main.go 第 49 行 `//go:embed web/classic/dist` 强制要求 classic 前端存在，不可跳过 classic 构建，否则 `go build` 报 `pattern web/classic/dist: no matching files found`。

---

### 阶段 B：传输二进制到手机

```bash
# 通过 adb（推荐）
adb push new-api-android-arm64 /sdcard/Download/

# 或通过文件管理器/U 盘等方式，放到手机任意可访问位置
```

**验证点**：手机文件管理器中能看到 `/sdcard/Download/new-api-android-arm64`。

---

### 阶段 C：在 Operit Ubuntu 终端内安装

#### C-1. 进入 Operit Ubuntu 终端

打开 Operit App → 找到 Ubuntu 终端入口（通常在工具或侧边栏）→ 进入。后续命令**均在 chroot 内执行**。

#### C-2. 获取部署脚本

**方式一**（推荐，仓库已 clone 到 chroot）：
```bash
cd /path/to/cloned-repo/deploy/operit
```

**方式二**（仓库未在 chroot，只传了二进制）：手动从仓库下载 `deploy/operit/` 整个目录到 chroot 内，或用 git clone：
```bash
apt update && apt install -y git
git clone https://github.com/koljs/new-api.git /tmp/new-api-repo
cd /tmp/new-api-repo/deploy/operit
```

#### C-3. 执行一键安装

```bash
sudo bash install.sh /sdcard/Download/new-api-android-arm64
```

**install.sh 会完成**：
- 创建目录结构 `/opt/new-api/{bin,config,data/logs,run,logs,scripts}`
- 复制全部管理脚本到 `/opt/new-api/scripts/`
- 复制配置模板到 `/opt/new-api/config/new-api.env`
- 安装二进制到 `/opt/new-api/bin/new-api`
- 设置正确权限（脚本 0755，配置 0600）

**验证点**：
```bash
ls -la /opt/new-api/bin/new-api
# 预期: -rwxr-xr-x ... /opt/new-api/bin/new-api
file /opt/new-api/bin/new-api
# 预期: ELF 64-bit LSB executable, ARM aarch64
ls /opt/new-api/scripts/
# 预期: start.sh stop.sh restart.sh status.sh update.sh backup.sh uninstall.sh
```

---

### 阶段 D：配置运行环境

#### D-1. 编辑配置文件（必须改 SESSION_SECRET）

```bash
nano /opt/new-api/config/new-api.env
```

**必须修改的字段**：
```ini
# 改成 32+ 位随机字符串（必须改！否则启动会 fatal）
SESSION_SECRET=用此命令生成: openssl rand -hex 32
```

**其他字段保持默认即可**（SQLite + 内存缓存 + 端口 3000）。

#### D-2. 验证配置加载

```bash
cat /opt/new-api/config/new-api.env
# 确认 SESSION_SECRET 已改为非默认值
```

---

### 阶段 E：首次启动与验证

#### E-1. 启动服务

```bash
/opt/new-api/scripts/start.sh
```

**预期输出**：
```
started new-api, pid=XXXX, listen=0.0.0.0:3000
log: /opt/new-api/logs/supervisor.log
```

**失败处理**：若输出 `ERROR: 启动失败`，查看日志：
```bash
tail -n 30 /opt/new-api/logs/supervisor.log
tail -n 30 /opt/new-api/data/logs/*.log
```

常见失败原因：
- `SESSION_SECRET is set to the default value` → 未改 SESSION_SECRET
- `address already in use` → 端口 3000 被占用，改 `new-api.env` 里的 PORT
- `permission denied` → 二进制无执行权限，`chmod +x /opt/new-api/bin/new-api`

#### E-2. 验证服务运行

```bash
# 状态检查
/opt/new-api/scripts/status.sh
# 预期: running, pid=XXXX

# HTTP 接口验证
curl -sS http://127.0.0.1:3000/api/status
# 预期: 返回 JSON，含 version 字段
```

#### E-3. 访问管理面板

手机浏览器打开 `http://127.0.0.1:3000`
- 同一 Wi-Fi 其他设备：`http://<手机内网IP>:3000`
- **默认管理员**：账号 `root` / 密码 `123456`
- **首次登录后立即修改密码**（系统设置 → 个人设置）

---

### 阶段 F：配置开机自启工作流（关键）

#### F-1. 创建"开机自启"工作流

1. Operit App → 工作流（或自动化）标签 → 新建工作流
2. **命名**：`new-api 自启`
3. **触发器**：系统事件 → **开机完成**（延迟 10 秒，等存储挂载）
4. **动作**：执行 Shell 命令
   - 执行环境：选 **Ubuntu** / chroot（不要选 Android Shell）
   - 命令内容：
     ```bash
     /opt/new-api/scripts/start.sh
     ```
   - 超时：30 秒
   - 失败重试：3 次，间隔 5 秒
5. 保存并启用

#### F-2. 创建"守护拉起"工作流（强烈建议叠加）

1. **命名**：`new-api 守护`
2. **触发器**：定时 → 每 5 分钟
3. **动作**：执行 Shell（Ubuntu 环境）
   ```bash
   /opt/new-api/scripts/start.sh
   ```
   > `start.sh` 是幂等的，已运行则安全跳过，可放心重复触发。

#### F-3. 创建"每日备份"工作流（可选但建议）

1. **命名**：`new-api 每日备份`
2. **触发器**：定时 → 每天 03:00
3. **动作**：执行 Shell
   ```bash
   /opt/new-api/scripts/backup.sh
   ```
   备份到 `/sdcard/new-api-backup/`，自动保留最近 7 份。

#### F-4. 验证工作流

重启手机，等 1-2 分钟后：
```bash
/opt/new-api/scripts/status.sh
# 预期: running
```

若未运行，检查 Operit 是否被系统冻结（见前置条件 2.2 的电池白名单设置）。

> 工作流 UI 在不同 Operit 版本可能略有差异，详细操作见 [OPERIT-WORKFLOW-GUIDE.md](./OPERIT-WORKFLOW-GUIDE.md)。

---

## 5. 日常管理命令速查表

| 操作 | 命令 |
|---|---|
| 启动 | `/opt/new-api/scripts/start.sh` |
| 停止 | `/opt/new-api/scripts/stop.sh` |
| 重启 | `/opt/new-api/scripts/restart.sh` |
| 状态 | `/opt/new-api/scripts/status.sh` |
| 查启动日志 | `tail -f /opt/new-api/logs/supervisor.log` |
| 查应用日志 | `tail -f /opt/new-api/data/logs/*.log` |
| 访问面板 | 浏览器 `http://127.0.0.1:3000` |
| 查看版本 | `/opt/new-api/bin/new-api --version` |

---

## 6. 版本升级流程

升级不影响数据（SQLite 库自动迁移），只需替换二进制：

```bash
# 1. 获取新版二进制（同阶段 A）
#    GitHub Actions 重新触发 android-build.yml，下载新 artifact

# 2. 传到手机
adb push new-api-android-arm64 /sdcard/Download/

# 3. 在 Operit Ubuntu 终端执行升级脚本
/opt/new-api/scripts/update.sh /sdcard/Download/new-api-android-arm64
```

**update.sh 会自动**：
1. 停止旧进程
2. 备份旧二进制为 `new-api.bak`
3. 替换为新二进制
4. 重新启动

**验证**：
```bash
/opt/new-api/bin/new-api --version
# 预期: 新版本号
curl -sS http://127.0.0.1:3000/api/status | grep version
```

> 工作流无需重新配置，只调用 `start.sh`，对二进制版本无感。

---

## 7. 数据备份策略

### 7.1 自动备份（推荐）

配置阶段 F-3 的每日备份工作流，自动备份到 `/sdcard/new-api-backup/YYYYMMDD-HHMM/`，保留 7 份。

### 7.2 手动备份

```bash
/opt/new-api/scripts/backup.sh
```

### 7.3 升级前备份（跨大版本必做）

```bash
cp -r /opt/new-api/data /sdcard/new-api-backup-pre-upgrade-$(date +%F)
```

---

## 8. 故障排查指南

### 8.1 服务无法启动

```bash
# 1. 查启动日志
tail -n 50 /opt/new-api/logs/supervisor.log

# 2. 查应用日志
tail -n 50 /opt/new-api/data/logs/*.log

# 3. 常见原因
# - SESSION_SECRET 未改 → 编辑 /opt/new-api/config/new-api.env
# - 端口占用 → 改 PORT 或停占用进程
# - 二进制损坏 → 重新下载/编译
# - 权限问题 → chmod +x /opt/new-api/bin/new-api
```

### 8.2 工作流触发但服务未启动

1. **检查 Operit 是否在白名单**：见前置条件 2.2
2. **检查工作流执行历史**：Operit → 工作流 → 对应工作流 → 执行记录
3. **手动测试 shell 节点**：在工作流编辑页点"试运行"
4. **确认 chroot 路径可见**：在工作流 shell 节点先执行 `ls /opt/new-api/bin/new-api`
5. **确认执行环境**：动作节点的"执行环境"应选 Ubuntu/chroot，不是 Android Shell

### 8.3 服务运行但访问不到

```bash
# 同一手机
curl http://127.0.0.1:3000/api/status

# 同一 Wi-Fi 其他设备（需查手机 IP）
curl http://<手机IP>:3000/api/status
```

若本机可访问但其他设备不行：
- 检查手机防火墙（一般无）
- 确认 chroot 共享 Android 网络栈（默认共享）
- 部分国产 ROM 限制跨设备访问，需关闭"局域网隔离"类设置

### 8.4 数据库锁定

SQLite 并发写入偶发 `database is locked`：
```bash
/opt/new-api/scripts/restart.sh
```
若频繁出现，考虑切换到 MySQL（但不推荐在 chroot 内装）。

### 8.5 进程被系统杀死

国产 ROM 后台清理导致。解决方案：
- Operit 加入电池优化白名单（见前置条件）
- 在"最近任务"里锁定 Operit 卡片
- 启用阶段 F-2 的守护工作流（每 5 分钟拉起）

---

## 9. 卸载流程

### 9.1 标准卸载（保留数据备份选项）

```bash
sudo /opt/new-api/scripts/uninstall.sh
```

脚本会：
1. 提示确认（输入 `YES` 继续）
2. 询问是否先备份到 `/sdcard/new-api-backup-YYYYMM-DD`
3. 停止进程
4. 删除整个 `/opt/new-api/` 目录

### 9.2 手动卸载

```bash
/opt/new-api/scripts/stop.sh
sudo rm -rf /opt/new-api
```

### 9.3 卸载后清理工作流

手动到 Operit → 工作流，禁用或删除以下三个工作流：
- `new-api 自启`
- `new-api 守护`
- `new-api 每日备份`

> 不清理会导致工作流触发时报"命令不存在"错误。

---

## 10. 关键约束与边界

### 10.1 不要做的事

- ❌ **不要**在 chroot 内安装 MySQL/PostgreSQL/Redis（污染系统、占内存）
- ❌ **不要**把数据放 `/data/local/tmp`（重启清空）
- ❌ **不要**跳过 classic 前端构建（main.go go:embed 强制要求）
- ❌ **不要**用 `git add -A` 或 `git add .` 提交（避免误加敏感文件）
- ❌ **不要**删除仓库中 nеw-аρi / QuаntumΝоuѕ 的品牌标识（受项目策略保护）

### 10.2 必须做的事

- ✅ **必须**修改 `SESSION_SECRET`（否则启动 fatal）
- ✅ **必须**首次登录后改默认密码 `root/123456`
- ✅ **必须**把 Operit 加入电池白名单（否则后台被杀）
- ✅ **必须**配置守护工作流（国产 ROM 必备）
- ✅ **必须**定期备份到 `/sdcard`（防 chroot 重置）

### 10.3 性能边界

- 单手机部署，适合个人/小团队使用（并发 ≤ 50）
- SQLite 单写并发限制，高并发请用服务器部署 + MySQL
- chroot 网络共享 Android 网络栈，延迟与手机网络一致
- 后台运行受 Android 系统调度影响，非实时保证

---

## 11. 快速验证部署是否成功（5 步检查）

```bash
# 1. 二进制存在且架构正确
file /opt/new-api/bin/new-api | grep -q "ARM aarch64" && echo "✅ 二进制OK" || echo "❌ 二进制异常"

# 2. 进程运行
/opt/new-api/scripts/status.sh | grep -q "running" && echo "✅ 进程OK" || echo "❌ 进程未运行"

# 3. 端口监听
curl -sS http://127.0.0.1:3000/api/status | grep -q "version" && echo "✅ 接口OK" || echo "❌ 接口异常"

# 4. 配置已改
grep -q "SESSION_SECRET=请改成" /opt/new-api/config/new-api.env && echo "❌ SESSION_SECRET 未改" || echo "✅ 配置OK"

# 5. 数据目录可写
touch /opt/new-api/data/.write_test && rm /opt/new-api/data/.write_test && echo "✅ 数据目录OK" || echo "❌ 数据目录不可写"
```

5 项全 ✅ 即部署成功。

---

## 12. 相关文件引用

| 文件 | 用途 |
|---|---|
| [build-android-arm64.sh](../build-android-arm64.sh) | 本地交叉编译脚本 |
| [install.sh](../install.sh) | 一键安装到 chroot |
| [scripts/start.sh](../scripts/start.sh) | 启动（幂等，setsid+nohup 脱离 shell） |
| [scripts/stop.sh](../scripts/stop.sh) | 停止（TERM→10s→KILL） |
| [scripts/restart.sh](../scripts/restart.sh) | 重启（含 2 秒端口释放等待） |
| [scripts/status.sh](../scripts/status.sh) | 状态 + 端口 + 资源占用 |
| [scripts/update.sh](../scripts/update.sh) | 升级（自动备份旧二进制） |
| [scripts/backup.sh](../scripts/backup.sh) | 备份到 /sdcard（保留 7 份） |
| [scripts/uninstall.sh](../scripts/uninstall.sh) | 卸载（含二次确认） |
| [config/new-api.env.example](../config/new-api.env.example) | 配置模板 |
| [test/e2e-test.sh](../test/e2e-test.sh) | 端到端测试（13 项） |
| [OPERIT-WORKFLOW-GUIDE.md](./OPERIT-WORKFLOW-GUIDE.md) | Operit 工作流配置详细指引 |
| [.github/workflows/android-build.yml](../../../.github/workflows/android-build.yml) | GitHub Actions 编译工作流 |

---

**文档结束。按此文档执行可完成完整部署，无需其他上下文。**
