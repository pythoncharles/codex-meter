# Codex Meter

Codex Meter 是一款原生 macOS 菜单栏应用，用于查看本机 Codex 账号的额度和 Token 历史用量。

应用通过本机 `codex app-server` 获取数据，不读取浏览器、不抓取网页，也不会直接解析 Codex 私有配置文件。

## 功能

- 菜单栏常驻，可显示或隐藏浮动面板
- 展示 Codex 返回的 5 小时额度和 7 天额度
- 展示剩余/已用百分比、进度环、重置时间和剩余倒计时
- 剩余额度低于 50% 时显示橙色，低于 20% 时显示红色
- 展示账号套餐等级和最近更新时间
- 支持手动刷新、刷新动画和断开连接提示
- 默认每 60 秒自动刷新，可选择 30 秒、1 分钟、5 分钟、15 分钟或仅手动
- 接收 `account/rateLimits/updated` 通知后自动更新
- 系统唤醒后自动刷新
- app-server 异常退出后自动重连，最多尝试 5 次
- 使用本地缓存保留最近一次成功数据，刷新失败时显示旧数据和错误提示
- 支持在设置中指定 `codex` 可执行文件路径

### 历史用量

点击“周额度”卡片的任意位置，面板会翻转到历史用量页面，显示：

- 累计 Token
- 单日 Token 峰值
- 最长聊天时长
- 当前连续使用天数
- 最长连续使用天数
- 最近 14 天的每日 Token 柱状图
- 最近 8 个自然周的每周 Token 柱状图
- 历史累计 Token 趋势曲线
- 点击或拖动图表查看对应日期和用量

历史数据来自 `account/usage/read`。如果当前 Codex 版本或账号没有返回该接口数据，应用会显示“暂无历史用量”，额度功能仍可正常使用。

## 系统要求

- macOS 14 或更高版本
- 已安装 Codex CLI，或已安装包含 Codex 可执行文件的 ChatGPT macOS 应用
- Codex 已使用 ChatGPT 账号登录

API Key 认证没有 ChatGPT 的 5 小时/周额度，应用会提示当前认证模式不支持。

运行已经打包好的应用不需要安装 Xcode。只有从源码编译时才需要可用的 Swift 编译器；安装 Xcode Command Line Tools 即可，不要求完整 Xcode：

```bash
xcode-select --install
```

## 快速开始

在项目根目录执行：

```bash
zsh Scripts/build-app.sh
open .build/CodexMeter.app
```

打包结果位于：

```text
.build/CodexMeter.app
```

修改代码后重新打包并重启：

```bash
pkill -x CodexMeter 2>/dev/null || true
zsh Scripts/build-app.sh
open .build/CodexMeter.app
```

也可以将 `.build/CodexMeter.app` 拖入“应用程序”目录后，像普通 macOS 应用一样启动。

## 使用方法

1. 启动 Codex Meter。
2. 点击菜单栏中的仪表图标。
3. 选择“显示或隐藏浮窗”。
4. 点击面板右上角刷新按钮可立即更新数据。
5. 点击周额度卡片进入历史用量，再点击返回按钮恢复额度卡片。
6. 点击齿轮按钮进入与周额度卡片同尺寸的设置卡片；可修改主题、背景透明度、自动刷新间隔和 Codex 路径，点击返回按钮恢复周额度卡片。

应用会依次在以下位置查找 Codex：

1. 设置中的自定义路径
2. 当前 `PATH`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. `~/.local/bin/codex`
6. `~/bin/codex`
7. `/Applications/ChatGPT.app/Contents/Resources/codex`
8. 登录 Shell 返回的 `command -v codex`

## 数据来源

应用启动以下本机子进程，并通过 stdin/stdout JSONL 通信：

```bash
codex app-server --listen stdio://
```

当前使用的 app-server 方法：

| 方法 | 用途 |
| --- | --- |
| `initialize` / `initialized` | 初始化 app-server 会话 |
| `account/read` | 检查账号和认证模式 |
| `account/rateLimits/read` | 读取额度窗口 |
| `account/usage/read` | 读取 Token 汇总和每日历史 |
| `account/rateLimits/updated` | 接收额度变化通知 |
| `account/updated` | 接收账号变化通知 |

应用将约 300 分钟的窗口识别为 5 小时额度，将约 10,080 分钟的窗口识别为周额度。服务端没有返回某个窗口时，界面不会虚构或补算该额度。

app-server 协议仍可能随 Codex 版本变化。升级 Codex 后，可以生成当前版本的协议 Schema 辅助排查字段变化：

```bash
zsh Scripts/refresh-protocol-schema.sh
```

生成结果位于 `ProtocolSchemas/`。

## 验证

构建并检查 `.app`：

```bash
zsh Scripts/build-app.sh
codesign --verify --deep --strict .build/CodexMeter.app
```

运行不依赖 Xcode 的核心自检：

```bash
swiftc \
  CodexMeter/Domain/Models.swift \
  CodexMeter/Infrastructure/JSONLStreamDecoder.swift \
  CodexMeter/Infrastructure/CodexBinaryLocator.swift \
  Scripts/SelfCheck/main.swift \
  -o .build/CodexMeterSelfCheck
.build/CodexMeterSelfCheck
```

连接本机 Codex app-server 做集成检查：

```bash
swiftc -parse-as-library \
  CodexMeter/Domain/Models.swift \
  CodexMeter/Infrastructure/JSONLStreamDecoder.swift \
  CodexMeter/Infrastructure/CodexBinaryLocator.swift \
  CodexMeter/Infrastructure/AppServerTransport.swift \
  CodexMeter/Infrastructure/CodexAppServerClient.swift \
  Scripts/IntegrationCheck.swift \
  -o .build/CodexMeterIntegrationCheck
.build/CodexMeterIntegrationCheck
```

安装了完整 Xcode 时，也可以运行 XCTest：

```bash
xcodebuild test -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS'
```

## 项目结构

```text
CodexMeter/
├── CodexMeterApp.swift              菜单栏入口
├── Domain/Models.swift              额度、账号和 Token 历史模型
├── Infrastructure/                 Codex 定位、app-server 通信和缓存
└── Presentation/                   状态管理、浮窗和图表界面
CodexMeterTests/                     XCTest
Resources/                           应用图标
Scripts/                             打包、自检和协议 Schema 脚本
```

## 已知限制

- Codex app-server 及部分协议字段可能随 Codex 版本调整。
- 历史用量完全取决于 `account/usage/read` 返回的数据范围，应用不会自行补造更早记录。
- 当前构建脚本使用本机临时签名，适合本机运行；分发给其他用户需要 Apple Developer 签名和公证。
- 设置项保存在当前用户的 `UserDefaults` 中，不会上传到网络。
