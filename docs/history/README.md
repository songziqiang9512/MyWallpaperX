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
| 2026-10-25 | App主窗口 / 播放列表 | 基础实现与初版审计 | [主窗口基础记录](development/main-window-playlists-foundation-2026-10-25.md) | 改造前源码快照、P/W施工安排、B1–B5有界证据与初版审计；不决定当前任务或最终验收 | [主界面改造方案](../development/main-window-playlists-redesign.md) |
| 2026-10-25 | App主窗口 / U/A/N15 | 新10项之前的完整候选 | [前轮UI与N15记录](development/main-window-playlists-ui-n15-2026-10-25.md) | 保原目标、实现、有限验证与真实异常终态；旧堆叠/无返回/取色不再现役 | [新10项与模态方案](../development/main-window-playlists-redesign.md#user-ui-revision-10) |
| 2026-10-25 | App主窗口 / UI R0–R4 | 上轮实施与限定验证 | [R0–R4记录](development/main-window-playlists-ui-r0-r4-2026-10-25.md) | 原A审计快照、真实失败负控与原生回归/Debug/试用边界；不定义新15项规则 | [当前主界面方案](../development/main-window-playlists-redesign.md#user-ui-revision-10) |
| 2026-10-25 | Scene / Web 启动专项 | 最终结算 | [冷暖启动专项结算](cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md) | 单一设计/失败/STOP历史及最终限定验收；旧门不改 | [启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web模型](../web/web-project-json-runtime-model.md) |
| 2026-10-25 | Scene / Web | 启动D16 | [统一运行包名](cross-topic/wallpaper-startup-d16-2026-10-25.md) | 修正对照输入、旧fixture反例与真实签名staging；污染名称控制保原点，不授性能因果 | [启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web模型](../web/web-project-json-runtime-model.md) |
| 2026-10-24 | Scene / Web | 启动D12 | [凭据与配对形状](cross-topic/wallpaper-startup-d12-2026-10-24.md) | 双loopback cookie先红后绿、真实Web六暖成组；P5入口STOP与原seek/C1限定证据 | [启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web模型](../web/web-project-json-runtime-model.md)、[Web状态](../web/current-state.md) |
| 2026-10-24 | Scene / Web | 启动第三批 | [P1b/D1实施与回退诊断](cross-topic/wallpaper-startup-p1b-d1-2026-10-24.md) | 捕获解析/租约取消与资源句柄；v2回退保护、v3五组和实音限定结果，未认整体提速 | [启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web模型](../web/web-project-json-runtime-model.md)、[Scene启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web宿主](../web/dedicated-host-process-design.md) |
| 2026-10-24 | Scene / Web | 启动第二批 | [P1a/P2a实施记录](cross-topic/wallpaper-startup-p1-p2a-2026-10-24.md) | 同次依赖/发布与FD基础通过有限回归；五组无正式提速结论，后继未完成 | [启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web模型](../web/web-project-json-runtime-model.md)、[Scene启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web宿主](../web/dedicated-host-process-design.md) |
| 2026-10-24 | Scene / Web | 启动首批 | [P0校准与局部改造](cross-topic/wallpaper-startup-p0-2026-10-24.md) | 偏好隔离修复、固定索引/原生窗口的交替对比、作者音频及未闭合准备长尾；正式噪声门未全过 | [启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web模型](../web/web-project-json-runtime-model.md)、[Scene启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web宿主](../web/dedicated-host-process-design.md) |
| 2026-10-19 | Web / Scene | 方案与取舍 | [准备成本收敛](cross-topic/playback-preparation-convergence-2026-10-19.md) | 原P1–P5、原始STOP与用户修订保留决策；实际功能反例、局部成本与测量限制，避免重开旧候选 | [Web模型](../web/web-project-json-runtime-model.md)、[Scene启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)、[Web宿主](../web/dedicated-host-process-design.md) |
| 2026-10-16 | 跨专题/获取 | 完成退役 | [SteamKit迁移完成](cross-topic/steamkit-migration-completed-2026-10-16.md) | 唯一获取链、旧plan Git身份与证据路径边界；不等同账号、Release或长稳验收 | [获取合同](../architecture/steam-workshop-acquisition-contract.md)、[发布边界](../release/release-signing.md) |
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
