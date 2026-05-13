# wechat-claude-code

基于 [Wechat-ggGitHub/wechat-claude-code](https://github.com/Wechat-ggGitHub/wechat-claude-code) 的改进版本。

在原版基础上完善了 **Windows 平台支持**。

## 改进点

### 1. Windows 平台完善

- `scripts/daemon.ps1` — Windows Task Scheduler 守护进程管理
- `main.ts` 中 `chcp 65001` 设置 UTF-8 编码，解决中文显示乱码
- PowerShell 执行策略自动绕过 (`-ExecutionPolicy Bypass`)
- Windows 路径处理 (`%APPDATA%` vs `~`)

### 2. 其他优化(以下内容提到的优化均为在平台迁移中多次迭代产生、所遇到的问题，在此写出问题描述以及处理方案)

#### 1、Skill 调用失败

**问题：** 微信端发送 `/<skill>` 后，Claude 回复找不到该 skill。

**根因：**
- `handleUnknown` 仅发送 `Use the X skill` 自然语言，未注入 SKILL.md 实际指令内容
- `main.ts` 并发守卫在 `processing` 状态时静默丢弃 skill 命令

**修复：**
- `skill-scanner.ts` 新增 `loadSkillContent()` 读取 SKILL.md 正文
- `handlers.ts` 注入完整 skill 指令到 prompt
- `main.ts` 并发守卫改为允许 skill 命令中断当前处理

#### 2、 日志中 Bearer token / API key 自动脱敏
每次 logger.info/warn/error/debug 带 data 参数时，writeLogLine 先调用 redact(data)：Bearer token：匹配Bearer<任意非空白字符>→替换为Bearer*** JSON 中的密钥字段：匹配 "token": "xxx"、"secret": "xxx"、"password": "xxx"、"api_key": "xxx" → 替换为 "token": "***"
#### 3、会话状态机启动时自动重置 stale `processing` 状态
这个bug在原处好像已经做了修复，但是我一开始克隆的代码并未包含，所以不重要。

## 功能特性

- **文字对话** — 微信直接发消息与 Claude 聊天
- **图片识别** — 发送照片让 Claude 分析
- **权限审批** — 回复 `y`/`n` 控制工具执行
- **斜杠命令** — `/help`, `/clear`, `/model`, `/skills`, `/<skill>`
- **实时进度** — 查看 Claude 工具调用（🔧 Bash, 📖 Read, 🔍 Glob...）
- **思考预览** — 💭 每次工具调用前展示推理摘要
- **中断支持** — 处理中发送新消息可打断当前任务
- **会话持久化** — 跨消息恢复上下文
- **限频保护** — 微信 API 限频时自动指数退避重试
- **跨平台** — Windows（Task Scheduler）、macOS（launchd）、Linux（systemd/nohup）

## 前置条件

- Node.js >= 18
- Windows / macOS / Linux
- 个人微信账号（需扫码绑定）
- 已安装 Claude Code（含 `@anthropic-ai/claude-agent-sdk`）

## 安装

```bash
# macOS / Linux
git clone https://github.com/harryleo3122001-ops/wechat-claude-code-windows.git ~/.claude/skills/wechat-claude-code
cd ~/.claude/skills/wechat-claude-code
npm install

# Windows (管理员：PowerShell)
git clone https://github.com/harryleo3122001-ops/wechat-claude-code-windows.git $env:USERPROFILE\.claude\skills\wechat-claude-code
cd $env:USERPROFILE\.claude\skills\wechat-claude-code
npm install
```

`postinstall` 自动编译 TypeScript。

## 快速开始（Windows需要管理员权限）

### 1. 首次设置

```bash
npm run setup
```

弹出二维码，微信扫码后配置工作目录。

### 2. 启动服务
# macOS / Linux
```bash
npm run daemon -- start
```
# Windows
```bash
npm run daemon:win -- start
```

### 3. 微信端命令

| 命令 | 说明 |
|------|------|
| `/help` | 显示帮助 |
| `/clear` | 清除当前会话 |
| `/reset` | 完全重置 |
| `/model <名称>` | 切换 Claude 模型 |
| `/permission <模式>` | 切换权限模式 |
| `/prompt [内容]` | 设置系统提示词 |
| `/status` | 查看会话状态 |
| `/cwd [路径]` | 查看/切换工作目录 |
| `/skills` | 列出已安装 skill |
| `/history [数量]` | 查看对话记录 |
| `/<skill>` | 触发任意已安装 Skill |

### 4. 管理服务

```bash
# macOS / Linux
npm run daemon -- status
npm run daemon -- stop
npm run daemon -- restart
npm run daemon -- logs

# Windows
npm run daemon:win -- status
npm run daemon:win -- stop
npm run daemon:win -- restart
npm run daemon:win -- logs
```

## 工作原理

```
微信（手机） ←→ ilink Bot API ←→ Node.js 守护进程 ←→ Claude Code SDK（本地）
```

- 守护进程通过长轮询监听微信 ilink Bot API 新消息
- 消息通过 `@anthropic-ai/claude-agent-sdk` 转发给 Claude Code
- 工具调用和思考摘要实时推送回微信
- 限频时自动重试

## 数据目录

- **Windows:** `%APPDATA%\wechat-claude-code\`
- **macOS / Linux:** `~/.wechat-claude-code/`

```
wechat-claude-code/
├── accounts/       # 绑定的微信账号数据
├── config.env      # 全局配置
├── sessions/       # 会话数据
├── get_updates_buf # 消息轮询同步缓冲
└── logs/           # 运行日志（每日轮转，保留 30 天）
```

## 开发

```bash
npm run dev    # 监听模式，TS 变更自动编译
npm run build  # 编译 TypeScript
```

## License

[MIT](LICENSE)

## 致谢

原项目：[Wechat-ggGitHub/wechat-claude-code](https://github.com/Wechat-ggGitHub/wechat-claude-code)
