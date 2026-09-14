<!-- document-role: stable-contract -->

# 重构调查与退役清单

> 2026-09-15 静态审计基线；不是任务队列，也不代表后续代码保持不变。
> 当前能力以[能力台账](../semantics/coverage-ledger.md)为准。
> 当前实施顺序见[重构计划](../engine-refactor-program.md)。只在相关执行卡需要时读取对应条目；不作为入仓必读。

## 2. 调查基线与证据边界

### 2.1 盘点方法与体量

用 `git ls-files -z` 枚举 tracked 文件，按后缀和目录计数；行数是文件行数，不是逻辑复杂度。读取实际调用点、机器 manifest、测试构造和现役文档；未读取私有研究原始表达、未扫描真实样本内容、未构建或启动 runtime。以下数字是本次改文档之前的快照，不应逐批复制维护。

| 面 | 本次静态盘点 | 解释 |
|---|---|---|
| 仓库 | 4,715 tracked 文件 | 其中 SceneStockAssets.bundle 3,122 项；不能把资源文件算作架构类型膨胀 |
| App Swift | 943 文件／244,010 行 | 不含 WallpaperDaemonSources 和测试 fixture |
| Scene Swift | 665 文件／173,460 行 | RenderGraph 目录共有 295 tracked 项，Runtime 137 项；文件数不是性能证据 |
| Scene 全部相关源码 | 701 文件／268,258 行 | 含 C/H 等及 QuickJS-NG；其 quickjs.c 单独 64,841 行，不能算成应删除的项目胶水 |
| Web Core | 46 源文件／10,516 行 | 当前宿主与诊断 harness 必须分开核对 |
| Modules | 149 源文件／42,170 行 | 库、Workshop、设置与 UI 也有职责泄漏 |
| 测试 | 282 个 test_*.py 模块；测试目录 300 tracked 项／188,068 行 | 包含大量内嵌 Swift harness；216 个 Python 文件含 swiftc 文本，不等于已测编译耗时 |
| 全部 docs Markdown | 68 文件／29,056 行 | 长行使行数严重低估阅读量 |
| Scene docs Markdown | 35 文件／3,216,435 字节 | 能力台账 725,188 B、当前运行证据 547,003 B、样本调试台账 124,277 B |
| 历史 Markdown | 22 文件／3,476,865 字节 | 默认阅读范围应排除；含唯一证据，不能按体量盲删 |
| 旧工程计划 | 182 行／50,670 字节 | 已将完整历史叙事保存在[归档](../../history/scene/engine-refactor-program-before-2026-09-15.md) |

本轮执行 `python3.12 -B script/check_code_health.py --check`：退出 1，19 个错误（既有）。包括 800 行上限、两个 locked allowance 增长、旧 Settings 路径残留。此结果只证明结构门未过，不能证明哪段运行最慢。

### 2.2 已确认的当前链与保留项

| ID | 代码事实／定位 | 设计含义 |
|---|---|---|
| F1 | [Application](../../../MyWallpaperX/App/MyWallpaperXApplication.swift) 在 `--mwx-scene-daemon` 分支装配 [SceneDaemonRuntime](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift)，后者独占 Host | Scene 已隔离到同二进制子进程；普通 App 不持有渲染 runtime，不重做迁移 |
| F2 | [FrameDriver](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+FrameDriver.swift) 在 daemon 主 RunLoop 上更新 VM、状态并逐 surface 渲染 | 上一轮“主线程”指 daemon 主线程，不等于主 App UI 线程；线程迁移必须连同 VM affinity 处理 |
| F3 | [Launch](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift) 已有后台准备；[PassEncoder](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift) 已有 PSO/library 缓存和 warmup | 不把异步启动、PSO 预热、同源 library 去重再列成从零建设 |
| F4 | [FramePreflight](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift) 构造 target/request；[Coordinator.prepareFrame](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift) 在锁内核验、准备池和候选 | admission 是优先测量边界；需要区别静态证明、实时绑定和事务生命周期 |
| F5 | [GraphExecutor](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift) 每帧 PreparedStage 携带命令、frameResources、persistentResources；[Preparation](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Preparation.swift) 为局部失败保存状态 | “prepared”混有 launch 产品和帧临时产品；不能把帧资源对象跨帧缓存 |
| F6 | [Validation](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Validation.swift) 已用输入摘要避免命中时重做 target plan；物理纹理 identity 仍检查 | 不恢复被撤回的对象身份→Bool memo；后续只消融被证明不可变的推导 |
| F7 | [Renderer](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift) 与 FramePreflight 分别求可见集合；[world projection](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+FrameWorldProjection.swift) 已缓存 topology 投影 | 两处输入不同，先统一 root visibility／dependency closure 合同，再共享结果；静态 world 与动态 topology 优化已有，不能重复做 |
| F8 | [MetalView](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift) 在动态文字、纹理组装和 renderer 之前取 drawable；[MainPassEncoder](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneMainPassEncoder.swift) 离屏时关主 pass，恢复 load/store | 可测 drawable 持有与带宽成本；不保证是主要瓶颈 |
| F9 | Coordinator 的 `submissionQueueAcceptsFrameLocked` 对 pending history tail 串行；FrameDriver 使用 all-surface 准入并在部分提交时回滚 CPU 状态 | 保留安全准入；多屏失败与不可撤销 GPU 提交必须先设计，再考虑增加 in-flight |
| F10 | [TextureRegistry](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift) 已有增量 digest；[VideoTextureSource](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneVideoTextureSource.swift) 用 CVMetalTextureCache；粒子已有 prepared operator 与稳定压缩循环 | 不再笼统要求每项“加缓存／零拷贝／预编译”；保留现有 owner 与回滚语义 |
| F11 | [Multiplexer](../../../MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift) 是路由表，不是全产品选择权威；公共 [command](../../../MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift) 直接引用 SceneUserPropertyValue | 公共控制边界仍与具体 Scene 类型耦合；不能把转发器误称完整协调器 |
| F12 | [Video handler](../../../MyWallpaperX/Modules/VideoLibrary/Core/VideoPlaybackCommandHandler.swift) 也经 WallpaperEngine 控制 Web；Application 只注册 video/scene；[WallpaperEngine](../../../MyWallpaperX/Core/Playback/WallpaperEngine.swift) 默认 dedicated Web adapter | Web 没有独立注册 handler 不等于不可播放；拆分必须撤销旧间接路径，防止重复 pause/stop |
| F13 | [Settings](../../../MyWallpaperX/Shared/Settings/AppKitSettingsView.swift) 仍直接调用 SteamWorkshopService；[runtime switch](../../../MyWallpaperX/Shared/UI/WallpaperRuntimeSwitch.swift) 直接 invalidate ImportedVideoAutoplayGate | 移入 Shared 并未彻底倒置依赖；需要真实移交而非继续包一层 |
| F14 | [color lowering](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderArtifactBuilder+ColorTransferSpecializedLowering.swift) 匹配生成 MSL 的变量、调用数量与源码形状 | 扩展／维护成本候选，不把编译期 matcher 直接算成稳态 CPU 热点 |

已存在但仍须运行回归的能力：唯一 compositor、纹理／target 池、history pin、粒子实例 ring、异步文字、deferred base image、compiler 预算、属性 revision、DaemonKit、解码缓存预算。它们不列入无条件删除项。

### 2.3 已有实验对新计划的约束

下述来自旧工程记录，本轮未重跑，不能跨构建、签名、路由、诊断模式比较绝对值；只用于避免重复无效方向。

- 复杂 graph 的历史普通模式 admission 约 25.5 ms、整段 CPU 约 34 ms；后继 daemon 记录仍有约 33.1 ms CPU 和约 12.1 s startup。**优先复测 admission 与冷启动分解，不据此承诺提速。**
- completion 唤醒两版曾增加到 509–534 busy／20 s，attempts 翻倍，未改善 FPS。E4 必须先有正常模式 busy 占比，不能把换 Timer 当第一步。
- counter 微基准折算约 1.70 µs／帧；整帧因诊断和冷准备混杂不可归因。counter 合批只在新测量支持时做，不排为毫秒级主攻点。
- executor 验证 Bool memo 曾撤回；缓存静态结果不能略过 fresh frame 的 texture、generation、history 与 function target 验证。
- 旧记录 code-health 19 errors／181 warnings，与本轮错误数量一致，但旧“已验收”卡不构成当前树全绿。
- Fast Suite 当前 7 项中 3 approved、4 selection-required；不能把两个代表内容或普通矩阵冒充完整 Suite PASS。

历史具体身份与实验见归档；近期独立运行事实查[运行证据](../semantics/runtime-evidence-current.md)。仍待本轮后续测量：正式签名正常模式的 p95/p99、分配／CoW、锁持有、GPU 带宽、多屏、功耗、冷／热启动、test 编译总时间。


## 6. 代码、测试与文档的退役清单

### 6.1 代码按职责删除，不按大文件删除

| 候选族 | 保留 | 要撤销的职责 | 执行卡 |
|---|---|---|---|
| FramePreflight／GraphExecutor／SubmissionCoordinator | live 资源与事务安全、局部失败 | 重复静态推导、同帧重复集合与不必要候选副本 | E1 |
| FrameDriver／MetalView | 唯一 clock、VM 顺序、surface output | 有证据后撤销多余等待／重试／drawable 持有 | E4 |
| ShaderFrontend／ShaderPreparation | 作者语言与颜色合同 | 已被类型化语义替代的源码形状族 | E5 |
| PlaybackControl／Manager／Engine／Shared | 一个产品意图与各 adapter 执行事实 | 公共层领域泄漏、重复 switch 状态与副作用 | E2 |
| tests 内巨大 SUPPORT／SWIFT_SOURCES | 独立输入和反例 | 重复 stub、内部符号锁定、已撤权实现期待 | E6 |

具体文件删除必须在对应批次确认全部引用、target membership、source_sets、layout manifest 和 tests 后列出；目前没有证据允许直接删除整族文件。引擎状态机保护的资源生命周期不按命名长短裁剪。

本次 19 个 code-health 错误的精确归属如下。路径按各行前缀展开，均为基点事实；执行时重新跑检查，不照旧数字销账。

| 前缀／范围 | 文件名 | 卡／处置 |
|---|---|---|
| [MyWallpaperX/Modules/SteamWorkshop/UI/](../../../MyWallpaperX/Modules/SteamWorkshop/UI/) | `AppKitSteamWorkshopBrowserItem.swift`、`SteamWorkshopItemDetailSheet.swift` | E6：恢复 locked allowance，按 UI 与请求投影职责消融 |
| baseline 中旧 VideoLibrary/UI/AppKitSettingsView.swift（历史路径，无现存文件） | 文件已不存在 | E6：核对迁移后只移除 stale baseline；不能给新路径新增 1536 行豁免 |
| [Compilation/Material](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/) 与 [Rendering/Graph](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/) | `SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift`、`SceneResolvedMaterialExecutionCapability.swift`、`SceneResolvedMaterialGraphExecutor.swift` | E1／E5：压缩准入与执行职责 |
| 同 Scene 根下 `Rendering/Dependencies/` | `SceneDependencyRenderPlan+BindingCompilation.swift` | E1：静态依赖准备 |
| 同 Scene 根下 `Compilation/Material/` | `SceneResolvedMaterialProgramFinalizer.swift`、`SceneResolvedMaterialShaderSchema.swift` | E1／E5：参数准备与语义收敛 |
| 同 Scene 根下 `Rendering/Frame/` | `SceneMetalRenderer.swift`、`SceneResolvedMaterialFramePreflight.swift` | E1／E3：帧准备与合成分责 |
| 同 Scene 根下 `Resources/Textures/` | `SceneTextureProviderPublication.swift` | E1：保留 publication 完整性，移除重复投影 |
| 同 Scene 根下 `Runtime/Session/` | `SceneDesktopWallpaperHost+FrameDriver.swift`、`SceneDesktopWallpaperHost+Launch.swift` | E1／E4：准备与帧事务；不为行数强行搬线程 |
| 同 Scene 根下 `Systems/Script/` | `SceneScriptScalarProgram.swift`、`SceneScriptScalarRuntime.swift`、`SceneScriptVectorProgram.swift` | E1／E6：共享 bridge 与帧事务，保留类型差异 |
| [MyWallpaperX/Shared/Settings/](../../../MyWallpaperX/Shared/Settings/) | `AppKitSettingsView.swift` | E2／E6：清除模块调用并按动作边界收敛 |
| `script/tests/fixtures/` | `SceneMaterialCopyHistoryRenderingHarness.swift` | E6：拆除重复 harness，保留 copy/history 可执行反例 |

### 6.2 文档逐项处置（当前文件全部保留或已无损归档）

路径相对 `docs/`。体量是 §2 的基点，不是性能收益。

| 精确文件／范围 | 处置与唯一去向 | 前置依赖与保留内容 |
|---|---|---|
| `scene/engine-refactor-program.md` | 本轮就地改为本档案；旧正文完整归档 | 原 M0–M6 注释是历史编号，不再决定下一批；不用批量改代码注释制造噪声 |
| `scene/design/runtime-as-built-map.md` | 下一文档批压缩为当前链、owner、线程和不变量；移走 M 批次流水 | 目前约 22 KB；保留 source anchors 与 memo／identity 反例，不冒充独立目标合同 |
| `scene/scene-compatibility-roadmap.md` | 保留兼容验收与优先级；明确性能不等 P5 | 不再重复工程批次；P1–P4 仍守画面与作者行为 |
| `scene/scene-open-breakpoint-queue-2026-09-09.md` | 条件退役候选：把仍开放项归样本调试／验收的现有数据源，留下指针后撤 active-plan | `test_document_role_index.py` 显式要求该日期化计划；先改语义等价治理门与 index，再归档，不能直接删文件 |
| `scene/semantics/coverage-ledger.md` | 顶层只留当前能力摘要、owner、明确缺口与专题链接；批次正文转冷档 | 47 个引用文件；保留所有现役 anchor 或映射；不重复六张专题表 |
| `scene/semantics/runtime-evidence-current.md` | 当前构建／仍有效正负证据的短索引；每个首断点只保留最新裁决和限制 | 34 个引用文件；旧 hash／版本／截图记录完整归档，唯一失败现场保留 |
| `scene/semantics/scene-sample-debug-ledger.md` | 当前首断点及证据指针；旧修复流水冷藏 | 与 acceptance 的人工 verdict 分开；先核对生成／修复数据源 |
| `scene/semantics/scene-sample-acceptance-ledger.md` | 保留生成视图 | `script/scene_sample_acceptance_verdicts.json` 是人工裁决输入；不手改生成结果冒充通过 |
| `scene/semantics/scene-corpus-capability-inventory.md` | 保留按需生成视图 | generator 与 snapshot 仍是事实来源；不每批重扫真实 corpus |
| `scene/semantics/effect-execution-coverage.md`、`render-graph-shader-coverage.md`、`scenescript-api-coverage.md`、`particle-component-coverage.md`、`runtime-input-property-coverage.md`、`advanced-object-coverage.md`（均在同一 semantics 目录） | 每专题只留当前合同／owner／缺口／证据指针 | 跨表共用状态仅在顶层索引，不新增复制日志；按专题逐份迁移，不一口气重写 |
| `scene/semantics/source-index.md`、`official-page-map.md`（同目录） | 保留来源 taxonomy／公开资料导航，按需读 | 安全边界和 provenance 不当成“杂文”删除；仅消除重复说明 |
| `scene/design/scene-runtime-daemon-contract.md`、`architecture/scene-launch-responsiveness-contract.md` | 保留 IPC／launch 合同；迁移步骤与旧批次退出正文 | 先保证当前 client／host consumer 一致，不与 runtime architecture 复制现状 |
| `scene/design/runtime-architecture.md`、`architecture/technology-stack-boundaries.md` | 长期合同只留边界与稳定设计；本计划验证后的改变再接管 | 五类产品是分类而非强制公共协议；移除样本／批次叙事需保留引用 |
| `scene/semantics/README.md`、`scene/README.md`、`README.md`（docs 根） | 短导航，一项事实只链接唯一 owner | 默认入口不强制读取整份地图／台账，禁止把下一任务写遍三个入口 |
| `history/` 已有 22 份 Markdown + 本轮旧计划归档 | 默认不读；物理删除不属于本轮 | 未来删除必须逐文件证明无独有证据、修引用并取得精确清单确认 |
| `web/current-state.md` 与 Web 专题合同 | 下次触达 Web 时刷新源码事实；删除重复历史数值 | 不将 2026-08-11 复核快照当当前运行 PASS |
| `architecture/appkit-migration.md` | 只保留真实残留与退役门 | 工程 `.swift` 统计不是 SwiftUI 实际调用证据，先核对 target 与 import |

当前层压缩验收：能力摘要、运行证据摘要分别以约 20 KB 的默认阅读段为设计预算；完整按需附录可以更大，不以硬删内容凑数。默认工程阅读只需“工作规则＋本计划当前卡＋一条相关合同”，不要求把 3.22 MB Scene 文档全部喂入上下文。统计 UTF-8 字节、默认段体量和重复维护点，不只统计行数。

### 6.3 文档执行顺序与防丢失

1. 列每个现役 anchor、引用文件、generator／测试 consumer；“文档互链”不等于 runtime 消费。
2. 提取仍改变 owner／失效／失败／验证的内容；过期叙事完整归档并标截止日期。
3. 当前文件就地缩短，保留必要 anchor／重定向；更新 role index、导航和真正的 machine consumer。
4. 跑文档／语义链接门，逐条检查旧失败与研究边界未丢；确认 default reading 更短。
5. 只在需要物理删除时提交精确删除清单；不清理 `.codex` 根、真实样本根或未知缓存。
