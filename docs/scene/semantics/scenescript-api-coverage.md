# SceneScript API 覆盖表（官方声明 v2.8）

> 核验日期：2026-08-15
>
> 官方基线：`lib.sceneScript.d.ts` **VERSION 2.8**，固定文档 revision `b26412295cbfd0ee5cdceff67e2c95069527aa1b`。
>
> 资料入口：[资料来源与证据索引](source-index.md)、[官方页面全目录](official-page-catalog.md)、[运行时系统语义](runtime-systems-reference.md)、[总覆盖台账](coverage-ledger.md)。固定客户端深层观察只在独立研究任务中查[2.8.42 SceneScript 静态取证](scenescript-runtime-implementation-contract.md)，implementation agent 不直接读取该页。
>
> Scene 实现身份、运行证据与聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)；本表不复制基线 commit，文内旧 commit/批次号只用于追溯，不定义现役顺序。

## 1. 当前结论与评级口径

当前结论只有一条：项目已用同一 QuickJS-NG scene domain 执行 pass-owned numeric scalar 与 object-owned origin/scale Vec3 `init/update`，并开放 allowlisted `WEMath.smoothStep`、callback-scoped immutable `engine.timeOfDay/frametime/runtime`、typed `engine.userProperties` snapshot、descriptor-bound `thisLayer` effect lookup，以及 callback-scoped `thisScene` layer lookup与只读 `ILayer.id/name/origin`；但**没有完整 SceneScript API/host runtime**。逐 API 表继续使用本专题定义的 `L0-L4` 表达接口覆盖；`S*` 只引用[运行证据索引](runtime-evidence-index.md)对精确 identity 的证据闭合等级。两轴正交，不能互相批量推导，也不能与其他专题的同名 `L` 横向比较。

| 能力面 | 当前结果 | 精确边界 |
|---|---|---|
| Generic ECMAScript VM/API | `L3 bounded scalar+Vec3+typed snapshots+effect/layer handles / S4 bounded visible` | QuickJS-NG 开放 inline scalar及object origin/scale Vec3 `init/update`、唯一 allowlisted `WEMath` module、immutable engine/user-property snapshots、descriptor-bound effect lookup，以及scene layer name/index/id/count lookup与只读origin；没有通用 file module graph、scene/layer mutation、event queue、timer/job scheduler、mutable `shared` 或完整 lifecycle |
| Binding/source evidence | `L1 / S1 preserved` | inline source、scene/object/effect/pass owner、完整 target path、properties、authored fallback、JSON value type 与可选 wrapper keys 可保真；source evidence 只用于 provenance/conflict rejection，不能取得执行权 |
| Bounded Text `update(value)` AST | `L3 bounded / S3 executed` | 不按 sample/layer/source hash 准入；只执行受控无循环 AST、Date getter 与 string/value 子集。现役 compiler/runtime 和自动门存在，但 fixed profile 撤权后没有刷新绑定当前产品身份的可见证据，因此本页不把它写成现役 `S4` |
| `WEMath` + `engine.timeOfDay` scalar | `L3 bounded / exact consumers S4 visible` | 原 `SceneTimeOfDayEffectScript*` Swift AST/compiler/runtime 产品族已删除。普通 binding IR 接纳 `script + user:null`，同一 generic VM 在真实 `2134765860` 建立 11 个 scalar owner，其中 6 个 `WEMath.smoothStep + engine.timeOfDay` target 在本地 12:00 输出 0、22:00 输出 1；route=`generic-only`，失败只保留该 target 的 previous-current。非 null `user + script` 仍冲突关闭 |
| Bounded media fade / launch-origin projections | `L3 bounded / exact positives S4 visible` | placeholder fade 只驱动严格 pass-owned Opacity producer；launch-origin 只覆盖 initial-false 的一个 typed cohort。两者都有绑定 fixture 的可见正证，但不执行 JavaScript、generic media event、mutable `shared`、任意 origin script 或整样本；对应样本整体仍可为 NON-PASS |
| Generic Vec3 property owner | `L3 bounded / S4 bounded visible` | object `origin/scale` 的loss-preserving binding由同一QuickJS domain执行；除既有真实`2802243144`两个origin owner外，真实`3122339805`又以`thisScene.getLayer("C29").origin`驱动layer `235` origin，结果进入统一frame snapshot。route=`generic-only`、failure=`previous-current`；只证明这些真实origin consumer，不外推全部Vec3 target或完整Vec3 API |
| `311115e3` 其余 bounded native projections | `L2 / S2 wired / visible unknown` | primary-button/hover hit-test、shared alpha、audio-scaled value、identity display、media playback/colors/title/artist 已有产品接线和自动测试源码，但没有该接线后的 fresh runtime/ROI；它们不是 generic event、VM callback、mutable shared 或 live media API |

表中的 `S4` 只引用运行证据索引登记的精确 App/fixture/ROI 身份。现役 `engine.timeOfDay` 证据来自一个原始只读真实样本的日/夜差分与 6 个 typed consumer；严格样本报告仍因 31 项其他陈旧/宽域期待为 NON-PASS，不把该切片扩张成 whole-scene、family 或 parity 结论。

上述 bounded 子集的执行 identity 来自作者结构和 typed target，不以完整样本/source identity 选择视觉答案。精确证据分别见 [E-TEXT-SCRIPT](runtime-evidence-index.md#e-text-script)、[E-EFFECT-BLEND-TRANSFORM](runtime-evidence-index.md#e-effect-blend-transform)、[E-MEDIA-PLAYBACK-PLACEHOLDER-FADE](runtime-evidence-index.md#e-media-playback-placeholder-fade)、[E-BOUNDED-LAUNCH-ORIGIN-TRANSITION](runtime-evidence-index.md#e-bounded-launch-origin-transition)和[E-BOUNDED-INPUT-PROJECTION-WIRING](runtime-evidence-index.md#e-bounded-input-projection-wiring)。

所有按 raw source/profile 选择的 fixed Text/date/greeting、TextureAnimation 与 native Audio Bars owner 都是 **sealed historical**：现役产品不再授予它们执行权，旧 commit、批次、报告、截图和 64-draw 只能追溯已退役实现，不能定义当前输出或下一步。普通 TEX/multi-image autoplay、host 16/32/64 频谱和 Effect Audio Bars 是独立非 SceneScript 能力，不能替下表 API 升级。

`3768229922` 仍没有恢复 generic click/shared/display：display scripts `397/202/354` 只有 provenance 与安全抑制；hidden controller/update、head `cursorClick`、mutable shared toggle、alpha/display mutation、开场 fade/destroy，以及人物头部点击切换 16 层文字/红框遮罩均未执行。`311115e3` 的 bounded primary-button projection 不证明这条链，见 [E-AUTHORED-STRAIGHT-RGB-SCALAR-ALPHA](runtime-evidence-index.md#e-authored-straight-rgb-scalar-alpha)。

当前首批只按 V2 闭合一个纵向结果：QuickJS-NG per-scene runtime/context → one typed owner → `init/update` → owner-local mutation → Swift frame transaction → next-frame visible consumer；完整 API、event、timer、dynamic layer 或发行平台不是第一条正确脚本画面的前置。owner、预算、reload/teardown 与 stale-handle 只按下方项目自有目标合同实施，不从固定客户端反编译表达反推代码。

### 1.1 MyWallpaperX V2 目标运行时合同

本节是 implementation agent 可以消费的项目自有合同，不描述官方内部实现：

- 每个 scene execution domain 默认独占 QuickJS-NG runtime/context、module registry、job queue 和预算账户；scene/reload generation 之间不共享 JS object 或 native handle。
- 每个 binding/layer/effect/dynamic object 有 typed script owner；host object 只暴露带 domain、owner/object identity、generation 和 capability 的 opaque handle，Swift 每次调用重新校验，VM 不持有 Swift/Metal 裸对象。
- global/module allowlist 默认不含 DOM、Node、WebWorker、文件、网络、进程或任意 native module；路径逃逸、动态 native load 和跨 scene import 拒绝。
- callback 只读取本帧 immutable value/event snapshot 和已提交 provider state，结果写入 owner-local mutation buffer；Swift 在帧边界校验 identity/generation/type/finite/conflict 后，以单一 topology/VM mutation transaction 提交。callback 不直接改正在遍历的 graph、Program、target 或 compositor。
- 每个 runtime 与 callback 必须有 heap、stack、deadline、每帧 CPU/job/timer/mutation/identity 预算。exception、unhandled rejection、NaN/Inf、stale handle、timeout 与 OOM 只熔断最小 owner；runtime 不再可信时才重建该 scene VM，同时保住不依赖脚本的安全画面。
- reload 建立新 generation，切换成功后才撤销旧 owner；teardown 停止 dispatch、interrupt callback、取消 job/timer/event、丢弃 pending mutation、按项目合同调用 `destroy` exactly once、撤销 handle 并证明 owner/job/timer/handle 归零。

官方事件顺序、默认值或数值边界未由公开合同/黑盒确认时保持 unknown；研究任务可按官方客户端工作流生成一个中性行为合同，fresh implementation context 只接收该合同和项目自有正反门。不得把 2.8.42 的 V8 数据结构、record、常量或静态调用顺序当成 QuickJS-NG 的实现模板。

等级使用本专题本地定义：

| 等级 | 本表含义 |
|---|---|
| `L0` | 没有可调用、可观察的 SceneScript runtime 行为 |
| `L1` | 能保真解析/保存该 API 所需 IR，但未路由 |
| `L2` | 已路由到 typed runtime/handle，但未真实执行 |
| `L3` | 已执行受限子集，并有正反例和生命周期门 |
| `L4` | 已由官方行为或 Windows golden 验证 |

### 1.2 本地证据代号

| 代号 | 代码/测试证据 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| `P` | [`SceneResourceIndex.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceIndex.swift)、[`SceneCapabilityProfile.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneCapabilityProfile.swift) | `.js` 分类和 package-level presence | 源码读取、模块加载、执行 |
| `I` | [`SceneDocument.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift)、[`SceneScriptBindingDefinition.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneScriptBindingDefinition.swift)、[`SceneRenderDescriptor.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneRenderDescriptor.swift)、[`SceneLayerVisibility.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneLayerVisibility.swift)、[`SceneTextScriptDefinition.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextScriptDefinition.swift) | 文档级五类binding保真inline source、owner、完整target path、properties、authored fallback与JSON value type；作者顶层`visible/alpha` script ownership可在value resolution前保真并使未证display authority失败关闭；layer顶层旧carrier与文字inline source继续保留 | 这只是provenance/故障隔离；file/module、schema-resolved Vec/value type、runtime handle、VM、API、事件与生命周期均未执行 |
| `W` | [`SceneParticleDefinitionParser.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleDefinitionParser.swift)、[`test_scene_particle_definitions.py`](../../../script/tests/test_scene_particle_definitions.py) | 动态 wrapper 的 `hasScript` presence 可诊断 | wrapper script 的源码或求值 |
| `D` | [`SceneDynamicSnapshot.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift)、[`SceneTextScriptSubsetCompiler.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextScriptSubsetCompiler.swift)、[`SceneMediaPlaybackPlaceholderFadeCompiler.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneMediaPlaybackPlaceholderFadeCompiler.swift)、[`SceneQuickJS.c`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJS.c)、[`SceneQuickJSHandleHost.c`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJSHandleHost.c)、[`SceneScriptLayerHandleBridge.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptLayerHandleBridge.swift)、[`SceneScriptScalarRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptScalarRuntime.swift)、[`SceneScriptVectorRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptVectorRuntime.swift)、[`test_scene_script_quickjs.py`](../../../script/tests/test_scene_script_quickjs.py) | typed target、固定优先级、bounded text/fade，以及真实ECMAScript scalar/Vec3 owner、allowlisted `WEMath`、immutable frame/user-property input与callback-scoped descriptor layer/effect handles；旧time-of-day与property-vector Swift AST/source-shape产品族已删除 | bool/string/Vec2/Vec4/matrix、其他module/API handle、event/timer与完整VM lifecycle |
| `F` | [`SceneFrameContext.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift)、[`SceneTextScriptRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextScriptRuntime.swift)、[`SceneDesktopWallpaperHost+FrameDriver.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift) | 同帧 wall date、simulation frame time 与 scene runtime 在 surface loop 外形成一次 typed frame snapshot；QuickJS callback 只读该快照并把成功值广播进各 surface transaction | live event/timer/provider、locale/DST/通用离线 clock、真实多屏输入一致性 |
| `G` | 2.8.42 主程序与 SceneScript module 的 Ghidra 有界静态证据，详见 [静态取证 §8](scenescript-runtime-implementation-contract.md#8-engine-与宿主生命周期静态互证gb) | 版本握手、effective time/pause、固定事件槽、watchdog/timer/audio tick、typed return、camera/material/particle/video/animation handle 与 host-owned teardown 的研究候选结构 | MyWallpaperX 已实现、官方可观察结果、完整 ABI，或对 implementation agent 的直接授权 |
| `N` | 全仓 `SceneScript`/VM/API 搜索及现有 Scene 测试 | 用于确认现役 VM/API 边界之外没有其他产品 bridge；`D/F` 已单列当前 scalar/frame-input 子集 | 不能把其他 Swift renderer 的同名能力算成脚本 API，也不能用缺失扫描否定已登记的 VM 子集 |

### 1.3 目标执行模型与来源边界

SceneScript 不是孤立的脚本引擎，而是与 Timeline、用户属性和作者默认值共同组成的属性绑定系统。本节同时使用多类证据，必须分开理解：

| 内容 | 来源 | 用法 |
|---|---|---|
| API、global、hook 签名和作者可见类型 | 官方 v2.8 declaration 与公开页面 | 定义兼容表面 |
| engine tick、owner、timer、cursor 和 teardown 结构 | 2.8.42 客户端有界静态取证 | 收窄实现顺序与 fixture；不代表 MyWallpaperX 已实现 |
| immutable snapshot、generation、预算和失败关闭 | MyWallpaperX 目标合同 | 项目安全与跨平台 policy；与官方实现不同处必须明确标注 |
| 当前等级 | 本表、总覆盖台账与运行证据索引 | 唯一实现状态 |

#### 1.3.1 求值优先级（从低到高）

```
authored default → userProperty → Timeline → SceneScript
```

- **authored default**：场景文件中的初始值
- **userProperty**：用户在属性面板设置的覆盖值
- **Timeline**：时间轴动画当前帧的计算值
- **SceneScript**：脚本 `init/update` 返回值或直接 setter

**核心规则**：
1. Timeline **先于** SceneScript 求值
2. SceneScript 可以覆盖 Timeline 的结果
3. 同一帧内，上述四级值按优先级合并为单一 immutable snapshot
4. 缺少某一级时跳过，不影响其他级

**实施约束**：
- 当前 `SceneDynamicSnapshot` 已预留 `.sceneScript` 优先级槽位（v22）
- Timeline 已有受限 `L2-L3` target/evaluator；SceneScript scalar+frame-input 子集为 `L3 bounded`，其他类型/API 仍逐项保持 `L0-L2`；精确现状见 [总覆盖台账](coverage-ledger.md#61-timeline-与-scenescript)
- 不得让 SceneScript 提前执行后被 Timeline 覆盖
- 不得让用户属性在脚本后才生效

#### 1.2.2 生命周期钩子

| 钩子 | 调用时机 | 返回值语义 | 当前等级 |
|---|---|---|---|
| `init(value)` | owner 创建后调用**一次** | 返回绑定 property 的初值 | scalar `L3 bounded`；其他类型 `L0` |
| `update(value)` | 脚本导出该 hook 时进入有效帧更新 | 返回当前帧的 property 值；动画应乘 `engine.frametime` | scalar `L3 bounded`；其他类型 `L0` |
| `destroy()` | owner 销毁前调用 | 无返回值，用于清理 | `L0` |

目标求值时序：

```
1. Timeline evaluator 计算当前帧所有动画值
2. SceneScript `update(value)` 接收 Timeline 结果作为入参
3. SceneScript 可返回新值覆盖，或不返回则保持入参值
4. 最终值写入 per-surface immutable snapshot
5. Renderer 消费 snapshot
```

静态取证确认没有导出 `update` 的 script record 不应被当成通用逐帧 consumer；初次调用、事件批处理和同帧 mutation 的完整边界仍按 §3 的逐项证据处理。

#### 1.2.3 八个官方全局对象

v2.8 declaration 顶层明确声明八个 global：

| 全局对象 | 接口 | 用途 |
|---|---|---|
| `thisLayer` | `ILayer` | 脚本所属 layer 的句柄 |
| `thisScene` | `IScene` | 当前场景：查找/创建/销毁 layer、camera 控制 |
| `console` | `IConsole` | 调试日志：`log(...)`、`error(...)` |
| `renderContext` | `IRenderContext` | 当前渲染上下文 |
| `input` | `IInput` | 光标位置和按键状态 |
| `localStorage` | `ILocalStorage` | screen/global 作用域持久化 |
| `engine` | `IEngine` | 时间、分辨率、用户属性、音频与资源注册 |
| `shared` | `Object` | 同一 SceneScript 环境共享对象 |

property-bound owner 通过 JavaScript 的 `this` 和 hook 参数暴露，不存在名为 `thisObject` 的第九个 global。随包 authoring type surface 明确没有 DOM/Node/WebWorker 声明，但类型缺席不单独证明官方 VM 的全部运行时负能力。MyWallpaperX 的目标 VM 必须使用 global allowlist，不暴露网络、任意文件、进程或 shell；`Date`、随机数和预算策略需要项目自有正反门，并将与官方行为的差异单独记录。

#### 1.2.4 事件系统

2.8.42 客户端静态路径确认每个 script record 有 19 个固定 event slot：

| 组 | slot |
|---|---|
| 生命周期与屏幕 | `init`、`update`、`resizeScreen`、`destroy` |
| 设置与动画 | `applyUserProperties`、`applyGeneralSettings`、`animationEvent` |
| cursor | `cursorEnter`、`cursorLeave`、`cursorMove`、`cursorDown`、`cursorUp`、`cursorClick` |
| media | `mediaStatusChanged`、`mediaPlaybackChanged`、`mediaPropertiesChanged`、`mediaThumbnailChanged`、`mediaTimelineChanged` |

**实施要求**：
- 事件按 generation 排队，旧事件不得覆盖新状态
- 事件回调中的异常必须隔离，不能终止 renderer
- `applyUserProperties` 首次调用传全部键，后续只传变化键（需 `hasOwnProperty` 检查）

事件 slot、客户端观察到的派发顺序和 MyWallpaperX 的 generation/error policy 是三种不同事实。逐事件的当前等级、静态边界和验收门见 §3。

#### 1.2.5 第一条 V2 纵向切片

SceneScript 首批不按 API 层级搭完整平台，只闭合一个真实 property owner：

```text
existing inline source/binding IR
  -> QuickJS-NG per-scene runtime/context
  -> one typed owner + minimal module/global allowlist
  -> init/update
  -> typed return or owner-local mutation buffer
  -> existing Swift frame transaction
  -> next-frame visible consumer
```

首批同时具备 interrupt/heap/stack budget、exception isolation、reload/teardown 和 stale-handle negative fixture，但只开放该真实脚本需要的最小 host API。cursor/audio/media/timer/dynamic layer 等后续能力复用同一 owner、mutation 和 transaction；它们不是首个 property 可见结果的前置。具体执行合同见本页 §1.1，开发顺序只看[现役路线 V2](../scene-compatibility-roadmap.md)。

## 2. Property-bound 核心合同

| API/合同 | 官方含义 | 等级 | 当前代码/测试证据 | 缺口与升级验收门 |
|---|---|---:|---|---|
| property-bound 实例 | 每份脚本绑定一个具体 property；通用逻辑通常绑定 layer visibility | `L1` | `I` 保真官方正式13处对应的五类 scene/object/effect/pass owner、完整target path、inline source/properties/authored fallback/JSON value type及可选`wrapperKeys`；独立source evidence又保真所有string-valued script wrapper，但nested/未知owner只提供拒绝证据，不提升为binding。`script + user:null` 保留显式 null provenance并允许 VM admission；只有非 null `user + script` 才是双 producer 冲突 | 补 file module graph、schema-resolved generic Vec/value type、runtime handle；重复/缺失 target 与 owner teardown 门。官方13处与297 launch exact13是两项不同计数 |
| `init(value)` / `update(value)` 的 typed value | 入参是绑定 property 当前值；返回兼容值写回；无返回则保持原值 | text String / Blend、Opacity scalar / launch-origin Vec3 为 `L3 bounded`；QuickJS pass scalar与object origin/scale Vec3为 `L3 bounded / S4 bounded visible`；其他generic类型仍 `L0` | QuickJS-NG在同一scene domain实际执行scalar与Vec3 ECMAScript `init/update`，输入是authored/user/Timeline合并后的current-frame preliminary value，成功结果才进入统一`sceneScript` channel；Vec3允许返回对象、原位修改或scalar splat。callback异常/错型不提交Script值，保留owner-entry current。真实`2802243144`两个origin owner完成callback；通用fixture另覆盖未见算术source、scale scalar splat、duplicate拒绝和bad-return局部不发布。各项都无sample/layer/hash dispatch，且VM owner不把裸JS/Metal handle暴露给Swift | generic bool/string、Vec2/Vec4/matrix、完整mutation/coercion/API、更多target、通用handle与官方行为对照；重复/excluded candidate仍缺typed conflict aggregation；单个真实样本不证明整样本兼容 |
| 直接赋值其他 property | 脚本可通过 `thisLayer`/其他 handle 同时修改多个 property | `L0` | `D` 只有 Swift target，没有 JS handle setter | 同帧 mutation buffer；确定冲突顺序、失效 handle 和只读字段；原子提交到 snapshot |
| source/module loader | 加载 inline 或 `.js` 源码及其 export/import | `L3 inline + WEMath bounded` | `I` binding IR保存已准入wrapper的inline source；QuickJS 执行 inline module，并只允许 import 项目自有 `WEMath.smoothStep`。unknown import 在 owner create 阶段 typed fail-closed，不暴露文件系统或 native module | `.js` file graph、规范化路径、UTF-8/大小限制、其他 allowlisted module、依赖图、循环/缺失/越界负向门 |
| ECMAScript VM | 受控 ECMAScript 环境，无 DOM/Web/Node/shell/任意文件系统 | `L3 bounded scalar+Vec3+typed snapshots / S4 bounded visible` | QuickJS-NG 固定 revision `bbe0480a68c664d7737eecde260fd47224b2c0d6`；每scene一个runtime/context，scalar与Vec3 binding共用generation-checked owner模型。真实`2134765860`闭合scalar日夜consumer，真实`2802243144`闭合两个object-origin Vec3 callback。callback的`engine`与user-property object均为每次调用创建的深冻结数据快照；无DOM、Node、filesystem、network或process host module | bool/string、Vec2/Vec4/matrix、其他host handle/module、更多真实producer/consumer、官方行为对照 |
| budget/error boundary | 每实例/每帧时间、指令、内存和 timer 有界；脚本错误不终止 renderer | `L1 bounded scalar / S4 bounded visible` | QuickJS domain设置 heap/stack/interrupt budget；contract harness覆盖 compile/callback exception、disabled fuse、bad return、infinite loop interrupt、stale owner与owner isolation；App 负 fixture 记录 `exception / previous-current`，后续 graph/compositor/next-frame 仍成功；本地 budget 不冒充官方 watchdog parity | OOM/recursion、timer/job budget、wall-time watchdog、diagnostic aggregation、更多 renderer/App failure injection |
| instance ownership | 每个scene execution domain及其中的binding owner隔离；switch/stop必须销毁 | `L1 scene domain / S3 executed` | 一个scene domain持有单一QuickJS runtime/context，多个bindings使用owner handles；launch generation递增，switch/stop前invalidate，旧owner callback返回stale/disabled；正反App fixture均记录`surfacesBefore=1 surfacesAfter=0`，当前证据仍只有单surface | pause/resume/timer/provider residue、真实多surface下输入/final snapshot/consumer/event/teardown一致性与scene切换stale handle可见门；不据此要求第二套per-surface VM |

## 3. 生命周期与事件

| 事件/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `init(value)` | owner 创建后调用一次，返回绑定 property 初值 | `L1 bounded scalar / S3 executed` | QuickJS-NG contract 与当前 App 正例执行 `init`，随后在同一 owner 上调用 `update`；不推导完整事件顺序 | 每实例恰好一次的独立计数、更多类型、异常降级、callback mutation 与 budget |
| `update(value)` | 每个渲染帧调用；动画应乘 `engine.frametime` | `L3 bounded scalar / S4 bounded visible` | text/fade/launch-origin仍是各自 bounded producer；time-of-day 已迁入 QuickJS scalar owner。通用 scalar callback 从 authored/user/Timeline preliminary current 取值，并读取同一 host frame 的 immutable `timeOfDay/frametime/runtime`；失败只保留该 owner 的 previous-current。真实 `2134765860` 以 11 owner、6 个日夜差分 target 进入 Program/graph | Vec/bool/string/object、raw/effective delta 官方 parity、event mutation、inverse4 与完整 teardown |
| `destroy()` | owner 销毁前调用 | `L0` | `G` 确认 destroy 请求排队，普通 update 后 drain，并按 `destroy → engine record removal → host record release` 执行；destroy callback 新 owner 已错过本轮 update但可能进入本帧 render preparation；项目仍无实例，`N` | switch/stop/动态删 layer 均恰好一次；destroy 内创建/timer/跨 handle/异常重入与 stop 后 residue |
| `resizeScreen(size)` | 分辨率变化时调用；首次创建不会自动调用 | `L0` | `N` | resize 正例和 startup 反例；每屏 size、去重和事件顺序 |
| `applyUserProperties(changed)` | 首次加载调用，之后只含变化键；使用 `hasOwnProperty` | launch-origin startup projection `L3 bounded`; generic event `L0` | launch-origin只把启动时已有scriptproperties/current property值投影进typed plan；不调用callback，也不建立首次全量/后续delta事件队列。其余属性系统不派发脚本事件；`D/N` | generation queue；真实初次全量/后续delta、批量改动、类型、顺序与callback mutation测试 |
| `applyGeneralSettings(changed)` | 首次及 app general setting 改变时调用，v2.8 当前主要是 language | `L0` | `N` | typed settings snapshot；初次/增量、未知键和多屏一致性 |
| `cursorEnter` / `cursorLeave` | 指针进入/离开对象边界 | generic `L0`；bounded hover projection `L2` | 项目已有surface-local camera/world/UV hit-test驱动特定origin cohort，但没有JS callback/event DTO；`G`静态结构不等于产品dispatch | world/local/puppet transform、候选顺序、边界抖动、parent/visible mutation、成对事件与fresh visible门 |
| `cursorMove` | 指针移动时传 `CursorEvent` | `L0` | `G` 确认命中 owner 可接收 move，hidden-solid 仍参与；项目无 dispatch，`N` | world/local 坐标、帧内合并、不同 owner 事件顺序和多按钮 |
| `cursorDown` / `cursorUp` / `cursorClick` | 对象上按下、释放和同对象完整点击 | generic `L0`；bounded click projection `L2` | 项目已有primary-button state、edge与admitted launch-master hit-test/toggle，但没有pressed/capture identity、JS callback或通用queue | drag-out/capture、候选顺序、parent mutation、puppet hitBox、多按钮、预算与fresh visible门 |
| 五个 media events | status/playback/properties/thumbnail/timeline 变化事件 | generic `L0`; bounded playback/colors/text wiring `L2-L3` | placeholder-fade已有历史运行子集；inbox现保存playback/colors/title/artist generation并接bounded consumer，但没有live provider或JS事件队列 | status/timeline/album/previous、live generation原子更新、缺字段、重复/乱序、provider仲裁与owner生命周期 |
| `animationEvent` | Timeline/puppet 指定帧向同 layer script 派发 name/frame | `L0` | `G` 确认它属于可回写绑定 property 的三个 event 之一；项目仍无 dispatch，`N` | typed return、crossing、loop/mirror、seek、低 FPS 跨多帧和一次性派发 |

`animationEvent` 由 Timeline 官方页面确认，但 v2.8 `IComponent` 没列该回调；实现必须保留兼容测试，不能任选一份官方资料后删除另一边。

## 4. 对象与句柄 API

<a id="41-通用-layer--scene"></a>
### 4.1 通用 layer / scene

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `IObject` | `getAnimation(name?)` 取当前 property 或命名动画 | current property `L3 bounded / S4 bounded visible`；named `L0` | callback-scoped `thisObject.getAnimation()` 只在 compiler 已证明当前 property 有 Timeline 时返回 typed handle；带参数调用、无 Timeline、callback 外 retained handle 均拒绝 | named lookup、缺失/重名策略、owner destroy/reload 与跨 callback 生命周期 |
| `IThisPropertyObjectBase` | v2.8 中是只继承 `IObject` 的空 property-owner 基类 | `L3 bounded` | scalar alpha 与 Vec3 origin/scale owner 以完整 authored path/descriptor/Timeline target 绑定当前 property；不添加声明外成员 | 其他 property owner/value type、动态 owner 与 destroy/reload |
| `thisLayer: ILayer` | 当前脚本 owner 的 layer handle | `L3 bounded effect-layer handle / S3 contract-executable` | callback 期间只读开放 descriptor-bound `getEffect(name|index)` 和 `getEffectCount()`；scalar/Vec3 owner 共用同一 catalog bridge，脚本不能伪造 effect identity；callback epoch与active owner阻止retained closure跨owner使用 | 其他 layer 字段/方法、销毁语义仍缺；effect name lookup尚无真实 authored consumer可见正证 |
| `ILayer` transform | `origin`, `angles`, `scale`, `parallaxDepth`, `name`, `visible` | `origin/id/name getter L3 bounded / S4 bounded visible`；其余`L0` | descriptor catalog只读开放safe-integer `id`、`name`与actual `Vec3 origin`；每帧以authored origin为底并叠加现役current snapshot。真实`3122339805`从跨层`C29.origin`更新layer `235` origin；stale handle在callback外拒绝 | setter、angles/scale/parallaxDepth/visible getter、local/world与parent语义、动态layer、官方重名行为仍缺 |
| `ILayer` orientation | `getTransformMatrix`, `rotateObjectSpace`, `lookAt`, `lookAtYaw` | `L0` | `N` | 数学/坐标合同、parent 情况和 2D/3D fixture |
| `ILayer` parenting | 两个 `setParent` overload、`getParent`, `getChildren` | `L0` | `G` 确认同步 parent/attachment resolution 与 mutation、adjustTransforms 的 world-to-new-local 重算、相同关系 no-op、parent getter 与 children snapshot；self/complexity guard 失败会解除旧 parent而不回滚；项目无 bridge，`N` | descendant cycle、缺失 identity/attachment、guard 含义、transactional safety policy、effective visibility/propagation 和销毁门 |
| `ILayer` attachment | `getAttachmentIndex/Matrix/Origin/Angles` | `L0` | `N` | puppet/model attachment identity、缺失返回和 world transform golden |
| `thisScene` lookup | `getLayer(name|index)`, `getLayerByID`, `getLayerCount`, `enumerateLayers` | name/index/id/count `L3 bounded / S4 bounded visible`；enumerate `L0` | callback-scoped descriptor catalog按authored source order查找；最多4096层，safe-integer id、有限origin，缺失/非整数/越界/超额/stale均拒绝。真实`3122339805`消费name lookup；C门覆盖index/id/count与stale反例 | `enumerateLayers`、dynamic layer、字符串ID与官方duplicate-name行为；当前重名取首个authored ordinal只属项目策略 |
| `thisScene` layer mutation | `createLayer`, `destroyLayer`, `sortLayer`, `getLayerIndex`, `getInitialLayerConfig` | `L0` | `G` 确认同步 create/init、2048 bridge identity cap、未知 index=`-1`/sort 失败、超长 sort 夹到尾部、render sort 不改 script record 顺序、普通 update 后 destroy drain、native lifetime 使 wrapper 失效、initial config detached；项目仍无 bridge，`N` | 负 index VM 边界、资产授权、有界 mutation、destroy callback 同帧 render/下帧 update、stale handle 与 create/destroy/sort 冲突 fixture |
| scene camera handles | `getCameraTransforms`, `setCameraTransforms`, `getAnimation` | `L0` | `G` 确认 getter/setter 禁止 global phase、读取同一 base record，setter 对 `eye/center/up/zoom` 做 typed partial update；项目仍无 JS bridge，`N` | finite/type 负门、2D/3D camera、screen resize、同帧 authored/animation 冲突和 round-trip |

### 4.2 内容、effect、动画和高级句柄

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `IImageLayer` 基础 | `alpha`, `color`, `alignment` | `L0` | `D` 有部分 Swift layer target，VM 不可调用 | JS getter/setter、颜色类型、每帧合成和无重建门 |
| `ITextLayer` | `text`, `color`, `alpha`, `opaquebackground`, `backgroundcolor`, `pointsize`, `font`, `padding`, `horizontalalign`, `verticalalign`, `anchor`, row/width limits | `L0` | 当前仅静态 CoreText；`D/N` | 全字段 typed setter、纹理 generation、layout/effect invalidation 和 text golden |
| `ISoundLayer` | `play`, `pause`, `stop`, `isPlaying`, `volume` | `L0` | Scene 无 sound-layer runtime | 音频解码、状态机、音量、pause/switch/stop 和无设备门 |
| `IEffectLayer` | `getEffect`, `getEffectCount`, `transformAttachmentToTexture`, `size`(只读), `perspective`, `solid` | effect lookup/count `L3 bounded`；其余 `L0` | descriptor authored ordinal和exact nonempty name是唯一 catalog authority；缺失名称、非整数、越界和错型在JS调用点拒绝，方法不可覆写 | duplicate name 当前取第一 authored ordinal，尚未对齐官方行为；transform/size/perspective/solid、通用 wrapper stale 与销毁门仍缺 |
| `IEffect` | material 枚举、`setMaterialProperty`, `executeMaterialFunction`, `visible`, `name` | name/function request `L3 bounded / S3 contract-executable`；其余 `L0` | `name` 只读；`executeMaterialFunction(name)`只产生frame-scoped typed request，scalar/Vec3共用bridge并进入既有GraphExecutor mutation carrier。未知function/effect、stale/overflow仍保持局部失败 | 无`setMaterialProperty`、visible/material枚举或任意function body；新descriptor-bound name lookup尚无真实authored consumer运行正证 |
| `IMaterial` | v2.8 仅继承 `IObject`；具体 shader property 通过 effect 方法访问 | `L0` | `N` | opaque handle identity/lifetime；不可伪造任意 shader API |
| `IParticleSystem` | `play`, `pause`, `stop`, `isPlaying`, `emitParticles(count?)`, `instance` | `L0` | `G` 确认 emit 缺省或 0 → 1、正整数原样、负数 no-op，并以零时间偏移进入共用 emitter/default/initializer dispatcher；项目仍无 JS commands，`W/N` | command queue、GPU 同 draw 可见性、暂停/停止区别、容量/预算和 teardown |
| particle instance | `alpha`, `size`, `count`, `speed`, `lifetime`, `rate`, `colorn`, `controlpoint0...7` | `L0` | `D` 仅预留 typed target；无 JS setter/consumer | 逐帧 override、control-point 坐标、generation 和数值边界门 |
| texture animation | `frameCount`, `duration`, `rate`, `play/pause/stop`, `isPlaying`, `get/setFrame`, `join` | TEX autoplay `L3 bounded` / SceneScript API `L0` | 普通单图 atlas 与严格 axis-aligned/integer/same-extent 的 BC1/2/3 cross-image multi-image 按 scene time 及作者 frame duration 循环；两个 fixed SHA owner 已封存并删除，保真的 TextureAnimation SceneScript 不控制播放 | 通用 instance-local detach/join、frame/rate/play/pause/stop/seek handle、owner timer/callback、同帧冲突与 Windows timing golden；旧 delayed-loop/time-of-day 报告只作历史，见 [E-R4-B19](runtime-evidence-index.md#e-r4-b19-fixed-texture-animation-profile-retirement) |
| video texture | `duration`, `rate`, `loop`, `play/pause/stop`, `isPlaying`, `get/setCurrentTime`, `addEndedCallback` | `L0` | `G` 确认缺 provider no-op/default、ended 后 play 先 seek 0、stop=pause+seek 0、非 loop 一次性 edge、loop 以时间回绕派发且主动 seek 不误报；callback owner-scoped 并经 engine batch 派发；底层 controller 为 host-owned registry producer，teardown 先停 worker、退注册再释放 media/GPU；项目无 handle，`N` | rate/loop setter 边界、callback 取消/重入、provider error、registry pump、device-reset retained intent、A/V/颜色和多屏时钟门 |
| `IAnimation` | `fps`, `frameCount`, `duration`, `name`, `rate`, playback 和 frame seek | playback `L3 bounded / S4 bounded visible`；其余 `L0` | zero-arg current-property handle 的 `play/pause/stop` 进入唯一 Timeline playback state；复用 authored evaluator/SceneClock，`play`恢复、`pause`保持、`stop`回到0，命令在 callback 后原子提交并于下一帧消费。真实`3780391264`的start-paused alpha/origin各提交一次`play`，origin下一帧发生数值推进 | named animation、metadata/rate/isPlaying/frame seek、event crossing、reload/teardown与官方时序对照 |
| `IAnimationLayer` | animation metadata；`name/rate/blend/visible`；playback/frame/end callback | `L0` | `G` 确认 ended frame 先派发 layer callbacks、第二遍才移除 one-shot，callback 期间 handle 仍存活；项目无 layer stack，`N` | evaluator/seek crossing、blend、callback 重入/预算和 owner teardown |
| image animation-layer management | count/get/create/playSingle/destroy animation layer | `L0` | `G` 确认 create/playSingle 共用 config 验证与 autosort/index 插入，playSingle 只追加 one-shot；destroy 接受 handle/nonnegative index/name，name 删除全部同名，无效值 no-op，显式 destroy 不冒充 ended；项目无实现，`N` | animation identity、同帧 create/destroy/sort 冲突、blend/root-motion 和 lifecycle golden |
| model animation-layer management | `rootmotion`, perspective 和 count/get/create/playSingle/destroy | `L0` | 无 3D runtime | root motion、blend/attachment、2D/3D scene 和 lifecycle golden |
| image bones/physics | bone count/index/parent；world/local transform/angles/origin；impulse/reset | `L0` | Puppet assets 可发现，runtime/API 均无 | mesh/bone solver、local/world round-trip、physics fixed step 和 reset |
| image blend shapes | index、get/set weight | `L0` | `N` | shape identity、range、missing shape、per-frame deformation |
| `ICamera` | `fov`(3D) 和 `zoom`(2D) | `L0` | 静态 camera 与 JS handle 未连接 | 2D/3D 类型约束、projection update 和 invalid value 门 |
| `IModelData` | `applyData` 高频兼容更新；`replaceData` 只能事件驱动；POSITION/NORMAL/TANGENT_SIGNED/UV/COLOR 格式常量 | `L0` | `G` 确认两者共用 mode bridge，update phase 拒绝 replace；项目无动态 model buffer runtime | 自有 buffer schema/size/type/CCW；buffer 增长、非 dynamic、shape/buffer 增删、material/vertex format/index/layout 变化逐项负门；GPU budget |
| scene model-data lifecycle | `createModelData`, `destroyModelData`, `createLayer(model)` | `L0` | `G` 确认 tokenized handle 与仍被 layer 引用时延迟销毁；项目仍无实现，`N` | handle ownership、共享引用计数、最后 layer 后释放、重复 destroy/stale token 和坏 buffer 负向门 |

## 5. Globals 与 engine 状态

| Global/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `thisLayer` / `thisScene` | 当前 owner 和 scene 的 typed handles | `L0` | `D/N` | 见对象句柄门；不可跨 scene/屏幕泄漏 |
| `console` | `log(...any)`、`error(...any)` | `L0` | `N` | per-script tag、速率限制、值序列化、错误不递归 |
| `renderContext` | v2.8 声明 `IRenderContext` 为空 | `L0` | `N` | 保留空 host object；未来声明升级前不得自创成员 |
| `input` | 全局输入快照 | `L0` | renderer pointer 不等于 JS global | 同帧不可变 snapshot、多屏坐标和权限降级 |
| `localStorage` | screen/global 两个持久化域 | `L0` | `G` 确认默认 screen、仅精确字符串 `global` 切域，其他值回落 screen；项目无 bridge，`N` | wallpaper/scene/screen namespace、配额、原子写、跨屏/重启和迁移策略 |
| `engine` environment queries | editor、portrait/landscape、desktop/mobile、wallpaper/screensaver | `L0` | `N` | macOS 模式映射和稳定 fixture；不伪装未支持平台 |
| `engine.screenResolution` / `canvasSize` | 每屏物理分辨率与 2D canvas/full wallpaper 尺寸 | `L0` | frame context 有 viewport，但无 JS bridge | scale factor、跨屏 canvas、resize 顺序和 pixel/point 门 |
| `engine.userProperties` | 当前用户属性对象；color属性自动呈现为Vec3 | `L3 bounded contract-executable` | scalar与Vec3 callback都接收同一effective property map的深冻结typed snapshot；number/bool/string保留类型，project color string转为`{x,y,z}`。C/Swift门覆盖读取与不可变性；当前真实Vec3样本消费的是同源`scriptProperties`，未直接读取该global | 真实authored consumer、key normalization官方对照、首次/增量/多屏一致性、更多property kind |
| `engine.timeOfDay` | 24 小时归一化到 `[0,1]` | `L3 bounded / S4 real visible differential` | Swift 从同帧 wall date 按当前时区计算本地民用日秒并限制到 `[0,1]`，C bridge 以 callback-scoped immutable scalar 暴露。真实 `2134765860` 的 4 个 `multiply` 与 2 个 `alpha` owner 在本地 12:00 均输出 0、22:00 均输出 1，旧固定 AST owner 已删除 | 时区/DST、跨午夜长稳、同帧 Date 一致性、非scalar/其他target、官方数值/像素 golden 与独立 effect ROI parity |
| `engine.frametime` / `runtime` | 上帧秒数（重绘可为 0）和scene累计运行时间 | `L3 bounded contract-executable` | 同一 immutable callback snapshot 分别暴露 host `simulationFrameTime` 与 `sceneTime`；C harness真实读取二者并覆盖非法/负值输入和脚本改写失败。真实 time-of-day 样本建立同一 bridge，但其作者 source 不消费这两个字段 | 真实 authored consumer、raw/effective数值 parity、0 delta、pause/switch/seek、inverse4 与 Windows 同帧多屏 golden |
| `shared` | 同 scene 脚本共享的 global object | initializer/cohort proof `L3 bounded`; mutable object `L0` | launch-origin只静态证明唯一`shared=false` initializer以及master/follower读写结构，并把结果编译为scene/host typed state；没有JS global/object identity或运行时mutation，`N` | mutable shared object、跨脚本mutation、每scene/屏隔离、初始化顺序、销毁和并发规则 |

## 6. Input、Audio 与 Media

| API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `input.cursorWorldPosition` | 当前 cursor 世界坐标，当前主要 X/Y | `L0` | `G` 确认 global-phase 拒绝、scene cursor pixel snapshot 经当前 view/projection 逆变换为 Vec3，2D policy 可把 z 置 0；项目无 JS bridge，`N` | camera/viewport 数值、屏外、resize 与 event snapshot 同帧 golden |
| `input.cursorScreenPosition` | 屏幕像素坐标 | `L0` | `G` 确认 global-phase 拒绝、与 world getter 共用 snapshot并按 canvas/viewport scale 与 Y policy输出像素坐标；项目无 bridge，`N` | Retina、多屏 origin、屏外、resize 和坐标取整 fixture |
| `input.cursorLeftDown` | 左键当前状态 | API `L0`；native state `L2` | per-surface primary-button state已由AppKit down/up更新并供bounded click projection消费；没有JS getter/bridge | down/up/capture、失焦、VM getter与event snapshot同帧 |
| `CursorEvent.worldPosition/localPosition/hitBox?` | 事件时 world/local 坐标与 puppet hit box；声明明确 screenPosition/button 未使用 | `L0` | `G` 确认六个事件共用 native cursor record builder，world/local/hit-box 为 dispatch 前独立 snapshot，并从 layer hit-box/detail virtual 取得可选 detail；这不是公开 `cursorHitTest` hook；项目无 DTO bridge，`N` | event-local/parent/puppet 数值、detail identity、未使用字段不得伪造 |
| [audio resolution constants](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) | `AUDIO_RESOLUTION_16/32/64` | `L0` | renderer host 已有三档 typed snapshot，native plan 内部严格验证 64；没有 JS global/constant bridge | 只接受三个常量；错误分辨率 fail closed |
| [`engine.registerAudioBuffers(resolution)`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) | 必须在 script global context 注册，返回逐帧频谱 | `L0` | `G` 确认 global-phase 限制、仅 16/32/64、默认 16 和 engine teardown 注销；exact source compiler 仅声明 native demand，没有 VM/API bridge | global-only enforcement、错误 resolution、重复注册/取消订阅与 stop 生命周期 |
| [`AudioBuffers`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) | 同长度 `left`, `right`, `average` Float32Array，每帧自动更新；低频到高频，通常 0...1 但可大于 1 | `L0` | `G` 确认三档 left/right/average backing arrays identity 跨帧稳定，并在 timer 与普通 update 前原地刷新；项目 host 只有 left/right，仍无 JS object/订阅 | 平均值数值、无设备 policy、跨屏 consumer generation 与受控脚本输入 |
| `MediaStatusEvent` | `enabled` 表示媒体集成可用/启用 | `L0` | `N` | enable/disable、无 provider 和订阅生命周期 |
| `MediaPlaybackEvent` | state 0 stopped / 1 playing / 2 paused | API/live ingress `L0`；bounded consumer `L2-L3` | strict placeholder-fade已有author-initial stopped运行子集；inbox现有typed playback generation，但没有live producer或JS dispatch | 公开授权的macOS provider、重复/切换仲裁、pause/resume/switch与跨播放器事件 |
| `MediaPropertiesEvent` | title/artist/subTitle/albumTitle/albumArtist/genres/contentType | API `L0`；title/artist carrier `L2` | inbox与bounded text runtime已接title/artist generation；无live producer/DTO/dispatch/fresh ROI | 其余字段、缺字段、Unicode、原子曲目切换和stale generation |
| `MediaThumbnailEvent` | thumbnail presence 和 primary/secondary/tertiary/text/high-contrast colors | API `L0`；current texture `L3 bounded`；colors `L2` | current `$mediaThumbnail`有typed provider/visibility/last-ready；inbox和bounded color consumer已接artwork colors，但没有live producer、event DTO/dispatch或fresh color ROI | 图像+颜色同generation、live producer、event ordering/owner lifecycle与无封面语义；typed provider不等于SceneScript API |
| `MediaTimelineEvent` | position/duration 秒值，播放时频繁发送 | `L0` | `N` | rate/seek/unknown duration、节流与时间单调性 |

<a id="7-render--scene-property-api"></a>
## 7. Render / scene property API

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| scene bloom | `bloom`, `bloomstrength`, `bloomthreshold` | `L0` | 自有 Bloom 路径不是 JS setter；`D/N` | typed scene target、HDR/order、开关反例和像素门 |
| clear/background | `clearenabled`, `clearcolor` | `L0` | 静态 general 可解析，无 JS bridge | 同帧 clear state、alpha/color space 和 resize/switch |
| lighting colors | `ambientcolor`, `skylightcolor` | `L0` | 无 2D/3D lighting runtime | lighting IR/renderer 后再开放；无消费者时不得假支持 |
| projection | `fov`, `nearz`, `farz` | `L0` | 静态 camera 子集，无 JS bridge | projection validation、near/far 反例、2D/3D golden |
| camera fade | `camerafade` | `L0` | `N` | 定义行为、场景 fixture 和生命周期门 |
| camera shake | enable/speed/amplitude/roughness | `L0` | 静态 Scene `general` 已有 bounded orthographic consumer，但没有 JS bridge；这不升级 SceneScript API | same-frame typed scene target、作者关闭、静态/JS 冲突顺序、pause/seek 与 2D/3D 门 |
| camera parallax | enable/amount/delay/mouseInfluence | `L0` | 静态作者参数的 renderer 子集不是 JS API | JS 动态写、同帧 pointer、关闭反例、WE 幅度/delay golden |
| `CameraTransforms` | `eye`, `center`, `up`, `zoom` 的 scene camera DTO | `L0` | `G` 确认四成员 native DTO、base getter 与逐成员 partial setter；默认 `(eye 2,2,2 / center 0,0,0 / up 0,1,0 / zoom 1)`，无 authored camera 的正交 fallback 为 `(eye 0,0,0 / center 0,0,-1 / up 0,1,0)`；项目无 bridge，`N` | getter/setter round-trip、finite/type validation、authored/animation conflict 和 2D/3D 门 |
| material property/function | effect 的 `setMaterialProperty` 和 `executeMaterialFunction` | function request `L3 bounded / S4 downstream representative`；property `L0` | descriptor-bound `thisLayer.getEffect(name|index)` 现可产生 typed material-function request，scalar/Vec3 owner 共用 mutation bridge；既有`9000000800...0803`证明下游GraphExecutor正/反与局部回退，但早于新descriptor catalog，不是新name lookup的fresh运行正证 | `setMaterialProperty`、任意function body、更广target/side effect、同帧冲突顺序与官方parity仍缺 |

## 8. Storage 与 timers

| API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `LOCATION_SCREEN` / `LOCATION_GLOBAL` | 默认 screen 域；global 在同 wallpaper 实例间共享 | `L0` | `G` 确认默认 screen、仅精确字符串 `global` 切域，其他值回落 screen；项目无实现，`N` | wallpaper/scene/screen namespace、跨屏隔离和迁移策略 |
| `localStorage.set/get/delete/clear` | 保存、读取、删除键或清空指定域 | `L0` | `G` 确认四者拒绝 global phase、key 必须 string、undefined 转 delete、版本 envelope 与损坏返回 undefined；项目无实现，`N` | 可序列化值边界、配额、原子写、跨重启/多屏、delete/clear 失败与 stop 不误删 |
| `engine.setTimeout` | 毫秒延迟，一次性 callback；返回函数可提前取消 | `L0` | `G` 确认 owner record、effective-delta scheduler、轮前 snapshot、新建 timer 不同轮执行、按 identity 删除；完全暂停不累计，恢复不 catch-up；项目无实现，`N` | 最小延迟、scene seek、cancel 幂等、callback throw/self-cancel 与 stop residue |
| `engine.setInterval` | 毫秒周期 callback；返回函数用于停止 | `L0` | `G` 确认每帧最多一次、完整周期重置、不 catch-up/不保留 overshoot；完全暂停不累计，owner teardown 逐条释放；项目无实现，`N` | scene seek、自取消/交叉取消、callback 预算和长帧/恢复 fixture |
| `clearTimeout` | v2.8 声明明确“未实现”，应调用返回的 cancel function | `L0` | `G` 发现内部同名兼容 binding，但公开声明仍是唯一公共合同 | 不公开该入口；兼容 fixture 锁定返回函数取消 |

## 9. Math、颜色与 ECMAScript 基础

| API | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `WEMath` | `smoothStep`, `mix`, `deg2rad`, `rad2deg` | module `smoothStep` `L3 bounded`；其余成员 `L0` | QuickJS module loader 只 allowlist `WEMath`，真实 import/export 执行三参数 `smoothStep`；非有限值与相等边界 typed exception，unknown module 在 owner create 阶段关闭。真实 `2134765860` 六个 time-of-day consumer完成日/夜差分 | `mix`/角度换算、完整 module graph、官方 NaN/Inf/相等边界结果、其他 target 与 Windows 数值 parity |
| `WEVector` | `angleVector2`, `vectorAngle2`，角度单位为 degree | `L0` | `N` | 象限、零向量、round-trip 和 epsilon 门 |
| `WEColor` | `rgb2hsv`, `hsv2rgb`, `normalizeColor`, `expandColor` | `L0` | `N` | hue wrap、灰色、越界、round-trip 和颜色空间门 |
| ECMAScript `Math` | SceneScript 可用的标准数学函数 | `L0` | 无 VM；`N` | 明确支持版本、deterministic random/seed 策略和数值兼容测试 |
| ECMAScript `Date` | 时钟/日期脚本读取 wall time | `L3 bounded` for text subset | `D/F` 把 `new Date()` 与 `getFullYear/getMonth/getDate/getDay/getHours/getMinutes/getSeconds` 映射到同帧 Gregorian wall date；自有固定时区 fixture 与 213/280 真实时钟门 | Date constructor args/其他方法、locale/UTC、DST、离线 clock adapter、通用 VM 与 Windows parity |

## 10. Value types

### 10.1 Property value 与事件 DTO

| 类型/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| property input union | `Number | Boolean | String | Vec2 | Vec3 | Vec4 | Mat3 | Mat4` | Number与object-origin/scale Vec3 `L3 bounded`；其余`L0` | C/Swift门锁定finite input、boxing、immutable snapshots与owner generation；真实`2802243144`执行两个Vec3 input | bool/string binding、Vec2/Vec4/matrix与完整schema |
| property return union | v2.8 声明返回 `Number | Boolean | String | Vec2 | Vec3 | Vec4`，没有 Mat3/Mat4 | Number与object-origin/scale Vec3 `L3 bounded`；其余`L0` | Vec3支持对象return、mutation和finite scalar splat；错型/非有限值只禁用该owner且不发布 | bool/string/Vec2/Vec4、完整coercion与官方返回语义对照 |
| `AnimationEvent` | `name`, `frame` | `L0` | `N` | Timeline/puppet source、crossing 和 frame 数值测试 |
| media/cursor DTO | 本文 Input/Media 表列出的 typed event object | `L0` | cursor record/event slot 有 `G` 静态证据，media DTO 仍为 `N`；项目均无 VM object | immutable event object、cursor 坐标/detail、media generation 和 owner isolation |

### 10.2 Vectors

| 类型 | 官方成员 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `Vec2` | `x/y`；构造 number/Vec3/string；length/distance、normalize/copy/equals/isFinite、negate、add/subtract/multiply/divide、dot/reflect/perpendicular/project、angle/angleBetween/rotate、mix/min/max/clamp、abs/sign/round/floor/ceil/fract/mod/step/smoothStep、`toString` | `L0` | `N` | 全方法 golden；mutation/return 语义、字符串格式、零长度和除零门 |
| `Vec3` | `x/y/z`；构造 number/Vec2/string；`fromSpherical/toSpherical`；Vec2 同族方法，另有 cross/refract；角度为 degree | `L3 bounded constructor/basic mutation` | QuickJS bootstrap提供finite构造、`x/y/z`、`copy/add/multiply/isFinite`；真实object-origin脚本执行builder初始化与字段mutation。未实现成员不冒充完整Vec3 | 其余构造重载与方法、球坐标、cross/refract、epsilon、字符串round-trip及官方golden |
| `Vec4` | `x/y/z/w`；构造 number/Vec2/Vec3/Vec4/string；通用 length/distance/arithmetic/dot/reflect/project/mix/rounding/step 方法 | `L0` | `N` | 全方法与 edge-case golden；构造扩展规则和 toString |

### 10.3 Matrices

| 类型 | 官方成员 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `Mat3` | identity、translation/scale/rotation/basis/fromMat4/compose；translation getter/setter、angle、add/subtract/multiply、translate/rotate/scale、transform point/direction、transpose/determinant/inverse/decompose/copy/equals/toString | `L0` | `N` | 列/行主序、乘法方向、degree、奇异逆矩阵、decompose 和 round-trip golden |
| `Mat4` | identity、translation/scale/axis rotation/Euler/basis/lookAt/compose；translation、right/up/forward、add/subtract/multiply、translate/rotate/scale、point/direction、transpose/inverse/determinant/extractEuler/normalMatrix/decompose/copy/equals/toString | `L0` | `N` | 坐标系/手性、T*R*S、Euler 顺序、奇异矩阵、normal matrix 和 WE golden |

## 11. Asset handles 与动态资源

| API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `engine.registerAsset(file, precache)` | 必须在脚本 global/root 执行；注册动态 layer 所需资产并确保发布包含；可预缓存 | `L0` | `G` 确认 global-only、按传入路径去重且首次 precache 选择 sticky；项目 `P` 只索引现有资源，无 script registry | 规范化/大小写、越界拒绝、precache 时点/预算、缺失/循环依赖和 owner teardown |
| `IAssetHandle` | `registerAsset` 返回并可传给 `createLayer` 的 opaque handle | `L0` | `G` 显示 VM 边界可携带路径值，但 v2.8 未声明成员；项目无 handle，`N` | 公共层保持 opaque identity/lifetime，不把内部路径表示扩张为可访问成员 |
| `thisScene.createLayer(asset)` | 由 path/config/asset handle/model data 创建动态 layer | `L0` | `G` 确认同步 host create/init、立即取得 native identity 并复用 wrapper、2048 bridge identity cap；update callback 新 owner可同轮 update，destroy callback 新 owner可能同帧 render/下帧 update；项目仍无动态 layer，`N` | asset ownership、初始化配置、有界 mutation、排序、publisher/resource dependency、预算和 teardown |
| texture/video animation handles | 从 image layer albedo 获取 animation/video handle | `L0` | `G` 已闭合 video 的 provider-missing、play/pause/stop、seek/loop ended edge 与 owner callback cleanup；现有纹理/视频 renderer仍不暴露 JS handle，`N` | wrapper identity、provider generation、rate/error、asset unload 后失效和 callback 重入 |
| custom model asset/material | model shape 的 `material` 使用已注册 `IAssetHandle`；model data 可共享 | `L0` | 无 model runtime；`N` | material precache、buffer/handle compatibility、共享引用计数和资源预算 |
| user shortcut | `engine.openUserShortcut(userPropertyName)` 打开已注册 shortcut | `L0` | 属性 UI 有类型占位，无脚本 API | macOS 产品授权/安全降级、未知 property、用户取消和非交互环境门 |

## 12. 官方声明自身的边界

这些不是播放器可以自行猜补的 API：

1. v2.8 引用了 `IAssetHandle`，但类型文件没有声明其成员；当前只可按 opaque handle 设计。
2. `ILayer` 继承 `IModel`，但 v2.8 文件未给出 `IModel` interface；不能凭第三方实现创造公共成员。
3. 页面目录列出 `IThisPropertyObject`，类型文件只出现空的 `IThisPropertyObjectBase`；property owner 的具体 union 应由绑定 IR 决定。
4. `IRenderContext` 在 v2.8 是空 interface；未来版本更新前只提供空对象。
5. `animationEvent` 在 Timeline 官方文档存在，但未列入 v2.8 `IComponent`；需要兼容 fixture，而不是抹掉其中一侧。
6. `CursorEvent.screenPosition`、`button` 和 `ITextureAnimation.loop` 在声明中被注释为未使用；当前实现不得把它们计入支持率。
7. `clearTimeout` 被明确标为未实现；取消 timeout/interval 使用注册函数返回的 cancel function。

## 13. 实施依赖与完成门

V2使用QuickJS-NG，但不先建设完整API平台。第一条可见纵向切片按以下顺序闭合，后续API复用同一owner和transaction：

1. **Source/owner**：复用现有inline IR，补最小module loader与稳定owner identity；不为已知source增加Swift profile。
2. **受控VM**：per-scene runtime/context、严格global allowlist、interrupt/heap/stack budget、exception与日志隔离。
3. **一个property闭环**：`init/update` typed return或mutation进入现有per-surface transaction，下一帧由真实consumer可见；失败只终止该script owner。
4. **生命周期**：destroy/reload/pause/teardown与stale handle，switch/stop后VM/timer/handle为0。
5. **基础handles与事件**：thisLayer/thisScene、time/user property，再按真实样本接cursor、audio、media；host先捕获共享输入，surface再加入viewport/pointer/matrix/provider。
6. **广度API**：effect/material、particle、animation/video、storage/timers、dynamic layer/asset；Puppet/model/physics只在对应consumer存在后开放。

SceneScript core 至少满足以下门后，相关行才可从 `L0` 升级：

- source 与 binding round-trip，不丢源码、owner、target、value type；
- 两屏实例隔离，同一 host frame 读取相同 timing，但不同 resolution/pointer 产生各自不可变 snapshot 和 generation；
- `init/update/destroy` 次数和顺序固定，switch/stop 后 VM、timer、handle、provider 为 0；
- typed return、无返回、错类型、NaN/Inf、throw、死循环均有正反测试，单脚本失败不影响 renderer；
- 用户属性、cursor、audio、media 事件使用 generation/order 合同，旧事件和旧资源不得覆盖新状态；
- 默认关闭的 effect/parallax/particle 仍保持关闭，脚本只修改作者明确绑定或显式访问的目标；
- 至少用通用 VM 执行的动态时钟文字、用户属性文字、cursor 局部坐标、受控音频 bins、media metadata 各一组隔离 fixture 验证；bounded Text AST 不替代此门，sealed fixed native clock/date profile 只能作历史；
- `L3` 还要求签名 App 真实运行、相关隔离样本正反例与 stop 生命周期；`L4` 需要相同输入下的 Windows Wallpaper Engine golden。

## 14. 更新规则

1. 新增 SceneScript 代码时先更新对应行的单值等级、代码/测试证据和明确边界；不能用 “VM 能运行 Hello World” 批量升级 API。
2. 一个 handle 的 getter、setter、method 和 lifecycle 可分别处于不同实现阶段；表格拆行不足时必须在“当前证据”里写清已执行成员。
3. 普通 renderer 已有同名能力不等于脚本 API 可用；只有真实 JS -> host -> dynamic snapshot -> consumer 链闭环才可记 `L3`。
4. 官方声明版本变化时，先比较 API diff，再更新本表；声明未定义/注释未使用的成员继续保持 unknown 或 unsupported。
5. 固定样本运行通过只证明没有崩溃和门内指标，不证明其中 SceneScript 已执行。
