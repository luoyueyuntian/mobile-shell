# Delivery Roadmap

## 目的

这份路线图定义“推荐实现顺序”，让后续 AI 避免一次性并行推进太多子系统。

原则：

- 先交付可日用的个人版基座
- 再增强自动化与上下文能力
- 最后才处理可选的个人增强能力

## Phase A：Daily Driver 基座

这一阶段完成后，应用应能作为个人 SSH 工作台日常使用。

### Slice A1：Host 基础模型与列表体验

- Host CRUD
- 分组展示
- 标签筛选
- 搜索
- 入口动作统一

### Slice A2：身份、凭证与 Known Hosts

- Host / Identity 关系
- 密码、私钥、证书的凭证存储
- Known Hosts 信任与冲突提示

### Slice A3：SSH 终端生命周期

- 打开会话
- 多会话切换
- 关闭与重连
- 错误反馈
- 基础历史

### Slice A4：SFTP 核心工作流

- 浏览目录
- 上传下载
- 创建目录
- 重命名
- 删除

### Slice A5：Port Forwarding 核心工作流

- 本地转发规则
- 启停与错误反馈

### Slice A6：Snippets 基础工作流

- 片段 CRUD
- 向当前终端发送命令

### Slice A7：Workspace 与基础日志

- 本地工作区
- 会话归属
- 基础会话日志或历史

## Phase B：Personal Power Features

这一阶段用于把产品从“能用”提升到“更像个人版 Termius”。

### Slice B1：Group / Host 继承能力完善

- group-level identity
- jump host
- startup snippet
- environment variables
- terminal theme / font inheritance

### Slice B2：Workspace 高级能力

- workspace templates
- command broadcast
- 更清晰的创建与恢复体验

### Slice B3：Snippets 高级能力

- startup snippets
- multi-execution
- snippet packages

### Slice B4：Autocomplete 与终端体验增强

- command autocomplete
- 更强的键盘辅助
- 更好的终端主题和字号体验

### Slice B5：Logs 增强

- log bookmarks
- 更强的日志导航

## Phase C：Selective Premium Personal

这一阶段只在前两阶段稳定后才考虑。

### Slice C1：个人同步能力

- 个人云端 vault 或同步抽象
- 本地优先
- 明确冲突策略

当前状态：

- 暂时冻结，不进入近期开发排序

### Slice C2：可选协议增强

- Mosh
- Telnet
- Serial

前提：

- 有明确用户价值
- 不破坏核心 SSH 路径
- 不把项目拖入平台级复杂度

## 与现有仓库 specs/plans 的关系

仓库内已经存在一些相关切片设计，例如：

- terminal workspaces
- workspace templates
- startup snippets
- command autocomplete
- host environment variables
- ssh certificates
- snippet packages
- snippet multi-execution

使用方式：

- 如果当前任务正好命中已有 spec/plan，优先沿用它
- 如果该 spec/plan 与本目录产品边界冲突，以本目录为准
- 如果一个任务跨多个现有 spec/plan，先重新拆分，再实现

## 单次开发的推荐粒度

一轮实现最好只完成下面其中之一：

- 一个 Phase A slice
- 一个 Phase B slice 的子能力
- 一个高风险边界的结构抽离

不要在一次开发里同时推进：

- 新终端能力
- 新持久化模型
- 新同步能力
- 新多人概念

## 进入下一阶段的条件

只有前一阶段满足以下条件，才进入下一阶段：

- 主要 P0 / P1 能力有明确验收证据
- 热点文件没有继续恶化
- 相关测试可稳定运行
- 当前阶段没有明显未闭环的核心路径
