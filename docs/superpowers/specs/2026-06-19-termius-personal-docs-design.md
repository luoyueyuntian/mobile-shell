# Termius Personal Documentation Design

## Goal

为 `MobileShell` 建立一套面向“个人版 Termius”方向的产品级文档，直接约束后续 AI 的需求理解、架构决策、实现顺序和验收口径。

## Scope

本次工作只产出文档，不直接引入新的产品功能。

文档需要覆盖：

- Termius 个人版对标分析
- 产品边界与非目标
- 功能需求与优先级
- 技术架构和模块边界
- 验收标准
- AI 执行契约
- 推荐交付路线图

## Documentation Structure

文档放在 `docs/product/termius-personal/`，并拆分为：

- `README.md`：阅读顺序与优先级
- `00-termius-benchmark.md`：官方产品分析基线
- `01-product-charter.md`：产品目标与阶段
- `02-functional-requirements.md`：正式需求
- `03-technical-architecture.md`：架构与边界
- `04-acceptance-quality-bar.md`：验收门槛
- `05-ai-execution-contract.md`：AI 工作规则
- `06-delivery-roadmap.md`：推荐交付顺序

## Design Principles

- 优先约束范围，而不是扩写愿景
- 优先支持“一个人日常使用”的高频价值
- 明确把团队和企业能力排除在本产品之外
- 文档分层清晰，避免一个大文件混合需求、架构、验收和流程
- 与现有 `AGENTS.md`、`docs/project-constraints.md` 和 feature specs 建立清楚的优先级关系

## Expected Outcome

后续 AI 可以用这套文档作为上位约束，先判断任务是否落在个人版范围内，再依据优先级与架构约束开展单功能切片开发，而不是无边界地扩展产品。
