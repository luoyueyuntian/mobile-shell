# Termius 个人版分析基线

## 目的

这一份文档不是为了完整复述 Termius，而是为了建立一个“对标基线”：

- 哪些能力是 Termius 个人版的核心
- 哪些能力属于付费个人版而不是团队版
- 哪些能力虽然存在于 Termius，但不应该成为 `MobileShell` 首发阻塞项

## 信息来源

以下内容基于我在 `2026-06-19` 访问的官方资料整理：

- [Termius 首页](https://termius.com/)
- [Termius Pricing](https://termius.com/pricing)
- [What is Termius?](https://termius.com/documentation/what-is-termius)

## 官方可确认的核心模型

从官方首页和文档可以确认，Termius 的核心不是“一个 SSH 会话列表”，而是一套围绕远程机器组织信息的工作模型：

- `Host`：远程机器的统一抽象，包含地址、协议、端口、认证方式与元数据
- `Group`：按环境、客户、用途等维度组织主机，并支持继承配置
- `Vault`：最上层的加密数据容器，承载 Hosts、Groups、Keys、Snippets、Port Forwards、Known Hosts 等
- `Identity / Keychain`：可复用的用户名、密码、SSH Key、证书等认证材料
- `Terminal`：终端会话本身
- `SFTP`：文件浏览、上传、下载
- `Port Forwarding`：本地、远端、动态转发
- `Snippets`：命令片段与自动化
- `Workspace`：会话组织与恢复
- `Logs / Known Hosts`：日志与主机可信记录

产品洞察：

- Termius 的价值不是“连上去”，而是“把连接、凭证、组织结构、自动化与上下文全部保存下来”。
- 它把用户的心智中心放在 `Host` 上，而不是放在“临时命令行字符串”上。

## 官方价格页可确认的个人版边界

`Pricing` 页面把个人版拆成 `Starter` 和 `Pro`，团队能力从 `Team` 才开始出现。

### Starter（个人基础版）

官方列出的个人基础能力：

- Local vault
- SSH and SFTP
- AI-powered autocomplete
- Port forwarding

### Pro（个人增强版）

官方列出的个人增强能力：

- Personal cloud vault
- Sync across mobile and desktop
- Snippets automation
- Log bookmarks

### Team 及以上（本项目明确不做）

这些能力从 `Team`/`Business`/`Enterprise` 开始出现，应该明确排除：

- Team vault
- Real-time collaboration
- Terminal multiplayer
- Secure data sharing
- Consolidated billing
- Team management console
- Granular access control
- Multiple vaults for organizational sharing
- SAML SSO
- 企业支持与合规能力

## 对 MobileShell 的产品结论

### 必须吸收的能力方向

这些是“个人版 Termius”不可丢掉的产品骨架：

1. `Host-first` 的信息组织方式
2. 可复用的身份、密钥与凭证
3. SSH 终端与 SFTP 的双工作流
4. 端口转发
5. 命令片段与操作自动化
6. 工作区、历史与日志上下文
7. 本地持久化和一键重连体验

### 应明确延后的能力

虽然官方产品具备下列能力，但它们不应阻塞本项目首个可发布版本：

- `Personal cloud vault` 与跨设备同步
- `AI-powered autocomplete` 的云依赖或复杂模型接入
- `Log bookmarks`
- 更重的导入迁移能力
- `Telnet`、`Mosh`、`Serial` 等非核心协议
- `FIDO2`、生物特征密钥、复杂硬件安全集成

原因：

- 本项目当前是 `iOS` 本地应用，不是多端 SaaS。
- 首发阶段应先把“稳定、可保存、可恢复、可复用”的个人 SSH 工作流做扎实。
- 过早引入云同步、复杂协议或账号体系，会把产品重心从“个人效率工具”拉向“平台工程”。

## 我们对标 Termius，但不盲从 Termius

`MobileShell` 的首发版本应当是“个人版 Termius 的高价值子集”，而不是“Termius 全量功能的弱复刻”。

本项目的取舍原则：

- 优先保留：日常使用频率高、能明显减少重复输入和上下文丢失的能力
- 优先延后：需要后端、账号系统、多端冲突解决、多人权限模型的能力
- 明确不做：团队协作和企业治理能力

## 对 AI 的直接约束

后续 AI 在实现或规划时必须遵守：

- 不得因为官方存在 `Team`、`Business`、`Enterprise` 能力，就在本项目中提前铺设团队模型
- 不得把“个人版”扩展成共享 Vault、协作编辑、成员邀请、团队审计
- 不得把“Starter 包含 AI autocomplete”解释成“必须先做云端 AI 功能才算可用”
- 如果某项能力需要账号体系、后台 API 或跨设备冲突合并，应默认归入后续阶段，而不是首发必做项
