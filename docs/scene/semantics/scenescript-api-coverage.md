# SceneScript API 覆盖表（官方声明 v2.8）

> 核验日期：2026-08-12
>
> 官方基线：`lib.sceneScript.d.ts` **VERSION 2.8**，固定文档 revision `b26412295cbfd0ee5cdceff67e2c95069527aa1b`。
>
> 资料入口：[资料来源与证据索引](source-index.md)、[SceneScript 随包实现合同](scenescript-runtime-implementation-contract.md)、[官方页面全目录](official-page-catalog.md)、[运行时系统语义](runtime-systems-reference.md)、[总覆盖台账](coverage-ledger.md)。
>
> Scene 实现基线、当前两层运行门、签名 App 身份及聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)；本表不复制基线 commit，文内 commit 号是各能力的历史落地提交。

## 1. 当前结论与评级口径

通用 SceneScript 当前仍是 **L0 runtime**。项目没有 ECMAScript VM、通用 file/module loader、host object bridge、事件队列或 timer scheduler。文档级 property binding IR 现在可把 inline `source`、scene/object/effect/pass owner、完整 JSON target path、`scriptproperties`、authored fallback 与 JSON value type 保真，覆盖正式取证的五类位置，达到局部 `L1`；nested/未知 owner 不会被错误提升，同 wrapper 的 `script + user` 冲突会诊断并拒绝。既有 layer 顶层 binding 仍送入 descriptor/cache，旧 cache 缺少该字段仍可解码。它没有建立 file/module、schema-resolved Vec/value type、runtime handle 或通用生命周期。

`8740737`及后续扩展曾建立与VM分离的七个fixed native Text profile；这些source SHA、Workshop命名profile、property配置、greeting shared-state消费与native formatter已在R4-B18全部退役。对应真实样本、截图与格式器报告只说明B18前历史实现，不再证明现役产品owner、当前文字输出或视觉。source identity现在只用于unsupported diagnostic，不选择产品执行。

`0e482550` 另新增一个不依赖 sample/layer/source hash 的 **L3 bounded property-bound text update subset**，也是B18后唯一现役Text脚本执行合同：只把inline source中唯一的`export function update(value)`解析为项目自有、无循环AST，不执行top-level/module。当前支持primitive literals/properties、变量/赋值、`if/else`、`return`、同型比较、`+`/`%`、string `slice`、`new Date()`与本地Gregorian年/月/日/星期/时分秒getter；2048 tokens、128 statements、512 evaluation steps任一越界或未知语义都不覆盖authored fallback。`clockWithPeriod`、greeting等未准入语法不再借fixed source绕过，只保留作者文字。它仍不是通用VM，也不开放`init`、engine、handle、event、timer、exception或module。

`d83606bf` 再新增一个无 sample/layer/source-hash 准入的 **L3 bounded property-bound Blend update subset**：只接受完整 `script,user,value` wrapper、唯一 exported `update`、常数声明、有限四则算术、`engine.timeOfDay`、`WEMath.smoothStep` 与 `Math.max`，编译结果只能写回 typed Blend `multiply` target；1024 tokens、128 AST nodes、256 evaluation steps和 `0...2` consumer range 任一失败都保留 authored fallback。它用同一帧本地 wall date 驱动 `2134765860` 的清晨/正午切换，但不创建 `engine`/`WEMath` module object，不开放其他 target、statement、function、event 或通用 VM。

`9a6a028` 曾以两个 **L3 bounded native audio profile** 按 raw source SHA-256 与完整 binding/property/layer/asset/shader/render-state 合同准入 `2241938645:282` 与 `3743305891:112` 的 64 段条形。B21已删除source/profile compiler、plan/verification、native geometry/renderer、host wiring与专用report；这些fixed SceneScript Audio Bars不再取得产品执行权。旧定向报告只说明B21前的准入与64-draw历史，不能证明现役owner、当前输出或视觉。

`d5bff76e` 与 `9c70cf06` 曾建立 delayed-loop/time-of-day 两个 **L3 bounded native texture-animation profile**；它们的source SHA、compiler、playback plan、专用clock与wall-date sprite plumbing已在R4-B19全部退役。对应定向报告只说明B19前实现，不再证明现役profile owner、当前时序或视觉。`SceneTextureAnimationScriptDefinition`仍保真wrapper/source/properties/user/authored value，但所有TextureAnimation SceneScript均不执行；普通TEX atlas和cross-image multi-image继续按scene time与作者frame duration原生autoplay。

Scene host 已有 16/32/64 档 left/right 频谱 snapshot，并由 stock effect及普通/Workshop Effect Audio Bars的现役Program/typed consumer按需驱动采集；这仍只是renderer输入/有界effect consumer。B21后没有任何SceneScript Audio Bars产品consumer，也没有VM、`engine.registerAudioBuffers` bridge、`AudioBuffers`/Float32Array object identity或脚本订阅，因此下表相关官方API全部保持`L0`。

`2938612768:[165,454,626,629,924]` 的 Opacity 值来自未支持 SceneScript，当前 strict planner 仍必须拒绝；只有 `2902406982:[365,372,647,664]` 的 direct binding 是正门。粗粒度总表中的“Script presence L1”只表示发现能力；现役bounded Text AST与已退役fixed profile的历史边界见 [E-TEXT-SCRIPT](runtime-evidence-index.md#e-text-script)。

等级沿用总覆盖台账：

| 等级 | 本表含义 |
|---|---|
| `L0` | 没有可调用、可观察的 SceneScript runtime 行为 |
| `L1` | 能保真解析/保存该 API 所需 IR，但未路由 |
| `L2` | 已路由到 typed runtime/handle，但未真实执行 |
| `L3` | 已执行受限子集，并有正反例和生命周期门 |
| `L4` | 已由官方行为或 Windows golden 验证 |

### 1.1 本地证据代号

| 代号 | 代码/测试证据 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| `P` | [`SceneResourceIndex.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceIndex.swift)、[`SceneCapabilityProfile.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneCapabilityProfile.swift) | `.js` 分类和 package-level presence | 源码读取、模块加载、执行 |
| `I` | [`SceneDocument.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift)、[`SceneScriptBindingDefinition.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneScriptBindingDefinition.swift)、[`SceneRenderDescriptor.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneRenderDescriptor.swift)、[`SceneTextScriptDefinition.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextScriptDefinition.swift) | 文档级五类 binding 保真 inline source、owner、完整 target path、properties、authored fallback 与 JSON value type；layer 顶层旧 carrier 与文字 inline source 继续保留 | file/module、schema-resolved Vec/value type、runtime handle、VM、API、生命周期 |
| `W` | [`SceneParticleDefinitionParser.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleDefinitionParser.swift)、[`test_scene_particle_definitions.py`](../../../script/tests/test_scene_particle_definitions.py) | 动态 wrapper 的 `hasScript` presence 可诊断 | wrapper script 的源码或求值 |
| `D` | [`SceneDynamicSnapshot.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift)、[`SceneTextScriptSubsetCompiler.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextScriptSubsetCompiler.swift)、[`SceneTimeOfDayEffectScriptCompiler.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneTimeOfDayEffectScriptCompiler.swift)、[`SceneTimeOfDayEffectScriptRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneTimeOfDayEffectScriptRuntime.swift)、[`test_scene_text_script_runtime.py`](../../../script/tests/test_scene_text_script_runtime.py)、[`test_scene_time_of_day_effect_script.py`](../../../script/tests/test_scene_time_of_day_effect_script.py) | typed target、固定优先级，以及无身份旁路的bounded text/Blend update AST/value；fixed Text profile已退役 | 通用ECMAScript、module/API object bridge、其他target、instance lifecycle |
| `F` | [`SceneFrameContext.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift)、[`SceneTextScriptRuntime.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextScriptRuntime.swift)、[`SceneDesktopWallpaperHost+FrameDriver.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift) | 同帧 wall date、per-surface evaluation/snapshot、bounded `new Date()` getter 与本地 `timeOfDay` scalar | 脚本实例、event/timer、locale/DST/通用离线 clock、任意 JS |
| `G` | 2.8.42 主程序与 SceneScript module 的 Ghidra 有界静态证据，详见 [实现层合同 §8](scenescript-runtime-implementation-contract.md#8-engine-与宿主生命周期静态互证gb) | 版本握手、effective time/pause、固定事件槽、watchdog/timer/audio tick、typed return、camera/material/particle/video/animation handle 与 host-owned teardown 结构 | MyWallpaperX 已实现、未闭合事件/冲突顺序、完整 ABI、官方性能/视觉等价 |
| `N` | 全仓 `SceneScript`/VM/API 搜索及现有 Scene 测试 | 没有 VM 或 handle bridge；除 `D/F` 单列的 bounded text `update`/Date getter 与 Blend time-of-day expression 外，无其他官方 API 执行测试 | 不能把其他 Swift renderer 的同名能力算成脚本 API |

### 1.2 目标执行模型与来源边界

SceneScript 不是孤立的脚本引擎，而是与 Timeline、用户属性和作者默认值共同组成的属性绑定系统。本节同时使用多类证据，必须分开理解：

| 内容 | 来源 | 用法 |
|---|---|---|
| API、global、hook 签名和作者可见类型 | 官方 v2.8 declaration 与公开页面 | 定义兼容表面 |
| engine tick、owner、timer、cursor 和 teardown 结构 | 2.8.42 客户端有界静态取证 | 收窄实现顺序与 fixture；不代表 MyWallpaperX 已实现 |
| immutable snapshot、generation、预算和失败关闭 | MyWallpaperX 目标合同 | 项目安全与跨平台 policy；与官方实现不同处必须明确标注 |
| 当前等级 | 本表、总覆盖台账与运行证据索引 | 唯一实现状态 |

#### 1.2.1 求值优先级（从低到高）

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
- Timeline 已有受限 `L2-L3` target/evaluator，通用 SceneScript 仍为 `L0`；精确现状见 [总覆盖台账](coverage-ledger.md#61-timeline-与-scenescript)
- 不得让 SceneScript 提前执行后被 Timeline 覆盖
- 不得让用户属性在脚本后才生效

#### 1.2.2 生命周期钩子

| 钩子 | 调用时机 | 返回值语义 | 当前等级 |
|---|---|---|---|
| `init(value)` | owner 创建后调用**一次** | 返回绑定 property 的初值 | `L0` |
| `update(value)` | 脚本导出该 hook 时进入有效帧更新 | 返回当前帧的 property 值；动画应乘 `engine.frametime` | `L0` |
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

#### 1.2.5 实施前置依赖

SceneScript 不能从"嵌入 JS VM"开始直接调用现有 renderer。最小正确顺序：

1. **Source/Binding IR**：保真保存 inline/file source、owner、property target、value type
2. **受控 VM core**：严格 global allowlist、module loader、预算、异常隔离
3. **Lifecycle core**：`init/update/destroy`，每屏实例，与 `SceneFrameContext` 同帧
4. **Per-surface evaluation**：host 先捕获共享 time/property，surface 加入 viewport/pointer；脚本返回进入 mutation buffer，校验后原子提交 snapshot
5. **基础 handles**：`thisLayer/thisScene` lookup、transform/visibility/text、engine timing
6. **事件输入**：user/cursor 事件，再接 audio/media generation snapshot
7. **广度 API**：effect/material、particle、animation、storage/timers、dynamic layer
8. **高级 API**：Puppet/model/physics 只能在对应 renderer 已有 runtime 后开放

## 2. Property-bound 核心合同

| API/合同 | 官方含义 | 等级 | 当前代码/测试证据 | 缺口与升级验收门 |
|---|---|---:|---|---|
| property-bound 实例 | 每份脚本绑定一个具体 property；通用逻辑通常绑定 layer visibility | `L1` | `I` 保真正式 13 处对应的五类 scene/object/effect/pass owner、完整 target path、inline source/properties/authored fallback/JSON value type；nested/未知 owner 不提升，`script + user` 冲突 fail-closed；未执行脚本 | 补 file/module、schema-resolved Vec/value type、runtime handle；重复/缺失 target 与 owner teardown 门 |
| `init(value)` / `update(value)` 的 typed value | 入参是绑定 property 当前值；返回兼容值写回；无返回则保持原值 | text String / Blend scalar 为 `L3 bounded`；generic `L0` | `D/F` 对唯一 exported text `update(value)` 的无循环 AST 写回 String；独立 Blend 子集只把 exact time-of-day expression 写回 `multiply` scalar。两者都无 sample/layer/hash 准入 | `init`、bool/Vec2/3/4、其他 number target、无返回/错类型诊断、block scope/coercion/exception、通用 owner 生命周期 |
| 直接赋值其他 property | 脚本可通过 `thisLayer`/其他 handle 同时修改多个 property | `L0` | `D` 只有 Swift target，没有 JS handle setter | 同帧 mutation buffer；确定冲突顺序、失效 handle 和只读字段；原子提交到 snapshot |
| source/module loader | 加载 inline 或 `.js` 源码及其 export/import | `L0` | `I` 只保存顶层 wrapper 的 inline source；没有 file/module loader 或 executable module graph | 规范化路径、UTF-8/大小限制、模块依赖图、循环/缺失/越界负向门 |
| ECMAScript VM | 受控 ECMAScript 环境，无 DOM/Web/Node/shell/任意文件系统 | `L0` | `N` | 选定 VM；严格 global allowlist；网络/文件/进程逃逸测试 |
| budget/error boundary | 每实例/每帧时间、指令、内存和 timer 有界；脚本错误不终止 renderer | `L3 bounded` for text/Blend subsets; generic `L0` | text parser/evaluator 固定 2048 tokens、128 statements、512 steps；Blend parser/evaluator 固定 1024 tokens、128 nodes、256 steps。语法/类型/值/预算失败均不覆盖 fallback；grammar 无 loop/回调/任意调用。`G` 确认官方另有耗时累计、单事件禁用和连续 watchdog | 通用 VM 的 wall-time/memory/recursion/OOM/exception/log throttle/instance fuse；本地 budget 不冒充官方 watchdog parity |
| instance ownership | 每屏/每 scene 的实例隔离；switch/stop 必须销毁 | `L0` | `F` 已有 per-surface transaction/snapshot，但没有任何脚本实例 | 双屏 frame/time 相同但 pointer/size/result/generation 隔离；pause/resume、switch、stop 后无 timer/handle/provider residue |

## 3. 生命周期与事件

| 事件/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `init(value)` | owner 创建后调用一次，返回绑定 property 初值 | `L0` | `G` 确认新 script record 尾插、`init` 同步执行；项目仍无实例，`N` | 每实例恰好一次；typed return、异常降级、callback mutation 与 budget |
| `update(value)` | 每个渲染帧调用；动画应乘 `engine.frametime` | `L3 bounded` for pure text subset; generic `L0` | `D/F` 每帧纯函数求唯一 text return，同帧 wall date 与 snapshot；没有 instance、callback mutation 或 engine frametime。`G` 的官方 live record 语义仍未实现 | 通用实例/owner、0 delta、长帧、暂停、callback mutation、frametime 与 teardown |
| `destroy()` | owner 销毁前调用 | `L0` | `G` 确认 destroy 请求排队，普通 update 后 drain，并按 `destroy → engine record removal → host record release` 执行；destroy callback 新 owner 已错过本轮 update但可能进入本帧 render preparation；项目仍无实例，`N` | switch/stop/动态删 layer 均恰好一次；destroy 内创建/timer/跨 handle/异常重入与 stop 后 residue |
| `resizeScreen(size)` | 分辨率变化时调用；首次创建不会自动调用 | `L0` | `N` | resize 正例和 startup 反例；每屏 size、去重和事件顺序 |
| `applyUserProperties(changed)` | 首次加载调用，之后只含变化键；使用 `hasOwnProperty` | `L0` | 现有属性系统不派发脚本事件；`D/N` | generation queue；初次全量/后续 delta、批量改动、类型和顺序测试 |
| `applyGeneralSettings(changed)` | 首次及 app general setting 改变时调用，v2.8 当前主要是 language | `L0` | `N` | typed settings snapshot；初次/增量、未知键和多屏一致性 |
| `cursorEnter` / `cursorLeave` | 指针进入/离开对象边界 | `L0` | `G` 确认 candidate snapshot、solid-only native hit test、hidden-solid 仍可 hover；visible toggle 不清状态，destroy 静默失效；项目无 dispatch，`N` | world/local/puppet transform、候选顺序、边界抖动、parent/visible mutation 与成对事件门 |
| `cursorMove` | 指针移动时传 `CursorEvent` | `L0` | `G` 确认命中 owner 可接收 move，hidden-solid 仍参与；项目无 dispatch，`N` | world/local 坐标、帧内合并、不同 owner 事件顺序和多按钮 |
| `cursorDown` / `cursorUp` / `cursorClick` | 对象上按下、释放和同对象完整点击 | `L0` | `G` 确认 pressed/capture identity、同 identity down/up 才完成 click；visible toggle 保留状态，destroy 静默清除且不补事件；项目无 dispatch，`N` | drag-out、候选顺序、parent mutation、puppet hitBox、多按钮和预算门 |
| 五个 media events | status/playback/properties/thumbnail/timeline 变化事件 | `L0` | Scene 没有 media snapshot 或 script queue；`N` | generation 原子更新、缺字段、乱序/旧封面取消、无 provider 稳定事件 |
| `animationEvent` | Timeline/puppet 指定帧向同 layer script 派发 name/frame | `L0` | `G` 确认它属于可回写绑定 property 的三个 event 之一；项目仍无 dispatch，`N` | typed return、crossing、loop/mirror、seek、低 FPS 跨多帧和一次性派发 |

`animationEvent` 由 Timeline 官方页面确认，但 v2.8 `IComponent` 没列该回调；实现必须保留兼容测试，不能任选一份官方资料后删除另一边。

## 4. 对象与句柄 API

### 4.1 通用 layer / scene

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `IObject` | `getAnimation(name?)` 取当前 property 或命名动画 | `L0` | `N` | typed animation handle；缺失/重名/owner 销毁语义 |
| `IThisPropertyObjectBase` | v2.8 中是只继承 `IObject` 的空 property-owner 基类 | `L0` | `I` 没有保留 owner 类型或绑定 property | binding compiler 根据 owner/property 生成具体 typed handle；不自行添加声明外成员 |
| `thisLayer: ILayer` | 当前脚本 owner 的 layer handle | `L0` | `D` 只有整数 layer target；B21已删除fixed native Audio Bars renderer，现役没有脚本layer handle | VM host identity、每实例 owner、跨层访问权限和失效门 |
| `ILayer` transform | `origin`, `angles`, `scale`, `parallaxDepth`, `name`, `visible` | `L0` | `G` 确认 native visible setter 与 cursor state 分离：隐藏不会让 solid 退出 hit test，也不清 hover/capture；项目静态 renderer 字段仍无 JS bridge，`D/N` | getter/setter 类型、local/world 语义、同帧写回、parent effective visibility、只支持类型的 fail closed |
| `ILayer` orientation | `getTransformMatrix`, `rotateObjectSpace`, `lookAt`, `lookAtYaw` | `L0` | `N` | 数学/坐标合同、parent 情况和 2D/3D fixture |
| `ILayer` parenting | 两个 `setParent` overload、`getParent`, `getChildren` | `L0` | `G` 确认同步 parent/attachment resolution 与 mutation、adjustTransforms 的 world-to-new-local 重算、相同关系 no-op、parent getter 与 children snapshot；self/complexity guard 失败会解除旧 parent而不回滚；项目无 bridge，`N` | descendant cycle、缺失 identity/attachment、guard 含义、transactional safety policy、effective visibility/propagation 和销毁门 |
| `ILayer` attachment | `getAttachmentIndex/Matrix/Origin/Angles` | `L0` | `N` | puppet/model attachment identity、缺失返回和 world transform golden |
| `thisScene` lookup | `getLayer(name|index)`, `getLayerByID`, `getLayerCount`, `enumerateLayers` | `L0` | 静态 descriptor 不暴露 JS handles；`N` | source order、重名、字符串 ID、动态 layer 和失效 handle tests |
| `thisScene` layer mutation | `createLayer`, `destroyLayer`, `sortLayer`, `getLayerIndex`, `getInitialLayerConfig` | `L0` | `G` 确认同步 create/init、2048 bridge identity cap、未知 index=`-1`/sort 失败、超长 sort 夹到尾部、render sort 不改 script record 顺序、普通 update 后 destroy drain、native lifetime 使 wrapper 失效、initial config detached；项目仍无 bridge，`N` | 负 index VM 边界、资产授权、有界 mutation、destroy callback 同帧 render/下帧 update、stale handle 与 create/destroy/sort 冲突 fixture |
| scene camera handles | `getCameraTransforms`, `setCameraTransforms`, `getAnimation` | `L0` | `G` 确认 getter/setter 禁止 global phase、读取同一 base record，setter 对 `eye/center/up/zoom` 做 typed partial update；项目仍无 JS bridge，`N` | finite/type 负门、2D/3D camera、screen resize、同帧 authored/animation 冲突和 round-trip |

### 4.2 内容、effect、动画和高级句柄

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `IImageLayer` 基础 | `alpha`, `color`, `alignment` | `L0` | `D` 有部分 Swift layer target，VM 不可调用 | JS getter/setter、颜色类型、每帧合成和无重建门 |
| `ITextLayer` | `text`, `color`, `alpha`, `opaquebackground`, `backgroundcolor`, `pointsize`, `font`, `padding`, `horizontalalign`, `verticalalign`, `anchor`, row/width limits | `L0` | 当前仅静态 CoreText；`D/N` | 全字段 typed setter、纹理 generation、layout/effect invalidation 和 text golden |
| `ISoundLayer` | `play`, `pause`, `stop`, `isPlaying`, `volume` | `L0` | Scene 无 sound-layer runtime | 音频解码、状态机、音量、pause/switch/stop 和无设备门 |
| `IEffectLayer` | `getEffect`, `getEffectCount`, `transformAttachmentToTexture`, `size`(只读), `perspective`, `solid` | `L0` | `G` 确认 native solid 为 layer flag bit 13，决定是否参加 cursor hit test；visible=false 不覆盖 solid；项目 effect renderer 不暴露 JS handle，`N` | name/index identity、effect-local transform、只读 enforcement、solid 同帧更新与候选顺序 |
| `IEffect` | material 枚举、`setMaterialProperty`, `executeMaterialFunction`, `visible`, `name` | `L0` | `G` 确认 property 按有序 instance records 分别查 metadata 并 typed 写 scalar/Vec2/3/4，缺失/错型只对该 instance no-op；function 按 descriptor-defined ordered record set 同步执行并恢复 active state；项目无 bridge，`N` | descriptor/pass 完整映射、function allowlist、同帧 graph update、未知值/单位/finite 负门 |
| `IMaterial` | v2.8 仅继承 `IObject`；具体 shader property 通过 effect 方法访问 | `L0` | `N` | opaque handle identity/lifetime；不可伪造任意 shader API |
| `IParticleSystem` | `play`, `pause`, `stop`, `isPlaying`, `emitParticles(count?)`, `instance` | `L0` | `G` 确认 emit 缺省或 0 → 1、正整数原样、负数 no-op，并以零时间偏移进入共用 emitter/default/initializer dispatcher；项目仍无 JS commands，`W/N` | command queue、GPU 同 draw 可见性、暂停/停止区别、容量/预算和 teardown |
| particle instance | `alpha`, `size`, `count`, `speed`, `lifetime`, `rate`, `colorn`, `controlpoint0...7` | `L0` | `D` 仅预留 typed target；无 JS setter/consumer | 逐帧 override、control-point 坐标、generation 和数值边界门 |
| texture animation | `frameCount`, `duration`, `rate`, `play/pause/stop`, `isPlaying`, `get/setFrame`, `join` | TEX autoplay `L3 bounded` / SceneScript API `L0` | 普通单图atlas与严格axis-aligned/integer/same-extent的BC1/2/3 cross-image multi-image按scene time及作者frame duration循环；B19已删除两个fixed SHA profile，保真的TextureAnimation SceneScript不控制播放 | 通用instance-local detach/join、frame/rate/play/pause/stop/seek handle、owner timer/callback、同帧冲突与Windows timing golden；旧delayed-loop/time-of-day报告只作历史，见 [E-R4-B19](runtime-evidence-index.md#e-r4-b19-fixed-texture-animation-profile-retirement) |
| video texture | `duration`, `rate`, `loop`, `play/pause/stop`, `isPlaying`, `get/setCurrentTime`, `addEndedCallback` | `L0` | `G` 确认缺 provider no-op/default、ended 后 play 先 seek 0、stop=pause+seek 0、非 loop 一次性 edge、loop 以时间回绕派发且主动 seek 不误报；callback owner-scoped 并经 engine batch 派发；底层 controller 为 host-owned registry producer，teardown 先停 worker、退注册再释放 media/GPU；项目无 handle，`N` | rate/loop setter 边界、callback 取消/重入、provider error、registry pump、device-reset retained intent、A/V/颜色和多屏时钟门 |
| `IAnimation` | `fps`, `frameCount`, `duration`, `name`, `rate`, playback 和 frame seek | `L0` | Timeline runtime 未实现 | evaluator/handle、loop mode、seek/event crossing 和 pause lifecycle |
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
| `engine.userProperties` | 当前用户属性对象 | `L0` | 属性系统不暴露 VM object | typed snapshot、key normalization、首次/增量一致性 |
| `engine.timeOfDay` | 24 小时归一化到 `[0,1]` | generic API `L0`；Blend subset `L3 bounded` | `G` 确认每帧从本地系统时间采样，与累计 scene runtime 分离；项目 `F` 现把 exact property-bound update grammar 中的该标识编译成 typed Blend multiply，按本地民用日秒逐帧求值，并用可注入 wall clock/固定时区 fixture 与 213 清晨/正午真实门验证；没有 JS global/object | 时区/DST、跨午夜长稳、同帧 Date 一致性、其他 owner/target、事件顺序、通用 VM 与 Windows 数值/像素 parity；bounded consumer 不替代 generic API |
| `engine.frametime` / `runtime` | 上帧秒数（重绘可为 0）和 scene 累计运行时间 | `L0` | `G` 确认两者与 engine tick/timer 共用 admitted/scaled/clamped effective delta；完全暂停不 tick/累计，恢复重置基线且不 catch-up；项目 `F` 无 JS global | 0 delta、switch/seek reset、smoothing/clamp 自有 policy、同帧多屏一致性 |
| `shared` | 同 scene 脚本共享的 global object | `L0` | `N` | 每 scene/屏隔离、初始化顺序、销毁和并发 mutation 规则 |

## 6. Input、Audio 与 Media

| API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `input.cursorWorldPosition` | 当前 cursor 世界坐标，当前主要 X/Y | `L0` | `G` 确认 global-phase 拒绝、scene cursor pixel snapshot 经当前 view/projection 逆变换为 Vec3，2D policy 可把 z 置 0；项目无 JS bridge，`N` | camera/viewport 数值、屏外、resize 与 event snapshot 同帧 golden |
| `input.cursorScreenPosition` | 屏幕像素坐标 | `L0` | `G` 确认 global-phase 拒绝、与 world getter 共用 snapshot并按 canvas/viewport scale 与 Y policy输出像素坐标；项目无 bridge，`N` | Retina、多屏 origin、屏外、resize 和坐标取整 fixture |
| `input.cursorLeftDown` | 左键当前状态 | `L0` | `G` 确认 getter 固定查询 left-button identity并读取 scene input bool，其他 identity false；项目无 bridge，`N` | down/up/capture、失焦与 event snapshot 同帧 |
| `CursorEvent.worldPosition/localPosition/hitBox?` | 事件时 world/local 坐标与 puppet hit box；声明明确 screenPosition/button 未使用 | `L0` | `G` 确认六个事件共用 native cursor record builder，world/local/hit-box 为 dispatch 前独立 snapshot，并从 layer hit-box/detail virtual 取得可选 detail；这不是公开 `cursorHitTest` hook；项目无 DTO bridge，`N` | event-local/parent/puppet 数值、detail identity、未使用字段不得伪造 |
| [audio resolution constants](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) | `AUDIO_RESOLUTION_16/32/64` | `L0` | renderer host 已有三档 typed snapshot，native plan 内部严格验证 64；没有 JS global/constant bridge | 只接受三个常量；错误分辨率 fail closed |
| [`engine.registerAudioBuffers(resolution)`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) | 必须在 script global context 注册，返回逐帧频谱 | `L0` | `G` 确认 global-phase 限制、仅 16/32/64、默认 16 和 engine teardown 注销；exact source compiler 仅声明 native demand，没有 VM/API bridge | global-only enforcement、错误 resolution、重复注册/取消订阅与 stop 生命周期 |
| [`AudioBuffers`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) | 同长度 `left`, `right`, `average` Float32Array，每帧自动更新；低频到高频，通常 0...1 但可大于 1 | `L0` | `G` 确认三档 left/right/average backing arrays identity 跨帧稳定，并在 timer 与普通 update 前原地刷新；项目 host 只有 left/right，仍无 JS object/订阅 | 平均值数值、无设备 policy、跨屏 consumer generation 与受控脚本输入 |
| `MediaStatusEvent` | `enabled` 表示媒体集成可用/启用 | `L0` | `N` | enable/disable、无 provider 和订阅生命周期 |
| `MediaPlaybackEvent` | state 0 stopped / 1 playing / 2 paused | `L0` | `N` | 状态映射、重复事件去重和 app 切换 |
| `MediaPropertiesEvent` | title/artist/subTitle/albumTitle/albumArtist/genres/contentType | `L0` | `N` | 缺字段、Unicode、原子曲目切换和 stale generation |
| `MediaThumbnailEvent` | thumbnail presence 和 primary/secondary/tertiary/text/high-contrast colors | `L0` | 项目保留current `$mediaThumbnail` typed provider、通用visibility binding与last-ready/fallback store，但没有live producer、event DTO/dispatch或derived colors；B20已删除fixed previous-transition脚本旁路，`N` | 图像+颜色同generation、live producer、event ordering/owner lifecycle与无封面语义；typed纹理provider不等于SceneScript API |
| `MediaTimelineEvent` | position/duration 秒值，播放时频繁发送 | `L0` | `N` | rate/seek/unknown duration、节流与时间单调性 |

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
| material property/function | effect 的 `setMaterialProperty` 和 `executeMaterialFunction` | `L0` | `G` 确认 ordered instance metadata lookup、scalar/Vec2/3/4 typed write、int/float 与 degree-to-radian metadata，以及 descriptor-defined ordered synchronous function execution；项目无 bridge，`N` | descriptor/pass identity、同帧 graph invalidation、function side effect 和 unsupported fail closed |

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
| `WEMath` | `smoothStep`, `mix`, `deg2rad`, `rad2deg` | generic module `L0`；Blend `smoothStep` subset `L3 bounded` | `N/F` 只在上述 exact time-of-day Blend grammar 执行三参数 `smoothStep`，有顺/逆边界、有限值与早晚相位 fixture；没有 module object，也不开放其余成员 | generic module/import、`mix`/角度换算、NaN/Inf/相等边界官方结果、其他 target 与 Windows 数值 parity |
| `WEVector` | `angleVector2`, `vectorAngle2`，角度单位为 degree | `L0` | `N` | 象限、零向量、round-trip 和 epsilon 门 |
| `WEColor` | `rgb2hsv`, `hsv2rgb`, `normalizeColor`, `expandColor` | `L0` | `N` | hue wrap、灰色、越界、round-trip 和颜色空间门 |
| ECMAScript `Math` | SceneScript 可用的标准数学函数 | `L0` | 无 VM；`N` | 明确支持版本、deterministic random/seed 策略和数值兼容测试 |
| ECMAScript `Date` | 时钟/日期脚本读取 wall time | `L3 bounded` for text subset | `D/F` 把 `new Date()` 与 `getFullYear/getMonth/getDate/getDay/getHours/getMinutes/getSeconds` 映射到同帧 Gregorian wall date；自有固定时区 fixture 与 213/280 真实时钟门 | Date constructor args/其他方法、locale/UTC、DST、离线 clock adapter、通用 VM 与 Windows parity |

## 10. Value types

### 10.1 Property value 与事件 DTO

| 类型/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| property input union | `Number | Boolean | String | Vec2 | Vec3 | Vec4 | Mat3 | Mat4` | `L0` | `D` 的 Swift type 集不含 matrix VM values | JS boxing/unboxing、exact property schema、finite validation |
| property return union | v2.8 声明返回 `Number | Boolean | String | Vec2 | Vec3 | Vec4`，没有 Mat3/Mat4 | `L0` | `N` | 返回类型严格按声明；matrix 输入/不可返回差异要有负向门 |
| `AnimationEvent` | `name`, `frame` | `L0` | `N` | Timeline/puppet source、crossing 和 frame 数值测试 |
| media/cursor DTO | 本文 Input/Media 表列出的 typed event object | `L0` | cursor record/event slot 有 `G` 静态证据，media DTO 仍为 `N`；项目均无 VM object | immutable event object、cursor 坐标/detail、media generation 和 owner isolation |

### 10.2 Vectors

| 类型 | 官方成员 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `Vec2` | `x/y`；构造 number/Vec3/string；length/distance、normalize/copy/equals/isFinite、negate、add/subtract/multiply/divide、dot/reflect/perpendicular/project、angle/angleBetween/rotate、mix/min/max/clamp、abs/sign/round/floor/ceil/fract/mod/step/smoothStep、`toString` | `L0` | `N` | 全方法 golden；mutation/return 语义、字符串格式、零长度和除零门 |
| `Vec3` | `x/y/z`；构造 number/Vec2/string；`fromSpherical/toSpherical`；Vec2 同族方法，另有 cross/refract；角度为 degree | `L0` | `N` | 球坐标轴约定、total internal reflection、epsilon 和字符串 round-trip |
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

SceneScript 不能从“嵌一个 JS VM”开始后直接调用 renderer。最小正确顺序是：

1. **Source/Binding IR**：inline source、五类 owner/完整 target path、properties、authored fallback 与 JSON value type 已局部达到 `L1`；仍需 file/module source、module dependency、schema-resolved Vec/value type 与 runtime handle identity。
2. **受控 VM core**：严格 global allowlist、module loader、Date/Math、预算、异常和日志隔离。
3. **Lifecycle core**：`init/update/destroy/resizeScreen`，每屏实例，与 `SceneFrameContext` 同帧。
4. **Per-surface evaluation transaction**：host 先捕获共享 time/property/audio/media，surface 再加入 viewport/pointer/matrix/provider；脚本返回和直接 setter 进入该 surface 的 mutation buffer，校验后原子提交 immutable snapshot。优先级保持 `authored -> user -> Timeline -> SceneScript`。
5. **基础 handles**：先落 `thisLayer/thisScene` lookup、transform/visibility/text 和 engine timing；不存在的对象、字段或类型 fail closed。
6. **事件输入**：user/general/cursor，再接 audio/media generation snapshot；事件优先于轮询 update。
7. **广度 API**：effect/material、particle、animation/video、storage/timers、dynamic layer/asset。
8. **高级 API**：Puppet/model/model-data/physics 只能在对应 renderer 已有真实 runtime 后开放。

SceneScript core 至少满足以下门后，相关行才可从 `L0` 升级：

- source 与 binding round-trip，不丢源码、owner、target、value type；
- 两屏实例隔离，同一 host frame 读取相同 timing，但不同 resolution/pointer 产生各自不可变 snapshot 和 generation；
- `init/update/destroy` 次数和顺序固定，switch/stop 后 VM、timer、handle、provider 为 0；
- typed return、无返回、错类型、NaN/Inf、throw、死循环均有正反测试，单脚本失败不影响 renderer；
- 用户属性、cursor、audio、media 事件使用 generation/order 合同，旧事件和旧资源不得覆盖新状态；
- 默认关闭的 effect/parallax/particle 仍保持关闭，脚本只修改作者明确绑定或显式访问的目标；
- 至少用通用 VM 执行的动态时钟文字、用户属性文字、cursor 局部坐标、受控音频 bins、media metadata 各一组隔离 fixture 验证；bounded Text AST不替代此门，B18前exact native clock/date profile已退役且只能作历史；
- `L3` 还要求签名 App 真实运行、相关隔离样本正反例与 stop 生命周期；`L4` 需要相同输入下的 Windows Wallpaper Engine golden。

## 14. 更新规则

1. 新增 SceneScript 代码时先更新对应行的单值等级、代码/测试证据和明确边界；不能用 “VM 能运行 Hello World” 批量升级 API。
2. 一个 handle 的 getter、setter、method 和 lifecycle 可分别处于不同实现阶段；表格拆行不足时必须在“当前证据”里写清已执行成员。
3. 普通 renderer 已有同名能力不等于脚本 API 可用；只有真实 JS -> host -> dynamic snapshot -> consumer 链闭环才可记 `L3`。
4. 官方声明版本变化时，先比较 API diff，再更新本表；声明未定义/注释未使用的成员继续保持 unknown 或 unsupported。
5. 固定样本运行通过只证明没有崩溃和门内指标，不证明其中 SceneScript 已执行。
