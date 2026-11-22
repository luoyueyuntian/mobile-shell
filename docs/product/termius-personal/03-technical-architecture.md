# Technical Architecture

## 架构目标

技术架构必须服务于以下结果：

- 让个人版能力可以按切片持续演进
- 不把新功能继续堆进 `MobileShell/ShellRootView.swift` 和 `MobileShell/Models.swift`
- 把 SSH / SFTP / Port Forwarding / Persistence 等边界层隔离出来，便于测试和替换
- 在保持当前项目可增量演进的前提下，逐步向目标结构收敛

## 强制遵守的上层约束

这一份文档建立在以下仓库约束之上：

- [AGENTS.md](../../../AGENTS.md)
- [docs/project-constraints.md](../../project-constraints.md)

尤其必须遵守：

- 依赖方向：`View -> Store -> Service/Persistence -> External library`
- 不向 `ShellRootView.swift` 继续堆大块 UI
- 不向 `Models.swift` 继续堆 unrelated store logic
- 新模块优先放入 `Features/`、`Shared/`、`Services/`、`Persistence/`

## 当前代码库现实

当前项目已经具备一些个人版 Termius 所需的核心类型与集成：

- 根视图：`MobileShell/ShellRootView.swift`
- 入口：`MobileShell/MobileShellApp.swift`
- 主 Store 与大量模型：`MobileShell/Models.swift`
- SSH / terminal / SFTP / port forwarding 集成：`MobileShell/ShellConnection.swift`
- 本地持久化与 Keychain：`MobileShell/Persistence.swift`

这意味着当前阶段应采用“增量抽离”而不是“大重写”策略。

## 目标模块图

### App 层

- `MobileShell/MobileShellApp.swift`
- 负责应用入口和顶层 store 装配

### Feature 层

建议按以下能力拆分：

- `MobileShell/Features/Hosts/`
- `MobileShell/Features/HostGroups/`
- `MobileShell/Features/Terminal/`
- `MobileShell/Features/Workspaces/`
- `MobileShell/Features/SFTP/`
- `MobileShell/Features/PortForwarding/`
- `MobileShell/Features/Snippets/`
- `MobileShell/Features/Logs/`
- `MobileShell/Features/Autocomplete/`
- `MobileShell/Features/Environment/`

说明：

- 如果当前仓库中某个能力还没被完全抽出来，后续新增代码也要优先放到目标目录里，而不是继续扩展根文件。

### Shared 层

- `MobileShell/Shared/Models/`
- `MobileShell/Shared/Views/`
- `MobileShell/Shared/Components/`
- `MobileShell/Shared/Extensions/`

Shared 层只承载跨 feature 的小而稳定的复用件，不承载产品流程。

### Services 层

建议逐步形成以下边界：

- `MobileShell/Services/SSH/`
- `MobileShell/Services/Terminal/`
- `MobileShell/Services/SFTP/`
- `MobileShell/Services/PortForwarding/`

当前已存在的协议与集成接口可以作为过渡基础：

- `ShellConnectionClient`
- `SSHCommandExecuting`
- `TerminalShellClient`
- `TerminalShellSession`
- `SFTPDirectoryListingClient`
- `PortForwardingClient`
- `PortForwardingSession`

### Persistence 层

建议逐步形成以下边界：

- `MobileShell/Persistence/Repositories/`
- `MobileShell/Persistence/Credentials/`
- `MobileShell/Persistence/Snapshots/`

当前已存在的边界基础：

- `JSONHostRepository`
- `CredentialVault`
- `KeychainCredentialVault`
- `HostPersistenceSnapshot`

## 权威领域模型

后续 AI 应优先复用或演进这些既有术语，而不是重新发明平行模型：

- `ShellHost`
- `SSHIdentity`
- `SSHKey`
- `SSHCertificate`
- `KnownHost`
- `PortForwardRule`
- `ShellSnippet`
- `TerminalSession`
- `TerminalWorkspace`
- `TerminalWorkspaceTemplate`
- `SessionLog`
- `HostGroupProfile`

领域规则：

- `Host` 是所有远程行为的锚点
- `Identity` 是可复用的认证组合
- `HostGroupProfile` 是继承配置的主要承载位置
- `Workspace` 组织终端会话上下文，而不是替代 Host 组织
- `SessionLog` 记录个人历史，不承担团队审计职责

## Store 组织策略

### 当前阶段

`MobileShellStore` 仍可作为组合根存在，但新增逻辑不应再直接无界增长。

### 推荐演进方式

- 把每个新增能力先拆成独立 model / view / helper store
- 由 `MobileShellStore` 做顶层编排和状态桥接
- 当某个能力拥有独立状态机时，为它引入 feature store 或 coordinator

### 禁止的做法

- 在 `MobileShellStore` 中继续叠加大段无关 UI 逻辑
- 让 view 直接调用 `Citadel`、`NIO` 或 `Security`
- 把云同步、团队共享等未启用能力先塞进 store 结构里

## 关键数据流

### 1. 打开终端

`Host row -> Terminal feature action -> Store resolves identity and known hosts -> Terminal service opens shell -> Session state updates -> Terminal view renders output`

要求：

- identity 解析与 jump chain 解析在 store/service 边界完成
- UI 层只触发动作，不自己拼接 SSH 请求

### 2. 打开 SFTP

`Host row -> Store builds connection request -> SFTP service loads directory -> Store updates path/items/loading/error -> SFTP view renders`

要求：

- 路径导航与 loading/error 状态在 store 层清晰可测
- 文件操作失败必须可见

### 3. 启停端口转发

`PortForwarding view -> Store validates rule -> PortForwarding service starts/stops session -> Store records active session and status`

要求：

- 规则编辑和规则运行状态分离
- 端口冲突、认证失败、连接失败要保留明确错误信息

### 4. 执行命令片段

`Snippet picker -> Store resolves target session(s) -> Terminal service send input -> Session log/history updates`

要求：

- 单会话执行先于多会话广播
- 自动化行为必须可追踪，不能静默失败

## 持久化原则

### 本地数据分层

- 普通结构数据：JSON snapshot
- 敏感数据：Keychain / credential vault
- 运行中会话：内存态，可恢复元数据按需持久化

### 兼容性要求

- snapshot 解码默认使用 `decodeIfPresent` 风格的向后兼容策略
- 新字段必须有安全默认值
- 不允许因为某个新功能字段缺失，导致旧数据整仓不可读

## 同步能力的架构约束

如果后续引入“个人同步”，必须满足：

- 不改变首发版 local-first 前提
- 不让 view 直接感知云同步细节
- 通过 repository 或 sync engine 边界注入
- 冲突处理策略先文档化，再实现

在这些条件满足前，不允许为了未来同步而在当前架构中引入无用复杂度。

## 测试架构

### 单元测试重点

- Host 过滤、搜索、组织
- identity 解析与继承
- known host 信任流程
- terminal session 生命周期
- SFTP 路径与文件操作状态更新
- port forwarding 规则与状态切换
- workspace、log、snippet 的持久化与恢复

### 目录规则

测试应镜像生产结构：

- `MobileShellTests/Features/Hosts/`
- `MobileShellTests/Features/Terminal/`
- `MobileShellTests/Features/Workspaces/`
- `MobileShellTests/Services/`
- `MobileShellTests/Persistence/`

## 演进原则

每次功能工作都应该至少做到下面之一：

- 增加新能力
- 顺手把目标区域往清晰边界推近一步

不允许出现这种情况：

- 功能做了，但 `ShellRootView.swift` 和 `Models.swift` 更难维护
- 为未来假想功能引入大量当前不用的抽象
