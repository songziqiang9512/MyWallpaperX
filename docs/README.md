# MyWallpaperX 文档入口

这个目录只保留一个当前答案：现役目录解释系统现在怎样工作、已经实现什么和下一步做什么；所有被替代的计划、评审、迁移记录和基线统一进入[历史文档索引](history/README.md)。

## 事实角色

| 角色 | 回答什么 | 权威入口 |
|---|---|---|
| 工作规则 | Agent 如何实现、验证、提交和保护工作区 | [`AGENTS.md`](../AGENTS.md) |
| 长期技术边界 | 技术栈、语言、进程、依赖和所有权 | [技术栈与架构路线](architecture/technology-stack-boundaries.md) |
| Scene 目标架构 | 如何把官方/静态/参考证据转成 MyWallpaperX 的兼容运行时 | [Scene 兼容运行时架构](scene/runtime-architecture.md) |
| Scene 现役计划 | 当前段位、剩余顺序、停止项和完成门 | [Scene 兼容执行路线](scene/scene-compatibility-roadmap.md) |
| Scene 官方结果研究 | 公开资料不足时如何研究固定官方客户端并把结果交给独立实现 | [官方客户端行为研究与一致性验证工作流](scene/semantics/official-client-behavior-research-workflow.md) |
| Scene 当前能力 | 每项能力现在是已执行、部分、仅结构还是缺失 | [Scene 能力台账](scene/semantics/coverage-ledger.md)及专项表 |
| Scene 当前运行证据 | 当前构建、样本、GPU/compositor、失败和未验证边界 | [运行证据索引](scene/semantics/runtime-evidence-index.md) |
| Web 当前状态 | Web 源码所有权、运行事实和缺口 | [Web 现役状态](web/current-state.md) |
| 历史 | 当时的计划、审计、迁移和基线 | [历史文档索引](history/README.md) |

这套顺序只裁决“现在是什么”：当前代码/配置与可复现运行证据 → `AGENTS.md` → 长期架构合同 → 专题当前状态和稳定合同 → 现役计划 → 历史证据。裁决“应该是什么”时，以官方作者行为、`AGENTS.md`、长期架构和现役路线为目标合同；旧代码、旧测试和目录即使真实存在，也不能覆盖目标。两者不一致时记为偏差债务并主动纠正，不把错误现状写回规范。

## Scene

- [Scene 专题入口](scene/README.md)：当前架构、路线、能力、证据和资料导航。
- [Scene 兼容运行时架构](scene/runtime-architecture.md)：官方公开合同、2.8.42 客户端静态观察、Mirage clean-room 模式和项目独立方案的边界。
- [Scene 兼容执行路线](scene/scene-compatibility-roadmap.md)：唯一现役 Scene 执行计划；当前先收口 V1 correctness atom 与 owner 债务，再依次闭合 V2、V3，以 V4 横切输入轨补齐 producer/provider，最后逐项进入 V5 epics。
- [官方客户端行为研究与一致性验证工作流](scene/semantics/official-client-behavior-research-workflow.md)：有界黑盒/静态研究、独立实现交接和预登记 parity 门。
- [语义手册](scene/semantics/README.md)：按格式、Graph/Shader、Effect、Particle、SceneScript、输入和高级对象进入专项合同。
- [能力台账](scene/semantics/coverage-ledger.md)：所有能力的当前状态、明确边界和待办。
- [运行证据索引](scene/semantics/runtime-evidence-index.md)：已运行的当前证据和失败边界。
- [Corpus 能力清单](scene/semantics/scene-corpus-capability-inventory.md)：真实作者输入的影响面；不证明运行支持。
- [Fast Scene Suite 合同](../script/scene_fast_suite.json)：七类低成本纵向门的机器定义；成员未批准时明确为 `selection-required`，不能把任意样本冒充 suite PASS。

## App、Web 与发布

- [AppKit 迁移](architecture/appkit-migration.md)：当前 SwiftUI 残留和迁移门。
- [Web 专题入口](web/README.md)：Web 当前状态、稳定合同和历史导航。
- [Web 现役状态](web/current-state.md)：当前 Web runtime 事实和待验收项。
- [发布签名](release/release-signing.md)：Developer ID、hardened runtime、notarization 与发布流程。

## 文档治理

[文档角色索引](document-role-index.json)机器化登记 active plan、stable contract 和 historical evidence。适用规则：

- 现役 plan/contract 使用稳定、无日期的路径，并在首部声明 `document-role`；日期写入正文的复核字段。
- 所有带日期 Markdown 只能位于 `docs/history/`；历史目录中的文件不能取得现役角色。
- 每个专题只允许一个现役执行计划。能力表、依赖图、来源索引和历史文档都不能决定下一任务。
- 同一当前事实只保留一个权威解释，其他文件放短指针；不在多个专题表复制 commit、矩阵数字和报告路径。
- 当前能力变化更新能力台账/专项表；运行证据变化更新运行证据索引；架构变化更新稳定架构；任务顺序变化只更新现役路线。
- 新的历史材料统一进入 `docs/history/{architecture,scene,web,cross-topic}`，并登记截止日期、独有价值和当前权威。
- 历史正文中的“当前”“下一步”和命令只属于其截止日期，不得被 Agent 当成现役指令。
- 脚本统一放在仓库根的 `script/`，Python 工具使用明确的 `python3.12`。

判断任何 Scene 问题时，不从历史计划或截图开始；先看当前代码/证据，再从能力台账定位缺口，最后按现役路线闭合最短可见纵向链。
