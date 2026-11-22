# Current State Gap Analysis

## 目的

这一份文档回答一个对后续 AI 非常重要的问题：

“哪些个人版 Termius 能力在当前仓库里已经有实现或测试基础，哪些才是真正应该继续开发的缺口？”

如果没有这份文档，后续 AI 很容易重复实现已经存在的切片，或者把精力放错到低优先级方向。

## 评估时间点

本分析基于 `2026-06-21` 的当前仓库状态整理。

## 结论摘要

`MobileShell` 并不是从零开始。

当前仓库已经覆盖了：

- Phase A 全部核心基座能力
- Phase B 绝大部分个人增强能力
- `Mosh` 的个人版主路径与真实主机联调验证
- 主要工程整理目标，包括 `MobileShellStore` 逻辑与 broad store tests 的大规模拆分

当前最清晰、最值得继续推进的方向是：

- 回到明确仍有缺口的功能项，例如 `Telnet / Serial`
- 继续打磨体验层问题，例如主机元数据展示、SFTP 大文件与覆盖反馈

仍应明确延后的方向：

- `C1: Personal cloud sync`

当前产品决策：

- `C1: Personal cloud sync` 暂时不考虑，不进入近期开发主线

## 路线图对照

### Phase A：Daily Driver 基座

#### A1 Host 基础模型与列表体验

状态：`已具备`

证据：

- `ShellHost` 与 Host CRUD 测试已存在
- [MobileShellTests/MobileShellStoreTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/MobileShellStoreTests.swift)
- [MobileShellTests/Features/Hosts/HostTagNavigationTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Hosts/HostTagNavigationTests.swift)
- [MobileShell/ShellRootView.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/ShellRootView.swift)

已覆盖内容：

- Host 增删改
- 分组展示
- 标签筛选
- 搜索
- 从 Host 进入终端与 SFTP

#### A2 身份、凭证与 Known Hosts

状态：`已具备`

证据：

- [MobileShellTests/MobileShellPersistenceTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/MobileShellPersistenceTests.swift)
- [MobileShellTests/Features/HostGroups/HostGroupIdentityTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/HostGroups/HostGroupIdentityTests.swift)
- [MobileShellTests/Features/Keychain/SSHCertificateTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Keychain/SSHCertificateTests.swift)
- [MobileShell/Models.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/Models.swift)
- [MobileShell/Persistence.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/Persistence.swift)

已覆盖内容：

- Host / Identity 关系
- Keychain / 凭证层分离
- SSH key 与 certificate
- Known Hosts 信任流程

#### A3 SSH 终端生命周期

状态：`已具备`

证据：

- [MobileShellTests/MobileShellStoreTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/MobileShellStoreTests.swift)
- [MobileShell/ShellConnection.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/ShellConnection.swift)

已覆盖内容：

- 打开终端
- 多会话切换
- 重连
- 交互式 shell
- 主机信任挑战重试
- 键盘快捷操作

#### A4 SFTP 核心工作流

状态：`已具备`

证据：

- [MobileShellTests/MobileShellStoreTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/MobileShellStoreTests.swift)
- [MobileShell/ShellConnection.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/ShellConnection.swift)
- [MobileShell/ShellRootView.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/ShellRootView.swift)

已覆盖内容：

- 浏览目录
- 上传下载
- 新建目录
- 重命名
- 删除
- 错误反馈

#### A5 Port Forwarding 核心工作流

状态：`已具备`

证据：

- [MobileShellTests/MobileShellStoreTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/MobileShellStoreTests.swift)
- [MobileShellTests/Features/PortForwarding/PortForwardingTypeTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/PortForwarding/PortForwardingTypeTests.swift)
- [MobileShellTests/Services/PortForwarding/DynamicPortForwardingEndToEndIntegrationTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Services/PortForwarding/DynamicPortForwardingEndToEndIntegrationTests.swift)

已覆盖内容：

- 本地与远端端口转发
- 动态端口转发（SOCKS5 `CONNECT`）
- 启停
- 类型化规则
- 失败反馈

说明：

- 当前个人版端口转发三种类型都已有实现入口；动态转发范围明确锁定在 `SOCKS5 + no-auth + CONNECT`。
- 动态转发已经补上真实主机联调验证：通过本地 SOCKS 代理连接远端主机自身的 `127.0.0.1:22`，可以读到 SSH banner。

#### A6 Snippets 基础工作流

状态：`已具备`

证据：

- [MobileShellTests/MobileShellStoreTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/MobileShellStoreTests.swift)
- [MobileShellTests/Features/Snippets/StartupSnippetTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Snippets/StartupSnippetTests.swift)
- [MobileShellTests/Features/Snippets/SnippetPackageTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Snippets/SnippetPackageTests.swift)
- [MobileShellTests/Features/Snippets/SnippetMultiExecutionTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Snippets/SnippetMultiExecutionTests.swift)

已覆盖内容：

- Snippet CRUD
- Startup snippets
- Package 组织
- 多会话执行

#### A7 Workspace 与基础日志

状态：`已具备`

证据：

- [MobileShellTests/Features/Workspaces/TerminalWorkspaceTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Workspaces/TerminalWorkspaceTests.swift)
- [MobileShellTests/Features/Workspaces/TerminalWorkspaceTemplateTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Workspaces/TerminalWorkspaceTemplateTests.swift)
- [MobileShellTests/Features/Logs/SessionLogTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Logs/SessionLogTests.swift)
- [MobileShell/Features/Logs/SessionLogsView.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/Features/Logs/SessionLogsView.swift)

已覆盖内容：

- 本地工作区
- 会话归属
- Workspace templates
- 基础 session logs

## Phase B：Personal Power Features

### B1 Group / Host 继承能力完善

状态：`已大体具备`

证据：

- [MobileShellTests/Features/HostGroups/HostGroupIdentityTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/HostGroups/HostGroupIdentityTests.swift)
- [MobileShellTests/Features/HostChains/HostChainTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/HostChains/HostChainTests.swift)
- [MobileShellTests/Features/Environment/HostEnvironmentVariableTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Environment/HostEnvironmentVariableTests.swift)
- [MobileShellTests/Features/Terminal/TerminalThemeInheritanceTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Terminal/TerminalThemeInheritanceTests.swift)
- [MobileShellTests/Features/Terminal/TerminalFontSizeInheritanceTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Terminal/TerminalFontSizeInheritanceTests.swift)

已覆盖内容：

- group identity
- jump host / host chain
- startup snippet inheritance
- environment variables
- terminal theme / font size inheritance

### B2 Workspace 高级能力

状态：`已大体具备`

证据：

- [MobileShellTests/Features/Workspaces/TerminalWorkspaceTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Workspaces/TerminalWorkspaceTests.swift)
- [MobileShellTests/Features/Workspaces/TerminalWorkspaceTemplateTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Workspaces/TerminalWorkspaceTemplateTests.swift)

已覆盖内容：

- workspace templates
- command broadcast

### B3 Snippets 高级能力

状态：`已具备`

证据：

- [MobileShellTests/Features/Snippets/StartupSnippetTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Snippets/StartupSnippetTests.swift)
- [MobileShellTests/Features/Snippets/SnippetMultiExecutionTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Snippets/SnippetMultiExecutionTests.swift)
- [MobileShellTests/Features/Snippets/SnippetPackageTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Snippets/SnippetPackageTests.swift)

### B4 Autocomplete 与终端体验增强

状态：`已大体具备`

证据：

- [MobileShellTests/Features/Autocomplete/CommandAutocompleteTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/Features/Autocomplete/CommandAutocompleteTests.swift)
- [MobileShellTests/MobileShellStoreTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/MobileShellStoreTests.swift)

已覆盖内容：

- command autocomplete
- 终端快捷输入辅助

### B5 Logs 增强

状态：`已具备`

现有基础：

- 已有 session logs 模型和列表页
- 已有日志持久化
- 已有 per-session 行输出捕获
- 已有 log bookmarks
- 已有日志卡片点击进入 detail sheet 的完整交互

已覆盖内容：

- session logs 列表
- 日志详情查看
- 日志持久化
- per-session 行输出捕获
- log bookmarks
- bookmark persistence in saved session logs
- bookmark creation from log detail lines
- 卡片点击打开详情流

## Phase C：Selective Premium Personal

### C1 个人同步能力

状态：`未开始`

说明：

- 当前仓库没有个人云端 vault 或跨设备同步实现
- 这不是短板，而是有意延后

### C2 可选协议增强

状态：`Mosh 已具备，Telnet / Serial 未开始`

说明：

- 当前仓库已具备可交付的个人版 `Mosh` 运行时路径
- `Telnet / Serial` 仍未开始
- `Mosh` 已完成的范围：
- Host 协议建模、配置保存、列表标识
- `mosh-server` preparation 结果解析与错误分类
- experimental Mosh preparation 可解析远端 `SSH_CONNECTION` IP
- SSH 驱动的 preparation client
- live Citadel stream-first preparation client
- `MobileShellStore` 内的 Mosh preparation/runtime 编排边界与失败文案测试
- live Mosh session 的 reconnect 路径
- iOS-only vendored `mosh.xcframework`
- iOS-only vendored `Protobuf_C_.xcframework`
- `locales.bundle` app resource wiring
- Objective-C++ bridge scaffold 与 Swift wrapper 控制面测试
- `MoshRuntimeClientBridge` 的 `connect / output / send / close` 单元测试
- runtime bridge 会优先使用 preparation 阶段解析出的远端 IP
- 持久化 store 工厂默认已注入 live `MoshPreparationClient` 与 `MoshRuntimeClient`
- 真实远端 `mosh-server` 端到端联调已经通过：
- 测试主机：`192.168.2.204`
- 已验证 `prepare-only` 和 `full session`
- 已验证 `uname -a` 命令发送、输出回传、session 收尾
- 当前剩余缺口：
- `Telnet / Serial` 仍未实现
- `Mosh` 还缺更广的会话质量验证，例如长时间稳定性、网络切换、复杂交互式程序、raw terminal 边界场景

## 结构性风险

当前结构风险已经明显下降，但仍有一个需要持续关注的热点：

1. [MobileShell/ShellRootView.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/ShellRootView.swift) 仍然偏大

说明：

- [MobileShell/Models.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShell/Models.swift) 已从历史热点收敛到约 `1k` 行量级
- [MobileShellTests/MobileShellStoreTests.swift](/Users/xuhuihui/my-project/mobile-shell/MobileShellTests/MobileShellStoreTests.swift) 已从 broad catch-all 收敛到较小残余集
- 仓库已经切换到 [project.yml](/Users/xuhuihui/my-project/mobile-shell/project.yml) + `xcodegen` 的工程生成方式，降低了手工维护 `pbxproj` 的风险

后续开发必须遵守：

- 新功能优先以 feature-local 文件落地
- 在碰到相关区域时顺手抽离边界
- 不得因为“功能已经很多了”就继续向热点文件堆实现

## 对后续 AI 的直接指令

如果你准备继续开发这个项目：

1. 先读 [README.md](/Users/xuhuihui/my-project/mobile-shell/docs/product/termius-personal/README.md)
2. 再读本文件
3. 不要重新实现已经被本文件标记为“已具备”的切片
4. 优先处理仍有明确用户价值但尚未落地的功能缺口
5. 在开始新切片前，先确认它没有落入已具备范围
