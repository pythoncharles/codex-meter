# codex-meter
结论

这款工具最适合做成一个原生 macOS 菜单栏应用 + 可置顶浮窗：

* UI：SwiftUI
* 窗口控制：AppKit NSPanel
* 数据来源：启动本机 codex app-server
* 通信方式：首选 stdio + JSONL
* 协议：Codex app-server JSON-RPC
* 查询接口：account/rateLimits/read
* 实时更新：监听 account/rateLimits/updated
* 保底刷新：定时轮询
* 本地存储：UserDefaults
* 不读取浏览器、不抓网页、不直接解析 Codex 私有配置文件

Codex app-server 官方支持 stdio、WebSocket 和 Unix Socket；其中 WebSocket 与 app-server 本身目前仍标注为实验性能力。对于单机菜单栏应用，由应用自己启动一个 app-server 子进程并通过标准输入输出通信，依赖最少、端口冲突最少，也不需要开放本地网络监听。 

⸻

一、功能定义

建议产品暂定名：

Codex Meter

首个版本展示：

功能	展示内容
5 小时额度	剩余百分比、已用百分比、进度条
周额度	剩余百分比、已用百分比、进度条
重置时间	绝对时间和倒计时
自动刷新	默认每 60 秒刷新
实时更新	接收 app-server 限额变化通知
菜单栏摘要	图标或文字显示最低剩余额度
浮窗	可拖动、置顶、自动记忆位置
状态诊断	未安装、未登录、服务异常、请求超时
手动刷新	点击按钮立即请求
开机启动	第二阶段支持

Codex 官方接口直接返回：

* usedPercent
* windowDurationMins
* resetsAt
* primary
* secondary
* rateLimitsByLimitId
* rateLimitReachedType
* planType
* 可选的 reset credits

其中 resetsAt 是 Unix 秒级时间戳，usedPercent 是当前窗口的已使用比例，因此：

remainingPercent = max(0, min(100, 100 - usedPercent))

接口还会主动推送 account/rateLimits/updated 通知。 

⸻

二、技术选型

2.1 推荐技术栈

UI 层：SwiftUI

原因：

* 原生适配 macOS
* 实现菜单栏图标简单
* 状态驱动 UI 适合额度数据
* 进度条、倒计时、设置界面开发效率高
* 无需 Electron 常驻大内存
* Apple Silicon 原生运行

最低系统建议：

macOS 14+
Swift 6
Xcode 16+

也可以降低到 macOS 13，但会增加兼容代码。

窗口层：AppKit

SwiftUI 负责内容，AppKit 负责浮窗行为。

使用：

NSPanel
NSStatusItem / MenuBarExtra
NSWindow.Level.floating
NSWindow.CollectionBehavior.canJoinAllSpaces
NSWindow.CollectionBehavior.fullScreenAuxiliary

NSPanel 配置建议：

panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.isMovableByWindowBackground = true
panel.collectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary
]

进程层：Foundation Process

使用 Swift 原生：

Process
Pipe
FileHandle

启动命令：

codex app-server --listen stdio://

Codex app-server 的 stdio 模式使用一行一条 JSON 消息的 JSONL 协议。 

并发层：Swift Concurrency

采用：

actor CodexAppServerClient
AsyncStream
Task
MainActor

不要在多个线程直接读写 Process 和请求字典。

⸻

三、总体架构

┌──────────────────────────────────────────────┐
│               Codex Meter App                │
├──────────────────────────────────────────────┤
│                                              │
│  MenuBarExtra        Floating NSPanel        │
│       │                     │                │
│       └──────────┬──────────┘                │
│                  ▼                           │
│            QuotaViewModel                    │
│                  │                           │
│           QuotaRepository                    │
│          ┌───────┴────────┐                  │
│          │                │                  │
│     CacheStore      CodexQuotaService        │
│                           │                  │
│                    AppServerClient actor      │
│                     │       │       │        │
│               RequestMap  Parser  Lifecycle  │
│                           │                  │
│                     stdin / stdout            │
└───────────────────────────┼──────────────────┘
                            │
                            ▼
                 codex app-server process
                            │
                            ▼
              account/rateLimits/read
              account/rateLimits/updated

⸻

四、核心模块设计

4.1 CodexBinaryLocator

职责：定位可执行文件。

查找顺序：

1. 用户设置的自定义路径
2. 当前应用继承的 PATH
3. /opt/homebrew/bin/codex
4. /usr/local/bin/codex
5. ~/.local/bin/codex
6. ~/bin/codex
7. 执行登录 shell：

/bin/zsh -lc 'command -v codex'

注意：通过 Finder 启动的 macOS GUI 应用通常不能获得终端完整的 shell PATH，所以不能只调用：

URL(fileURLWithPath: "/usr/bin/env")

最后需要验证：

codex --version

状态设计：

enum CodexInstallationStatus {
    case checking
    case available(path: URL, version: String?)
    case notFound
    case invalid(path: URL, reason: String)
}

⸻

4.2 AppServerProcessManager

职责：

* 启动 app-server
* 持有子进程
* 读取 stdout
* 读取 stderr
* 写入 stdin
* 检测异常退出
* 自动重启
* 应用退出时终止子进程

启动参数：

process.executableURL = codexBinaryURL
process.arguments = [
    "app-server",
    "--listen",
    "stdio://"
]

不要使用：

codex app-server --listen ws://0.0.0.0:4500

原因是没有必要暴露网络接口。官方也明确提示，非 loopback WebSocket 监听在部分情况下可能默认无认证，不应直接暴露到远程网络。 

建议重启退避：

第 1 次：1 秒
第 2 次：2 秒
第 3 次：4 秒
第 4 次：8 秒
此后最大 30 秒

如果连续失败 5 次，停止自动重启并提示用户手动重试。

⸻

4.3 JSON-RPC 客户端

Codex app-server 使用类似 JSON-RPC 2.0 的双向消息，但线上消息省略：

"jsonrpc": "2.0"

请求：

{
  "method": "account/rateLimits/read",
  "id": 6
}

响应：

{
  "id": 6,
  "result": {
    "rateLimits": {}
  }
}

通知：

{
  "method": "account/rateLimits/updated",
  "params": {
    "rateLimits": {}
  }
}

官方协议要求：每次建立连接后，必须先发送一次 initialize，收到成功响应后再发送 initialized 通知；未完成握手前发送其他请求会返回 Not initialized。 

初始化请求：

{
  "method": "initialize",
  "id": 1,
  "params": {
    "clientInfo": {
      "name": "codex_meter",
      "title": "Codex Meter",
      "version": "0.1.0"
    }
  }
}

初始化成功后：

{
  "method": "initialized"
}

然后查询账户：

{
  "method": "account/read",
  "id": 2,
  "params": {
    "refreshToken": false
  }
}

再查询额度：

{
  "method": "account/rateLimits/read",
  "id": 3
}

⸻

4.4 消息模型

不要只为当前示例写死一个 DTO。需要允许 app-server 升级后出现未知字段。

struct RPCRequest<Params: Encodable>: Encodable {
    let method: String
    let id: Int?
    let params: Params?
}
struct RPCResponse<Result: Decodable>: Decodable {
    let id: Int
    let result: Result?
    let error: RPCError?
}
struct RPCError: Decodable, Error {
    let code: Int
    let message: String
}

由于通知与响应结构不同，入站消息建议先解析信封：

struct RPCEnvelope: Decodable {
    let id: Int?
    let method: String?
    let result: JSONValue?
    let params: JSONValue?
    let error: RPCError?
}

JSONValue 可定义为：

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

或者先用 JSONSerialization 区分消息类型，再对局部数据做强类型解码。

⸻

4.5 请求关联

维护：

private var nextRequestID = 1
private var pendingRequests: [
    Int: CheckedContinuation<JSONValue, Error>
]

每个请求：

1. 分配递增 ID
2. 保存 continuation
3. 写入 JSONL
4. 等待对应 ID 的响应
5. 设置 10 秒超时
6. 收到响应后删除 pending entry
7. 进程终止时统一取消所有请求

伪代码：

func send<P: Encodable, R: Decodable>(
    method: String,
    params: P?
) async throws -> R

写入时必须保证：

JSON 数据 + \n

不要把多条消息拼成一条，也不要对 stdout 按任意 buffer 直接做整段 JSON 解码。必须按换行切割。

⸻

五、额度数据模型

struct RateLimitWindowDTO: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval
}
struct RateLimitBucketDTO: Decodable {
    let limitId: String
    let limitName: String?
    let primary: RateLimitWindowDTO?
    let secondary: RateLimitWindowDTO?
    let rateLimitReachedType: String?
    let planType: String?
}
struct RateLimitsResultDTO: Decodable {
    let rateLimits: RateLimitBucketDTO?
    let rateLimitsByLimitId: [String: RateLimitBucketDTO]?
    let rateLimitResetCredits: RateLimitResetCreditsDTO?
}

领域模型：

struct QuotaWindow: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case fiveHour
        case weekly
        case other(minutes: Int)
    }
    let kind: Kind
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: Date
    let windowDurationMinutes: Int
}
struct CodexQuotaSnapshot: Equatable, Sendable {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?
    let otherWindows: [QuotaWindow]
    let planType: String?
    let reachedType: String?
    let fetchedAt: Date
}

⸻

六、5 小时和周额度识别逻辑

不能永久假设：

primary = 5 小时
secondary = 周额度

更稳妥的方式是根据 windowDurationMins 识别。

enum KnownQuotaDuration {
    static let fiveHours = 5 * 60
    static let oneWeek = 7 * 24 * 60
}

识别：

switch window.windowDurationMins {
case 300:
    kind = .fiveHour
case 10_080:
    kind = .weekly
default:
    kind = .other(minutes: window.windowDurationMins)
}

为了兼容服务端可能出现轻微不同的周期，可以增加容差：

func classify(minutes: Int) -> QuotaWindow.Kind {
    if abs(minutes - 300) <= 5 {
        return .fiveHour
    }
    if abs(minutes - 10_080) <= 60 {
        return .weekly
    }
    return .other(minutes: minutes)
}

遍历顺序：

1. 优先遍历 rateLimitsByLimitId
2. 每个 bucket 收集 primary
3. 收集 secondary
4. 去除重复窗口
5. 识别 300 分钟
6. 识别 10080 分钟
7. 未识别窗口保留到 otherWindows
8. 如果没有 rateLimitsByLimitId，退回 rateLimits

去重 key：

limitId + windowDurationMins + resetsAt

官方同时提供向后兼容的单 bucket rateLimits 和多 bucket rateLimitsByLimitId，因此客户端应优先支持后者，同时保留前者作为回退。 

⸻

七、剩余百分比和重置时间

剩余百分比

let remaining = max(0, min(100, 100 - usedPercent))

展示时四舍五入：

85%

详细模式可以显示：

已使用 15.3%
剩余 84.7%

不要根据本地使用量自行估算额度；app-server 返回值才是数据源。

重置时间

同时显示：

今天 14:35 重置
剩余 2小时17分钟

周额度：

8月10日 周一 09:00 重置
剩余 3天22小时

转换：

Date(timeIntervalSince1970: resetsAt)

使用系统时区展示，不写死中国或日本时区。

倒计时只在本地每秒更新 UI，不需要每秒请求 app-server。

当倒计时归零：

1. 立即调用一次 account/rateLimits/read
2. 如果失败，保留旧数据并标记为过期
3. 不要直接把剩余额度修改为 100%

⸻

八、刷新策略

建议采用“通知 + 轮询 + 生命周期触发”的混合方案。

实时通知

监听：

account/rateLimits/updated

收到后立即更新界面和缓存。

定时轮询

默认每 60 秒执行：

account/rateLimits/read

设置项：

30 秒
1 分钟
5 分钟
15 分钟
仅手动

建议最低限制为 30 秒，不提供每秒轮询。

额外触发

以下情况立即刷新：

* 应用启动
* app-server 初始化完成
* 用户点击刷新
* Mac 从睡眠唤醒
* 网络恢复
* 重置倒计时归零
* 收到 account/updated
* 浮窗重新打开且数据超过 60 秒

并发控制

同一时间只允许一个刷新请求。

guard !isRefreshing else {
    return
}

如果刷新期间再次产生刷新事件，只记录：

needsRefreshAfterCurrentRequest = true

当前请求完成后最多补一次。

⸻

九、UI 方案

9.1 菜单栏

菜单栏标题可以提供三种模式：

仅图标：◉
5h 剩余：5h 78%
最低额度：62%

推荐默认：

C 78%

其中显示 5 小时和周额度中较低的剩余值。

状态颜色语义：

>= 50%：正常
20%～49%：提醒
< 20%：警告
0%：耗尽

不能只依赖颜色，也要显示数值，保证无障碍可读性。

菜单项：

Codex Meter
────────────
显示浮窗
立即刷新
自动刷新：1 分钟
────────────
设置
诊断信息
退出

9.2 浮窗

推荐尺寸：

宽度：320
高度：230
圆角：16

布局：

┌────────────────────────────────┐
│ Codex Meter             ↻  ⚙  │
│ Pro                    已更新  │
│                                │
│ 5 小时额度                     │
│ ███████████████░░░  78% 剩余  │
│ 今天 14:35 重置 · 2小时17分钟 │
│                                │
│ 周额度                         │
│ ███████████░░░░░░░  62% 剩余  │
│ 8月10日 09:00 重置 · 3天22小时│
│                                │
│ ● 已连接 Codex app-server      │
└────────────────────────────────┘

支持：

* 拖动
* 始终置顶开关
* 所有桌面显示
* 单击菜单栏切换显示
* Esc 隐藏
* 记忆窗口位置
* 深色模式
* Reduce Motion
* VoiceOver 标签

9.3 错误状态

Codex 未安装

未找到 Codex CLI
请安装 Codex CLI，或在设置中选择 codex 可执行文件。

未登录 ChatGPT

Codex 尚未登录 ChatGPT
请先在终端运行 codex 并完成登录。

Codex 官方支持使用 ChatGPT 登录，登录信息由 Codex 自己维护；本工具不应读取、复制或保存其 OAuth token。 

API Key 模式

当前 Codex 使用 API Key
ChatGPT 5 小时和周额度仅适用于 ChatGPT 账户模式。

服务崩溃

Codex app-server 已断开
正在重新连接……

数据过期

数据更新失败
显示 10:21 的最后可用数据

⸻

十、缓存设计

缓存只保存展示数据，不保存认证凭证。

struct CachedQuotaSnapshot: Codable {
    let snapshot: CodexQuotaSnapshot
    let cachedAt: Date
    let codexVersion: String?
}

建议：

* 缓存位置：UserDefaults
* 数据有效提示阈值：5 分钟
* 超过 30 分钟仍可展示，但标记“数据已过期”
* 重新连接后立即覆盖

禁止缓存：

* OAuth access token
* refresh token
* ChatGPT account token
* API Key
* app-server stdout 全量日志

⸻

十一、安全原则

1. 只启动用户本机的 codex 二进制。
2. 默认使用 stdio，不监听 TCP 端口。
3. 不读取 ~/.codex 中的认证文件。
4. 不读取浏览器 Cookie。
5. 不注入 ChatGPT token。
6. 不上传额度数据。
7. 不记录账户邮箱到日志。
8. stderr 日志需要过滤可能出现的敏感字段。
9. 不允许用户在普通输入框中粘贴 token。
10. 首版不做自定义远程 app-server 地址。

⸻

十二、工程目录

CodexMeter/
├── CodexMeterApp.swift
├── App/
│   ├── AppDelegate.swift
│   ├── AppState.swift
│   └── DependencyContainer.swift
├── Domain/
│   ├── Models/
│   │   ├── CodexQuotaSnapshot.swift
│   │   ├── QuotaWindow.swift
│   │   └── ConnectionState.swift
│   ├── Services/
│   │   └── QuotaRepositoryProtocol.swift
│   └── Errors/
│       └── CodexMeterError.swift
├── Infrastructure/
│   ├── Codex/
│   │   ├── CodexBinaryLocator.swift
│   │   ├── AppServerProcessManager.swift
│   │   ├── CodexAppServerClient.swift
│   │   ├── JSONLStreamDecoder.swift
│   │   ├── RPCModels.swift
│   │   ├── AccountModels.swift
│   │   ├── RateLimitModels.swift
│   │   └── RateLimitMapper.swift
│   ├── Cache/
│   │   └── QuotaCacheStore.swift
│   ├── Settings/
│   │   └── SettingsStore.swift
│   └── System/
│       ├── WakeObserver.swift
│       └── LaunchAtLoginManager.swift
├── Presentation/
│   ├── ViewModels/
│   │   ├── QuotaViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── MenuBar/
│   │   └── MenuBarContentView.swift
│   ├── FloatingPanel/
│   │   ├── FloatingPanelController.swift
│   │   └── FloatingQuotaView.swift
│   ├── Settings/
│   │   └── SettingsView.swift
│   └── Components/
│       ├── QuotaCardView.swift
│       ├── QuotaProgressView.swift
│       ├── ConnectionBadge.swift
│       └── ErrorStateView.swift
├── Resources/
│   └── Assets.xcassets
├── Tests/
│   ├── JSONLStreamDecoderTests.swift
│   ├── RateLimitMapperTests.swift
│   ├── CodexAppServerClientTests.swift
│   └── Fixtures/
│       ├── rate_limits_standard.json
│       ├── rate_limits_multi_bucket.json
│       ├── rate_limits_missing_secondary.json
│       └── rate_limits_unknown_window.json
└── README.md

⸻

十三、可直接交给 Codex 的开发任务书

Codex Meter macOS 开发任务

你需要在当前目录创建一个完整、可编译、可运行的原生 macOS 项目，项目名称为 CodexMeter。

1. 产品目标

开发一款 macOS 菜单栏和桌面浮窗工具，通过本机 codex app-server 获取当前 ChatGPT Codex 使用额度。

必须支持：

1. 展示 5 小时额度。
2. 展示周额度。
3. 展示已使用百分比。
4. 展示剩余百分比。
5. 展示重置时间。
6. 展示距离重置的倒计时。
7. 自动刷新。
8. 手动刷新。
9. 监听额度变化通知。
10. Codex 未安装、未登录、服务断开时显示清晰错误。
11. 不抓取网页。
12. 不读取浏览器 Cookie。
13. 不直接读取或解析 Codex 认证文件。
14. 不保存任何 OAuth token、API Key 或浏览器凭证。

2. 技术要求

使用：

* Swift
* SwiftUI
* AppKit
* Swift Concurrency
* macOS 14+
* Xcode 原生工程
* 不引入第三方依赖

浮窗使用 NSPanel，菜单栏使用 MenuBarExtra 或等价的 AppKit 实现。

数据层通过 Foundation.Process 启动：

codex app-server --listen stdio://

使用 stdin/stdout 与 app-server 通信。

通信格式是每行一条 JSON 消息的 JSONL。

不要启动 HTTP 服务。

不要默认监听 TCP 端口。

3. 实现顺序

严格按照以下阶段开发。每完成一个阶段，先运行测试或构建，确认成功后再进入下一阶段。

阶段一：初始化工程

1. 创建 CodexMeter.xcodeproj。
2. 创建 macOS App target。
3. Deployment Target 设置为 macOS 14。
4. 配置应用为菜单栏应用。
5. 默认不在 Dock 中显示应用图标。
6. 建立 Domain、Infrastructure、Presentation、Tests 目录。
7. 确保空项目可以成功执行：

xcodebuild \
  -project CodexMeter.xcodeproj \
  -scheme CodexMeter \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

阶段二：实现 CodexBinaryLocator

实现 CodexBinaryLocator。

按以下顺序查找 codex：

1. 用户配置的自定义路径。
2. 当前进程 PATH。
3. /opt/homebrew/bin/codex。
4. /usr/local/bin/codex。
5. ~/.local/bin/codex。
6. ~/bin/codex。
7. 使用 /bin/zsh -lc "command -v codex"。

找到后执行：

codex --version

验证文件可执行且命令能正常退出。

不得把具体用户名写死到路径中。

为以下情况编写测试：

* 自定义路径有效。
* PATH 中存在 codex。
* Homebrew Apple Silicon 路径存在。
* 所有路径均不存在。
* 文件存在但不可执行。
* codex --version 退出码非零。

阶段三：实现 JSONLStreamDecoder

创建一个增量 JSONL 解码器。

要求：

1. 接收任意大小的 Data 分片。
2. 正确处理一条 JSON 被拆分到多个 Data 分片的情况。
3. 正确处理一个 Data 中包含多条 JSON 的情况。
4. 使用换行符切分消息。
5. 忽略纯空白行。
6. 保留最后一条未完整消息。
7. 单条错误 JSON 不得导致后续消息无法处理。
8. 对单条消息设置合理长度上限，例如 4 MB。

测试至少覆盖：

* 一次输入一条完整消息。
* 一条消息拆成三个分片。
* 一次输入三条消息。
* 消息包含 UTF-8 中文。
* 空行。
* 非法 JSON 后跟合法 JSON。
* 超长消息。

阶段四：实现 AppServerProcessManager

通过 Process 启动：

codex app-server --listen stdio://

实现：

* start
* stop
* restart
* write
* stdout 异步读取
* stderr 异步读取
* terminationHandler
* 当前进程状态
* 异常退出通知

要求：

1. 同一时刻只能运行一个子进程。
2. stop 必须关闭 stdin，并终止子进程。
3. 应用退出时清理子进程。
4. stderr 只保留最近 100 行用于诊断。
5. 日志不得打印 token、Authorization header 或 API Key。
6. 子进程异常退出时向上层发送事件。
7. 自动重启采用指数退避，最大 30 秒。
8. 连续失败 5 次后停止自动重启。

阶段五：实现 JSON-RPC 客户端

创建 actor：

actor CodexAppServerClient

实现请求、响应和通知处理。

连接建立后必须执行：

第一步：

{
  "method": "initialize",
  "id": 1,
  "params": {
    "clientInfo": {
      "name": "codex_meter",
      "title": "Codex Meter",
      "version": "0.1.0"
    }
  }
}

收到成功响应后发送：

{
  "method": "initialized"
}

然后才能调用其他方法。

实现：

func connect() async throws
func disconnect() async
func requestRateLimits() async throws -> RateLimitsResultDTO
func requestAccount() async throws -> AccountReadResultDTO
func notifications() -> AsyncStream<AppServerNotification>

请求接口：

{
  "method": "account/rateLimits/read",
  "id": 3
}

账户接口：

{
  "method": "account/read",
  "id": 2,
  "params": {
    "refreshToken": false
  }
}

处理通知：

account/rateLimits/updated
account/updated

每个请求设置 10 秒超时。

进程退出时，所有 pending request 必须以连接中断错误结束。

请求 ID 必须单调递增。

所有 stdin 写操作必须串行。

阶段六：实现额度 DTO 和映射

建立以下 DTO：

struct RateLimitWindowDTO: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval
}
struct RateLimitBucketDTO: Decodable {
    let limitId: String
    let limitName: String?
    let primary: RateLimitWindowDTO?
    let secondary: RateLimitWindowDTO?
    let rateLimitReachedType: String?
    let planType: String?
}
struct RateLimitsResultDTO: Decodable {
    let rateLimits: RateLimitBucketDTO?
    let rateLimitsByLimitId: [String: RateLimitBucketDTO]?
    let rateLimitResetCredits: RateLimitResetCreditsDTO?
}

字段必须兼容缺失值和未知字段。

领域模型：

struct CodexQuotaSnapshot {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?
    let otherWindows: [QuotaWindow]
    let planType: String?
    let reachedType: String?
    let fetchedAt: Date
}

映射规则：

1. 优先解析 rateLimitsByLimitId。
2. 如果不存在，再解析 rateLimits。
3. 同时收集每个 bucket 的 primary 和 secondary。
4. 300 分钟识别为 5 小时额度。
5. 10080 分钟识别为周额度。
6. 5 小时允许正负 5 分钟容差。
7. 周额度允许正负 60 分钟容差。
8. 其他窗口存入 otherWindows。
9. 剩余百分比为 100 - usedPercent。
10. 剩余百分比限制到 0 到 100。
11. 不要假定 primary 永远是 5 小时。
12. 不要假定 secondary 永远是周额度。
13. 根据 limitId + windowDurationMins + resetsAt 去重。

编写至少以下 fixture 和测试：

* primary 为 5 小时，secondary 为周。
* primary 和 secondary 顺序反转。
* 只有 5 小时。
* 只有周额度。
* 多个 limit ID。
* 没有 rateLimitsByLimitId。
* usedPercent 为小数。
* usedPercent 小于 0。
* usedPercent 大于 100。
* resetsAt 在过去。
* 未知窗口时长。
* primary 和 secondary 均为 null。

阶段七：实现 Repository

创建：

protocol QuotaRepositoryProtocol {
    func start() async
    func stop() async
    func refresh() async
    func events() -> AsyncStream<QuotaRepositoryEvent>
}

事件包括：

enum QuotaRepositoryEvent {
    case snapshot(CodexQuotaSnapshot)
    case connectionState(ConnectionState)
    case error(CodexMeterError)
    case account(AccountInfo?)
}

Repository 负责：

* 定位 codex。
* 启动 app-server。
* 完成 initialize。
* 查询 account。
* 查询 rate limits。
* 监听 rateLimits updated。
* 监听 account updated。
* 自动重连。
* 写入缓存。
* 防止并发刷新。
* 请求失败时保留最后成功数据。

阶段八：实现缓存和设置

使用 UserDefaults。

缓存：

* 最近一次成功额度。
* 最近更新时间。
* Codex 版本。

设置：

* 自动刷新开关。
* 刷新间隔。
* 浮窗是否置顶。
* 是否在所有 Space 显示。
* 是否显示 Dock 图标。
* 菜单栏显示模式。
* 用户自定义 codex 路径。
* 浮窗最后位置。

允许刷新间隔：

30 秒
60 秒
300 秒
900 秒
仅手动

不要保存认证信息。

阶段九：实现 QuotaViewModel

QuotaViewModel 必须标记：

@MainActor

状态：

enum QuotaScreenState {
    case loading
    case loaded(CodexQuotaSnapshot)
    case stale(CodexQuotaSnapshot, error: String)
    case codexNotInstalled
    case notLoggedIn
    case unsupportedAuthMode
    case disconnected(message: String)
}

功能：

* 启动 Repository。
* 处理 Repository 事件。
* 手动刷新。
* 自动刷新。
* 防止多个 Timer。
* Mac 睡眠唤醒后刷新。
* 网络恢复后刷新。
* 重置倒计时归零后刷新。
* 每秒更新倒计时文本，但不每秒请求 app-server。

阶段十：实现菜单栏

创建菜单栏入口。

菜单栏显示模式：

1. 仅图标。
2. 5 小时剩余百分比。
3. 5 小时和周额度中的最低剩余百分比。

菜单内容：

* 当前 5 小时额度。
* 当前周额度。
* 显示或隐藏浮窗。
* 立即刷新。
* 打开设置。
* 打开诊断页。
* 退出应用。

刷新时显示轻量加载状态，但不要阻塞菜单操作。

阶段十一：实现浮窗

使用 NSPanel。

要求：

* 320 点左右宽度。
* 无普通标题栏。
* 圆角背景。
* 可拖动。
* 可以置顶。
* 可加入所有 Space。
* 支持全屏辅助显示。
* 失去焦点后默认不自动关闭。
* 单击菜单栏图标切换显示和隐藏。
* Esc 隐藏。
* 记忆窗口位置。
* 支持深色和浅色模式。

浮窗显示：

Codex Meter
当前套餐
最后更新时间
5 小时额度
进度条
剩余百分比
重置绝对时间
重置倒计时
周额度
进度条
剩余百分比
重置绝对时间
重置倒计时
连接状态
手动刷新按钮
设置按钮

进度条表达的是“剩余额度”，标题必须明确写“剩余”，避免用户误解为已使用。

阶段十二：错误页面

实现清晰的错误状态。

Codex 未安装：

未找到 Codex CLI
请安装 Codex CLI，或在设置中选择 codex 可执行文件。

Codex 未登录：

Codex 尚未登录 ChatGPT
请先在终端运行 codex 并完成登录。

API Key 模式：

当前 Codex 使用 API Key
ChatGPT 5 小时和周额度不适用于当前认证模式。

服务断开：

Codex app-server 已断开
正在尝试重新连接。

数据过期：

额度更新失败
当前显示的是最后一次成功获取的数据。

所有错误状态提供：

* 重试按钮。
* 打开诊断信息。
* 在合适情况下选择 Codex 路径。

阶段十三：诊断页

诊断页展示：

* Codex 路径。
* Codex 版本。
* app-server 进程状态。
* 当前连接状态。
* 当前认证模式，但不展示 token。
* 最近成功刷新时间。
* 最近错误。
* 最近 100 行脱敏 stderr。
* 复制诊断信息按钮。

复制内容不得包含：

* OAuth token
* API Key
* Authorization header
* Cookie
* 用户邮箱

阶段十四：测试

必须提供单元测试。

核心测试：

1. JSONL 分片解析。
2. JSON-RPC 请求与响应关联。
3. 请求超时。
4. 进程退出时 pending request 失败。
5. initialize 顺序。
6. 未 initialize 时不能发送业务请求。
7. rate limit DTO 解码。
8. 5 小时识别。
9. 周额度识别。
10. 多 bucket 去重。
11. remaining percent 边界处理。
12. resetsAt 时间转换。
13. 通知触发更新。
14. 并发刷新合并。
15. 缓存读取和写入。

对 Process 层做协议抽象，不要让测试依赖真实 Codex 安装。

创建：

protocol AppServerTransport {
    func start() async throws
    func stop() async
    func send(_ data: Data) async throws
    func incomingData() -> AsyncStream<Data>
    func events() -> AsyncStream<TransportEvent>
}

生产环境实现 ProcessAppServerTransport，测试实现 MockAppServerTransport。

阶段十五：README

README 必须包含：

1. 项目功能。
2. 系统要求。
3. Codex CLI 前置要求。
4. 构建步骤。
5. 运行步骤。
6. 工作原理。
7. 使用的 app-server 方法。
8. 隐私说明。
9. 常见错误。
10. 当前限制。
11. app-server 协议变化的兼容策略。

明确说明：

* 本项目不抓网页。
* 本项目不读取浏览器 Cookie。
* 本项目不保存 ChatGPT token。
* 本项目依赖 Codex app-server，目前该接口可能随 Codex 版本变化。

4. 完成标准

只有全部满足以下条件才算完成：

* Xcode 工程可以打开。
* Debug 构建成功。
* 应用可以显示菜单栏入口。
* 应用可以启动本机 codex app-server。
* 完成 initialize 和 initialized 握手。
* 能调用 account/rateLimits/read。
* 能解析 5 小时额度。
* 能解析周额度。
* 能显示剩余百分比。
* 能显示重置时间。
* 能显示本地倒计时。
* 能自动刷新。
* 能处理 account/rateLimits/updated。
* 能处理 Codex 未安装。
* 能处理用户未登录。
* 能处理子进程退出。
* 所有测试通过。
* 不存在编译警告。
* 不包含 token、Cookie 或网页抓取代码。

5. 最终执行

开发完成后执行：

xcodebuild \
  -project CodexMeter.xcodeproj \
  -scheme CodexMeter \
  -configuration Debug \
  -destination 'platform=macOS' \
  clean build

然后执行测试：

xcodebuild \
  -project CodexMeter.xcodeproj \
  -scheme CodexMeter \
  -destination 'platform=macOS' \
  test

修复所有编译错误和测试失败。

最终输出：

1. 创建和修改的文件清单。
2. 核心架构说明。
3. app-server 握手流程。
4. 额度识别规则。
5. 构建结果。
6. 测试结果。
7. 当前仍存在的限制。
8. 手动验收步骤。

不要只生成设计文档。必须实际创建完整工程、实现代码、执行构建并修复错误。


https://learn.chatgpt.com/docs/app-server