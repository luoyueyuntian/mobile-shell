# MobileShell Personal 文档总览

这套文档用于约束 `MobileShell` 向“个人版 Termius”方向演进时的产品边界、实现优先级、架构拆分和 AI 工作方式。

目标不是写一份泛泛的产品介绍，而是给后续 AI 或工程师一个可以直接执行的、分层清晰的开发契约，尽量减少范围漂移、重复设计和无效实现。

## 适用范围

- 平台：`iOS / iPadOS`
- 用户：`单个个人用户`
- 产品定位：`个人 SSH 工作台`，覆盖主机管理、终端、SFTP、端口转发、身份凭证、片段自动化、工作区与日志
- 明确排除：`团队协作`、`共享 Vault`、`多人终端`、`企业权限管理`、`集中计费`、`SSO/SAML`、`审计合规后台`

## 文档优先级

当不同文档之间出现冲突时，按以下顺序解释：

1. [AGENTS.md](../../../AGENTS.md)
2. [docs/project-constraints.md](../../project-constraints.md)
3. 当前目录下的 [01-product-charter.md](./01-product-charter.md)
4. 当前目录下的 [02-functional-requirements.md](./02-functional-requirements.md)
5. 当前目录下的 [03-technical-architecture.md](./03-technical-architecture.md)
6. 当前目录下的 [04-acceptance-quality-bar.md](./04-acceptance-quality-bar.md)
7. 当前目录下的 [05-ai-execution-contract.md](./05-ai-execution-contract.md)
8. 当前目录下的 [06-delivery-roadmap.md](./06-delivery-roadmap.md)
9. `docs/superpowers/specs/` 与 `docs/superpowers/plans/` 下的单功能规格与计划

说明：

- 当前目录负责定义“产品级”边界。
- `docs/superpowers/specs/` 和 `docs/superpowers/plans/` 负责定义“单个功能切片”的实现细节。
- 单功能规格不能反向扩大本目录已经明确排除的产品范围。

## 建议阅读顺序

1. [00-termius-benchmark.md](./00-termius-benchmark.md)
   了解当前 Termius 个人版的能力边界，以及本项目为什么只吸收其中一部分作为首发范围。
2. [01-product-charter.md](./01-product-charter.md)
   确认产品目标、用户类型、版本边界与阶段划分。
3. [02-functional-requirements.md](./02-functional-requirements.md)
   查看正式需求清单与优先级。
4. [03-technical-architecture.md](./03-technical-architecture.md)
   查看代码结构、数据模型、依赖边界和关键流程。
5. [04-acceptance-quality-bar.md](./04-acceptance-quality-bar.md)
   查看验收口径、测试要求和完成定义。
6. [05-ai-execution-contract.md](./05-ai-execution-contract.md)
   在实际动手前先读这一份，避免 AI 跑偏。
7. [06-delivery-roadmap.md](./06-delivery-roadmap.md)
   按推荐顺序拆分后续实现切片。
8. [07-current-state-gap-analysis.md](./07-current-state-gap-analysis.md)
   在真正写代码前先看这一份，避免重复实现仓库里已经存在的能力。

## 这套文档解决什么问题

- 让 AI 不再把 `MobileShell` 误做成团队版、企业版或后台系统
- 让 AI 不再把“个人版 Termius”错误理解为“必须一次性复刻所有平台和所有协议”
- 让功能优先级回到“单人日常运维效率”而不是炫技
- 让实现优先使用现有模型和约束，而不是把 `ShellRootView.swift` 和 `Models.swift` 继续堆大

## 与当前仓库的关系

仓库里已经存在一些与个人版 Termius 高度相关的设计与实现雏形，例如：

- Host tags
- Command autocomplete
- Terminal workspaces
- Workspace templates
- Startup snippets
- SSH certificates
- Host environment variables
- Port forwarding types

这些内容是很好的下层切片基础，但它们不是产品级边界定义。本目录负责把这些分散能力纳入一个统一产品框架里。

## 后续工作规则

- 新需求先判断是否落在本目录定义的范围内。
- 如果需求跨越多个子系统，先补单功能 spec，再写实现 plan。
- 如果需求会引入团队或企业能力，默认拒绝，除非用户明确改变产品方向。
- 如果准备实现路线图中的某个 slice，先对照 [07-current-state-gap-analysis.md](./07-current-state-gap-analysis.md) 确认它是否已经存在实现或测试基础。
