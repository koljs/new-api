# Operit 1.12.0 工作流自启配置指引

> 适用于 Operit 1.12.0，将 `new-api` 部署到 Operit 内置 Ubuntu chroot 后，配置开机自启与守护任务。
> 不同小版本 UI 文案可能略有差异，请按概念匹配，必要时搜索关键词。

## 一、前置确认

完成下列检查后再配置工作流，否则工作流触发后无服务可启动：

1. **二进制已就位**
   ```bash
   ls -lh /opt/new-api/bin/new-api
   file /opt/new-api/bin/new-api   # 应为 ELF 64-bit LSB executable, ARM aarch64
   ```
2. **配置文件已编辑**
   ```bash
   nano /opt/new-api/config/new-api.env
   # 必须修改 SESSION_SECRET
   ```
3. **手动启动一次验证通过**
   ```bash
   /opt/new-api/scripts/start.sh
   curl -sS http://127.0.0.1:3000/api/status | head -c 200
   ```
   返回 JSON 即正常。验证后 `stop.sh` 停掉，留给工作流接管。

## 二、Operit 权限模式

new-api 工作流只需要 **进入 Ubuntu chroot 执行 shell** 这一项能力，**不需要**无障碍 / ADB / Root 模式中的任何 UI 自动化能力。

但 Operit 进入 chroot 本身可能需要 root。1.12.0 的实际机制：

- Operit 的 chroot 通过 root 权限挂载并进入，App 内的「Ubuntu 终端」入口已自带 root 上下文。
- 工作流里的「Shell」节点，**如果在 chroot 内执行**，会自动继承 chroot 环境；如果是在 Android 层执行，需要通过 Operit 提供的「在 Ubuntu 中执行」专用节点。

**请在配置前先在 Operit 主界面确认**：
- 设置 → 工具 → Ubuntu 子系统 是否已开启
- 设置 → 权限管理 → Root 是否已授予

## 三、方案 A：开机自启工作流（首选）

### A.1 新建工作流

1. 打开 Operit App，进入「工作流」标签页（底部导航或侧边栏的「自动化」入口）。
2. 点右上角 `+` 新建工作流。
3. 命名：`new-api 自启`
4. 描述：`开机后启动 new-api 服务`

### A.2 配置触发器

1. 在工作流编辑页，点击「触发条件」/「事件」节点。
2. 选择类型：**事件触发**（不是手动 / 定时）。
3. 事件来源：**系统事件**。
4. 事件类型：选择 **开机完成**（关键字：`BOOT_COMPLETED` / `开机` / `设备启动`）。
   - 1.12.0 内可能叫「设备启动完成」或「开机自启」。
5. 延迟：建议填 `10` 秒，等 Android 把存储挂载好再触发 chroot。

### A.3 配置动作

1. 点击「+ 动作」/「添加步骤」。
2. 类型选择：**Shell 命令** / **执行 Shell**。
3. **执行环境**：选「Ubuntu」/「chroot」/「Linux 环境」（**不要**选「Android Shell」）。
   - 如果 1.12.0 没有显式的环境选择项，说明 shell 默认就在 chroot 内，直接进入下一步。
4. 命令内容：
   ```bash
   /opt/new-api/scripts/start.sh
   ```
5. 超时：填 `30` 秒（启动很快，但首次 SQLite 初始化可能稍慢）。
6. 失败处理：勾选「失败后重试」，重试次数 `3`，间隔 `5` 秒。

### A.4 保存并启用

1. 右上角保存。
2. 确认工作流开关为「已启用」状态。
3. 重启手机验证（或用「手动运行」测试一次）。

## 四、方案 B：守护定时任务（更鲁棒，强烈推荐叠加用）

方案 A 只在开机时触发一次，如果进程被系统杀死不会自动恢复。叠加方案 B 可做守护。

### B.1 新建工作流

命名：`new-api 守护`

### B.2 配置触发器

1. 类型：**定时触发**。
2. 频率：**每 5 分钟**（或「自定义 Cron」`*/5 * * * *`，如果 1.12.0 支持）。
3. 仅在充电时执行：**关闭**（守护任务要 24 小时运行）。

### B.3 配置动作

shell 命令（`start.sh` 内部已做幂等判断，已运行时直接退出，不会重复拉起）：
```bash
/opt/new-api/scripts/start.sh
```

### B.4 保存启用

建议同时启用方案 A + B：A 负责开机即启，B 负责拉起被杀的进程。

## 五、方案 C：每日备份工作流（可选但建议）

### C.1 新建工作流

命名：`new-api 每日备份`

### C.2 触发器

定时 → 每天 `03:00`（凌晨流量低）。

### C.3 动作

shell 命令：
```bash
/opt/new-api/scripts/backup.sh
```

备份会写到 `/sdcard/new-api-backup/YYYYMMDD-HHMM/`，自动保留最近 7 份。

## 六、国产 ROM 自启动白名单（关键，否则工作流跑不起来）

Operit App 自身必须能开机启动并保持后台运行，否则它的工作流永远不会触发。

| ROM | 设置位置 |
|---|---|
| MIUI / HyperOS | 设置 → 应用设置 → 应用管理 → Operit → 自启动：开；省电策略：无限制 |
| ColorOS / OxygenOS | 设置 → 电池 → 应用耗电管理 → Operit → 允许后台运行 + 允许自启 |
| EMUI / 鸿蒙 | 设置 → 电池 → 更多电池设置 → 关闭「休眠时始终保持网络连接」对 Operit 的影响；应用启动管理 → Operit 改为「手动管理」并打开全部开关 |
| Flyme | 设置 → 电池 → 后台管理 → Operit → 允许后台运行 + 允许自启 |
| 原生 / Pixel | 设置 → 应用 → Operit → 电池 → 不受限 |

额外建议：
- 在「最近任务」里把 Operit 卡片锁定（下拉锁定）。
- 关闭「智能后台清理」类功能对 Operit 的影响。

## 七、调试与排查

### 7.1 检查工作流是否真的执行了

工作流执行历史在 Operit → 工作流 → 点击对应工作流 → 「执行记录」/「日志」。

### 7.2 手动测试 shell 节点

在工作流编辑页，点击 shell 动作节点上的「测试」/「试运行」按钮，看输出。

### 7.3 chroot 内手动排查

```bash
# 在 Operit Ubuntu 终端内
/opt/new-api/scripts/status.sh
cat /opt/new-api/logs/supervisor.log
tail -n 100 /opt/new-api/data/logs/*.log
```

### 7.4 工作流执行了但服务没起来

最常见原因：
1. **环境变量没加载**：确认 `new-api.env` 文件存在且 `SESSION_SECRET` 已改。
2. **chroot 路径不对**：在工作流 shell 节点先执行 `which new-api` 或 `ls /opt/new-api/bin/` 确认路径可见。
3. **shell 在 Android 层而非 chroot 内执行**：检查动作节点的「执行环境」选项。
4. **Operit 被系统冻结**：见第六节 ROM 白名单。

### 7.5 启动了但访问不到

- 同一手机：浏览器访问 `http://127.0.0.1:3000`
- 同一 Wi-Fi 其他设备：`http://<手机内网IP>:3000`，需确认 Operit chroot 共享 Android 网络栈（默认共享）。
- 外网：需要端口转发或 frp，不在本指引范围。

## 八、关闭自启

临时停：Operit → 工作流 → 对应工作流开关切到「已禁用」。

永久卸载 new-api 服务（保留数据备份）：
```bash
sudo /opt/new-api/scripts/uninstall.sh
```
卸载后请同步到 Operit 工作流页面把三个工作流也禁用或删除，避免触发时报「命令不存在」。

## 九、版本升级流程（Operit 工作流配合）

1. 主机或 GitHub Actions 重新编译二进制（参考 `deploy/operit/build-android-arm64.sh` 或触发 `.github/workflows/android-build.yml`）。
2. `adb push new-api-android-arm64 /sdcard/Download/`，然后在 Operit 文件管理器或 chroot 内 `cp` 到 chroot 可见路径。
3. 在 Operit Ubuntu 终端执行：
   ```bash
   /opt/new-api/scripts/update.sh /sdcard/Download/new-api-android-arm64
   ```
4. 升级脚本会自动停旧进程 → 备份旧二进制 → 替换 → 启动。

升级不需要重新配置工作流，工作流只调用 `start.sh`，对二进制版本无感。

## 十、速查表

| 场景 | 工作流动作 shell |
|---|---|
| 开机自启 | `/opt/new-api/scripts/start.sh` |
| 守护拉起 | `/opt/new-api/scripts/start.sh` |
| 每日备份 | `/opt/new-api/scripts/backup.sh` |
| 重启服务 | `/opt/new-api/scripts/restart.sh` |
| 状态检查 | `/opt/new-api/scripts/status.sh` |
| 停止服务 | `/opt/new-api/scripts/stop.sh` |
