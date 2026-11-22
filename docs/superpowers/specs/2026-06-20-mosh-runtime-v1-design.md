# Mosh Runtime V1 Design

## Goal

让 `MobileShell` 的 `Mosh` Host 首次具备真实可连接的终端能力。

这一切片的目标不是完整复制 `Mosh` 的所有高级能力，而是在保持当前 `SSH` 链路稳定的前提下，打通一条最小但真实可用的 `Mosh` 会话路径：

1. 先通过现有 SSH 凭证启动远端 `mosh-server`
2. 解析 `mosh-server` 返回的连接信息
3. 建立真实的 `Mosh` 终端会话
4. 把该会话接入现有 terminal UI 和生命周期

## Scope

本次切片包含：

- 为 `Mosh` Host 增加真实终端运行时入口
- 新增 `MoshPreparation` 阶段：通过 SSH 启动远端 `mosh-server`
- 新增 `MoshRuntime` 阶段：建立真实 `Mosh` 会话并提供终端输出流
- 在 `MobileShellStore` 中按协议对 `ssh` / `mosh` 终端入口分流
- 针对 `mosh-server` 缺失场景给出明确安装提示
- 对 preparation / runtime 失败场景做清晰错误分类
- 针对成功与失败路径增加测试

本次切片不包含：

- 自动安装 `mosh-server`
- `Mosh` 会话 roaming / 网络切换恢复优化
- 后台保活
- 云同步
- `Mosh` 上的 `SFTP`
- `Mosh` 上的 `Port Forwarding`
- `Telnet` / `Serial`

## Product Behavior

### 1. Mosh Host Terminal Entry

当用户点击一个 `protocol == .mosh` 的 Host 终端入口时：

- 不再显示“未实现”提示
- 不回退到 SSH shell
- 不创建假 session
- 进入真实 `Mosh` 会话流程

### 2. Missing `mosh-server`

如果远端缺少 `mosh-server`：

- 必须返回清晰的产品级提示
- 文案说明这是远端环境缺少依赖，不是用户字段填写错误
- 提供明确安装方向
- 不自动执行安装

### 3. Runtime Failure

如果 preparation 成功但 Mosh runtime 建立失败：

- 返回 Mosh 连接失败提示
- 不回退到 SSH shell
- 不保留半成品 terminal session

### 4. SSH Behavior

现有 `SSH` Host 的终端行为必须保持不变：

- 正常打开 SSH 交互会话
- 正常使用工作区、日志、快捷键、自动补全
- 不因为 Mosh 接入而改变现有链路

## Architecture

### 1. Host Model

继续复用已经存在的：

- `RemoteAccessProtocol`
- `MoshHostConfiguration`
- `ShellHost.protocol`
- `ShellHost.moshConfiguration`

本次切片不再重新设计 Host 模型。

### 2. Mosh Preparation Layer

新增一条准备阶段服务，放在：

- `MobileShell/Services/Mosh/`

建议类型：

- `MoshPreparationClient`
- `MoshServerLaunchResult`
- `MoshPreparationError`

职责：

- 使用现有 `SSHConnectionRequest`
- 在远端执行 `mosh-server`
- 解析标准返回结果
- 把缺依赖和一般启动失败区分开

### 3. Mosh Runtime Layer

新增一条运行时服务，同样放在：

- `MobileShell/Services/Mosh/`

建议类型：

- `MoshRuntimeClient`
- `MoshRuntimeSession`

职责：

- 根据 preparation 结果建立真实 `Mosh` 会话
- 暴露输出流
- 接收输入
- 提供关闭能力

### 4. Store Orchestration

`MobileShellStore` 负责协议分流：

- `ssh`：继续走现有 `openInteractiveTerminal` 链路
- `mosh`：走 preparation -> runtime

要求：

- preparation 失败时不创建 session
- runtime 失败时不创建假 session
- 成功时把 `Mosh` 会话接入现有终端状态机

### 5. UI Layer

`View` 层不需要知道底层是 SSH 还是 Mosh。

要求：

- 终端 UI 继续只消费统一的 session / lines / state
- 错误提示由 store 提供清晰产品文案
- Host 列表和 Host 编辑页的 `Mosh` 配置保持现有行为

## Data Flow

### Successful Path

1. 用户点击 `Mosh` Host 终端入口
2. Store 根据 `host.protocol` 进入 `Mosh` 分支
3. Store 构造现有 `SSHConnectionRequest`
4. `MoshPreparationClient` 通过 SSH 启动远端 `mosh-server`
5. 解析出连接参数
6. `MoshRuntimeClient` 建立真实 `Mosh` 会话
7. Store 创建正常 terminal session 状态
8. UI 显示真实会话输出

### Missing Server Path

1. 点击 `Mosh` Host 终端入口
2. preparation 阶段远端返回缺少 `mosh-server`
3. Store 映射成产品级提示
4. 不创建 terminal session

### Runtime Failure Path

1. preparation 成功
2. runtime 建立失败
3. Store 设置错误提示
4. 不创建 terminal session

## Error Handling

最少区分这些错误类型：

- `moshServerMissing`
- `moshServerLaunchFailed`
- `moshHandshakeParseFailed`
- `moshRuntimeConnectFailed`

要求：

- `moshServerMissing` 必须能触发安装建议文案
- 其余错误不应该被误报成“请安装 mosh-server”
- 任一错误都不能创建假 session

## Testing

### Preparation Tests

- 标准 `mosh-server` 输出能够被解析
- `mosh-server: command not found` 映射为 `moshServerMissing`
- 非标准失败输出映射为 `moshServerLaunchFailed`

### Store Tests

- `Mosh` Host 点击终端时，会先调用 `MoshPreparationClient`
- preparation 成功后，会调用 `MoshRuntimeClient`
- preparation 失败时，不创建 session
- runtime 失败时，不创建 session
- 缺少 `mosh-server` 时，提示文案正确
- `SSH` Host 继续走旧链路，不回归

### UI / Session Tests

- 成功路径下 terminal session 正常出现
- 输出流会进入现有 terminal lines
- 失败路径下不会出现半成品 tab

### Regression Tests

- 现有 SSH 终端相关测试继续通过
- 工作区、日志、snippet、autocomplete 路径不回归

## Acceptance Criteria

以下条件全部满足时，本切片可验收：

1. 配置好的 `Mosh` Host 可以发起真实终端会话
2. 缺少 `mosh-server` 的目标机返回明确安装提示
3. 不自动安装 `mosh-server`
4. 不回退成 SSH shell
5. 不创建半成品 terminal session
6. 现有 `SSH` Host 终端行为不回归
7. 不引入云同步、SFTP-over-Mosh、PortForwarding-over-Mosh 或 roaming 优化

## Non-Goals

这一切片明确不解决：

- 自动安装远端依赖
- `Mosh` roaming 优化
- 网络切换恢复
- 会话恢复
- 云同步
- `Telnet`
- `Serial`

## Why This Slice Is Right Now

这一步适合作为 `Mosh` 的第二个切片，因为：

- Host 协议模型和配置已经存在
- 用户现在已经能保存 `Mosh` Host，但还不能真正使用
- 只要先打通最小真实连接链路，就能把 `Mosh` 从“占位协议”升级成“真实可用协议”
- 同时又不会因为一次切片过大，把项目拖入完整 `Mosh` 高级特性实现
