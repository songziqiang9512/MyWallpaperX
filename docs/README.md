# MyWallpaperX 文档入口

这个目录按用途分组，避免继续把当前规范、历史计划和排障记录混在顶层。

## 当前事实入口

- [architecture/technology-stack-boundaries.md](architecture/technology-stack-boundaries.md)：项目长期技术栈职责、跨语言/跨进程边界，以及 VM、shader compiler 和第三方 native 依赖的准入顺序；候选不等于现役能力。
- [scene/README.md](scene/README.md)：Scene 专题入口；区分现役台账、专项合同、公开参考和历史快照。
- [scene/semantics/coverage-ledger.md](scene/semantics/coverage-ledger.md)：Scene 当前系统级摘要；新会话从这里定位系统，再进入专项能力表。
- [scene/semantics/runtime-evidence-index.md](scene/semantics/runtime-evidence-index.md)：Scene 当前提交、正式运行门、签名身份与能力证据包。
- [scene/semantics/capability-dependency-map.md](scene/semantics/capability-dependency-map.md)：Scene 公共依赖与当前开发顺序。
- [web/README.md](web/README.md)：Web 壁纸专题入口；其中带日期的运行数字是历史基线，当前结论需由代码和最新可复现报告核对。
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

## 目录分类

- `architecture/`：现役技术栈边界、AppKit 迁移目标，以及带日期的架构快照。
- `web/`：Web 壁纸规范、运行模型、评测标准、样本回归记录和历史方案。
- `scene/`：Scene 壁纸设计、`semantics/` 现役语义手册、`reference/` 公开参考快照和历史评审。
- `release/`：发布、签名、版本和 notarization。
- `reviews/`：跨项目审计、模块审查和 WaifuX 对比资料。

## 使用规则

- 判断框架结构时以代码和 `AGENTS.md` 为准；判断长期技术职责与候选准入时看现役[技术栈与架构路线边界](architecture/technology-stack-boundaries.md)，`architecture/` 旧 memo 只作线索；判断 Scene 能力和闭环状态时看覆盖台账、专项表与运行证据索引。
- Web 暂无独立的持续更新状态台账；需要当前结论时核对代码、评测标准和最新可复现报告，不把 2026-07 的 roadmap 数字直接复用为当前 HEAD。
- 专题下的 `regression/` 与 `reviews/` 下的文件主要用于查历史原因和证据，不反向覆盖当前规范。
- 新增长期规范时放入对应专题目录；新增一次性样本回归或排障记录时放入该专题已有的 `regression/`，没有合适归属时先在对应专题建立清晰入口，不新设空泛归档目录。
- 脚本统一放在仓库根目录的 `script/`，不要再新增 `scripts/`。
- 文档描述与当前代码或运行门禁冲突时，以当前代码和最新可复现证据为准，并回补对应现役文档，不能只在旧 review 中追加新结论。
