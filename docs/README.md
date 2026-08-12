# MyWallpaperX 文档入口

这个目录按“长期规范、当前状态、现役执行计划、稳定合同、历史证据”分工。同一事实只允许一个现役权威入口；标题或正文中的“当前”不能覆盖本页标明的文档角色。

## 文档角色与裁决顺序

| 角色 | 回答什么 | 不回答什么 |
|---|---|---|
| 长期规范 | 技术、所有权、性能、安全和准入边界 | 单项能力是否已经完成 |
| 当前状态 | 当前代码所有权、能力等级、运行证据和缺口 | 过去批次为什么这样做 |
| 现役执行计划 | 当前批次顺序、断点和验收门 | 能力真值或长期技术选型 |
| 稳定合同 | 格式、生命周期、测试和发布应满足什么 | 当前 HEAD 是否已经满足 |
| 历史证据 | 当时的代码、样本、报告和取舍 | 当前状态或下一任务 |

冲突时按以下顺序裁决：当前代码/配置与可复现运行证据 -> `AGENTS.md` 工作规则 -> 长期技术规范 -> 专题当前状态/专项表 -> 稳定合同 -> 现役执行计划 -> 历史证据。代码存在只证明实现路径，用户可见能力与性能仍需相应运行证据。

## 当前事实入口

- [architecture/technology-stack-boundaries.md](architecture/technology-stack-boundaries.md)：项目长期技术栈职责、跨语言/跨进程边界，以及 VM、shader compiler 和第三方 native 依赖的准入顺序；候选不等于现役能力。
- [scene/README.md](scene/README.md)：Scene 专题入口；区分现役台账、专项合同、公开参考和历史快照。
- [scene/semantics/coverage-ledger.md](scene/semantics/coverage-ledger.md)：Scene 当前系统级摘要；新会话从这里定位系统，再进入专项能力表。
- [scene/semantics/runtime-evidence-index.md](scene/semantics/runtime-evidence-index.md)：Scene 当前提交、正式运行门、签名身份与能力证据包。
- [scene/semantics/capability-dependency-map.md](scene/semantics/capability-dependency-map.md)：Scene 公共依赖与当前开发顺序。
- [web/current-state.md](web/current-state.md)：Web 当前源码所有权、证据边界、发布缺口与下一门。
- [web/README.md](web/README.md)：Web 稳定规范、现役状态与历史证据导航。
- [architecture/appkit-migration-plan-2026-05-17.md](architecture/appkit-migration-plan-2026-05-17.md)：AppKit 迁移目标与当前 SwiftUI 残留。
- [release/release-signing.md](release/release-signing.md)：发布签名与 notarization 流程。

## Scene 语义参考

- [scene/semantics/README.md](scene/semantics/README.md)：现役语义手册索引；按系统进入专项能力表。
- [scene/semantics/official-page-map.md](scene/semantics/official-page-map.md)：179 个官方 Scene 页面逐页映射到唯一合同 anchor、分类和产品决策；这是资料完整性门。
- [scene/semantics/capability-dependency-map.md](scene/semantics/capability-dependency-map.md)：公共依赖层与实施波次；用于避免属性、脚本、粒子、Provider 和 Render Graph 相互绕开或重复实现。

## 历史参考

- [architecture/framework-architecture-memo.md](architecture/framework-architecture-memo.md)：2026-05-05 的模块接入与框架约定快照；仍有独有的接入检查表，但必须与当前代码核对。
- [reviews/web-scene-current-state-roadmap-2026-07-19.md](reviews/web-scene-current-state-roadmap-2026-07-19.md)：Web / Scene 的 2026-07-19 至 2026-07-25 评估快照，不是当前状态入口。
- [scene/scene-capability-development-plan-2026-07-22.md](scene/scene-capability-development-plan-2026-07-22.md)：历史总体实施批次、样本门和测试方法；当前等级与待办以专项表为准。
- 专题下的 `regression/` 与普通 `reviews/` 文件默认是历史证据，不反向覆盖现役入口。

## 已完成实施计划

- [scene/scene-render-chain-refactor-plan-2026-08-03.md](scene/scene-render-chain-refactor-plan-2026-08-03.md)：Scene R0-R5 owner 收敛与旧链删除的已完成实施记录；当前能力、下一任务和运行基线继续以专项台账、能力依赖图和运行证据索引为准。

## 目录分类

- `architecture/`：现役技术栈/性能边界、AppKit 迁移目标，以及带日期的架构快照。
- `web/`：Web 现役状态、稳定规范、评测标准、样本回归记录和历史方案。
- `scene/`：Scene 当前事实、现役执行计划、`semantics/` 语义手册、`reference/` 公开参考快照和历史评审。
- `release/`：发布、签名、版本和 notarization。
- `reviews/`：跨项目审计、模块审查和 WaifuX 对比资料。

## 使用规则

- 判断框架结构时以代码和 `AGENTS.md` 为准；判断长期技术职责、性能和候选准入时看现役[技术栈与架构路线边界](architecture/technology-stack-boundaries.md)，`architecture/` 旧 memo 只作历史线索；判断 Scene 能力和闭环状态时看覆盖台账、专项表与运行证据索引。
- Web 当前结论从[现役状态](web/current-state.md)进入；带日期的 Web plan、progress、roadmap 和 regression 只作历史证据，不能直接复用其“当前”或数字。
- 专题下的 `regression/` 与 `reviews/` 下的文件主要用于查历史原因和证据，不反向覆盖当前规范。
- 新增长期规范时放入对应专题目录；新增一次性样本回归或排障记录时放入该专题已有的 `regression/`，没有合适归属时先在对应专题建立清晰入口，不新设空泛归档目录。
- 脚本统一放在仓库根目录的 `script/`，不要再新增 `scripts/`。
- 文档描述与当前代码或运行门禁冲突时，以当前代码和最新可复现证据为准，并回补对应现役文档，不能只在旧 review 中追加新结论。
- 新文档必须在专题入口归类；带日期文件默认是历史快照，若被列为现役迁移目标或现役执行计划，必须写明完成/退役条件。能力数字、报告路径和 commit 不复制到长期规范。
