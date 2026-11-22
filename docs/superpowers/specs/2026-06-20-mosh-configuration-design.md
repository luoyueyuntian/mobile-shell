# Mosh Configuration Design

## Goal

为 `MobileShell` 增加个人版 `Mosh` 协议建模能力，让用户可以把 Host 配置为 `Mosh` 类型并保存相关参数，同时保持当前运行时仍只支持 `SSH` 真实连接。

这一切片的目标不是实现真实 `Mosh` 会话，而是把协议抽象、Host 配置、UI 入口和持久化先打通，避免后续接入真实 `Mosh` 传输时返工 Host 模型和产品入口。

## Scope

本次切片包含：

- 为 Host 增加 `SSH / Mosh` 协议选择
- 为 `Mosh` Host 增加本地可保存配置
- 在 Host 列表中展示 `Mosh` 协议标识
- 在终端入口中对 `Mosh` Host 给出明确“未实现运行时”的产品级提示
- 本地 JSON 持久化与兼容解码
- 针对模型、持久化、Store 和 UI 条件显示的测试

本次切片不包含：

- 真实 `Mosh` 会话传输
- `mosh-server` 探测或启动
- UDP 建链
- roaming / reconnect / predictive transport
- 云同步
- 团队协作
- 对 `SFTP` / `Port Forwarding` 增加新的 `Mosh` 特殊语义

## Product Behavior

### 1. Host Protocol

每个 Host 增加协议类型，首批支持：

- `ssh`
- `mosh`

默认协议为 `ssh`。

### 2. Mosh Configuration

当 Host 协议为 `mosh` 时，用户可以保存以下配置：

- `udpPort`
- `serverCommand`
- `predictiveEcho`
- `useExperimentalConnection`

默认值：

- `udpPort = 60001`
- `serverCommand = "mosh-server new -s"`
- `predictiveEcho = true`
- `useExperimentalConnection = false`

### 3. Add / Edit Host

在 `AddHostSheet` 和 `EditHostSheet` 中：

- 增加 `Protocol` 选择器
- 选择 `ssh` 时，保持当前 UI 体验不变
- 选择 `mosh` 时，显示 `Mosh` 配置区

本次切片不要求在 `mosh` 模式下隐藏现有 SSH 世界字段，例如：

- password
- ssh key
- identity
- jump host

原因：

- 后续真实 `Mosh` 接入很可能仍依赖现有 SSH 世界的认证和路由信息
- 这一步先做协议建模，不做传输层裁剪

### 4. Host List

在 Host 列表中，`mosh` Host 需要有明确的轻量协议标识。

要求：

- `ssh` Host 不强制额外强调
- `mosh` Host 必须一眼可识别
- 标识应足够轻，不压过现有连接状态、认证摘要、路由摘要

### 5. Terminal Entry

当用户从 Host 列表尝试打开 `mosh` Host 的终端时：

- 不得静默回退到 `ssh`
- 不得创建假终端 session
- 不得调用现有 `TerminalShellClient`
- 必须显示一个明确的产品级提示

提示语义要求：

- 告诉用户该 Host 的 `Mosh` 配置已保存
- 明确当前版本尚未实现真实 `Mosh` 会话
- 不把这件事表达成技术错误或用户配置错误

### 6. SFTP / Port Forwarding

本次切片不改变：

- `SFTP`
- `Port Forwarding`

它们继续保持当前 `SSH` 语义，不为 `Mosh` 引入新行为或新分支。

## Data Model

### 1. Protocol Type

新增协议枚举：

```swift
enum RemoteAccessProtocol: String, CaseIterable, Codable, Sendable {
    case ssh
    case mosh
}
```

### 2. Mosh Configuration

新增配置模型：

```swift
struct MoshHostConfiguration: Equatable, Codable, Sendable {
    var udpPort: Int
    var serverCommand: String
    var predictiveEcho: Bool
    var useExperimentalConnection: Bool
}
```

建议提供默认值构造：

```swift
extension MoshHostConfiguration {
    static let `default` = MoshHostConfiguration(
        udpPort: 60001,
        serverCommand: "mosh-server new -s",
        predictiveEcho: true,
        useExperimentalConnection: false
    )
}
```

### 3. ShellHost Extension

在 `ShellHost` 上增加：

- `protocol`
- `moshConfiguration`

要求：

- 旧数据没有这些字段时，兼容解码
- 默认协议回落为 `ssh`
- 默认 `moshConfiguration` 可为 `nil`

### 4. Persistence Compatibility

所有新增字段必须采用向后兼容解码：

- `decodeIfPresent`
- 安全默认值

旧版 Host JSON 在没有协议字段时必须仍能成功加载。

## Architecture

### View Layer

View 负责：

- 展示协议选择器
- 在 `mosh` 时展示配置区
- 在 Host 列表中展示协议标识
- 在终端入口中展示“未实现”的产品提示

View 不负责：

- 协议运行时分流实现
- 真实会话传输
- 构造低层连接请求

### Store Layer

Store 负责：

- 保存和更新 Host 的协议与 `Mosh` 配置
- 对 `mosh` Host 的终端入口做受控分流
- 统一返回“未实现运行时”的产品提示

Store 不负责：

- 伪造终端会话
- 通过 SSH client 假装连通 `mosh`

### Service / Connection Layer

本次切片不新增真实 `Mosh` runtime。

但从架构上要形成清晰分流点：

- `ssh` 继续走当前链路
- `mosh` 进入受控未实现分支

这样后续接入真实 `Mosh` 时，可以替换该分支而不是重做 UI / Host 模型。

## UI Flow

### Add Host Flow

1. 用户打开新增 Host 表单
2. 默认协议为 `SSH`
3. 切换到 `Mosh`
4. 展示 `Mosh` 配置区
5. 用户填写并保存
6. Host 在本地持久化为 `mosh`

### Edit Host Flow

1. 用户打开已有 Host 编辑页
2. 切换协议
3. 表单根据协议显示或隐藏 `Mosh` 配置区
4. 保存后 Host 协议状态更新

### Open Terminal Flow

1. 用户点击 `Mosh` Host 的终端入口
2. Store 判断 `host.protocol == .mosh`
3. 不创建 session
4. 显示产品级提示

## Testing

### Model / Persistence

- `RemoteAccessProtocol` round-trip
- `MoshHostConfiguration` round-trip
- 旧版 `ShellHost` JSON 无协议字段时仍能成功解码
- 保存 `Mosh` Host 后重新加载仍保留协议与配置

### Store / Behavior

- 新建 `Mosh` Host 时协议和配置被正确保存
- 编辑 `SSH` Host 为 `Mosh` 时协议状态正确更新
- 编辑 `Mosh` Host 回 `SSH` 时行为符合设计
- 打开 `Mosh` Host 终端时：
  - 不创建终端 session
  - 不调用现有 `TerminalShellClient`
  - 返回明确提示

### UI

- `Protocol` 切换到 `Mosh` 时显示配置区
- 切回 `SSH` 时隐藏配置区
- Host 列表显示 `Mosh` 标识
- `Mosh` 终端入口会触发未实现提示

## Acceptance Criteria

以下条件全部满足时，本切片可验收：

1. 用户可以创建并保存 `Mosh` Host
2. 用户可以编辑已有 Host 为 `Mosh`
3. `Mosh` 配置在应用重启后仍然存在
4. Host 列表中 `Mosh` Host 可被识别
5. 用户尝试打开 `Mosh` 终端时，看到明确提示
6. 不创建假 session，不回退成 SSH
7. 现有 `SSH` Host 行为不回归
8. 不引入云同步、团队能力或真实 `Mosh` 传输

## Non-Goals

这一切片明确不解决：

- 真实 `Mosh` 连接实现
- `mosh-server` 生命周期
- UDP 会话建立
- 网络切换恢复
- `SFTP` over `Mosh`
- `Port Forwarding` over `Mosh`
- 云端同步

## Why This Slice Is Right Now

这一步适合作为 `Mosh` 首切片，因为它：

- 不会破坏现有 SSH 主链路
- 能尽快让产品模型正式支持多协议
- 让后续真实 `Mosh` 接入有稳定 Host/UI 边界可复用
- 避免一开始就把项目拖入协议运行时复杂度
