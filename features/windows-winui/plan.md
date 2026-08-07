# Implementation And Validation Plan

## Target

Spec: 用户请求（会话）：生成独立的 .NET 8 + WinUI 3 Windows `.msix` 安装包
Spec Review: None identified
Owner: 王成龙
Last Updated: 2026-08-07

Status: Complete

## Context Reviewed

- instructions: AGENTS.md
- spec: 用户请求（会话），已确认 .NET 8 + WinUI 3
- review: None identified
- code/tests/docs: `CodexMeter/Infrastructure/CodexAppServerClient.swift`、`CodexMeter/Infrastructure/AppServerTransport.swift`、`CodexMeter/Domain/Models.swift`、`Scripts/build-app.sh`、`README.md`

## Summary

- Goal: 新增独立 Windows WinUI 3 客户端，并由 GitHub Actions 在 Windows Runner 产出 `.msix`。
- Non-Goals: 不修改 macOS 应用代码；不提供未获授权的代码签名证书或商店发布。
- Primary Risk: 当前 macOS 主机不能编译或安装 WinUI/MSIX，需以 GitHub Actions 作为实际构建证据。

## Open Questions

| Question | Owner | Blocks Development | Target Date |
|---|---|---|---|
| 正式发布用的代码签名证书 | 王成龙 | No | 发布正式版前 |

## Implementation Approach

- 在 `Windows/CodexMeter.Windows/` 中新建单项目 MSIX 的 WinUI 3 工程，Windows 端只拥有自己的界面、托盘和进程通信代码。
- 复用 macOS 客户端与 `codex app-server --listen stdio://` 的 JSON-RPC 契约，不引用或编译 Swift 源文件。
- 通过 `.github/workflows/windows-msix.yml` 在 `windows-latest` 中恢复、构建并上传 `.msix` 工件。

Architecture Check:
- Boundary: `Windows/` 仅包含 Windows 代码；`CodexMeter/` 继续仅包含 macOS 代码。
- SSOT: Codex app-server JSON-RPC 协议及现有 macOS 字段映射。
- Existing Mechanism: 本机子进程的 stdin/stdout JSONL 通信。
- Interface: Windows 的 `CodexClient` 直接封装 JSON-RPC，不建立跨平台抽象层。
- Docs: README 增加 Windows 构建与安装说明。
- Locality: 所有 Windows 实现限制在 `Windows/` 与单个 GitHub Actions 工作流。
- Design Checks: 改动扩散通过目录隔离避免；不引入仅有一个实现的跨平台接口。
- Test Target: 解析的剩余额度、Codex 可执行文件定位、MSIX 工作流产物路径。
- Refactor Needed First: None identified
- Separate long-term architecture decision doc needed: No，当前仅新增单一 Windows 客户端。

TDD Planning:
- Use TDD for slices where a public behavior can be tested first.
- 不为 WinUI 视图编造无法在 macOS 执行的本地测试；解析和定位逻辑采用 Windows 项目单元测试，实际打包由 CI 验证。

## Key Decisions

| Decision | Rationale | Rejected Alternative |
|---|---|---|
| `Windows/` 独立 WinUI 3 项目 | 保持平台 UI 与打包规则各自维护，避免 AppKit/WinUI 条件编译 | 在 Swift 项目中交叉编译 Windows，AppKit 不支持且维护边界不清 |
| GitHub Actions Windows Runner 打包 | 当前开发机为 macOS，Runner 具备 Windows SDK 与 MSIX 工具链 | 在 macOS 模拟 Windows 打包，不能验证 WinUI/MSIX |
| 初版未签名 MSIX | 未提供发布证书，仍可产生 CI 工件供测试 | 生成并长期使用自签名证书，用户安装体验和安全性较差 |

## Affected Surface

| Area | Files / Modules | Expected Change | Risk |
|---|---|---|---|
| Windows 客户端 | `Windows/CodexMeter.Windows/` | WinUI 3 UI、Codex 通信和本地设置 | Medium |
| Windows 测试 | `Windows/CodexMeter.Windows.Tests/` | 额度映射和路径定位测试 | Low |
| 构建产物 | `.github/workflows/windows-msix.yml` | Windows MSIX CI 工件 | Medium |
| 文档 | `README.md` | Windows 安装与开发说明 | Low |

## Execution Plan

1. 建立独立 Windows 应用与核心额度查询
   - Outcome: Windows 用户可输入或自动定位 Codex，并显示 5 小时和周额度。
   - Human Review: No (agent-only)
   - Status: Complete
   - Touches: `Windows/CodexMeter.Windows/`
   - Dependencies: None identified
   - Validation: Windows 单元测试与 GitHub Actions 构建日志。
   - Recovery: 删除 `Windows/` 目录即可完全回退，不影响 macOS。
2. 加入 MSIX 自动构建
   - Outcome: 推送后产生可下载的 Windows `.msix` 工件。
   - Human Review: No (agent-only)
   - Status: Complete
   - Touches: `.github/workflows/windows-msix.yml`
   - Dependencies: 切片 1
   - Validation: GitHub Actions 工件和 `msbuild` 打包日志。
   - Recovery: 禁用工作流，不影响源代码和 macOS 发布。
3. 补齐使用文档
   - Outcome: 用户可区分 macOS `.app` 与 Windows `.msix` 的下载和安装方式。
   - Human Review: Yes (HITL)
   - Status: Complete
   - Touches: `README.md`
   - Dependencies: 切片 2
   - Validation: 文档链接与实际 CI 产物路径一致。
   - Recovery: 回退文档与工作流提交。

## Validation Plan

| Acceptance / Risk | Validation Method | Expected Evidence |
|---|---|---|
| Windows 与 macOS 源码隔离 | 目录与项目引用检查 | Windows 项目不引用 `CodexMeter/` Swift 文件 |
| JSON-RPC 额度映射 | Windows 单元测试 | 五小时/周额度及剩余百分比测试通过 |
| MSIX 可生成 | GitHub Actions `windows-latest` | 可下载的 `.msix` 工件 |
| 未签名包的安装限制清晰 | README 审核 | 明确说明测试包需要受信任签名后才能面向普通用户分发 |

## Coverage Expectations

- Existing coverage command: `dotnet test Windows/CodexMeter.Windows.Tests/CodexMeter.Windows.Tests.csproj`（在 Windows Runner）
- Expected new or updated tests: 额度映射与路径优先级。
- Coverage threshold or target: TBD

## Rollback / Recovery

- 删除 `Windows/` 与 `.github/workflows/windows-msix.yml` 即可回退；不影响 `CodexMeter/` 的 macOS 应用。

## Assumptions

- 用户的 Windows 环境已安装并登录 Codex CLI，或安装了包含 Codex 的 ChatGPT Windows 应用。
- 初版允许以 CI 工件形式提供未签名 `.msix`，正式公开分发前由用户提供代码签名证书。
