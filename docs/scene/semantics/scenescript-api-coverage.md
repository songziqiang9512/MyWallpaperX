# SceneScript API 覆盖表（官方声明 v2.8）

> 核验日期：2026-08-15
>
> 官方基线：`lib.sceneScript.d.ts` **VERSION 2.8**，固定文档 revision `b26412295cbfd0ee5cdceff67e2c95069527aa1b`。
>
> 资料入口：[资料来源与证据索引](source-index.md)、[官方页面全目录](official-page-catalog.md)、[运行时系统语义](runtime-systems-reference.md)、[总覆盖台账](coverage-ledger.md)。固定客户端深层观察只在独立研究任务中查[2.8.42 SceneScript 静态取证](scenescript-runtime-implementation-contract.md)，implementation agent 不直接读取该页。
>
> Scene 实现身份、运行证据与聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)；本表不复制基线 commit，文内旧 commit/批次号只用于追溯，不定义现役顺序。

## 1. 当前结论与评级口径

当前结论只有一条：项目已用同一QuickJS-NG scene domain执行scalar（含bounded object layer alpha）、Boolean object layer visibility、String、object Vec3与pass-owned typed Vec2/Vec3 owner，并开放bounded `WEMath`、`WEColor.hsv2rgb`、callback-scoped immutable engine/user-property/single-surface pointer与canvas snapshot、typed handles、16/32/64 AudioBuffers、events、timer/job及exact-once teardown；thumbnail event现同时携带presence与primary/secondary/tertiary/text/high-contrast五个冻结Vec3，旧native media-color owner已删除。共享domain现对每owner inline source实施256 KiB硬上限、对candidate实施2 MiB聚合上限、对fresh candidate owner work实施4096硬上限，在QuickJS interrupt内轮询construction cancellation，并以不可配置、无setter的host accessor与私有slot隔离`engine`及`thisLayer/thisScene/thisObject`三个callback handle，作者global污染不能误伤后续owner；同一domain的不可变user-property JSON按精确字节复用，输入变化成功解析/冻结后才原子刷新。它们进入现有property transaction、resource publication和唯一Metal compositor，但**没有完整SceneScript API/host runtime**。普通Boolean value-only owner只接受真正Bool输入/返回；新增的单一dependency-bearing image cohort仅额外开放只读`thisScene` layer查询、owner自身visibility setter与现役video provider的`getVideoTexture()` handle，不开放`thisLayer/thisObject/shared`、跨target mutation、timer/audio或动态构造。pass Vec2当前复用Vec3 host object完成作者现有`multiply`脚本，published value仍是Vec2，这不等于官方Vec2 class/API已实现。Program门证明scalar/String/vector/Boolean update或media callback失败后target在本owner generation内进入disabledTargets，失败帧及所有后继frame都不发布SceneScript高优先级值，也不提交同callback staged video command；resolver每帧重新跟随authored/user/Timeline current，video命令只原子进入现役provider registry。`shared`仍按作者合同可变，通用domain即时JS state rollback仍未闭合。

| 能力面 | 当前结果 | 精确边界 |
|---|---|---|
| Generic ECMAScript VM/API | `L3 bounded scalar+Bool+String+object alpha/visibility/Vec3+pass Vec2/Vec3+typed snapshots/handles/events/lifecycle` | QuickJS-NG开放inline scalar、严格value-only Bool、object alpha/String/Vec3及exact pass Vec2/Vec3 `init/update`，共用WEMath、bounded WEColor、immutable input、typed handles、AudioBuffers、events、timer/job和exact-once teardown。普通Bool owner不共享side-effect capability；单一dependency-bearing Bool cohort只增加只读scene lookup、own visibility与video handle/command。pass Vec2只复用现有Vec3 host object的x/y/basic multiply，不宣称官方Vec2 class。captured-primary move出旧quad后继续按当前投影派发；仍无file module graph、Vec4/matrix、完整Vec2 API、多按钮、失焦、async module或完整multi-surface lifecycle |
| Binding/source evidence | `L1 / S1 preserved` | inline source、scene/object/effect/pass owner、完整 target path、properties、authored fallback、JSON value type 与可选 wrapper keys 可保真；source evidence 只用于 provenance/conflict rejection，不能取得执行权 |
| Bounded Text `update(value)` AST | `L3 bounded / S3 executed` | 不按 sample/layer/source hash 准入；只执行受控无循环 AST、Date getter 与 string/value 子集。现役 compiler/runtime 和自动门存在，但 fixed profile 撤权后没有刷新绑定当前产品身份的可见证据，因此本页不把它写成现役 `S4` |
| `WEMath` + `engine.timeOfDay` scalar | `L3 bounded / exact consumers S4 visible` | 原 `SceneTimeOfDayEffectScript*` Swift AST/compiler/runtime 产品族已删除。普通 binding IR 接纳 `script + user:null`，同一 generic VM 在真实 `2134765860` 建立 11 个 scalar owner，其中 6 个 `WEMath.smoothStep + engine.timeOfDay` target 在本地 12:00 输出 0、22:00 输出 1；route=`generic-only`，失败只保留该 target 的 previous-current。非 null `user + script` 仍冲突关闭 |
| Retired bounded media fade / launch-origin projection | `L0 product owner / historical` | playback placeholder fade与launch-origin的专用compiler/program/runtime均已由generic QuickJS owner取代并删除；历史可见证据只作迁移前oracle，不证明现役owner或完整media/cursor API。后继generic click真实切片仍可因本批外graph缺口保持NON-PASS |
| Generic Vec3 property owner | `L3 bounded / S4 bounded visible` | object `origin/scale/angles` 的loss-preserving binding由同一QuickJS domain执行；真实`2067939514`的3个angles owner发布非零z角度，真实新增`3509243656`的8个angles owner也进入统一frame snapshot。route=`generic-only`、failure=`previous-current`；前者只证明整幅非黑构图中的真实非零consumer，后者整景仍黑且只算执行证据，不外推独立rotation ROI、全部Vec3 target或完整Vec3 API |
| Generic object scalar alpha owner | `L3 bounded / S3 real owner-executed` | 非既有shared-alpha incumbent的exact `script/value`与primitive `script/scriptproperties/value`由同一QuickJS scalar owner执行；完整path/descriptor/bit definition守恒，成功target解除display suppression，失败保留current。真实`3509243656`有60个completion但整景黑，`2902406982`有8个且整幅非黑，`3768724269`的缺`getParent`与跨属性visible mutation各自局部失败。只证明bounded owner执行与whole-composition safety，不证明alpha ROI、shared初始化/global order、跨属性/跨owner visible mutation、旧shared-alpha owner迁移、完整API或parity |
| Generic object Boolean visibility owner | `L3 bounded / S4 one dependency-video interaction` | exact `objects[index].visible`、Bool authored definition与ordinary root image/solid leaf进入同一QuickJS value-only owner；effect-bearing leaf可准入。一个额外bounded cohort允许单一external-primary image dependency，且只开放只读`thisScene`、owner自身visibility与scene video handle。真正Bool返回进入同一snapshot，`undefined`保留输入，bad return只熔断本owner并撤销staged video command。真实`2959875782`有17/17首帧completion；真实`3775355045/3775373546`执行video命令，前者pointer移入时显示hidden X-Ray video、移出恢复。普通owner仍不开放`shared`/handle/timer/audio/event/destroy；dependency cohort不开放`thisLayer/thisObject`、跨target mutation或动态代码。前者不证明目标像素，后者不证明完整display/IVideoTexture、全部X-Ray、整corpus或parity；见[E-V4-SCENESCRIPT-LAYER-VISIBILITY-BOOLEAN](runtime-evidence-index.md#e-v4-scenescript-layer-visibility-boolean)与[E-V4-SCENESCRIPT-VIDEO-XRAY](runtime-evidence-index.md#e-v4-scenescript-video-xray) |
| Pass-owned typed Vec2 value owner | `L3 bounded / S3 real consumer-executed` | finite two-component fallback、source、wrapper/provider provenance与完整object/effect/pass/constant identity守恒时，同一QuickJS owner以现有Vec3 host ABI执行，输出只发布x/y到typed Vec2 target。真实`2067939514`的25个audio scale owner全部完成，7个active Transform进入普通Program；provider冲突/额外wrapper局部拒绝 | 官方Vec2 constructor/class及完整method family仍未实现；其余pass vector shape、mixed provider、multi-surface、独立Transform ROI与官方parity未证明 |
| Pass-owned typed Vec3 + `WEColor.hsv2rgb` owner | `L3 bounded / S3 real consumer-executed` | finite triple、source、wrapper/provider provenance与完整object/effect/pass/constant identity守恒时，同一QuickJS Vec3 owner执行；allowlisted `WEColor.hsv2rgb`接收finite normalized HSV Vec3、hue按周期包裹并返回typed Vec3。真实`2884628849`的隔离author-property门形成4个completion，active Tint进入普通Program/GPU/publication/compositor/next-frame | 整样本因无关layer passthrough严格NON-PASS；属性门主动启用作者automatic Tint，黄→绿全景变化不是默认画面或眼部ROI正确性。`rgb2hsv/normalizeColor/expandColor`、官方数值parity、其他pass Vec3 shape与multi-surface仍缺 |
| `311115e3` 其余 bounded native projections | shared-alpha incumbent `L2 bounded`；identity display `L2 / S2 wired`；media-color native owner `L0 product owner / historical` | native hover、primary-button click、launch-origin、audio-scaled value与media colors已分别被generic cursor/vector/AudioBuffers/`MediaThumbnailEvent` owner取代并删除。bounded shared-alpha incumbent仍持有其精确subset；非incumbent object alpha现由generic scalar owner执行，但不据此外推shared初始化或撤权完成。identity display仍只有有界产品接线；五色generic API的精确边界见本页Media表、[E-V4-SCENESCRIPT-LAYER-ALPHA-PROPERTY](runtime-evidence-index.md#e-v4-scenescript-layer-alpha-property)与[E-V4-MEDIA-COLOR-OWNER-PARTITION](runtime-evidence-index.md#e-v4-media-color-owner-partition) |

表中的 `S4` 只引用运行证据索引登记的精确 App/fixture/ROI 身份。现役 `engine.timeOfDay` 证据来自一个原始只读真实样本的日/夜差分与 6 个 typed consumer；严格样本报告仍因 31 项其他陈旧/宽域期待为 NON-PASS，不把该切片扩张成 whole-scene、family 或 parity 结论。

上述 bounded 子集的执行 identity 来自作者结构和 typed target，不以完整样本/source identity 选择视觉答案。精确证据分别见 [E-TEXT-SCRIPT](runtime-evidence-index.md#e-text-script)、[E-EFFECT-BLEND-TRANSFORM](runtime-evidence-index.md#e-effect-blend-transform)、[E-V2-SCENESCRIPT-MEDIA-PLAYBACK-EVENT](runtime-evidence-index.md#e-v2-scenescript-media-playback-event)、[E-V2-SCENESCRIPT-MEDIA-PROPERTIES-EVENT](runtime-evidence-index.md#e-v2-scenescript-media-properties-event)、[E-V2-SCENESCRIPT-AUDIO-BUFFERS](runtime-evidence-index.md#e-v2-scenescript-audio-buffers)、[E-V2-SCENESCRIPT-CURSOR-ENTER-LEAVE](runtime-evidence-index.md#e-v2-scenescript-cursor-enter-leave)、[E-V2-SCENESCRIPT-CURSOR-CLICK-LAUNCH-OWNER-RETIREMENT](runtime-evidence-index.md#e-v2-scenescript-cursor-click-launch-owner-retirement)、[E-V2-SCENESCRIPT-OWNER-TIMERS](runtime-evidence-index.md#e-v2-scenescript-owner-timers)、[E-V2-SCENESCRIPT-PROMISE-JOBS](runtime-evidence-index.md#e-v2-scenescript-promise-jobs)、[E-V2-SCENESCRIPT-DYNAMIC-TEXT-LAYER](runtime-evidence-index.md#e-v2-scenescript-dynamic-text-layer)和[E-V2-SCENESCRIPT-OWNER-TEARDOWN](runtime-evidence-index.md#e-v2-scenescript-owner-teardown)。

所有按 raw source/profile 选择的 fixed Text/date/greeting、TextureAnimation 与 native Audio Bars owner 都是 **sealed historical**：现役产品不再授予它们执行权，旧 commit、批次、报告、截图和 64-draw 只能追溯已退役实现，不能定义当前输出或下一步。普通 TEX/multi-image autoplay、host 16/32/64 频谱和 Effect Audio Bars 是独立非 SceneScript 能力，不能替下表 API 升级。

`3768229922` 仍没有恢复其head-click/shared/display纵向链：虽然generic `cursorClick` callback已存在，但display scripts `397/202/354`仍只有 provenance 与安全抑制；hidden controller/update、该owner的mutable shared toggle、alpha/display mutation、开场 fade/destroy，以及人物头部点击切换16层文字/红框遮罩均未执行。一个不同作者object的generic click可见结果不证明这条链，见 [E-AUTHORED-STRAIGHT-RGB-SCALAR-ALPHA](runtime-evidence-index.md#e-authored-straight-rgb-scalar-alpha)。

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
| `D` | [`SceneDynamicSnapshot.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift)、[`SceneTextScriptSubsetCompiler.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextScriptSubsetCompiler.swift)、[`SceneQuickJS.c`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJS.c)、[`SceneQuickJSLayerHost.c`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJSLayerHost.c)、[`SceneQuickJSJobHost.c`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJSJobHost.c)、[`SceneQuickJSMediaEventHost.c`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJSMediaEventHost.c)、[`SceneQuickJSHandleHost.c`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJSHandleHost.c)、[`SceneQuickJSTimerHost.c`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneQuickJSTimerHost.c)、[`SceneScriptOwnerLifecycleBridge.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptOwnerLifecycleBridge.swift)、[`SceneScriptDynamicLayerRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptDynamicLayerRuntime.swift)、[`SceneScriptLayerHandleBridge.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptLayerHandleBridge.swift)、[`SceneScriptMediaEventBridge.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptMediaEventBridge.swift)、[`SceneScriptScalarRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptScalarRuntime.swift)、[`SceneScriptStringRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptStringRuntime.swift)、[`SceneScriptVectorRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript/SceneScriptVectorRuntime.swift)、[`test_scene_script_quickjs.py`](../../../script/tests/test_scene_script_quickjs.py) | typed target、固定优先级、bounded text，以及真实ECMAScript scalar/strict value-only Bool/String/Vec3 owner、allowlisted `WEMath`、immutable frame/user-property input、callback-scoped descriptor layer/effect/dynamic-text handles、typed event、owner-isolated timer、bounded Promise job drain与exact-once owner teardown/quiescence；旧time-of-day/property-vector/fade Swift产品族已删除 | Vec4/matrix、完整Vec2 class、其他module/API handle、async module、asset/model/image dynamic layer、multi-surface lifecycle与官方parity |
| `F` | [`SceneFrameContext.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift)、[`SceneTextScriptRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextScriptRuntime.swift)、[`SceneDesktopWallpaperHost+FrameDriver.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift) | 同帧 wall date、simulation frame time 与 scene runtime 在 surface loop 外形成一次 typed frame snapshot；QuickJS callback只读该快照，timer按同一frame time至多推进一次，成功值再广播进各surface transaction | live provider、locale/DST/通用离线 clock、真实多屏输入一致性与pause/seek产品门 |
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
| `destroy()` | owner 销毁前调用 | 无返回值，用于清理 | `L3 bounded` |

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
| `init(value)` / `update(value)` 的 typed value | 入参是绑定property当前值；返回兼容值写回；无返回则保持原值 | QuickJS pass scalar、pass Vec2、object String/Vec3为`L3 bounded` | pass scalar接受完整identity/provenance守恒的primitive或exact `{user,value}` `scriptProperties`；动态值每帧从共享effective property snapshot解析。真实`3396722575`的Scroll scalar随live slider由`-0.2`更新为`-0.35`，真实293的Water Waves strength随audio generation发布并被普通Program消费。pass Vec2从同一preliminary snapshot取得pair，以Vec3 host object执行后仅发布x/y；真实206的25项均随audio generation改变。callback异常/错型保留owner-entry current | generic bool/Vec4/matrix、官方Vec2 class与完整coercion/API、color/Vec nested property、更多target及官方行为对照 |
| 直接赋值其他 property | 脚本可通过 `thisLayer`/其他 handle 同时修改多个 property | authored `thisLayer.origin/scale/angles` `L3 bounded / S4 stock consumer visible`；其余`L0` | active owner的authored transform setter写入字段掩码明确的owner-local mutation，不直接修改共享layer record；Swift在frame末尾对identity/type/finite/重复target整批校验，成功值下一帧只经现有`SceneDynamicSnapshot`生效。exception或冲突不提交，非transform static setter继续拒绝 | 其他handle/字段、同帧跨owner作者顺序、visible/text等各自consumer invalidation、static sort与官方行为对照 |
| source/module loader | 加载 inline 或 `.js` 源码及其 export/import | `L3 inline + WEMath bounded` | `I` binding IR保存已准入wrapper的inline source；QuickJS 执行 inline module，并只允许 import 项目自有 `WEMath.smoothStep/mix`。inline source按UTF-8精确计费，单owner上限256 KiB、candidate聚合上限2 MiB，C入口在分配前独立复核。unknown import 在 owner create 阶段 typed fail-closed，不暴露文件系统或 native module | `.js` file graph、规范化路径、其他 allowlisted module、依赖图、循环/缺失/越界负向门 |
| ECMAScript VM | 受控 ECMAScript 环境，无 DOM/Web/Node/shell/任意文件系统 | `L3 bounded scalar+String+object Vec3+pass Vec2/Vec3` | 每scene一个runtime/context，所有binding共用generation-checked owner；真实`2067939514`的25个pass Vec2与`2938612768`的pass scalar都消费同一AudioBuffers snapshot，真实`2884628849`执行pass Vec3/WEColor。callback input仍是深冻结typed snapshot，无DOM/Node/filesystem/network/process | bool、Vec4/matrix、官方Vec2 class、其他module/handle、更多consumer与官方对照 |
| budget/error boundary | 每实例/每帧时间、指令、内存和 timer 有界；脚本错误不终止 renderer | `L1 bounded scalar / S4 bounded visible` | QuickJS domain设置 heap/stack/interrupt budget；单owner source 256 KiB、candidate聚合source 2 MiB与construction work 4096均在建域前检查，C入口再守住单source分配。QuickJS interrupt在instruction budget前轮询construction cancellation并把原始Swift取消错误传回；timer另有每owner 32槽与0…86400000 ms范围，单callback job上限64。contract harness覆盖 compile/callback/timer/job exception、disabled fuse、bad return、infinite loop interrupt、timer/job overflow、stale owner、owner isolation、source边界、解释器内取消与host-global污染；App 负 fixture记录`exception / previous-current`，后续graph/compositor/next-frame仍成功；本地budget不冒充官方watchdog parity | OOM/recursion、每帧跨callback聚合job/timer量、wall-time watchdog、diagnostic aggregation、更多renderer/App failure injection |
| Promise/job drain | callback产生的microtask必须在同一owner host和预算内排空；残留不得交给下一owner | `L3 bounded / S3 executed` | 每callback最多执行64个pending job；handled rejection可继续，unhandled rejection、job exception、context mismatch与预算超限熔断当前owner并清空scene context队列。timer resolve的Promise在同一timer callback host内排空；module顶层job/top-level await保持拒绝；stop/switch teardown实测清零destroy callback新建job | 当前真实corpus无Promise/async/await/queueMicrotask调用，未取得App可见consumer；async module、跨帧外部Promise source、每帧聚合预算和官方动态对照仍缺 |
| instance ownership | 每个scene execution domain及其中的binding owner隔离；switch/stop必须销毁 | `L3 bounded / S4 lifecycle continuity` | 一个scene domain持有单一QuickJS runtime/context，多个bindings使用owner handles；stop/switch逐owner执行exact-once `destroy()`，随后丢弃timer/job/mutation/dynamic layer、递增generation并禁用旧owner。Developer ID App的stop→relaunch与同输入switch均记录`owners=1 destroyCallbacks=1 quiescent=1 failures=0`，旧generation contract门保持stale，当前证据仍只有单surface | pause/resume、provider residue、失败的新scene activate原子回滚、真实多surface下输入/final snapshot/consumer/event/teardown一致性与官方生命周期对照；不据此要求第二套per-surface VM |

## 3. 生命周期与事件

| 事件/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `init(value)` | owner 创建后调用一次，返回绑定 property 初值 | `L1 bounded scalar / S3 executed` | QuickJS-NG contract 与当前 App 正例执行 `init`，随后在同一 owner 上调用 `update`；不推导完整事件顺序 | 每实例恰好一次的独立计数、更多类型、异常降级、callback mutation 与 budget |
| `update(value)` | 每个渲染帧调用；动画应乘 `engine.frametime` | `L3 bounded scalar+String+object Vec3+pass Vec2/Vec3` | generic callback从preliminary current取值；typed finite成功值只进入当帧SceneScript publication，callback/update失败及disabled后继帧不发布高优先级值，resolver保留并继续跟随每帧authored/user/Timeline current，disjoint peer仍提交。真实206的25个pass Vec2随audio generation产生非unit输出 | bool/Vec4/matrix、官方Vec2 API、raw/effective delta parity、通用layer/domain JS state rollback与更广mutation |
| `destroy()` | owner 销毁前调用 | `L3 bounded / S4 lifecycle continuity` | stop/switch在撤销owner前以callback-scoped handles与immutable engine调用zero-arg export恰好一次；callback即使新建dynamic text、interval与Promise job，返回或抛异常后仍清空jobs/timers/mutations/layers并禁用旧generation。C门覆盖幂等、stale、异常与peer存活，Developer ID App两条生命周期运行均记录exact-one/quiescent | 动态删单owner时的destroy、destroy与普通update同轮顺序、跨handle重入、失败的新scene activate回滚、multi-surface和官方行为对照 |
| `resizeScreen(size)` | 分辨率变化时调用；首次创建不会自动调用 | `L0` | `N` | resize 正例和 startup 反例；每屏 size、去重和事件顺序 |
| `applyUserProperties(changed)` | 首次加载调用，之后只含变化键；使用 `hasOwnProperty` | Vec3 owner `L3 bounded / S4 visible`；scalar dispatch `L2 contract-executable` | QuickJS在scalar/Vec3 owner首轮准备全部typed properties，以后只准备值变化或删除为null的键；无变化不派发。Vec3真实`2974757317`的10个origin owner实际消费callback并产生可见卡片位移。scalar已有同一dispatch/delta/异常隔离实现与自动正反门；真实`3396722575`证明nested input更新后scalar `update`输出`-0.35`，但该作者脚本没有导出`applyUserProperties`，故不把它记作真实scalar callback消费 | scalar真实导出callback consumer、String/其他owner、跨类型批量顺序、reload/多scene、callback mutation冲突和官方行为对照 |
| `applyGeneralSettings(changed)` | 首次及 app general setting 改变时调用，v2.8 当前主要是 language | `L0` | `N` | typed settings snapshot；初次/增量、未知键和多屏一致性 |
| `cursorEnter` / `cursorLeave` | 指针进入/离开对象边界 | generic `L3 bounded / S4 visible` | AppKit pointer经实际camera/world/model inverse与quad hit-test，对作者object owner派发immutable world/local Vec3 event；同一scene domain共享mutable `shared` carrier。真实`2974757317`记录exact 1 enter + 1 leave、0 VM failure并可见移动；旧native hover owner已删除 | parent/rotated/puppet、候选与跨layer顺序、边界抖动、hidden/visible mutation、多surface和官方坐标/事件对照 |
| `cursorMove` | 指针移动时传 `CursorEvent` | generic `L3 bounded single-surface captured-primary / S4 isolated-visible` | surface ordered sample的位置真实变化时，未捕获owner只收current hit；down捕获后即使离开旧quad也按当前world/local projection继续派发。同owner同batch按序读取staged authored transform并只提交最终合并值，后续callback失败撤回该owner此前输出。真实`3122339805:207`以`captureActive=1/currentHit=0/localX=-0.860673`把`thisLayer.origin`更新为`(1083.710815,800,0)`；13-layer派生fixture继续证明可见位移稳定。[E-V4-SCENESCRIPT-CURSOR-MOVE-DRAG](runtime-evidence-index.md#e-v4-scenescript-cursor-move-drag) | multi-surface、多按钮、失焦、跨owner传播、parent/puppet/perspective、任意JS/C副作用回滚及官方坐标/顺序仍缺 |
| `cursorDown` / `cursorUp` / `cursorClick` | 对象上按下、释放和同对象完整点击 | generic `L3 bounded single-surface / S4 click-visible` | AppKit local/global primary event进入surface-local有界ordered batch，每个sample以同一current camera/world/model inverse命中作者object；down捕获owner，release向capture派发up，同一object仍命中才派发click。真实`2974757317`在同一main callback内记录press/release并exact一次`cursorClick`；真实`3122339805`证明captured move出旧quad后仍执行；512-event overflow整批拒绝并清capture，旧native owner已删除。[E-V4-SCENESCRIPT-CURSOR-MOVE-DRAG](runtime-evidence-index.md#e-v4-scenescript-cursor-move-drag) | multi-surface仍按frame snapshot；release-outside真实consumer、多按钮、失焦、候选传播/parent mutation、puppet hitBox与官方顺序/坐标对照仍缺 |
| 五个 media events | status/playback/properties/thumbnail/timeline 变化事件 | thumbnail presence+五色/playback/properties `L3 bounded`；properties为`S4 bounded visible`、thumbnail/playback为`S3 executed`；status/timeline `L0` | artwork、playback与properties各自generation只向实际导出相应callback的owner派发；generation 0/stale/same-generation conflict拒绝，缺输入不消费而可同代重试。同一scalar/vector owner内顺序为playback→thumbnail→`update`，String另在thumbnail前派发properties；均复用typed handles与成功update才提交的mutation buffer。真实`2067939514`证明thumbnail animation命令，真实`2938612768`证明playback与title，真实`2974757317`证明四个five-color Vec owner。没有跨类型通用event queue或live macOS producer | status/timeline JS事件、properties其余字段、previous cover、跨类型/跨owner完整event ordering、重复provider仲裁、reload/teardown与官方行为对照；作者可变`shared`/任意JS heap state不回滚，callback createLayer后异常的C registry reconciliation未闭合 |
| `animationEvent` | Timeline/puppet 指定帧向同 layer script 派发 name/frame | `L0` | `G` 确认它属于可回写绑定 property 的三个 event 之一；项目仍无 dispatch，`N` | typed return、crossing、loop/mirror、seek、低 FPS 跨多帧和一次性派发 |

`animationEvent` 由 Timeline 官方页面确认，但 v2.8 `IComponent` 没列该回调；实现必须保留兼容测试，不能任选一份官方资料后删除另一边。

## 4. 对象与句柄 API

<a id="41-通用-layer--scene"></a>
### 4.1 通用 layer / scene

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `IObject` | `getAnimation(name?)` 取当前 property 或命名动画 | current property `L3 bounded / S4 bounded visible`；named `L0` | callback-scoped `thisObject.getAnimation()` 只在 compiler 已证明当前 property 有 Timeline 时返回 typed handle；带参数调用、无 Timeline、callback 外 retained handle 均拒绝 | named lookup、缺失/重名策略、owner destroy/reload 与跨 callback 生命周期 |
| `IThisPropertyObjectBase` | v2.8 中是只继承 `IObject` 的空 property-owner 基类 | `L3 bounded` | scalar alpha 与 Vec3 origin/scale/angles owner 以完整 authored path/descriptor/Timeline target 绑定当前 property；不添加声明外成员 | 其他 property owner/value type、动态 owner 与 destroy/reload |
| `thisLayer: ILayer` | 当前脚本 owner 的 layer handle | `L3 bounded effect-layer handle / S3 contract-executable` | callback 期间只读开放 descriptor-bound `getEffect(name|index)` 和 `getEffectCount()`；scalar/Vec3 owner 共用同一 catalog bridge，脚本不能伪造 effect identity；callback epoch与active owner阻止retained closure跨owner使用 | 其他 layer 字段/方法、销毁语义仍缺；effect name lookup尚无真实 authored consumer可见正证 |
| `ILayer` transform | `origin`, `angles`, `scale`, `parallaxDepth`, `name`, `visible` | `id/name/origin/scale/angles getter L3 bounded`；owner-bound authored与owned dynamic `origin/angles/scale` setter `L3 bounded / S4 visible`；dynamic visible setter `L3 bounded`；其余`L0` | descriptor catalog开放safe-integer identity与同一frame snapshot；authored transform setter只允许`thisLayer`，按字段写owner-local finite mutation，成功整批在frame末提交并从下一帧进入唯一dynamic snapshot。dynamic text仍复用原topology transaction。stock 3D Clock已持续提交angles并可见，非transform authored setter仍局部拒绝 | parallaxDepth、authored visible/text、local/world与parent语义、asset/model/image layer、跨owner冲突顺序及官方坐标/视觉对照 |
| `ILayer` orientation | `getTransformMatrix`, `rotateObjectSpace`, `lookAt`, `lookAtYaw` | `L0` | `N` | 数学/坐标合同、parent 情况和 2D/3D fixture |
| `ILayer` parenting | 两个 `setParent` overload、`getParent`, `getChildren` | `L0` | `G` 确认同步 parent/attachment resolution 与 mutation、adjustTransforms 的 world-to-new-local 重算、相同关系 no-op、parent getter 与 children snapshot；self/complexity guard 失败会解除旧 parent而不回滚；项目无 bridge，`N` | descendant cycle、缺失 identity/attachment、guard 含义、transactional safety policy、effective visibility/propagation 和销毁门 |
| `ILayer` attachment | `getAttachmentIndex/Matrix/Origin/Angles` | `L0` | `N` | puppet/model attachment identity、缺失返回和 world transform golden |
| `thisScene` lookup | `getLayer(name|index)`, `getLayerByID`, `getLayerCount`, `enumerateLayers` | name/index/id/count `L3 bounded / S4 bounded visible`；enumerate `L0` | callback-scoped catalog按当前authored+dynamic render order查找；最多4096层，safe-integer id、有限origin，缺失/非整数/越界/超额/stale均拒绝。真实`3122339805`消费name lookup；代表动态layer可由opaque handle取得index/count | `enumerateLayers`、字符串ID与官方duplicate-name行为；当前重名取首个catalog ordinal只属项目策略 |
| `thisScene` layer mutation | `createLayer`, `destroyLayer`, `sortLayer`, `getLayerIndex`, `getInitialLayerConfig` | bounded text create/destroy/sort/index `L3 / S4 representative visible`；initial config `L0` | `createLayer`只接finite、budgeted text config，分配domain内负safe-integer identity；每owner最多64、scene动态最多256、总catalog最多4096。opaque handle含domain/owner identity，跨owner、stale、伪造对象拒绝；sort只接受当前owner动态layer。C mutation snapshot经launch-scoped Swift transaction原子校验，并在下一帧复用CoreText publication与唯一Metal compositor；exception整批丢弃并保留authored previous-current；stop/switch teardown实测清零owner dynamic layer | asset/model/image layer、name保真到render descriptor、static sort、`getInitialLayerConfig`、destroy/update同轮精确顺序、callback create后异常的C registry reconciliation、同帧跨owner可见顺序、多surface与官方parity |
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
| video texture | `duration`, `rate`, `loop`, `play/pause/stop`, `isPlaying`, `get/setCurrentTime`, `addEndedCallback` | `L3 bounded / S4 one real interaction` | 官方公开API形状作为`official-public-contract`；当前QuickJS只向dependency-bearing Bool owner发布persistent layer-identity handle。frame snapshot提供duration/rate/loop/isPlaying/currentTime/ended generation；typed setters/commands与owner-scoped ended callback在VM成功后原子进入现役`SceneVideoTextureSourceRegistry`。真实`3775355045/3775373546`执行双video同步脚本，前者body hover可见hidden provider。missing/wrong layer、overflow、callback异常与跨target mutation局部拒绝且不提交command；host suspend/restore沿现有provider lifecycle | 只覆盖当前Bool owner、单scene、已有video layer与短窗；callback取消/重入/真实ended长窗、provider error、device reset、A/V同步、颜色metadata parity、多屏时钟、其他owner及完整官方行为仍缺 |
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
| `thisLayer` / `thisScene` | 当前owner和scene的typed handles | `L3 bounded` | descriptor-bound static layer getter/effect/animation identity与scene lookup已执行；owned dynamic text layer支持typed setter/create/destroy/sort，generation/owner/伪造handle拒绝 | authored static setter/sort、asset/model/image layer、完整parent/topology、跨scene/screen泄漏负门与官方parity |
| `console` | `log(...any)`、`error(...any)` | `L0` | `N` | per-script tag、速率限制、值序列化、错误不递归 |
| `renderContext` | v2.8 声明 `IRenderContext` 为空 | `L0` | `N` | 保留空 host object；未来声明升级前不得自创成员 |
| `input` | 全局输入快照 | `L3 bounded single-surface` | 同一QuickJS domain安装不可扩展只读getter host；只在callback且存在精确single-surface frame snapshot时取值，global phase与无归属surface拒绝 | 其他input device、multi-surface screen identity、权限降级与官方对照 |
| `localStorage` | screen/global 两个持久化域 | `L0` | `G` 确认默认 screen、仅精确字符串 `global` 切域，其他值回落 screen；项目无 bridge，`N` | wallpaper/scene/screen namespace、配额、原子写、跨屏/重启和迁移策略 |
| `engine` environment queries | editor、portrait/landscape、desktop/mobile、wallpaper/screensaver | `L0` | `N` | macOS 模式映射和稳定 fixture；不伪装未支持平台 |
| `engine.screenResolution` / `canvasSize` | 每屏物理分辨率与2D canvas/full wallpaper尺寸 | `screenResolution L0`；`canvasSize L3 bounded single-surface / S4 representative visible` | 唯一surface callback从现有frame context发布冻结`canvasSize`，代表text consumer完成并显示数值；无精确single surface时不猜identity并局部拒绝 | `screenResolution`、multi-surface、resize顺序、Retina pixel/point及官方对照 |
| `engine.userProperties` | 当前用户属性对象；color属性自动呈现为Vec3 | `L3 bounded contract-executable` | scalar与Vec3 callback都接收同一effective property map的深冻结typed snapshot；number/bool/string保留类型，project color string转为`{x,y,z}`。C/Swift门覆盖读取与不可变性；当前真实Vec3样本消费的是同源`scriptProperties`，未直接读取该global | 真实authored consumer、key normalization官方对照、首次/增量/多屏一致性、更多property kind |
| `engine.timeOfDay` | 24 小时归一化到 `[0,1]` | `L3 bounded / S4 real visible differential` | Swift 从同帧 wall date 按当前时区计算本地民用日秒并限制到 `[0,1]`，C bridge 以 callback-scoped immutable scalar 暴露。真实 `2134765860` 的 4 个 `multiply` 与 2 个 `alpha` owner 在本地 12:00 均输出 0、22:00 均输出 1，旧固定 AST owner 已删除 | 时区/DST、跨午夜长稳、同帧 Date 一致性、非scalar/其他target、官方数值/像素 golden 与独立 effect ROI parity |
| `engine.frametime` / `runtime` | 上帧秒数（重绘可为 0）和scene累计运行时间 | `L3 bounded contract-executable` | 同一 immutable callback snapshot 分别暴露 host `simulationFrameTime` 与 `sceneTime`；C harness真实读取二者并覆盖非法/负值输入和脚本改写失败。真实 time-of-day 样本建立同一 bridge，但其作者 source 不消费这两个字段 | 真实 authored consumer、raw/effective数值 parity、0 delta、pause/switch/seek、inverse4 与 Windows 同帧多屏 golden |
| `shared` | 同 scene 脚本共享的 global object | mutable carrier `L3 bounded / S4 visible` | 同一QuickJS scene domain给cursor owner与Vec3 consumer暴露同一mutable object identity；真实`2974757317`的enter/leave writer与10个origin consumer形成可见位移。当前不把top-level `shared=false`源码当作通用initializer执行 | 通用initializer/module顺序、任意owner/API共享、per-screen语义、reload/销毁、并发与官方行为对照 |

## 6. Input、Audio 与 Media

| API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `input.cursorWorldPosition` | 当前cursor世界坐标，当前主要X/Y | `L3 bounded single-surface / S4 representative visible` | 同帧未裁剪AppKit位置经现有orthographic camera inverse成为冻结Vec3；合法大canvas/depth矩阵使用finite inverse/residual门。C门覆盖逐callback刷新/global拒绝/非法ABI；代表text consumer完成，stock clock已越过本getter | parent/perspective、resize、屏外/event同帧golden、multi-surface与官方数值对照 |
| `input.cursorScreenPosition` | 屏幕像素坐标 | `L3 bounded single-surface / S4 representative visible` | 与world getter共用surface snapshot，以drawable物理像素和top-down Y发布冻结`{x,y}`；无精确surface局部拒绝 | Retina缩放、跨屏origin、resize、坐标取整与官方golden |
| `input.cursorLeftDown` | 左键当前状态 | `L3 bounded single-surface / S3 executed` | 同一surface snapshot读取当前AppKit primary-button identity；getter只在callback开放，代表consumer同轮执行。ordered event batch另向cursor callback保留同帧down/up，不把polling getter伪装成事件流 | polling仍只表示callback时current状态；失焦、multi-button/multi-surface与官方时序对照仍缺 |
| `CursorEvent.worldPosition/localPosition/hitBox?` | 事件时 world/local 坐标与 puppet hit box；声明明确 screenPosition/button 未使用 | `L3 bounded world/local` | generic enter/leave/down/up/click均在dispatch前复制immutable world/local Vec3；C/Swift门锁定DTO不可写。当前不伪造`hitBox` | parent/rotated/puppet数值、detail identity、event时序/坐标官方对照；未使用字段不得伪造 |
| [audio resolution constants](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) | `AUDIO_RESOLUTION_16/32/64` | `L3 bounded` | module求值期的engine只暴露三个只读常量；callback期engine不携带注册常量/API | 其他数值、callback注册和非法分辨率失败关闭；完整module/lifecycle仍缺 |
| [`engine.registerAudioBuffers(resolution)`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) | 必须在 script global context 注册，返回逐帧频谱 | `L3 bounded` | module求值期开放默认16及exact 16/32/64；重复同档返回同一object，callback期注册和错误档位拒绝；owner存在性驱动既有唯一音频采集需求 | stop/reload注销与多scene/multi-surface生命周期仍待V2 lifecycle门；不证明官方FFT数值 |
| [`AudioBuffers`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) | 同长度 `left`, `right`, `average` Float32Array，每帧自动更新；低频到高频，通常 0...1 但可大于 1 | `L3 bounded` | QuickJS持有三档稳定Float32Array identity，host在event/update前由同一generation snapshot原地覆盖left/right并计算`(left+right)/2`；NaN/Inf/负值、错长度与stale owner拒绝。`2684431262`证明8个layer-scale与1个particle-rate consumer读取同一非零generation，旧专用owner已删除 | 完整teardown、多scene/multi-surface与官方数值/像素golden未闭合 |
| `MediaStatusEvent` | `enabled` 表示媒体集成可用/启用 | `L0` | `N` | enable/disable、无 provider 和订阅生命周期 |
| `MediaPlaybackEvent` | state 0 stopped / 1 playing / 2 paused | API `L3 bounded / S3 executed`；live ingress `L0` | QuickJS module evaluation前安装冻结常量对象；typed inbox snapshot按playback generation去重并在同帧`update`前派发`mediaPlaybackChanged({state})`。旧专用fade owner已删除；callback异常只禁用对应owner并保留peer/previous-current | 公开授权的macOS provider、跨类型event queue、重复/切换仲裁、pause/resume/switch/teardown与跨播放器事件 |
| `MediaPropertiesEvent` | title/artist/subTitle/albumTitle/albumArtist/genres/contentType | API `L3 bounded scalar/vector/String`；String/Text `S4 bounded visible`；cross-type `S3 executed` | inbox按properties generation冻结完整七字段，统一media coordinator按authored ordinal在同帧update前向三类owner派发；缺省optional字段按项目策略置空。同generation去重、stale、错型、字段预算/控制字符与callback failure由门锁定。既有`2938612768`的3个Text owner有可见publication；真实`3780391264`另执行8个scalar/vector与4个String owner | live producer、真实原子曲目切换/clear、multi-surface、全部19个非String occurrence与官方行为对照。项目事件顺序不声明官方语义。见[E-V4-MEDIA-PROPERTIES-SEVEN-FIELD-STRING](runtime-evidence-index.md#e-v4-media-properties-seven-field-string)与[E-V4-UNIFIED-MEDIA-FRAME-BATCH](runtime-evidence-index.md#e-v4-unified-media-frame-batch) |
| `MediaThumbnailEvent` | thumbnail presence 和 primary/secondary/tertiary/text/high-contrast colors | API `L3 bounded / S3 real consumers executed`；current texture `L3 bounded` | current `$mediaThumbnail`继续使用typed provider/visibility/last-ready；同一artwork generation的event冻结`hasThumbnail`与五个finite Vec3，缺色规范为`Vec3(0,0,0)`，nested DTO不可写。side-effect-free G 阶段形成8个pass candidates，MaterialProgram先得到C=4；fresh candidate domain只构造C，失败整域丢弃并排除失败target后重建，G−C不执行。旧native family已删除；默认`generic-only`，route演练`4→0→4`。事件现与其他media channel共用authored-order coordinator；真实`3780391264:194 origin`只证明thumbnail callback/animation side effect与下一帧整构图，`thisLayer.visible` mutation目前仅有自动正反门 | 能产生`layerMutations=... committed`的真实visibility门、live producer、clear/platform lifecycle、previous cover、multi-surface、visibility/颜色独立ROI与官方事件顺序；截图不证明最终颜色或完整样本。见 [E-V4-MEDIA-COLOR-OWNER-PARTITION](runtime-evidence-index.md#e-v4-media-color-owner-partition)与[E-V4-UNIFIED-MEDIA-FRAME-BATCH](runtime-evidence-index.md#e-v4-unified-media-frame-batch) |
| `MediaTimelineEvent` | position/duration 秒值，播放时频繁发送 | API `L3 bounded / S3 executed`；live ingress `L0` | 独立timeline generation冻结finite nonnegative `position/duration`，Swift/C ABI/QuickJS DTO不可写；统一media coordinator在update前派发并按generation去重。真实`3768020435:382#effect#0/pass#0/Progress`收到`12.5/90`且走`generic-only` | live producer、rate/seek/unknown duration、节流/单调性、multi-surface及官方时序对照；见[E-V4-UNIFIED-MEDIA-FRAME-BATCH](runtime-evidence-index.md#e-v4-unified-media-frame-batch) |

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
| `engine.setTimeout` | 毫秒延迟，一次性 callback；返回函数可提前取消 | `L3 bounded / S3 executed` | `D/F` 在callback-scoped `engine`开放0…86400000 ms一次性timer；每owner与timer identity绑定，返回函数幂等取消，轮前snapshot保证callback中新建timer不同轮执行。同一runtime只推进一次，pause的零frame-time不累计；执行门覆盖取消、callback throw、跨owner取消拒绝、Promise resolve和peer存活，stop/switch运行证明destroy中新建timer也归零 | 当前真实corpus扫描无作者调用，未取得App可见consumer；pause/resume、scene seek、callback/帧总预算聚合和官方动态对照仍缺 |
| `engine.setInterval` | 毫秒周期 callback；返回函数用于停止 | `L3 bounded / S3 executed` | `D/F` 每owner固定最多32个timer，周期每帧至多执行一次、重置完整周期、不追赶也不保留overshoot；执行门覆盖长帧、自取消、预算溢出、同runtime不重复推进、job drain和owner销毁释放；stop/switch运行记录teardown后timer=0 | 当前真实corpus扫描无作者调用，未取得App可见consumer；pause/resume、scene seek、callback/帧总预算聚合与官方动态对照仍缺 |
| `clearTimeout` | v2.8 声明明确“未实现”，应调用返回的 cancel function | `L0` | `G` 发现内部同名兼容 binding，但公开声明仍是唯一公共合同 | 不公开该入口；兼容 fixture 锁定返回函数取消 |

## 9. Math、颜色与 ECMAScript 基础

| API | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `WEMath` | `smoothStep`, `mix`, `deg2rad`, `rad2deg` | module `smoothStep/mix` `L3 bounded`；其余成员 `L0` | QuickJS module loader只allowlist `WEMath`；`smoothStep`与numeric finite `mix(a,b,t)=a+(b-a)t`执行真实import/export，错参/非有限结果typed exception，unknown module在owner create阶段关闭。真实`2134765860`闭合smoothStep日夜consumer，真实`2974757317`闭合mix cursor/Vec3 consumer | vector mix、角度换算、完整module graph、官方NaN/Inf边界与Windows数值parity |
| `WEVector` | `angleVector2`, `vectorAngle2`，角度单位为 degree | `L0` | `N` | 象限、零向量、round-trip 和 epsilon 门 |
| `WEColor` | `rgb2hsv`, `hsv2rgb`, `normalizeColor`, `expandColor` | `hsv2rgb L3 bounded`；其余 `L0` | [官方公开合同](https://docs.wallpaperengine.io/en/scene/scenescript/reference/module/WEColor.html)声明normalized HSV Vec3→normalized RGB Vec3；现役allowlisted module只执行finite `hsv2rgb`，hue周期包裹，saturation/value越界对当前owner typed exception。真实pass Vec3 Tint consumer见[E-V4-SCENESCRIPT-PASS-VEC3-WECOLOR](runtime-evidence-index.md#e-v4-scenescript-pass-vec3-wecolor) | `rgb2hsv/normalizeColor/expandColor`、灰色/边界官方动态golden、round-trip、颜色空间细节与Windows数值parity |
| ECMAScript `Math` | SceneScript 可用的标准数学函数 | `L0` | 无 VM；`N` | 明确支持版本、deterministic random/seed 策略和数值兼容测试 |
| ECMAScript `Date` | 时钟/日期脚本读取 wall time | `L3 bounded` for text subset | `D/F` 把 `new Date()` 与 `getFullYear/getMonth/getDate/getDay/getHours/getMinutes/getSeconds` 映射到同帧 Gregorian wall date；自有固定时区 fixture 与 213/280 真实时钟门 | Date constructor args/其他方法、locale/UTC、DST、离线 clock adapter、通用 VM 与 Windows parity |

## 10. Value types

### 10.1 Property value 与事件 DTO

| 类型/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| property input union | `Number | Boolean | String | Vec2 | Vec3 | Vec4 | Mat3 | Mat4` | Number、object String/Vec3与pass Vec2 transport `L3 bounded` | pass Vec2以pair进入snapshot、VM边界补z=0；真实206执行25项 | bool/Vec4/matrix、官方Vec2 class与完整schema |
| property return union | v2.8声明返回`Number | Boolean | String | Vec2 | Vec3 | Vec4` | Number、String、object Vec3与pass Vec2 transport `L3 bounded` | pass pair只发布finite x/y；错型/非有限值禁用最小owner | bool/Vec4、官方Vec2 return identity、完整coercion与官方对照 |
| `AnimationEvent` | `name`, `frame` | `L0` | `N` | Timeline/puppet source、crossing 和 frame 数值测试 |
| media/cursor DTO | 本文 Input/Media 表列出的 typed event object | media thumbnail presence+五色/playback/properties与五个cursor callback `L3 bounded`；其余`L0` | media DTO按typed generation派发；thumbnail五色及cursor world/local均使用独立不可变Vec3，owner generation、stale/conflict与异常隔离有C/Swift门及真实运行 | cursor hitBox/多按钮/完整坐标空间、status/timeline/其余properties字段与跨event排序 |

### 10.2 Vectors

| 类型 | 官方成员 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `Vec2` | `x/y`；构造 number/Vec3/string；完整声明方法族 | official class/API仍`L0`；pass value transport `L3 bounded` | 当前pass Vec2在Swift/C边界补z=0并复用现有Vec3 `x/y/multiply`，返回时丢弃z；没有暴露或宣称Vec2 constructor/prototype | 全方法golden、constructor/type identity、mutation/return语义、零长度和除零门 |
| `Vec3` | `x/y/z`；构造 number/Vec2/string；`fromSpherical/toSpherical`；Vec2 同族方法，另有 cross/refract；角度为 degree | `L3 bounded constructor/basic mutation/string color coercion` | QuickJS bootstrap提供finite构造、`x/y/z`、`copy/add/multiply/isFinite`；现接受exact三分量空格或逗号string，`toString()`产生`"x y z"`，用于作者thumbnail颜色脚本的`== "0 0 0"`缺色判断。真实object-origin与四个media-color pass owner执行；未实现成员不冒充完整Vec3 | 其余构造重载与方法、球坐标、cross/refract、epsilon、完整字符串格式/精度与官方golden |
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
| `thisScene.createLayer(asset)` | 由 path/config/asset handle/model data 创建动态 layer | text config `L3 bounded / S4 representative visible`；asset/model/path `L0` | 项目当前只接受无外部资源的typed text config，并经同一mutation transaction/CoreText publication/compositor出画面；其他overload不伪造资源或ABI | asset ownership、初始化配置、publisher/resource dependency、模型/图片layer预算和 teardown |
| texture/video animation handles | 从 image layer albedo 获取 animation/video handle | texture animation `L0`；video `L3 bounded` | 当前`IImageLayer.getVideoTexture()`只对现有scene video provider和dependency-bearing Bool owner返回按layer identity复用的handle；snapshot/command仍由Swift registry持有，JS不拥有player。texture animation handle仍未实现 | 其他owner、provider generation显式JS可见性、rate/error、asset unload后失效、callback重入与texture animation API |
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
