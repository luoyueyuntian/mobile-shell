# Dynamic Port Forwarding V1 Design

## Goal

让 `MobileShell` 的 `dynamic` port forwarding 规则首次具备真实可启动能力。

这一切片的目标不是一次性做完完整 SOCKS 代理栈，而是在保持现有 local / remote forwarding 结构稳定的前提下，补上一条最小但真实可用的动态转发路径：

1. 在本地启动一个 SOCKS5 listener
2. 通过现有 SSH 会话按请求建立 `direct-tcpip` channel
3. 仅支持个人版最常见的 `TCP CONNECT` 代理场景
4. 继续复用现有 rule model、store orchestration、开关和历史记录

## Scope

本次切片包含：

- 为 `PortForwardKind.dynamic` 增加真实可启动的本地 SOCKS5 listener
- 支持 SOCKS5 greeting 与 `CONNECT` request
- 支持 `IPv4`、`domain name`、`IPv6` 三种目标地址编码
- 在 SSH 侧复用现有 `createDirectTCPIPChannel` 能力连接目标主机和端口
- 让 store 可以像 local / remote forwarding 一样启动、停止 dynamic rule
- 对常见失败路径返回明确产品级提示
- 为协议解析、store 行为和 build 回归增加测试

本次切片不包含：

- SOCKS4 / SOCKS4a
- SOCKS5 用户名密码鉴权
- `BIND`
- `UDP ASSOCIATE`
- UDP 转发
- 多会话复用优化
- 代理规则、分流、PAC
- 云同步
- `Telnet` / `Serial`

## Product Behavior

### 1. Dynamic Rule Start

当用户启动一个 `kind == .dynamic` 的端口转发规则时：

- 应在 `localHost:localPort` 启动本地 listener
- 成功后规则应被标记为 active
- UI 不再显示“Dynamic port forwarding is not supported yet”
- 历史记录应写入启动记录

### 2. Dynamic Rule Stop

当用户关闭一个已激活的 dynamic rule 时：

- 本地 listener 应被关闭
- 关联的 SSH client 与已建立的 channel 应随 session 关闭
- 规则恢复为 inactive

### 3. SOCKS Protocol Support

V1 只支持：

- SOCKS version `5`
- auth method `0x00`（no authentication）
- command `0x01`（`CONNECT`）

如果客户端请求：

- 不支持的版本
- 不包含 `no auth` method
- `BIND`
- `UDP ASSOCIATE`
- 不支持的地址类型

都必须收到明确的 SOCKS failure response，并关闭当前连接。

### 4. SSH Behavior

现有 local / remote forwarding 行为必须保持不变：

- local forwarding 继续使用现有本地 listener + `direct-tcpip`
- remote forwarding 继续使用现有 Citadel remote forwarding API
- dynamic forwarding 的引入不能改变已存在的 SSH request 构建与 host key challenge 逻辑

## Architecture

### 1. Store Boundary

`MobileShellStore` 继续负责：

- 根据 rule 解析对应 SSH host
- 构造 `SSHConnectionRequest`
- 调用 `PortForwardingClient.start(rule:using:)`
- 保存 active session
- 维护错误提示与历史记录

dynamic forwarding 不应再在 store 层被提前拒绝。是否可启动由 `PortForwardingClient` 决定。

### 2. Port Forwarding Service Boundary

继续由 `CitadelPortForwardingClient` 统一按 rule kind 分发：

- `.local` -> 现有 local forwarding session
- `.remote` -> 现有 remote forwarding session
- `.dynamic` -> 新的 SOCKS5 dynamic forwarding session

dynamic forwarding 的协议细节不能堆回 `MobileShellStore` 或 `PortForwardingView`。

### 3. Dynamic Forwarding Runtime

新增服务放在：

- `MobileShell/Services/PortForwarding/`

建议新增一个聚焦文件，承载以下职责：

- 启动 NIO `ServerBootstrap`
- 接收本地 SOCKS5 客户端连接
- 解析 greeting 与 request
- 校验版本、method、command、address type
- 在请求合法时调用 `SSHClient.createDirectTCPIPChannel`
- 用现有 `PortForwardGlueHandler` 把本地 socket 与 SSH channel 连接起来

建议类型：

- `CitadelDynamicPortForwardingSession`
- `SOCKS5ServerHandshake`
- `SOCKS5ConnectRequest`

其中：

- `SOCKS5ServerHandshake` / `SOCKS5ConnectRequest` 保持纯值解析，便于单测
- `CitadelDynamicPortForwardingSession` 负责 NIO / SSH 集成

### 4. File Placement

由于 `MobileShell/ShellConnection.swift` 已经承担过多职责，本次不应继续把完整 SOCKS 协议实现直接堆进该文件。

允许在 `ShellConnection.swift` 中只保留：

- `PortForwardingClient` 分发入口
- 调用新 dynamic session 的一小段 glue code

协议解析与 listener 处理逻辑应下沉到新服务文件。

## Data Flow

### Successful Path

1. 用户启动 dynamic rule
2. Store 解析 SSH host 并构造 `SSHConnectionRequest`
3. `CitadelPortForwardingClient` 为该 rule 建立 SSH client
4. `CitadelDynamicPortForwardingSession` 在 `localHost:localPort` 启动 SOCKS5 listener
5. 某个本地客户端接入 listener
6. 服务端返回 `no-auth` greeting response
7. 客户端发送 `CONNECT` request
8. Session 解析目标地址和端口
9. 通过 SSH 建立 `direct-tcpip` channel 到目标
10. 返回 SOCKS success response
11. 本地 socket 与 SSH channel 进入双向转发

### Unsupported Command Path

1. 客户端发送 `BIND` 或 `UDP ASSOCIATE`
2. Session 返回 SOCKS command-not-supported response
3. 当前连接关闭
4. 整个 dynamic listener 继续运行，不影响其他连接

### Listener Startup Failure Path

1. 用户启动 dynamic rule
2. 本地监听端口被占用，或 listener 启动失败
3. Store 接收错误并显示 `Port forward error: ...`
4. 规则保持 inactive

## Error Handling

至少区分这些错误语义：

- listener 启动失败
- SOCKS version 不支持
- auth method 不支持
- command 不支持
- address type 不支持
- SSH channel 建立失败

约束：

- 单个 SOCKS 客户端请求失败时，不应导致整个 dynamic rule session 崩溃，除非 listener 本身失效
- rule 启动失败时，必须通过现有 `portForwardErrorMessage` 暴露给 UI
- 客户端握手失败时，优先走 SOCKS response，而不是把内部错误直接回显给 UI

## UI

现有 `PortForwardingView` 结构基本可复用，但文案需要纠正：

- `PortForwardKind.dynamic.description` 不能再描述为“未来再实现的占位能力”
- dynamic editor 仍然只显示 `localHost` / `localPort`
- 列表 row 继续展示 `SOCKS host:port`

本切片不新增高级代理配置 UI。

## Testing

### Protocol Tests

新增 focused tests 覆盖：

- 接受包含 `0x00` 的 SOCKS5 greeting
- 拒绝缺少 `0x00` 的 greeting
- 解析 domain request
- 解析 IPv4 request
- 解析 IPv6 request
- 拒绝 `BIND`
- 拒绝 `UDP ASSOCIATE`

### Store Tests

- 启动 dynamic rule 时，会调用 injected `PortForwardingClient`
- 成功启动后 rule 标记为 active
- 失败时 rule 保持 inactive 并显示错误

### Regression Tests

- local / remote forwarding 现有测试继续通过
- app build 继续通过

## Acceptance Criteria

以下条件全部满足时，本切片可验收：

1. `kind == .dynamic` 的规则可以成功启动并停止
2. 本地标准 SOCKS5 客户端可以通过该 listener 发起 `CONNECT`
3. `IPv4` / `domain name` / `IPv6` 目标都可被正确解析
4. `BIND` 与 `UDP ASSOCIATE` 会被明确拒绝
5. 不要求客户端提供鉴权信息
6. local / remote forwarding 行为不回归
7. 不引入云同步、Telnet、Serial、UDP relay 或 PAC 相关能力

## Non-Goals

这一切片明确不解决：

- 多用户代理权限控制
- 企业代理策略
- SOCKS 用户名密码
- `UDP ASSOCIATE`
- DNS over proxy 策略配置
- 智能分流
- 云同步
- `Telnet`
- `Serial`

## Why This Slice Is Right Now

这一步适合作为当前 port forwarding 的下一个切片，因为：

- UI、数据模型和规则管理已经支持 `dynamic`
- 用户已经能保存 dynamic rule，但当前无法真正使用
- 最小 SOCKS5 `CONNECT` 已经足够覆盖个人版最核心场景：浏览器、本地开发工具、CLI 通过 SSH 出口访问远端网络
- 把范围锁在 `no-auth + CONNECT`，可以显著降低实现风险，避免一上来把代理协议做成一个过大的子项目
