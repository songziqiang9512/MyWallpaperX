# MyWallpaperX 文档入口

这个目录按用途分组，避免继续把当前规范、历史计划和排障记录混在顶层。

## 当前优先看

- [architecture/framework-architecture-memo.md](architecture/framework-architecture-memo.md)：截至 2026-05-05 的框架结构、公共协议和模块边界基线；使用前需与当前代码核对。
- [reviews/web-scene-current-state-roadmap-2026-07-19.md](reviews/web-scene-current-state-roadmap-2026-07-19.md)：Web / Scene 当前能力、验证结果、闭环边界和后续路线。
- [scene/semantics/coverage-ledger.md](scene/semantics/coverage-ledger.md)：Scene 当前系统级摘要；新会话从这里定位系统，再进入专项能力表。
- [scene/semantics/official-page-map.md](scene/semantics/official-page-map.md)：179 个官方 Scene 页面逐页映射到唯一合同 anchor、分类和产品决策；这是资料完整性门。
- [scene/semantics/capability-dependency-map.md](scene/semantics/capability-dependency-map.md)：公共依赖层与实施波次；用于避免属性、脚本、粒子、Provider 和 Render Graph 相互绕开或重复实现。
- [scene/scene-capability-development-plan-2026-07-22.md](scene/scene-capability-development-plan-2026-07-22.md)：Scene 对齐 Wallpaper Engine 常用播放能力的现役实施顺序、样本规范和测试门。
- [scene/semantics/README.md](scene/semantics/README.md)：Wallpaper Engine Scene 的现役语义手册入口，包含官方逐页表、专项能力表、依赖图和证据索引。
- [architecture/project-working-memory.md](architecture/project-working-memory.md)：截至 2026-05-17 的 AppKit / Steam 协作快照；使用前需与当前代码核对。
- [web/README.md](web/README.md)：Web 壁纸专题入口。
- [agents/README.md](agents/README.md)：多 Agent 协作与角色入口。
- [release/release-signing.md](release/release-signing.md)：发布签名与 notarization 流程。

## 目录分类

- `architecture/`：当前架构事实、AppKit 迁移和跨 Web / Scene 的整体方案。
- `web/`：Web 壁纸规范、运行模型、评测标准、样本回归记录和历史方案。
- `scene/`：Scene 壁纸设计、现役计划、`semantics/` 语义手册和历史评审。
- `steam/`：Steam Workshop、SteamCMD、下载库重构和相关评审。
- `release/`：发布、签名、版本和 notarization。
- `reviews/`：跨项目审计、模块审查和 WaifuX 对比资料。
- `agents/`：协作角色、流程和审查标准。

## 使用规则

- 判断框架结构时先看 `architecture/` 并与当前代码核对；判断 Web / Scene 能力和闭环状态时看对应专题入口与现役状态文档。
- `archive/`、`regression/`、`reviews/` 下的文件主要用于查历史原因和证据，不反向覆盖当前规范；其中 `reviews/web-scene-current-state-roadmap-2026-07-19.md` 是 Web / Scene 的现役状态入口。
- 新增长期规范时放入对应专题目录；新增一次性排障记录时放入专题下的 `regression/` 或 `archive/`。
- 脚本统一放在仓库根目录的 `script/`，不要再新增 `scripts/`。
- 文档描述与当前代码或运行门禁冲突时，以当前代码和最新可复现证据为准，并回补对应现役文档，不能只在旧 review 中追加新结论。
