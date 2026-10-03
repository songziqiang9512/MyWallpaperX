# MyWallpaperX 文档入口

这里把当前事实、目标合同、任务顺序与历史分开。跨模块任务从[仓库开发工作流](development/repository-workflow.md)和[源码职责图](architecture/repository-map.md)定位；Scene 细节从[开发工作流](scene/development/development-workflow.md)进入。历史资料保留在[历史索引](history/README.md)，不决定当前任务。

任务查询（[频率依据与局限](history/cross-topic/repository-improvement-completion-2026-10-03.md#task-route-frequency)）：`python3.12 -B script/document_registry.py --list`，或 `--query scene`、`--query 发布`、`--query 设计`。查询复用下方角色索引和现役 design area，仅返回指针；查询返回 `firstRead`、owner、分阶段 gate 引用与动态解析的最近测试；先读 `firstRead`，其余 `documents` 按首断点选取，不是整组必读；支持 `--query "修复 Scene 视觉缺陷"`、`--query "发布新版本"`、`--query "设计前置判定"`，不会自动执行命令。术语可查 `S0-S5`、`E-*`、`named source taxonomy`、`recognized/wired`、`owned paths`、`家族/防御面`，每项只转到一个权威。

## 事实角色

| 角色 | 回答什么 | 权威入口 |
|---|---|---|
| 工作规则 | Agent 如何实现、验证、提交和保护工作区 | [`AGENTS.md`](../AGENTS.md) |
| 长期技术边界 | 技术栈、语言、进程、依赖和所有权 | [技术栈与架构路线](architecture/technology-stack-boundaries.md) |
| Scene 目录依赖 | Compilation / Rendering 结构边及有界扫描合同 | [依赖边界试点](scene/architecture/scene-dependency-boundaries.md) |
| Scene 目标架构 | 播放器职责、逐对象加载／更新／合成／释放与编码合同 | [Scene 兼容运行时架构](scene/architecture/runtime-architecture.md)、[Sampler 缺省输入优先级](scene/capabilities/sampler-alias-precedence.md) |
| Scene 启动响应 | 详情诊断、异步 preparation、候选首帧、回滚和分层缓存合同 | [Scene 启动响应与按需诊断合同](scene/architecture/scene-launch-responsiveness-contract.md) |
| Scene 日常开发 | 如何选首断点、做纵向切片、消融常驻成本和选择验证门 | [Scene 开发工作流](scene/development/development-workflow.md) |
| 工程重构 | 播放架构、成本消融、跨引擎控制、测试与文档退役 | [重构执行档案](scene/roadmap/engine-refactor-program.md) |
| Scene 现役计划 | 当前段位、剩余顺序、停止项和完成门 | [Scene 兼容执行路线](scene/roadmap/scene-compatibility-roadmap.md) |
| Scene 官方结果研究 | 公开资料不足时如何研究固定官方客户端并把结果交给独立实现 | [官方客户端行为研究与一致性验证工作流](scene/development/official-client-behavior-research-workflow.md) |
| Scene 当前能力 | 每项能力现在是已执行、部分、仅结构还是缺失 | [Scene 能力台账](scene/capabilities/coverage-ledger.md)及专项表 |
| Scene 当前运行证据 | 当前构建、样本、GPU/compositor、失败和未验证边界 | [运行证据索引](scene/capabilities/runtime-evidence-current.md) |
| Steam 获取迁移 | 统一 SteamKit 获取、主动登录、结构化分页、卡片进度、队列与自动入库；E2/E6/E8 的专项细化 | [Steam 获取迁移计划](scene/roadmap/scene-steamkit-migration-plan.md) |
| Web 当前状态 | Web 源码所有权、运行事实和缺口 | [Web 现役状态](web/current-state.md) |
| 历史 | 当时的计划、审计、迁移和基线 | [历史文档索引](history/README.md) |

这套顺序只裁决“现在是什么”：当前代码/配置与可复现运行证据 → `AGENTS.md` → 长期架构合同 → 专题当前状态和稳定合同 → 现役计划 → 历史证据。裁决“应该是什么”时，以官方作者行为、`AGENTS.md`、长期架构和现役路线为目标合同；旧代码、旧测试和目录即使真实存在，也不能覆盖目标。两者不一致时记为偏差债务并主动纠正，不把错误现状写回规范。

## Scene

从 [Scene 一页说明](scene/README.md)开始：先理解进程、准备、逐帧合成与代码职责，再选择重构或兼容路线。长期设计、能力表、研究和历史均按需进入，不把它们当成入仓必读清单。

## App、Web 与发布

- [当前版本更新说明](releases/2.10.0.md)：该版本的发布记录，不代表 HEAD 或实时发布状态。

- [AppKit 迁移](architecture/appkit-migration.md)：当前 SwiftUI 残留和迁移门。
- [Web 专题入口](web/README.md)：Web 当前状态、稳定合同和历史导航。
- [Web 现役状态](web/current-state.md)：当前 Web runtime 事实和待验收项。
- [Agent 自动发布与签名](release/release-signing.md)：一句话发布、正式更新日志、Developer ID、notarization 与发布结果核验。
- [Batch 2 设计导航](scene/roadmap/batch2/batch2-design-index.md)：跨 owner 能力的设计裁决；不取代现役实施路线。

## 文档治理

[仓库改良完成记录](history/cross-topic/repository-improvement-completion-2026-10-03.md)保存原提案验收（[旧入口与永久锚点](development/repository-improvement.md)）；持续治理由[仓库开发工作流](development/repository-workflow.md)接管。

[文档角色索引](document-role-index.json)登记所有 Git 可见的 docs Markdown：active-plan、stable-contract、historical-evidence、navigation、current-state、reference。发现范围包括未跟踪且未忽略的新文件，不遍历忽略的本机证据缓存。运行 `python3.12 -B script/document_registry.py --audit` 机器核对首跳、全量登记、合同路由与术语；`python3.12 -B script/document_health.py --check` 检查正文默认只降、有据调整、归档载荷/锚点和复核年龄。新增权威或合理预算扩展、移动、合并和退役按[工作流中的精确调整登记](development/repository-workflow.md#代码与知识交付)办理，不绕过实际正文、锚点与索引校验。stable-contract 的 `lastReviewed` 与 `reviewBasis` 明示日期来源及复核上限：Git 文档维护日期不冒充产品重新验收，导航审计只证明入口/结构。超过 60 天须实际复核相应范围并保存依据。适用规则：

- 现役 plan/contract 通常使用稳定、无日期的路径，并在首部声明 `document-role`；日期写入正文的复核字段。确需保留日期化的现役派生队列时，必须同时在 `document-role-index.json` 的 `additionalPaths` 和文档角色表中显式登记，并写明其派生性质与退役条件。
- 未被角色索引显式登记的带日期 Markdown 只能位于 `docs/history/` 或 `docs/scene/history/`；历史目录中的文件不能取得现役角色。
- 每个决策范围只允许一个现役执行计划：工程重构由 E 路线决定，Scene 作者兼容由 P 路线决定；断点队列只是 P 路线的派生短表，不独立规定阶段。现役计划只保留当前阶段、顺序、完成门和退役条件；批次结果、route 数字、样本身份和报告摘要回到各自能力/证据权威。能力表、依赖图、来源索引和历史文档都不能决定下一任务。
- 导航页只说明文档角色并链接权威入口，不复制当前阶段、完成数量、commit、矩阵数字、报告路径或本机缓存位置；同一当前事实只保留一个权威解释，其他文件放短指针。
- 当前能力变化更新能力台账/专项表；运行证据变化更新运行证据索引；架构变化更新稳定架构；任务顺序变化只更新现役路线。
- Scene 历史进入 `docs/scene/history/`；全仓、架构和 Web 历史进入 `docs/history/{architecture,web,cross-topic}`，并登记截止日期、独有价值和当前权威。
- 历史正文中的“当前”“下一步”和命令只属于其截止日期，不得被 Agent 当成现役指令。
- 脚本统一放在仓库根的 `script/`，Python 工具使用明确的 `python3.12`。

判断任何 Scene 问题时，不从历史计划或截图开始；先看当前代码/证据，再从能力台账定位缺口，最后按现役路线闭合最短可见纵向链。
