# SceneScript API 覆盖表（官方声明 v2.8）

> 核验日期：2026-07-23
>
> 官方基线：`lib.sceneScript.d.ts` **VERSION 2.8**，固定文档 revision `b26412295cbfd0ee5cdceff67e2c95069527aa1b`。
>
> 资料入口：[资料来源与证据索引](source-index.md)、[SceneScript 随包实现合同](scenescript-runtime-implementation-contract.md)、[官方页面全目录](official-page-catalog.md)、[运行时系统语义](runtime-systems-reference.md)、[总覆盖台账](coverage-ledger.md)。
>
> Scene 实现基线、当前两层运行门、签名 App 身份及聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)；本表不复制基线 commit，文内 commit 号是各能力的历史落地提交。

## 1. 当前结论与评级口径

SceneScript 当前仍是 **L0 runtime**。项目只能发现独立 `.js` 文件和 inline `script` 的存在；inline 内容进入 `SceneDocument` 时被压缩为 `hasInlineScript: Bool`，粒子动态 wrapper 也只保留 `hasScript: Bool`。目前没有可执行源码 IR、property-script 绑定 IR、ECMAScript VM、host object bridge、事件队列、timer scheduler 或脚本输出消费者。

`SceneDynamicSnapshot` 已预留 `.sceneScript` 优先级和 `scriptInstanceProperty` target；v22 已把 host-shared inputs、per-surface evaluation/final snapshot、binding program、transaction 与 generation 用在 layer alpha、纯 solid color、direct text、exact Local Contrast/Opacity 和受限 X-Ray target。项目仍没有 SceneScript source IR、producer、VM、API bridge、instance state 或输出 consumer，因此这些都不是 SceneScript 执行证据。`2938612768:[165,454,626,629,924]` 的 Opacity 值来自 SceneScript，当前 strict planner 必须拒绝；只有 `2902406982:[365,372,647,664]` 的 direct binding 是正门。粗粒度总表中的 “Script presence L1” 只表示发现能力，本表对每一项 **API 行为** 均给单值 `L0`。

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
| `I` | [`SceneDocument.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift)、[`SceneRenderDescriptor.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneRenderDescriptor.swift) | 递归发现 inline `script`，只传递布尔值 | 源码、绑定 property、导出事件、返回类型 |
| `W` | [`SceneParticleDefinitionParser.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleDefinitionParser.swift)、[`test_scene_particle_definitions.py`](../../../script/tests/test_scene_particle_definitions.py) | 动态 wrapper 的 `hasScript` presence 可诊断 | wrapper script 的源码或求值 |
| `D` | [`SceneDynamicSnapshot.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift)、[`test_scene_dynamic_snapshot.py`](../../../script/tests/test_scene_dynamic_snapshot.py) | typed target、固定优先级和手工注入的 `.sceneScript` 值 | JavaScript、SceneScript source/property binding compiler、API bridge |
| `F` | [`SceneFrameContext.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift)、[`SceneDesktopWallpaperHost.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift)、[`test_scene_frame_context.py`](../../../script/tests/test_scene_frame_context.py) | 同帧时间、host-shared inputs 与 per-surface evaluation/snapshot 基础设施 | SceneScript producer、脚本实例、事件、Date/timer、输出提交 |
| `N` | 全仓 `SceneScript`/VM/API 搜索及现有 Scene 测试 | 没有 VM、handle bridge 或任一官方 API 执行测试 | 不能把其他 Swift renderer 的同名能力算成脚本 API |

## 2. 执行模型与求值顺序（官方合同，2026-07-25 补充）

SceneScript 不是孤立的脚本引擎，而是与 Timeline、用户属性和作者默认值共同组成的**声明式属性绑定系统**。官方明确的求值顺序和覆盖规则决定了 VM 设计、事件队列和 snapshot 合同。

### 2.1 求值优先级（从低到高）

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
- Timeline 和 SceneScript 均为 `L0`，实施时必须遵守上述顺序
- 不得让 SceneScript 提前执行后被 Timeline 覆盖
- 不得让用户属性在脚本后才生效

### 2.2 生命周期钩子

| 钩子 | 调用时机 | 返回值语义 | 当前等级 |
|---|---|---|---|
| `init(value)` | owner 创建后调用**一次** | 返回绑定 property 的初值 | `L0` |
| `update(value)` | **每个渲染帧**调用 | 返回当前帧的 property 值；动画应乘 `engine.frametime` | `L0` |
| `destroy()` | owner 销毁前调用 | 无返回值，用于清理 | `L0` |

**执行时序**（每帧）：
```
1. Timeline evaluator 计算当前帧所有动画值
2. SceneScript `update(value)` 接收 Timeline 结果作为入参
3. SceneScript 可返回新值覆盖，或不返回则保持入参值
4. 最终值写入 per-surface immutable snapshot
5. Renderer 消费 snapshot
```

### 2.3 六大全局对象

每个 SceneScript 实例运行在受控 ECMAScript 环境中，可访问以下全局对象：

| 全局对象 | 接口 | 用途 |
|---|---|---|
| `engine` | `IEngine` | 应用级功能：时间、分辨率、用户属性、音频注册、资源注册 |
| `input` | `IInput` | 光标位置和按键状态 |
| `thisScene` | `IScene` | 当前场景：查找/创建/销毁 layer、camera 控制 |
| `thisLayer` | `ILayer` | 脚本所属 layer 的句柄 |
| `thisObject` | `IThisPropertyObject` | 脚本 owner 对象（类型由绑定 property 决定） |
| `console` | `IConsole` | 调试日志：`log(...)`、`error(...)` |
| `shared` | `Shared` | 同场景脚本间的共享数据对象 |

**安全边界**：
- 无 DOM/Web/Node.js/shell/任意文件系统访问
- 无网络请求能力
- `Date` 和 `Math.random()` 必须由 host 控制以保证确定性
- 每实例/每帧必须有时间、指令、内存预算

### 2.4 事件系统

SceneScript 采用**事件驱动模型**，而非轮询。支持 10+ 事件类型：

**生命周期事件**：`init`、`update`、`destroy`

**用户交互事件**：
- `resizeScreen(size)` — 分辨率变化
- `applyUserProperties(changed)` — 属性变化（首次全量，后续增量）
- `applyGeneralSettings(changed)` — 应用设置变化

**光标事件**：
- `cursorEnter/cursorLeave/cursorMove` — 进入/离开/移动
- `cursorDown/cursorUp/cursorClick` — 按下/释放/点击

**媒体事件**：
- `mediaStatusChanged/mediaPlaybackChanged/mediaPropertiesChanged`
- `mediaThumbnailChanged/mediaTimelineChanged`

**动画事件**：
- `animationEvent(name, frame)` — Timeline/puppet 指定帧触发

**实施要求**：
- 事件按 generation 排队，旧事件不得覆盖新状态
- 事件回调中的异常必须隔离，不能终止 renderer
- `applyUserProperties` 首次调用传全部键，后续只传变化键（需 `hasOwnProperty` 检查）

### 2.5 实施前置依赖

SceneScript 不能从"嵌入 JS VM"开始直接调用现有 renderer。最小正确顺序：

1. **Source/Binding IR**：保真保存 inline/file source、owner、property target、value type
2. **受控 VM core**：严格 global allowlist、module loader、预算、异常隔离
3. **Lifecycle core**：`init/update/destroy`，每屏实例，与 `SceneFrameContext` 同帧
4. **Per-surface evaluation**：host 先捕获共享 time/property，surface 加入 viewport/pointer；脚本返回进入 mutation buffer，校验后原子提交 snapshot
5. **基础 handles**：`thisLayer/thisScene` lookup、transform/visibility/text、engine timing
6. **事件输入**：user/cursor 事件，再接 audio/media generation snapshot
7. **广度 API**：effect/material、particle、animation、storage/timers、dynamic layer
8. **高级 API**：Puppet/model/physics 只能在对应 renderer 已有 runtime 后开放

## 3. Property-bound 核心合同

| API/合同 | 官方含义 | 等级 | 当前代码/测试证据 | 缺口与升级验收门 |
|---|---|---:|---|---|
| property-bound 实例 | 每份脚本绑定一个具体 property；通用逻辑通常绑定 layer visibility | `L0` | `I/W` 只保留 presence，没有 property identity | 建立 `ScriptSource + owner + target + authoredValue + valueType` IR；重复/缺失 target fail closed |
| `init(value)` / `update(value)` 的 typed value | 入参是绑定 property 当前值；返回兼容值写回；无返回则保持原值 | `L0` | `D` 有 typed snapshot，但没有脚本输入/返回桥 | bool/number/string/Vec2/3/4 的返回、无返回、错类型、NaN/Inf、异常隔离测试 |
| 直接赋值其他 property | 脚本可通过 `thisLayer`/其他 handle 同时修改多个 property | `L0` | `D` 只有 Swift target，没有 JS handle setter | 同帧 mutation buffer；确定冲突顺序、失效 handle 和只读字段；原子提交到 snapshot |
| source/module loader | 加载 inline 或 `.js` 源码及其 export/import | `L0` | `P/I` 不保存可执行 source IR | 保真源码、规范化路径、UTF-8/大小限制、模块依赖图、循环/缺失/越界负向门 |
| ECMAScript VM | 受控 ECMAScript 环境，无 DOM/Web/Node/shell/任意文件系统 | `L0` | `N` | 选定 VM；严格 global allowlist；网络/文件/进程逃逸测试 |
| budget/error boundary | 每实例/每帧时间、指令、内存和 timer 有界；脚本错误不终止 renderer | `L0` | `N` | 超时、死循环、递归、OOM、异常、日志节流、单实例熔断和下一帧恢复门 |
| instance ownership | 每屏/每 scene 的实例隔离；switch/stop 必须销毁 | `L0` | `F` 已有 per-surface transaction/snapshot，但没有任何脚本实例 | 双屏 frame/time 相同但 pointer/size/result/generation 隔离；pause/resume、switch、stop 后无 timer/handle/provider residue |

## 3. 生命周期与事件

| 事件/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `init(value)` | owner 创建后调用一次，返回绑定 property 初值 | `L0` | `I/D/N` | 每实例恰好一次；先后顺序、typed return、异常降级可测 |
| `update(value)` | 每个渲染帧调用；动画应乘 `engine.frametime` | `L0` | `F/N` | 与 frame context 同帧；0 delta、长帧 clamp、暂停和预算门 |
| `destroy()` | owner 销毁前调用 | `L0` | `N` | switch/stop/动态删 layer 均恰好一次；回调内 handle 失效顺序明确 |
| `resizeScreen(size)` | 分辨率变化时调用；首次创建不会自动调用 | `L0` | `N` | resize 正例和 startup 反例；每屏 size、去重和事件顺序 |
| `applyUserProperties(changed)` | 首次加载调用，之后只含变化键；使用 `hasOwnProperty` | `L0` | 现有属性系统不派发脚本事件；`D/N` | generation queue；初次全量/后续 delta、批量改动、类型和顺序测试 |
| `applyGeneralSettings(changed)` | 首次及 app general setting 改变时调用，v2.8 当前主要是 language | `L0` | `N` | typed settings snapshot；初次/增量、未知键和多屏一致性 |
| `cursorEnter` / `cursorLeave` | 指针进入/离开对象边界 | `L0` | renderer 有 pointer，不存在 script hit-test dispatch；`N` | 可见/隐藏/solid、parent transform、遮挡、边界抖动和成对事件门 |
| `cursorMove` | 指针移动时传 `CursorEvent` | `L0` | `N` | world/local 坐标、帧内合并、不同 owner 事件顺序 |
| `cursorDown` / `cursorUp` / `cursorClick` | 对象上按下、释放和同对象完整点击 | `L0` | `N` | capture、拖出、隐藏/销毁中断、puppet hitBox、按钮限制门 |
| 五个 media events | status/playback/properties/thumbnail/timeline 变化事件 | `L0` | Scene 没有 media snapshot 或 script queue；`N` | generation 原子更新、缺字段、乱序/旧封面取消、无 provider 稳定事件 |
| `animationEvent` | Timeline/puppet 指定帧向同 layer script 派发 name/frame | `L0` | `N` | crossing、loop/mirror、seek、低 FPS 跨多帧和一次性派发 |

`animationEvent` 由 Timeline 官方页面确认，但 v2.8 `IComponent` 没列该回调；实现必须保留兼容测试，不能任选一份官方资料后删除另一边。

## 4. 对象与句柄 API

### 4.1 通用 layer / scene

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `IObject` | `getAnimation(name?)` 取当前 property 或命名动画 | `L0` | `N` | typed animation handle；缺失/重名/owner 销毁语义 |
| `IThisPropertyObjectBase` | v2.8 中是只继承 `IObject` 的空 property-owner 基类 | `L0` | `I` 没有保留 owner 类型或绑定 property | binding compiler 根据 owner/property 生成具体 typed handle；不自行添加声明外成员 |
| `thisLayer: ILayer` | 当前脚本 owner 的 layer handle | `L0` | `D` 只有整数 layer target | VM host identity、每实例 owner、跨层访问权限和失效门 |
| `ILayer` transform | `origin`, `angles`, `scale`, `parallaxDepth`, `name`, `visible` | `L0` | renderer 静态字段不是脚本 API；`D/N` | getter/setter 类型、local/world 语义、同帧写回、只支持类型的 fail closed |
| `ILayer` orientation | `getTransformMatrix`, `rotateObjectSpace`, `lookAt`, `lookAtYaw` | `L0` | `N` | 数学/坐标合同、parent 情况和 2D/3D fixture |
| `ILayer` parenting | 两个 `setParent` overload、`getParent`, `getChildren` | `L0` | 静态 parent graph 不等于动态 API；`N` | 调整 transform、attachment、循环拒绝、frame-end mutation 和销毁门 |
| `ILayer` attachment | `getAttachmentIndex/Matrix/Origin/Angles` | `L0` | `N` | puppet/model attachment identity、缺失返回和 world transform golden |
| `thisScene` lookup | `getLayer(name|index)`, `getLayerByID`, `getLayerCount`, `enumerateLayers` | `L0` | 静态 descriptor 不暴露 JS handles；`N` | source order、重名、字符串 ID、动态 layer 和失效 handle tests |
| `thisScene` layer mutation | `createLayer`, `destroyLayer`, `sortLayer`, `getLayerIndex`, `getInitialLayerConfig` | `L0` | `N` | frame-end mutation queue、资产授权、排序、回收、预算和 initial config 深拷贝 |
| scene camera handles | `getCameraTransforms`, `setCameraTransforms`, `getAnimation` | `L0` | renderer 有静态 camera；无 JS bridge | 2D/3D camera、screen resize、动态 target 冲突和可逆测试 |

### 4.2 内容、effect、动画和高级句柄

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `IImageLayer` 基础 | `alpha`, `color`, `alignment` | `L0` | `D` 有部分 Swift layer target，VM 不可调用 | JS getter/setter、颜色类型、每帧合成和无重建门 |
| `ITextLayer` | `text`, `color`, `alpha`, `opaquebackground`, `backgroundcolor`, `pointsize`, `font`, `padding`, `horizontalalign`, `verticalalign`, `anchor`, row/width limits | `L0` | 当前仅静态 CoreText；`D/N` | 全字段 typed setter、纹理 generation、layout/effect invalidation 和 text golden |
| `ISoundLayer` | `play`, `pause`, `stop`, `isPlaying`, `volume` | `L0` | Scene 无 sound-layer runtime | 音频解码、状态机、音量、pause/switch/stop 和无设备门 |
| `IEffectLayer` | `getEffect`, `getEffectCount`, `transformAttachmentToTexture`, `size`(只读), `perspective`, `solid` | `L0` | effect renderer 不暴露 JS handle；`N` | name/index identity、effect-local transform、只读 enforcement、hit-test 更新 |
| `IEffect` | material 枚举、`setMaterialProperty`, `executeMaterialFunction`, `visible`, `name` | `L0` | 现有 material/effect IR 不是 script bridge | material slot/property schema、function allowlist、同帧 graph update、未知值 fail closed |
| `IMaterial` | v2.8 仅继承 `IObject`；具体 shader property 通过 effect 方法访问 | `L0` | `N` | opaque handle identity/lifetime；不可伪造任意 shader API |
| `IParticleSystem` | `play`, `pause`, `stop`, `isPlaying`, `emitParticles(count?)`, `instance` | `L0` | 粒子模拟器无 JS commands；`W/N` | fixed-step command queue、emit 边界、暂停/停止区别和 teardown |
| particle instance | `alpha`, `size`, `count`, `speed`, `lifetime`, `rate`, `colorn`, `controlpoint0...7` | `L0` | `D` 仅预留 typed target；无 JS setter/consumer | 逐帧 override、control-point 坐标、generation 和数值边界门 |
| texture animation | `frameCount`, `duration`, `rate`, `play/pause/stop`, `isPlaying`, `get/setFrame`, `join` | `L0` | sprite-sheet runtime 不暴露 handle | shared timer/join、frame clamp、暂停/停止、layer 销毁 |
| video texture | `duration`, `rate`, `loop`, `play/pause/stop`, `isPlaying`, `get/setCurrentTime`, `addEndedCallback` | `L0` | 内嵌 MP4 播放不等于 JS API | seek/loop/rate/end callback、取消、错误和多屏时钟门 |
| `IAnimation` | `fps`, `frameCount`, `duration`, `name`, `rate`, playback 和 frame seek | `L0` | Timeline runtime 未实现 | evaluator/handle、loop mode、seek/event crossing 和 pause lifecycle |
| `IAnimationLayer` | animation metadata；`name/rate/blend/visible`；playback/frame/end callback | `L0` | `N` | puppet/model layer stack、blend、autosort、callback 和销毁门 |
| image animation-layer management | count/get/create/playSingle/destroy animation layer | `L0` | `N` | config validation、single-shot auto-remove、callback order、budget |
| model animation-layer management | `rootmotion`, perspective 和 count/get/create/playSingle/destroy | `L0` | 无 3D runtime | root motion、blend/attachment、2D/3D scene 和 lifecycle golden |
| image bones/physics | bone count/index/parent；world/local transform/angles/origin；impulse/reset | `L0` | Puppet assets 可发现，runtime/API 均无 | mesh/bone solver、local/world round-trip、physics fixed step 和 reset |
| image blend shapes | index、get/set weight | `L0` | `N` | shape identity、range、missing shape、per-frame deformation |
| `ICamera` | `fov`(3D) 和 `zoom`(2D) | `L0` | 静态 camera 与 JS handle 未连接 | 2D/3D 类型约束、projection update 和 invalid value 门 |
| `IModelData` | `applyData` 高频兼容更新；`replaceData` 只能事件驱动；POSITION/NORMAL/TANGENT_SIGNED/UV/COLOR 格式常量 | `L0` | 无动态 model buffer runtime | buffer schema/size/type/CCW、update 禁止 replace、GPU budget 和销毁门 |
| scene model-data lifecycle | `createModelData`, `destroyModelData`, `createLayer(model)` | `L0` | `N` | handle ownership、共享引用、最后 layer 后释放、坏 buffer 负向门 |

## 5. Globals 与 engine 状态

| Global/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `thisLayer` / `thisScene` | 当前 owner 和 scene 的 typed handles | `L0` | `D/N` | 见对象句柄门；不可跨 scene/屏幕泄漏 |
| `console` | `log(...any)`、`error(...any)` | `L0` | `N` | per-script tag、速率限制、值序列化、错误不递归 |
| `renderContext` | v2.8 声明 `IRenderContext` 为空 | `L0` | `N` | 保留空 host object；未来声明升级前不得自创成员 |
| `input` | 全局输入快照 | `L0` | renderer pointer 不等于 JS global | 同帧不可变 snapshot、多屏坐标和权限降级 |
| `localStorage` | screen/global 两个持久化域 | `L0` | `N` | namespace、配额、序列化、原子写、跨屏/重启和清理策略 |
| `engine` environment queries | editor、portrait/landscape、desktop/mobile、wallpaper/screensaver | `L0` | `N` | macOS 模式映射和稳定 fixture；不伪装未支持平台 |
| `engine.screenResolution` / `canvasSize` | 每屏物理分辨率与 2D canvas/full wallpaper 尺寸 | `L0` | frame context 有 viewport，但无 JS bridge | scale factor、跨屏 canvas、resize 顺序和 pixel/point 门 |
| `engine.userProperties` | 当前用户属性对象 | `L0` | 属性系统不暴露 VM object | typed snapshot、key normalization、首次/增量一致性 |
| `engine.timeOfDay` | 24 小时归一化到 `[0,1]` | `L0` | `N` | 可注入 wall clock、时区/DST、离线确定性 fixture |
| `engine.frametime` / `runtime` | 上帧秒数（重绘可为 0）和 scene 累计运行时间 | `L0` | `F` 有 Swift timing，无 JS global | pause/resume、0 delta、switch reset、同帧一致性 |
| `shared` | 同 scene 脚本共享的 global object | `L0` | `N` | 每 scene/屏隔离、初始化顺序、销毁和并发 mutation 规则 |

## 6. Input、Audio 与 Media

| API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `input.cursorWorldPosition` | 当前 cursor 世界坐标，当前主要 X/Y | `L0` | renderer 已算部分坐标但未桥接；`N` | camera/parent transform 后的 world golden |
| `input.cursorScreenPosition` | 屏幕像素坐标 | `L0` | `N` | Retina、多屏 origin、屏外和 resize fixture |
| `input.cursorLeftDown` | 左键当前状态 | `L0` | `N` | down/up/capture 与 event snapshot 同帧 |
| `CursorEvent.worldPosition/localPosition/hitBox?` | 事件时 world/local 坐标与 puppet hit box；声明明确 screenPosition/button 未使用 | `L0` | `N` | hit-test、坐标变换、未使用字段不得伪造 |
| audio resolution constants | `AUDIO_RESOLUTION_16/32/64` | `L0` | `N` | 仅接受三个常量；错误分辨率 fail closed |
| `engine.registerAudioBuffers(resolution)` | 必须在 script global context 注册，返回逐帧频谱 | `L0` | Scene 没有 audio snapshot；`N` | global-only enforcement、按需 capture、取消订阅、静音/拒权零输入 |
| `AudioBuffers` | 同长度 `left`, `right`, `average` Float32Array | `L0` | `N` | 数组长度/更新时点/数值范围、不可跨帧错误复用、受控频谱 fixture |
| `MediaStatusEvent` | `enabled` 表示媒体集成可用/启用 | `L0` | `N` | enable/disable、无 provider 和订阅生命周期 |
| `MediaPlaybackEvent` | state 0 stopped / 1 playing / 2 paused | `L0` | `N` | 状态映射、重复事件去重和 app 切换 |
| `MediaPropertiesEvent` | title/artist/subTitle/albumTitle/albumArtist/genres/contentType | `L0` | `N` | 缺字段、Unicode、原子曲目切换和 stale generation |
| `MediaThumbnailEvent` | thumbnail presence 和 primary/secondary/tertiary/text/high-contrast colors | `L0` | texture provider 尚无 media source；`N` | 图像+颜色同 generation、无封面 fallback、旧 decode 取消 |
| `MediaTimelineEvent` | position/duration 秒值，播放时频繁发送 | `L0` | `N` | rate/seek/unknown duration、节流与时间单调性 |

## 7. Render / scene property API

| API 面 | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| scene bloom | `bloom`, `bloomstrength`, `bloomthreshold` | `L0` | 自有 Bloom 路径不是 JS setter；`D/N` | typed scene target、HDR/order、开关反例和像素门 |
| clear/background | `clearenabled`, `clearcolor` | `L0` | 静态 general 可解析，无 JS bridge | 同帧 clear state、alpha/color space 和 resize/switch |
| lighting colors | `ambientcolor`, `skylightcolor` | `L0` | 无 2D/3D lighting runtime | lighting IR/renderer 后再开放；无消费者时不得假支持 |
| projection | `fov`, `nearz`, `farz` | `L0` | 静态 camera 子集，无 JS bridge | projection validation、near/far 反例、2D/3D golden |
| camera fade | `camerafade` | `L0` | `N` | 定义行为、场景 fixture 和生命周期门 |
| camera shake | enable/speed/amplitude/roughness | `L0` | 当前不消费 shake 属性 | seeded evaluator、作者默认关闭、四参数和暂停测试 |
| camera parallax | enable/amount/delay/mouseInfluence | `L0` | 静态作者参数的 renderer 子集不是 JS API | JS 动态写、同帧 pointer、关闭反例、WE 幅度/delay golden |
| `CameraTransforms` | `eye`, `center`, `up`, `zoom` 的 scene camera DTO | `L0` | `N` | getter/setter round-trip、finite/type validation 和 2D/3D 门 |
| material property/function | effect 的 `setMaterialProperty` 和 `executeMaterialFunction` | `L0` | authored material graph 无脚本 bridge | shader property registry、function side effect、unsupported fail closed |

## 8. Storage 与 timers

| API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `LOCATION_SCREEN` / `LOCATION_GLOBAL` | 默认 screen 域；global 在同 wallpaper 实例间共享 | `L0` | `N` | wallpaper/scene/screen namespace 和迁移策略 |
| `localStorage.set/get/delete/clear` | 保存、读取、删除键或清空指定域 | `L0` | `N` | 可序列化值、配额、损坏恢复、跨重启/多屏、stop 不误删 |
| `engine.setTimeout` | 毫秒延迟，一次性 callback；返回函数可提前取消 | `L0` | `N` | scene-time scheduler、最小延迟、同帧顺序、pause/resume、取消幂等 |
| `engine.setInterval` | 毫秒周期 callback；返回函数用于停止 | `L0` | `N` | drift/catch-up policy、回调预算、自取消和 stop teardown |
| `clearTimeout` | v2.8 声明明确“未实现”，应调用返回的 cancel function | `L0` | `N` | 不暴露虚假 `clearTimeout`；兼容 fixture 锁定返回函数取消 |

## 9. Math、颜色与 ECMAScript 基础

| API | 官方成员与含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| `WEMath` | `smoothStep`, `mix`, `deg2rad`, `rad2deg` | `L0` | `N` | 边界/NaN/Inf 数值 fixture，与官方/Windows 结果比对 |
| `WEVector` | `angleVector2`, `vectorAngle2`，角度单位为 degree | `L0` | `N` | 象限、零向量、round-trip 和 epsilon 门 |
| `WEColor` | `rgb2hsv`, `hsv2rgb`, `normalizeColor`, `expandColor` | `L0` | `N` | hue wrap、灰色、越界、round-trip 和颜色空间门 |
| ECMAScript `Math` | SceneScript 可用的标准数学函数 | `L0` | 无 VM；`N` | 明确支持版本、deterministic random/seed 策略和数值兼容测试 |
| ECMAScript `Date` | 时钟/日期脚本读取 wall time | `L0` | `F` 采样 wall date 但未注入 VM | 同帧固定 Date、时区/DST、离线 clock adapter 和可复现 fixture |

## 10. Value types

### 10.1 Property value 与事件 DTO

| 类型/API | 官方含义 | 等级 | 当前证据 | 缺口与验收门 |
|---|---|---:|---|---|
| property input union | `Number | Boolean | String | Vec2 | Vec3 | Vec4 | Mat3 | Mat4` | `L0` | `D` 的 Swift type 集不含 matrix VM values | JS boxing/unboxing、exact property schema、finite validation |
| property return union | v2.8 声明返回 `Number | Boolean | String | Vec2 | Vec3 | Vec4`，没有 Mat3/Mat4 | `L0` | `N` | 返回类型严格按声明；matrix 输入/不可返回差异要有负向门 |
| `AnimationEvent` | `name`, `frame` | `L0` | `N` | Timeline/puppet source、crossing 和 frame 数值测试 |
| media/cursor DTO | 本文 Input/Media 表列出的 typed event object | `L0` | `N` | immutable event object、generation 和 owner isolation |

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
| `engine.registerAsset(file, precache)` | 必须在脚本 global/root 执行；注册动态 layer 所需资产并确保发布包含；可预缓存 | `L0` | `P` 只索引现有资源；无 script asset registry | global-only 静态/运行时门、规范化路径、越界拒绝、precache budget、缺失/循环依赖 |
| `IAssetHandle` | `registerAsset` 返回并可传给 `createLayer` 的 opaque handle | `L0` | `N` | v2.8 声明引用但未给 interface body；先按 opaque identity/lifetime 实现，不猜成员 |
| `thisScene.createLayer(asset)` | 由 path/config/asset handle/model data 创建动态 layer | `L0` | `N` | asset ownership、初始化配置、动态排序、publisher/resource dependency 和 teardown |
| texture/video animation handles | 从 image layer albedo 获取 animation/video handle | `L0` | 现有纹理/视频 renderer 不暴露 JS handle | provider generation、seek/playback、asset unload 后失效和 callback cleanup |
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

1. **Source/Binding IR**：保真保存 inline/file source、owner、property target、value type、module dependency；presence 不再只是 Bool。
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
- 至少用动态时钟文字、用户属性文字、cursor 局部坐标、受控音频 bins、media metadata 各一组隔离 fixture 验证；
- `L3` 还要求签名 App 真实运行、相关隔离样本正反例与 stop 生命周期；`L4` 需要相同输入下的 Windows Wallpaper Engine golden。

## 14. 更新规则

1. 新增 SceneScript 代码时先更新对应行的单值等级、代码/测试证据和明确边界；不能用 “VM 能运行 Hello World” 批量升级 API。
2. 一个 handle 的 getter、setter、method 和 lifecycle 可分别处于不同实现阶段；表格拆行不足时必须在“当前证据”里写清已执行成员。
3. 普通 renderer 已有同名能力不等于脚本 API 可用；只有真实 JS -> host -> dynamic snapshot -> consumer 链闭环才可记 `L3`。
4. 官方声明版本变化时，先比较 API diff，再更新本表；声明未定义/注释未使用的成员继续保持 unknown 或 unsupported。
5. 固定样本运行通过只证明没有崩溃和门内指标，不证明其中 SceneScript 已执行。
