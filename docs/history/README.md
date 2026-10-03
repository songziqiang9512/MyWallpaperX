# MyWallpaperX 历史文档索引

本目录保留全仓、Web和架构历史；[Scene 历史](../scene/history/README.md)集中在 Scene 专题内。这里的文件用于解释“当时为什么这样做”和保存不可替代的证据，不决定当前能力、架构或下一任务。

## 使用合同

- 本页是统一历史入口，不是历史证据正文；除本页及 Scene 历史导航外，`docs/history/**/*.md` 和 `docs/scene/history/**/*.md` 均由[文档角色索引](../document-role-index.json)自动发现并显式登记为 `historical-evidence`，不能登记为现役计划或稳定合同。
- 文件名带日期的历史 Markdown 位于 `docs/history/` 或 `docs/scene/history/`；无日期的现役计划或稳定合同必须通过文档角色索引的 `additionalPaths` 明确纳管。
- 历史正文中的“当前”“下一步”“必须”“运行此命令”只适用于文件注明的截止日期和当时环境。
- 当前事实依次查[文档入口](../README.md)、[Scene 能力台账](../scene/capabilities/coverage-ledger.md)、[Scene 运行证据](../scene/capabilities/runtime-evidence-current.md)或[Web 现役状态](../web/current-state.md)。
- 当前执行顺序只查[Scene 兼容执行路线](../scene/roadmap/scene-compatibility-roadmap.md)以及仍明确登记为 active plan 的专题文件。
- 当前文档只有在需要引用独有研究结论或历史证据 anchor 时才深链具体文件；不得从历史文件续接任务。
- 新的当前状态不写入本目录。被新证据或新计划替代的文件在完整保留独有信息后移入本目录，并同步文档角色索引。

## 历史材料

| 截止日期 | 专题 | 类型 | 文件 | 独有价值 | 当前权威 |
|---|---|---|---|---|---|
| 2026-10-03 | 仓库 | 完成记录 | [仓库改良实施与验收](cross-topic/repository-improvement-completion-2026-10-03.md) | 原提案18项、M1–M8、等价裁决与证据边界；固定最近100提交scope计数与未分类边界（同页分节保留） | [仓库工作流](../development/repository-workflow.md)、[仓库地图](../architecture/repository-map.md)、[README](../README.md) |
| 2026-10-02 | 跨领域 | 改良提案 | [仓库改良方案研究](cross-topic/repo-improvement-program-2026-10-02.md) | 六视角现状侦察＋四主题业界调研收敛的 18 条 P0-P2 改良条目全档（P0 5/P1 7/P2 6，逐条含证据/验收门/退役条件与路线图；两轮三视角审查＋独立终审后修订版 3；研究工作流全程零写入，实施须另行立项） | [文档入口](../README.md)、[AGENTS](../../AGENTS.md) |
| 2026-10-02 | 全项目 | 审查记录 | [全项目 Bug 与优化机会审查](cross-topic/project-wide-review-2026-10-02.md) | 16 车道并行静态审查、逐条独立核实后的 50 条确认问题与 7 条驳回候选全档（bug: high 4/medium 9/low 11；optimization: high 0/medium 6/low 20；741 文件） | [文档入口](../README.md)、[AGENTS](../../AGENTS.md) |
| 2026-10-02 | 跨领域 | 结构对比 | [Mirage HEAD 与 MyWallpaperX 结构对比](cross-topic/mirage-vs-mwx-structure-comparison-2026-10-02.md) | Mirage HEAD `77e4886e` 六域 43 条结构对比全档（render/particle/clock/property/camera/modules：corroborated 32/gap 在案引用 7/mirage-specific 4；HEAD 相对 da4fa7b3 考证 3 处行为漂移＋1 处新能力已逐条标注；third-party-reference-pattern，运行时行为与性能不在范围） | [Mirage 显示链路参考](../scene/development/reference/miragewallpaper-rendering-reference.md)、[运行时架构](../scene/architecture/runtime-architecture.md) |
| 2026-10-02 | Scene | 统计快照 | [Scene 引擎能力全景统计](cross-topic/scene-capability-census-2026-10-02.md) | 21 维度 431 项官方全集 × 台账 L0/L1/L2 × 208 样本语料使用的派生全景：台账口径完整执行 62/191=32.5%、官方全集口径 15.3%；官方站 72 URL 联网复核并入 7 项新发现；权威=能力台账 | [能力台账](../scene/capabilities/coverage-ledger.md)、[文档入口](../README.md) |
| 2026-09-30 | App 全端 UI | 审查记录 | [UI 代码全面审查](cross-topic/ui-code-review-2026-09-30.md) | 163 个 UI Swift 文件、12 区域并行评审+逐条独立复核的 41 条问题清单与完整证据（1 high / 20 medium / 19 low / 1 存疑） | [文档入口](../README.md)、[AGENTS](../../AGENTS.md) |
| 2026-05-05 | Architecture | architecture snapshot | [框架架构备忘](architecture/framework-architecture-memo.md) | 早期模块接入和目录约定 | [AGENTS](../../AGENTS.md)、[文档入口](../README.md)、[技术栈边界](../architecture/technology-stack-boundaries.md) |
| 2026-07-19 至 2026-07-25 | Web + Scene | cross-topic review | [Web 与 Scene 状况评估](cross-topic/web-scene-current-state-roadmap-2026-07-19.md) | 当时的跨专题评估和证据来源 | [Web 现役状态](../web/current-state.md)、[Scene 路线](../scene/roadmap/scene-compatibility-roadmap.md)、[Scene 能力台账](../scene/capabilities/coverage-ledger.md)、[运行证据](../scene/capabilities/runtime-evidence-current.md) |
| 2026-07-20 | Web | runtime baseline | [外部代表样本基线](web/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md) | 5 个外部样本的当时运行证据 | [Web 现役状态](../web/current-state.md) |
| 2026-07-20 | Web | runtime baseline | [Steam 代表样本基线](web/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md) | 3 个 Steam 样本的当时运行证据 | [Web 现役状态](../web/current-state.md) |
| 2026-04-13 | Web | plan | [Web 兼容执行方案](web/web-compatibility-execution-plan-2026-04-13.md) | 早期分类修复策略 | [Web 现役状态](../web/current-state.md) |
| 2026-04-14 | Web | plan | [Web 单宿主输入方案](web/web-native-input-host-plan-2026-04-14.md) | 早期 macOS 输入/宿主设计 | [Web 现役状态](../web/current-state.md) |
| 2026-04-15 | Web | progress snapshot | [Web 官方对齐进度](web/web-official-alignment-progress-2026-04-14.md) | 第一轮官方对齐批次记录 | [Web 现役状态](../web/current-state.md) |

Git 历史继续保存每次文档变更。本目录不是 changelog，也不接受为了“留档”而复制现役文档的平行副本。
