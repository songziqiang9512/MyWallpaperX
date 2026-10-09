<!-- document-role: active-plan -->
<!-- retirementCondition: 启动冷路径的解析核函数全部 nonisolated 单实现、后台段执行并被门禁断言锁定后，若后续引入替代编排则整体归档。 -->

# Web 冷路径 descriptor 解析后台下沉

> 复核基线：2026-10-09，工作树（批二 dcca8d64 / 批四 07704a86 之后）。本文是设计裁决，不是当前能力或运行验收。

## 目标合同与设计判据

点击播放的冷路径（分析缓存未命中）在主线程做完整 descriptor 解析：project.json 多次读盘、入口 HTML 与依赖 JS/CSS 的 BFS 静态扫描（`resolvedWebStaticContentSummary`）、目录 listing（`webSampleStructure`）、预设绑定的候选根 stat。批二已把运行时清单的读盘/校验/写盘下沉；批四的记忆缓存把重复调用面归零后，首个未命中冷解析成为主线程最后一个重 IO 残留。横切 SteamWorkshopService 解析链与启动主链=是；触碰唯一权威合同（descriptor 单一构造源）=是；判据成立，先设计后实施。

## 当前事实与证据

- 冷解析入口 `computeResolvedWebProjectDescriptor`（`SteamWorkshopWebResolvedRuntimeModels.swift`）：`webPropertyDefinitionSourceRecord`（读记录存储=actor）→ 链式调用解析 helpers。
- 解析链 actor 访问面终审：唯一直接 actor 读是 `webPropertyDefinitionSourceRecord`；书签解析（`resolvedBookmarkedWebPropertyURL`）有副作用（security scope 管理、陈旧书签回写）必须留主线程，但**解析链只消费 preset 绑定**（`definition==nil` → kind 为 pathlikePreset 或提前返回），从不触书签分支；其余全部为纯 record+URL+FS（loadWebProjectRoot/declaredEntry/webPresetValues/sampleStructure/staticContentSummary 的 BFS/riskFlags/presetBindings/candidateRoots/existingWebResourceURL）。
- 间接 actor 读藏在三个 helper 内部：`webPropertyDefinitions`/`webSampleStructure` 内部各自再调 `webPropertyDefinitionSourceRecord`；`resolvedWebStaticContentSummary` 内部再调 `webPropertyDefinitions`；`resolvedWebStructuralRiskFlags` 内部再调两者。这是拆分的全部动因——不是它们需要 actor 状态，而是调用形状没把已解析的输入传下去。
- 同步调用面（属性面板 rebuild/详情页/诊断/宿主桥闭包）在批四已定型为保持同步 API；descriptor 全异步化是 UI 状态机重构，不在本设计范围。

## owner

- 解析核（nonisolated 纯函数族）：SteamWorkshopService Web Core——单一实现，主线程与后台段共用。
- 启动冷路径编排：`resolvedWebPlaybackContext`（批二已 async）——actor 快照 → 后台段。
- 记忆缓存/失效钩子：批四的 `webProjectDescriptorCache` 不变，两条编排共享。

## 方案设计与选型

选 **(a) 解析核 nonisolated 化 + 启动编排后台化**。候选 (b) descriptor 整体 async 化被批四否决（同步 UI 表面涟漪）；候选 (c) 维持现状（批四已把重复面归零，冷解析有界一次每 mtime 态）不满足启动主链零重 IO 的既定方向。

1. **拆分而非复制**：四个内部再解析的 helper 各拆为「主线程 wrapper（保留原签名，快照 actor 输入后调核）+ nonisolated 静态核（显式收 sourceRecord/definitions 等参数）」。wrapper 是既有调用方（属性面板/校验报告等）的唯一入口，核是两段执行的同一实现——无第二链路。
2. **书签分支外提**：`resolvedWebResourceBinding` 拆为 nonisolated 核（收 `bookmarkedURL: URL?` 参数）+ 主线程 wrapper（usesBookmarks 且非 pathlike 时先解析书签再调核）。preset 路径（解析链唯一消费者）传 nil——与现状等价（该路径从不触书签）。
3. **启动冷路径编排**（`resolvedWebPlaybackContext` 内）：主线程 memo 检查 → `webPropertyDefinitionSourceRecord` 快照 → 后台段（分析缓存读盘+校验扫描（含批四会话新鲜快速路径，校验器镜像批二 isRuntimeManifestValid 形态）→ 未命中则解析核全量构造 descriptor）→ 主线程 memo 存 + 批二后台双清单写盘。
4. **同步路径不变**：`computeResolvedWebProjectDescriptor`（memo → 同步分析缓存读 → 同步解析核 → 同步保存）保持批四形态，服务同步 UI 表面；其成本已由 memo 有界。

## 失败与退出

- 后台解析与主线程快照间记录状态漂移：与既有 mtime 键纪律同级（批四已论证），无新增弱化。
- 后台段异常/超时无兜底需求：解析核全部 `try?`/可选语义，失败返回 nil → 启动走「没有找到可播放的 HTML 入口文件」既有失败出口。
- 退出条件：若解析核 nonisolated 化引入行为回归（审查或门禁红），回退本设计并维持批四形态；wrapper/核双签名长期并存即技术债，归档时必须已无 wrapper 直接调用方新增。

## 验收

- 焦点模块与 `web_property_persistence_gate` 全绿（启动冷路径行为不变——三 App 启动、A→B→A、缓存冷写热校验；空 HOME 首阶段即无任何清单的冷启动场景）。
- 后台段封闭性的机器证据：default-MainActor 项目里 nonisolated 函数回读 MainActor 成员是编译错误——解析核全部 nonisolated 且构建通过，等价于「后台段零 actor 回读」的编译期断言（强于运行期抽样探针）。
- 独立子代理审查：拆分等价性（核与原实现逐行）、书签相邻段（preconditions/presetBindings，经 resolvedWebResourceBinding 触 security scope 与陈旧书签回写）确实留在主线程收尾、同步路径零改动、两编排共享 memo/装载器/解析核无重复实现。
- 实施偏差记录：设计初稿第 2 点拟以 bookmarkedURL 参数外提书签分支；实施发现解析链的 preset 绑定从不进入书签分支（definition==nil → kind 恒为 pathlikePreset 或提前返回），且 preconditions 的 definition 变体活触书签——两者一并留在主线程收尾段（assembleResolvedWebProjectDescriptor），比参数外提更短且不触碰书签副作用语义。
