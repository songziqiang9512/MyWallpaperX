# Scene 运行输入、Timeline 与属性覆盖表

> 状态：现役专项表
>
> 最近核对：2026-07-29
>
> 本页的 direct dynamic text 实现基线为 `1762743`；精确全局当前状态见 [总覆盖台账](coverage-ledger.md)。
>
> 本专项的 direct text 定向门：`.codex/scene-dynamic-text-targeted-213-final-20260723-1907/report.json`；全局正式门统一见 [运行证据索引](runtime-evidence-index.md)。

本表把 Frame Context、动态目标、Timeline、用户属性、文字、光标、音频、媒体和纹理 provider 放在同一执行合同下。官方语义摘要见 [`runtime-systems-reference.md`](runtime-systems-reference.md)，等级口径见 [`coverage-ledger.md`](coverage-ledger.md)。

## 1. 固定求值合同

同一 host frame 先捕获共享输入，再为每个 surface 独立求值。目标值只能按以下顺序产生：

```text
HostFrameInputs(time, properties, audio, media)
  -> SurfaceFrameContext(viewport, pointer, matrices, providers)
  -> authored base
  -> user property direct binding
  -> Timeline
  -> lifecycle/input/media event dispatch
  -> SceneScript stable-order execution
  -> mutation/type/finite/target validation
  -> immutable SurfaceDynamicSnapshot commit
  -> generation/invalidation reconciliation
  -> renderer / text / particle / provider consumers
```

高优先级输入无效时保留最近一个合法低优先级值；未知目标、重复定义和非有限数值 fail-closed。纹理内容不进入普通 value 字典，只传 provider identity、状态和 generation。共享时间、用户属性、音频和媒体可以在 host 捕获一次；viewport、pointer、矩阵、surface provider、SceneScript 实例和最终 dynamic snapshot 必须按 surface 隔离。

## 2. Frame Context 与动态目标

| 能力 | 等级 | 当前证据 | 当前边界 / 下一门 |
|---|---|---|---|
| 宿主单一 frame driver | `L3` | [`SceneDesktopWallpaperHost.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift)、[`test_scene_frame_context.py`](../../../script/tests/test_scene_frame_context.py)、[E-FRAME](runtime-evidence-index.md#e-frame) | 固定 60 Hz Timer；补屏幕刷新率/目标 FPS |
| 同帧 host/scene/wall time | `L3` | [`SceneFrameContext.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift)、[E-FRAME](runtime-evidence-index.md#e-frame) | 未排除暂停时间，未标 discontinuity |
| shader/video/particle/parallax 共用 timing | `L3` | [`SceneMetalView.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift)、[E-FRAME](runtime-evidence-index.md#e-frame) | 补 pause、delta clamp、fixed step |
| typed value 六类 | `L2` | `bool/scalar/vector2/vector3/vector4/string`；[`SceneDynamicSnapshot.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift) | texture/provider 不属于普通值；新增类型仍需 wire/type/finite 门 |
| typed target 族 | `L2` | scene/camera/layer/effect/text/particle/script instance 已定义；layer alpha/color、exact stock Local Contrast strength 与 exact stock Opacity alpha 进入 compiler | 其他 effect target 不得直接开放 live；SceneScript 值必须与 direct binding 分开 |
| 固定 source priority | `L3` | authored -> property -> Timeline -> SceneScript；property 与受限 Timeline producer 已执行，`.timeline` 覆盖同 target 的 property 值 | SceneScript 尚无 producer，接入后必须复用同一 resolver |
| property binding program persistence | `L3` | format 22 持久化 definitions、instructions、rebuild-required keys 与 effective values；严格 decode/validation | layer alpha/solid color、direct text 三字段、Local Contrast strength 与 Opacity alpha 均有真实 consumer |
| host-shared / surface-local scope | `L3` | property 输入由 host 捕获，每个 surface 有独立 transaction/snapshot/generation；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | pointer/matrix/provider/script 接入后继续补双屏隔离门 |
| target invalidation domain | `L3` | alpha/color/effect scalar 为 value-only；direct text 为 per-layer texture generation；mixed/hidden/no-consumer/SceneScript/unsupported key 标记 rebuild | visibility/topology、通用 provider 和 simulation target 继续登记 |
| per-surface evaluation transaction | `L3` | property 与 Timeline evaluation、validation、同帧合并及 atomic commit 已闭环；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-TIMELINE](runtime-evidence-index.md#e-timeline) | event/SceneScript mutation 尚未接入 |
| changed-target generation | `L3` | 每 surface 持有 generation，相同 payload 不增加；跨 surface 不共享 owner | local input/script/provider 接入后继续验证独立 diff |
| live consumer | `L3` | layer alpha、solid-only color、visible direct text content/point-size/color、strict Local Contrast/Opacity 与 23 处 Timeline effect constant 读取 snapshot；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-TIMELINE](runtime-evidence-index.md#e-timeline) | hidden/no-consumer text、particle/container/non-solid color、SceneScript 与 unsupported Timeline target 仍重建或 fail closed |
| Scene pause/resume | `L0` | 播放控制未控制 Scene clock | pause 冻结 scene time；resume 不补长帧 |
| delta clamp / dropped-time | `L0` | `frameTime` 只做单调差值 | 同时保留 raw delta 和 simulation delta |
| offline fixed-time adapter | `L0` | Debug PNG readback 不是离线 adapter | 注入 frame index/time/seed/provider replay |

B0 live-property 子阶段已从空 snapshot 脚手架合龙到真实 producer/consumer：format 22 在既有 value-only target 上加入 direct text content/point-size/color。文本 consumer 按 layer signature 去重、异步生成、拒绝 stale completion 并保留 last-ready texture；缺少 compiler mapping、有效可见 consumer 或 direct user binding 时继续走 `requestSceneRender` fallback。

## 3. Scene 与 Camera 输入

| 字段/能力 | 等级 | 当前消费 | 缺口 |
|---|---|---|---|
| `general.orthogonalprojection` | `L3` | cover projection 与 canvas size；[E-BASE](runtime-evidence-index.md#e-base) | Windows 多比例像素门 |
| `general.clearcolor` | `L3` | 主 pass clear color；[E-BASE](runtime-evidence-index.md#e-base) | HDR/color-space golden |
| `general.clearenabled` | `L2` | 已进入 descriptor，但 renderer 总会 clear | author-off 正反门与透明背景策略 |
| `general.nearz/farz` | `L3` | image/particle projection 使用并有边界保护；[E-BASE](runtime-evidence-index.md#e-base) | 3D camera 与异常值 golden |
| Camera Parallax enable | `L3` | 只有作者开启时运行；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | Scene options 完整字段 |
| parallax amount/delay | `L3` | smoother 与 layer transform 消费；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | WE 数值/时序标定 |
| parallax mouse influence | `L2` | 字段已进入 offset；当前还叠加 layer-to-camera 静态项，`0` 不保证所有 2D layer 完全不动 | 先锁定 `0` 关闭鼠标驱动的官方反例，再校准非零幅度 |
| per-layer parallax depth / propagation | `L3` | 非零 depth、parent propagation 和阻断；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | effect-local/3D 坐标 golden |
| camera shake | `L1` | binding 名称可分类，renderer 不消费 | 独立 shake 状态和作者启用门 |
| camera zoom / perspective runtime control | `L0` | 无 live target consumer | camera target + projection invalidation |
| environment/gravity/wind | `L0` | Scene general 无对应 IR | 与 particle/puppet/3D solver 共用输入 |
| official Scene Bloom/HDR target identity | `L1` | `.scene(.bloomEnabled/.bloomThreshold)` 已定义；无 binding/producer | 稳定 authored path 和类型定义 |
| official Scene Bloom/HDR runtime | `L0` | 无 producer/consumer 或全场 post | HDR target、tone map、layer HDR brightness |

现有 `SceneBloomPipeline` 是按 layer effect 路径选择的受限近似，不是 `general` 下官方 Scene Bloom/HDR 的实现。

<a id="op-parallax-camera"></a>
### 3.1 [Camera Parallax](https://docs.wallpaperengine.io/en/scene/parallax/introduction.html) 官方合同

官方 Camera Parallax 是 Scene 级作者开关。`Amount`、`Delay` 和 `Mouse influence` 是所有元素共享的输入；启用后每层才获得独立的二维 `Parallax depth`。`Mouse influence = 0` 在 2D Scene 中等价于鼠标不再驱动该效果；逐层 X 或 Y 深度单独设为 `0` 会关闭对应方向，两轴都为 `0` 会关闭该层 Camera Parallax。播放器不得因为自己具备 pointer 能力而替作者开启它。

| 精确合同 | 等级 | 当前代码事实 | 最小升级门 |
|---|---|---|---|
| Scene enable 是全局前置条件 | `L3` | [`SceneLayerParallax.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneLayerParallax.swift) 先检查 `configuration.enabled`；有 author-off 门 | 保持默认关闭，补 cache/重建后的反例 |
| per-axis depth zero | `L3` | X/Y 独立相乘；`xOnly` 与两轴全零有 [`test_scene_layer_parallax.py`](../../../script/tests/test_scene_layer_parallax.py) | 加入负深度、极值和多比例数值门 |
| mouse influence zero | `L2` | mouse 项会归零，但当前公式仍含 layer-to-camera 静态偏移 | 官方零值 fixture 必须对所有普通 2D layer 输出零位移 |
| nonzero mouse influence / delay | `L3` | pointer smoother 和 authored scalar 已消费 | 与 Windows 同输入的幅度、方向和时间曲线 golden |

<a id="op-parallax-oversized"></a>
### 3.2 [Oversized Image](https://docs.wallpaperengine.io/en/scene/parallax/oversized.html) 官方合同

Oversized Image 不是新的 layer/effect 类型，而是作者保留原始大图尺寸、把项目分辨率设为常见桌面尺寸，再调 Camera Parallax strength，使鼠标到四角时可以探索图像但不越出图像边界。官方把边缘覆盖交给作者尺寸和参数，不要求播放器私自 clamp、缩放或补灰底。

| 精确合同 | 等级 | 当前代码事实 | 最小升级门 |
|---|---|---|---|
| authored source size / layer scale 路由 | `L2` | 普通 image geometry 已进入 descriptor/render transform；没有 oversized 专用分支 | 固定大图 fixture 验证四角映射和作者尺寸不被改写 |
| 边缘覆盖与无灰底 | `L2` | cover/clear 与 Camera Parallax 各自存在，但没有 oversized 四角运行门 | 作者合法 strength 下四角均覆盖；不得增加隐式 clamp |

<a id="op-parallax-depth"></a>
### 3.3 [Depth Parallax](https://docs.wallpaperengine.io/en/scene/parallax/depthparallax.html) 官方合同

Depth Parallax 是独立 image effect，依赖 depth map，并且官方要求先全局启用 Camera Parallax。作者通常把该 image layer 的普通 `Parallax depth` X/Y 都设为 `0`，避免 Camera Parallax 位移与 depth-map UV 变形叠加；effect 自身另有 X/Y `Depth`、`Perspective`、`Center` 和 quality/occlusion 选择。生成 depth map 的 Editor Extensions DLC 只属于作者工具，播放器只消费导出资源。

| 精确合同 | 等级 | 当前代码事实 | 最小升级门 |
|---|---|---|---|
| `depthparallax` declaration identity | `L1` | 通用 effect definition 可保留 file/pass/resource，未形成专用 IR | depth map、可选 mask、depth/perspective/center/quality typed contract |
| global Camera Parallax dependency | `L1` | Camera 开关和普通 layer depth 可执行，但未与该 effect 建依赖诊断 | global-off、layer-depth-nonzero 和缺 depth map 均 fail closed |
| depth-map effect runtime | `L0` | 无专用 executor 或 effect-local pointer projection | 基础/24-layer/64-layer profile、X/Y zero、center/perspective 和 author-off pixel gates |

## 4. Timeline

<a id="op-timeline-introduction"></a>
### 4.1 [Introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html)：identity、timebase 与 target axes

Timeline 是带预定义时长的 component-property 动画，不是 Effect animation。官方创建合同包含 mode、从首帧到末帧的 `Seconds`、关键帧槽数量 `Frames`、可选 `Name`、`Start paused` 和 `Wrap loop frames`。目标必须保存 component/object、property 以及 vector axis；例如 `Origin.x` 可以单独动画，隐藏 graph 中的 Y/Z lane 只改变编辑视图，不会把 lane 从 animation 删除。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| dynamic `animation` wrapper presence | `L1` | 粒子 `instanceoverride` 仍只记 `hasAnimation` 并诊断，随包 7 处未进 Timeline IR | 不得冒充 Timeline IR |
| animation identity / optional name | `L1` | 身份由宿主 JSON 路径（layer + host 属性名，或 layer/effect/pass/constant 名）决定；官方 optional name 在随包 48 处中未出现，未保存 | 出现合法 fixture 后补 name 与 owner scope |
| duration seconds / authored frame slots | `L2` | `fps`/`length` 原样保存，时长按 `length / fps` 换算（随包三例交叉验证 1.0s / 0.5s / 0.5s）；`smoothing`/`stiffness` 随包 16 处全为 null，只保真不解释 | 异常值（`length` 与末帧不符）无反例可依 |
| component/property/axis target | `L3` | lane 以 `c0/c1/c2` 对应 component 下标，必须从 `c0` 起连续否则 fail-closed；已 typed 编译为 `.layer(.alpha)` 与 `.effectConstant`，lane 数与值类型不符报 `componentMismatch` | `origin`/`angles`/`scale` 因 `relative` 未执行；`maxwidth`/`zoom` 无 target |
| keyframe frame/time/value | `L2` | `frame`/`value`/`front`/`back`/`lockangle`/`locklength` 六个键在 180 个真实 keyframe 上全部保真；帧号必须严格递增 | 同 frame 多 lane 与异常顺序目前只有负例门，无 Windows 对照 |
| scene-time evaluation | `L3` | 纯函数 evaluator，同一 `sceneTime` 必得同一结果，不持播放状态、不逐帧累加；host 每帧算一次后经 per-surface transaction 写回 | 未接 pause/resume 与 seek |
| wrap-loop frames | `L1` | `wraploop` 已保真（随包 9 处），执行按普通 loop 降级并记 `wrapLoopIgnored` | 官方未公开首尾平滑算法，需合法 fixture |

<a id="op-timeline-combined"></a>
### 4.2 [Combined Animations](https://docs.wallpaperengine.io/en/scene/timeline/combined.html)

Combined Animation 会把新的 property lane 加入一个已有 animation，并复用已有 animation 的 mode、时长和其他设置；它可以同步不同 property 类型和不同 axis。lane 必须保留作者 membership 与稳定顺序。官方页面没有定义两个 lane 写入同一最终 target 时的冲突优先级，因此在取得合法 fixture 前应拒绝歧义，而不是按 dictionary 顺序猜值。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| existing-animation membership | `L1` | `options.parent`/`options.children` 的双向 key 引用已保真；随包唯一实例是 `3768229922` object 55 的 `origin`（`children: [{"key": "zoom"}]`）与 `zoom`（`parent: {"key": "origin"}`），两者共享同一份 options | 组内成员必须共用持有方 clock，分组语义未实现，编译期整组报 `combinedAnimationUnsupported` |
| authored lane order | `L2` | lane 按 `c0/c1/c2` 下标顺序保真；同一 target 被多条 Timeline 写入时全部拒绝并报 `duplicateTarget`，不按声明序或字典序猜 | 官方未定义冲突优先级，维持 fail closed |
| atomic multi-target commit | `L3` | 全部 Timeline 值在同一帧算出后一次性送进 `SceneSurfaceEvaluationTransaction`，与 property 输入同一次原子提交 | 分组语义落地后需补组内同帧一致性门 |

<a id="op-timeline-modes"></a>
### 4.3 [Playback](https://docs.wallpaperengine.io/en/scene/timeline/modes.html) 与 Bézier modes

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| Loop | `L3` | 按 `length` 取模，跨周期同相位；真实执行 7 处 | 与 wrap-loop 平滑开关的联合门待 `wraploop` 落地 |
| Mirror | `L2` | 周期 `2*length` 的三角波，端点不重复采样；单测覆盖折返段与上行段同值 | 随包 6 处 mirror 全落在被 `relative` 拒绝的 layer transform 上，真实样本 0 处执行；端点是否重复采样官方未定义 |
| Single | `L3` | 到末帧后保持末值不回绕；真实执行 21 处 | — |
| start paused | `L3` | 恒停首帧，真实执行 6 处；`2067939514` 为负门（同级脚本在 `mediaThumbnailChanged` 里调 `play()`，无 VM 时不得自动播放） | 与 Scene pause 的分离待 pause/resume 落地 |
| Bézier `both/left/right/none` | `L1` | 每 keyframe 的左右 handle 与 `enabled` 已独立保真 | **求值不消费 tangent，一律线性**：handle 的 `x` 是「帧偏移」还是「归一化段长比例」两种解释不等价（`2067939514` 的 `0→15` 帧段在 frame=3.75 处分别约 0.767 与 0.970，线性 0.5，仅中点因对称巧合相同），需视觉定标后才能宣称 Bézier parity |

<a id="op-timeline-events"></a>
### 4.4 [Animation Events](https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html)

Animation Event 可放在 Timeline 或 Puppet animation 的指定 frame，包含作者名称，同一 frame 可以有多个事件；只有动画穿过该 frame 时才触发。SceneScript handler 必须绑定在播放该 animation 的同一 layer，并通过 `animationEvent(event, value)` 读取 `event.name`。事件可以再控制 layer/effect、sound 或其他 animation，但不能在没有 VM 时被当作已执行。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| event frame/name IR | `L0` | 无 event IR | 保真顺序、同 frame 多事件和 Timeline/Puppet owner identity |
| forward/reverse/loop crossing | `L0` | 无 evaluator/dispatch | 大 delta 不漏发，Mirror 方向和 Loop 边界不重复 |
| same-layer SceneScript dispatch | `L0` | 无 VM 或 event queue | evaluator 后、script update 前稳定排队；单 handler 异常不破坏其他 surface |

第一实现批必须先完整保存 identity、target axis、keyframe、mode、tangent、combined lane 和 event，再接 scalar/vector evaluator；不能只从 `duration` 或截图推测动画。

## 5. User Property 定义与面板

<a id="op-user-overview"></a>
### 5.1 [Overview](https://docs.wallpaperengine.io/en/scene/userproperties/overview.html)、共享绑定、Group 与 Display Condition

User Property 是 wallpaper 级 key/value，不属于某个单独 layer。一个 key 可以被多个作者目标共享；运行时必须对同一有效值做 fan-out，不能复制成彼此漂移的控件。Group 是线性分段标记：它包含其后全部 property，直到下一个 Group；第一个 Group 之前的 property 不分组，Group 本身没有运行值。Display Condition 的公开形态是 `propertyKey.value == literal`，Checkbox 使用 `true/false`，Combo 使用 option 的隐藏 value；它只控制面板可见性，不能删除或重置隐藏 property 的值。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| wallpaper-level property key/catalog | `L3` | 定义、默认值、override、排序和持久化已存在；[E-PROPERTY](runtime-evidence-index.md#e-property) | 稳定 wire schema 与跨版本 migration |
| one key -> multiple authored targets | `L3` | binding program 保留 fan-out；layer alpha 多 target 原子提交，strict catalog target 可加入同一原子 transaction，混合 target 整 key 重建 | 其他 target 逐项补真实 consumer 与 failure isolation |
| linear Group boundary | `L3` | [`SteamWorkshopSceneService+SceneProperties.swift`](../../../MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift) 按下一个 Group 截止 | 大型表单和空 group UI 门 |
| `key.value == bool/comboValue` condition | `L3` | 复用受控 condition evaluator；隐藏不删除值；[E-PROPERTY](runtime-evidence-index.md#e-property) | 只承诺已测 equality 子集，不扩张成任意表达式 |
| default / override / reset | `L3` | authored fallback 与 wallpaper-scoped override/reset；layer alpha、solid color、direct text、strict Local Contrast/Opacity 可 live，texture bookmark 或非 live key 重建；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | 跨重启 UI 自动门 |
| first/change-only `applyUserProperties` | `L0` | 无 SceneScript event | 首次发送全量，后续 payload 只含变化 key，顺序确定 |

<a id="op-user-color"></a>
### 5.2 [Color](https://docs.wallpaperengine.io/en/scene/userproperties/color.html) 与 Scheme Color

官方 Editor 会为每个 wallpaper 默认加入 Scheme Color；作者既可新建 color property，也可把多个 effect/target 绑定到同一个 Scheme Color 或自定义 color key。MyWallpaperX 当前只会解析导出文件里实际存在的普通 color definition，不会在缺失时合成 Scheme Color，也没有 Scheme Color 专用 scope。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| ordinary `color` definition/control | `L3` | UI、字符串值和持久化可用；[E-PROPERTY](runtime-evidence-index.md#e-property) | 颜色空间、全部 target 与 live snapshot |
| `schemecolor` exported identity | `L1` | 若导出为普通 color definition 可被 generic parser 识别 | 明确 built-in identity/default/scope；缺失时是否合成需合法 fixture |
| shared color target fan-out | `L2` | 重复 binding 可保留，只有受支持白名单经整场重建应用 | 多 effect/layer 同帧原子更新和颜色类型验证 |

<a id="op-user-slider"></a>
### 5.3 [Slider](https://docs.wallpaperengine.io/en/scene/userproperties/slider.html)

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| default/min/max/fraction/precision UI | `L3` | min/max/step/fraction/precision、UI 和持久化；[E-PROPERTY](runtime-evidence-index.md#e-property) | authored range/step validation 与 live value |
| numeric target update | `L2` | layer alpha slider 与 exact `brcontraststrength` 已 typed/clamp/live；其余 numeric target 仍重建 | 每个 target 分别补 compiler semantic 与 consumer 后才能升级 |

<a id="op-user-checkbox"></a>
### 5.4 [Checkbox](https://docs.wallpaperengine.io/en/scene/userproperties/checkbox.html)

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| `bool` control/value | `L3` | UI、条件值、持久化和受支持 visibility/boolean target；[E-PROPERTY](runtime-evidence-index.md#e-property) | live target program；不得按 property 名猜 effect |
| conditional target expected value | `L3` | binding 保存 `condition` 并比较实际 bool/value | 完整类型不匹配和 fallback 反例 |

<a id="op-user-combo"></a>
### 5.5 [Combo](https://docs.wallpaperengine.io/en/scene/userproperties/combo.html)

Combo option 的显示 label 与 hidden value 是两个字段；binding、Display Condition 和 SceneScript 都必须得到 hidden value，不能把本地化 label 当协议值。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| ordered label + hidden value options | `L3` | option label/value、条件和持久化已分离；[E-PROPERTY](runtime-evidence-index.md#e-property) | 重复 hidden value、未知当前值和本地化负向门 |
| combo conditional binding | `L3` | 与 authored option value 比较后控制受支持 target | 编译 target program；不能比较 label |

<a id="op-user-text"></a>
### 5.6 [Text Input](https://docs.wallpaperengine.io/en/scene/userproperties/text.html)

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| `textinput` control/value | `L3` | UI、默认值和持久化；[E-PROPERTY](runtime-evidence-index.md#e-property) | Unicode 长度/invalid text policy |
| real-time text target update | `L3` | direct content/point-size/color 经 per-surface snapshot 和 per-layer async generation 更新；重复值去重，stale/failed completion 不替换 last-ready texture；[E-DYNAMIC-TEXT](runtime-evidence-index.md#e-dynamic-text) | SceneScript/time/media producer、长文本布局和 Windows golden |
| author `text` label | `L3` | 只读面板内容；[E-PROPERTY](runtime-evidence-index.md#e-property) | 它不是可写 runtime property |

<a id="op-user-texture"></a>
### 5.7 [Texture](https://docs.wallpaperengine.io/en/scene/userproperties/texture.html)

官方 Texture property 可替换 image layer、effect mask 或 particle texture，允许兼容的 image/video；用户未选择文件时必须使用作者导入的 texture。替换 texture 不会自动重做作者 effect 或 mask，因此播放器必须继续使用原有 graph/mask，不能根据新图片内容猜适配。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| `texture` / observed `scenetexture` identity | `L1` | 两种 raw type 归一并保留 runtimeType | 只证明当前 parser 兼容归一，不宣称所有版本 schema 等价 |
| PNG/JPEG picker/bookmark/provider | `L3` | security scope、decode、per-screen upload 和受限 static image-blend consumer；[E-PROVIDER](runtime-evidence-index.md#e-provider) | cancellation、更多格式和通用 material |
| authored texture fallback | `L3` | property absent/unavailable 时受限 candidate 回退作者 layer；[E-PROVIDER](runtime-evidence-index.md#e-provider) | 推广至 image albedo/effect mask/particle/material 全目标 |
| generic image/video replacement targets | `L0` | effect mask、particle texture、video 和普通 albedo 没有通用 consumer | target/slot identity、自动尺寸映射、格式、generation 和 teardown |

<a id="op-user-texture-variants"></a>
### 5.8 [Texture Variants](https://docs.wallpaperengine.io/en/scene/userproperties/texturevariant.html)

Texture Variant 只能由 Checkbox/Combo User Property 控制，不能由 SceneScript 切换。variant 与 base 必须同为 image 或同为 video，并具有相同分辨率；每个 variant group 同时只显示一个 texture。Combo 多选时应保留一个未分配 option 代表 base texture。`Replace` 与 `Alpha-blended` 是不同合成语义；透明叠加元素要使用独立 group，因为一个 group 不会同时显示两个 variant。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| variant group/option/condition IR | `L0` | 无 schema | group order、Checkbox/Combo hidden value 和 base option |
| type/resolution compatibility | `L0` | 无 validation | image/video 同类型同分辨率正反 fixture |
| one-active-per-group selection | `L0` | 无 selector/provider identity | base fallback、未匹配值和 property generation |
| Replace / Alpha-blended compose | `L0` | 无 executor | 独立 group、alpha/premultiply/order pixel gates |
| SceneScript mutation prohibition | `L0` | 无 VM；未来 API 不得暴露 variant setter | API surface negative test |

<a id="op-user-shortcut"></a>
### 5.9 [User Shortcut](https://docs.wallpaperengine.io/en/scene/userproperties/usershortcut.html)

User Shortcut 可由用户绑定 file、directory、web page 或 console command，但只能通过 SceneScript cursor click 调用 `engine.openUserShortcut(key)`；一次 click/up/down CursorEvent 只允许执行一个 command，重叠 layer 需要作者关闭 click propagation。shortcut 绑定到本机，不能跨电脑共享，也不进入 wallpaper preset，用户必须逐机配置。可选 icon 可作为 texture，`applyUserProperties` payload 通过 `isbound` 和 `file` 暴露绑定状态/label。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| `usershortcut` definition/persistence | `L0` | parser 归入 unsupported | macOS 类型/授权、逐机存储、preset 排除和安全 UI |
| cursor-triggered open | `L0` | 无 pointer click、SceneScript VM 或 host API | 单事件单命令、click propagation 和 invalid key 门 |
| shortcut icon provider | `L0` | 无 shortcut provider | bound/unbound generation、square icon fallback 和取消 |
| `isbound` / `file` change payload | `L0` | 无 `applyUserProperties` event | first/full 与 change-only payload、隐私与屏保策略 |

当前 21 样本 census：424 definitions、952 bindings、195 条 conditional bindings。定义/绑定总数只证明扫描覆盖，不能证明所有 target 可调。

## 6. User Property target 矩阵

| target 族 | 观察数量 | 当前分类/执行 | 等级 | 下一门 |
|---|---:|---|---|---|
| layer visibility | 230 | 可分类；受支持 key 通过文档改写和整场重建生效；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | 编译 target program；visibility graph invalidation |
| text content/point size/color | 267 | direct binding 编译为 typed text target；有效可见层经 per-layer generation 无重建更新，hidden/no-consumer 整 key 重建；[E-DYNAMIC-TEXT](runtime-evidence-index.md#e-dynamic-text) | `L3` | SceneScript/system/media producer与 Windows layout golden |
| camera binding family | 5 | 字段名可识别；整族没有统一 executor | `L1` | typed compiler 分出可执行与 unsupported |
| camera parallax actionable subset | 3 | 当前白名单经重建生效；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | live camera target 和无重建门 |
| camera shake subset | 2 | 可识别但 renderer 不消费 | `L1` | shake state/evaluator 和 author-off |
| effect visibility family | 129 | target path 可识别；原 20 条白名单加 2 条 exact stock Local Contrast visibility target 可操作 | `L1` | authored effect ID 和完整 compiler |
| effect visibility actionable subset | 22 | 20 条旧白名单经重建生效；`2902406982` layers `167/177` 的 Local Contrast visibility 始终保留在面板，关闭后仍可重开；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | topology invalidation 和完整条件门 |
| shader constant family | 122 | UserPropertyBindings census 保留 target path/value；v22 继承 Local Contrast/Opacity strict target | `L1` | typed uniform/pass identity 和完整 compiler |
| shader constant actionable subset | 20 + 4 strict | census 的 19 条旧白名单经重建进入受限 executor，Local Contrast strength 与 `2902406982:[365,372,647,664]` stock Opacity alpha live 消费 snapshot；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | generic executor、SceneScript 与通用 live uniform |
| layer alpha | 73 | 编译为 `.layer(.alpha)`；image/solid/text 读取 per-surface snapshot，当前 census 没有 particle/utility alpha binding；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | 扩展到新 layer kind 前先补对应 consumer；mixed/no-consumer 继续重建 |
| layer color | 73 | 全部目标为 solid；25 条纯 color key 由 snapshot/tint live 消费并在属性面板开放，48 条 `basecolor` 因同键含未支持目标整场重建；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | 补颜色空间/premultiply golden；non-solid/mixed target 继续 fail closed |
| script instance properties | 43 | 路径存在；不保存源码/绑定程序 | `L1` | 编译 `.scriptInstanceProperty`，等待 VM consumer |
| particle instance override | 6 | authored 静态 override 可消费；动态 binding 未分类 | `L1` | alpha/count/size/speed/color typed target |
| Scene bloom/threshold target identity | 2 | `.scene(.bloomEnabled/.bloomThreshold)` 已定义，binding 尚未分类 | `L1` | 稳定 authored path、type 与 scope |
| Scene bloom/threshold binding/runtime | 2 | 无 binding compiler、producer 或 Scene post consumer | `L0` | target program + HDR post chain |
| layer scale | 1 | binding 未分类；静态 transform 可执行 | `L1` | typed transform target 与 frame geometry |
| sound volume target identity | 1 | `.layer(.volume)` 已定义，binding 未分类 | `L1` | binding compiler 和 sound owner identity |
| sound volume runtime | 1 | 无 sound IR/player | `L0` | playback/lifecycle 后再开放 |

当前旧 census 的 unsupported 统计仍需在 v22 上重算。已确认 alpha/color、Local Contrast、Opacity 与 direct text 三类 target 进入 binding program；`2134765860` 的 content/point-size/color 正门与 `2938612768` SceneScript Opacity 负门分别保持。mixed、hidden/no-consumer、non-solid color、其他 shader constant 和 unsupported key 仍由 rebuild/fail-closed 路径处理。

## 7. Text

| 能力 | 等级 | 当前边界 | 下一门 |
|---|---|---|---|
| static content raster | `L3` | CoreText 启动时栅格；[E-TEXT](runtime-evidence-index.md#e-text) | dynamic layer texture store |
| package/system font resolution | `L3` | 包内字体、8 个官方 `systemfont_*` 别名，15 个客户端 stock 名字全部随包真实字体（8 原版 `stockBundled` / 7 替代 `stockSubstituted`；stock 41/alias 19/包内 184/未知 0）；[E-TEXT-FONTREF](runtime-evidence-index.md#e-text-fontref) | 7 个替代字形非官方轮廓；原版无 Windows 栅格化逐像素对照；family/weight/CJK/emoji golden |
| point size | `L3` | authored `pointsize * 300 / 72` 官方 300 DPI 换算；[E-TEXT-POINTSIZE](runtime-evidence-index.md#e-text-pointsize) | Windows 逐像素对照、去掉本地 1024 px 字号夹取 |
| alignment/baseline/padding | `L2` | 部分字段/geometry 进入链路 | 每种 alignment 正反像素门 |
| row/width overflow limits | `L3` | `limitrows`/`maxrows`/`limitwidth`/`maxwidth`/`limituseellipsis` 进 IR 并由 CoreText 消费，两个数值只在对应开关打开时生效（语料 393 个关闭态带默认 `maxwidth: 500`，79 个已超宽）；[E-TEXT-LIMITS](runtime-evidence-index.md#e-text-limits) | Windows 逐像素对照省略号回退与断点、按运行时文本重新测量外框 |
| color/alpha | `L3` | 静态 descriptor 和 direct color generation consumer；[E-DYNAMIC-TEXT](runtime-evidence-index.md#e-dynamic-text) | premultiplied alpha 与 Windows golden |
| outline/shadow/text effects | `L1` | 可见字段/effect 可能被保留 | 独立 style IR 与执行器 |
| property-driven dynamic text | `L3` | 只更新变化 layer，重复值不生成，旧 generation/失败结果不覆盖 last-ready；真实 `2134765860` 三字段正门 | 长文本/emoji/多语言布局与多屏压力门 |
| SceneScript clock/date/media text | `L0` | 无 VM 或 media snapshot | Date/media producer -> text target -> texture generation |
| dynamic Layer Image particle source | `L0` | 无 emission bitmap refresh | 只在 text texture 变化时更新 emission source |

## 8. Cursor、Audio 与 Media

| 输入/provider | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| current pointer bounded projection | `L3` | view-normalized -> scene world，以及忽略 parent/rotation/scale/parallax 的 axis-aligned authored layer UV；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | 完整层级逆矩阵前不得宣称通用 layer-local |
| full layer/effect/control-point local pointer | `L0` | 无 parent/world inverse 或 effect/control-point 投影 | hierarchy/rotation/scale/parallax 正反 golden |
| previous pointer storage | `L2` | Frame Context 保存；renderer 未消费 | shader built-in 和 event delta consumer |
| pointer buttons/down/up/click | `L0` | 无状态或事件队列 | 同帧 event snapshot 与坐标空间 |
| audio declarations | `L3` | effect 与粒子两套 schema 分别保真解析（字段名不同，粒子无 `audioamount`）；[E-AUDIO-EFFECT](runtime-evidence-index.md#e-audio-effect) | 粒子声明保真不等于可执行 |
| 16 stereo buffers | `L3` | left/right host-shared 快照每帧广播给所有 surface，静音/无权限稳定归零；stock effect 与 strict relocated Simple Audio Bars stereo up/down profile 已消费；[E-AUDIO-INPUT](runtime-evidence-index.md#e-audio-input) | 频段划分与归一化是工程选择，无官方数值合同；采集 30 Hz 与渲染 60 Hz 之间不插值 |
| 32/64 stereo buffers | `L3 bounded` | 与 16 档由同一次 FFT 生成并进入 host-shared snapshot；只供 exact Simple Audio Bars `32+CLIP_LOW` / `64+CLIP_HIGH` profile；[E-AUDIO-INPUT](runtime-evidence-index.md#e-audio-input) | 其他 Workshop shader 与 SceneScript `registerAudioBuffers` 尚无 consumer/bridge，不外推 |
| audio `average` 缓冲 | `L0` | host snapshot 只有 left/right；没有 SceneScript `AudioBuffers` object 或 `average` consumer | 由 SceneScript bridge 在同一帧、同一分辨率从左右声道建立受控数组，并验证对象/数组生命周期 |
| audio consumer registration/lifecycle | `L3` | 采集由 consumer 存在性驱动，launch 声明/teardown 撤销，暂停/锁屏/休眠停采并归零 | 新增 consumer 必须同批扩充判定，否则采集不会启动 |
| media status/playback/properties/timeline | `L0` | 无 snapshot | 可注入 provider 和原子 generation |
| generic media thumbnail identity | `L1` | `$mediaThumbnail` runtime reference 可分类 | current/previous typed identity、producer、decode cancellation、authored fallback |
| media events | `L0` | 无 SceneScript dispatch | 每屏队列、顺序和异常隔离 |

Scene 不复用 Web 的固定 FFT 频段/频率合同；SceneScript 按作者选择 16、32 或 64 bins，并在 render frame 更新。

官方 [IEngine.registerAudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) 只接受 16/32/64 三档，[AudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) 的 `left`/`right`/`average` 等长数组按帧自动更新、由低频排到高频，数值通常在 0...1 但允许超过 1；shader 侧 [Audio globals](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 同样明确为正值且不归一化。当前 16/32/64 host snapshot 满足 renderer consumer 的输入形状，但没有 SceneScript VM、engine method、`average` 数组或脚本订阅，因此不能据此升级任何 SceneScript API。

<a id="op-media-overview"></a>
### 8.1 [Audio Visualizer](https://docs.wallpaperengine.io/en/scene/audiovisualizer/overview.html) 资料边界

官方 Audio Visualizer overview 明确仍在建设，目前只公开 Album Cover 和 Media Playback 两篇作者指南。这两个页面不能反向证明完整 audio visualization、FFT 映射或 Windows media backend 私有行为；Scene 的频谱、媒体和 Web audio 合同继续分开建账。

<a id="op-media-information"></a>
### 8.2 [Media Information](https://docs.wallpaperengine.io/en/scene/audiovisualizer/mediainformation.html) 与动态文字

官方通过 SceneScript media events 提供 title、album title、artist、playback/status、timeline 和 thumbnail 派生颜色，但媒体播放器或文件可能不提供某些 metadata。作者必须允许字段缺失。动态媒体文字可能很长，官方要求用 text `Point size` 调字号，不用 layer `Scale` 降低清晰度，并配置 left alignment、`Max width`、`Max rows` 和可选 overflow ellipsis。Playback `stopped` 与 `paused` 不同；官方隐藏示例只在 stopped 时隐藏，paused 仍显示。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| status/playback/properties/timeline snapshot | `L0` | Scene 没有 media snapshot | 可注入、同 host frame 原子 generation，missing field 保留 nil/fallback |
| media property events | `L0` | 无 SceneScript VM/dispatch | title/albumTitle/albumArtist 等 typed event 和逐 surface queue |
| missing metadata fallback | `L0` | 无 producer/consumer | 缺字段不得保留上一首错误文本；作者 fallback/空值策略可测 |
| media text layout constraints | `L0` | 静态 text 有部分 layout，但没有 media-driven text | point size、max width/rows、ellipsis 和长 Unicode title golden |
| stopped versus paused visibility | `L0` | 无 playback state consumer | 枚举映射、初始 stopped、paused 保持可见和恢复顺序 |
| thumbnail derived colors | `L0` | 无 `MediaThumbnailEvent`；layer Bloom/clear color 不等价 | primary/text/其他公开色值与无 thumbnail fallback |
| authored color transition | `L0` | 无 media event + SceneScript update | 由作者脚本按 `engine.frametime` 插值；host 不得默认套 transition |

<a id="op-media-album-cover"></a>
### 8.3 [Current / Previous Album Cover](https://docs.wallpaperengine.io/en/scene/audiovisualizer/albumcover.html)

官方 Album Cover binding 明确区分 `Current album cover` 和 `Previous album cover`。没有媒体或封面时作者 placeholder 必须继续可见；建议封面使用方形 `100x100...256x256`，不把高分辨率封面当作可靠输入。平滑换封面不是 provider 自动效果：官方配方是 current cover 作为当前图，previous cover 绑定到 Blend/Blend Gradient 输入，再由 `Single`、`Start paused` 的 Timeline 控制 Blend amount，并在 `mediaThumbnailChanged` 中播放 animation。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| `$mediaThumbnail` generic reference | `L1` | system texture reference 可分类；没有 producer/consumer | 升级前先分出 current/previous，不把单 identity 同时冒充两者 |
| current cover identity/provider | `L0` | 无 current typed identity 或 frame publication | hasThumbnail、ready/pending/unavailable、generation 和 decode cancel |
| previous cover identity/provider | `L0` | 无 previous typed identity/history | 新封面提交时原 current 原子转为 previous；stop/reset 清空 |
| authored placeholder fallback | `L0` | system/media 尚未接现有 fallback consumer | 无播放、无封面、decode 失败均回退作者 texture/solid，不显示空白 |
| authored cover transition graph | `L0` | 通用 Timeline evaluator 已有，但仍缺 current/previous cover、Blend 通用 consumer、media event 与 SceneScript restart | 新 thumbnail event -> restart Single animation；缺封面不误触发 |
| recommended cover extent policy | `L0` | 无 media decode/resize policy | 保持 aspect、方形目标、<=256 建议与异常输入预算门 |

## 9. Texture / Video provider

| provider 能力 | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| layer/named/property identity/status/generation | `L3` | 受限 provider 有 ready/pending/unavailable；静态 resource generation 与 named frame epoch 分离；[E-PROVIDER](runtime-evidence-index.md#e-provider) | 显式 dynamic generation、metadata 与通用 producer/consumer 生命周期 |
| authored fallback chain | `L3` | 受限 static image blend；[E-PROVIDER](runtime-evidence-index.md#e-provider) | 推广至 material/effect/nested consumer |
| property PNG/JPEG | `L3` | bookmark/security scope/decode/per-screen upload；[E-PROVIDER](runtime-evidence-index.md#e-provider) | cancellation、更多格式、通用 material |
| embedded MP4 image layer | `L3` | TEX payload 播放并消费共享 host time；[E-VIDEO](runtime-evidence-index.md#e-video) | pause/seek/loop/switch 精确合同 |
| video as generic material provider | `L0` | 无 slot consumer | typed frame provider 与 generation |
| named primary variant producer | `L3` | bounded `_a` current-frame publication；[E-UTILITY](runtime-evidence-index.md#e-utility) | 通用 target/extent/format |
| named secondary variant identity | `L2` | registry identity 保留 `_b` | producer/consumer flow 尚未执行 |
| Texture Variant provider | `L0` | 无 variant schema/selection | property selection + authored fallback |
| system/media provider identity | `L1` | enum/reference 脚手架 | producer、consumer、teardown |
| generic material slots `0...7` | `L2` | nullable hole、candidate order、combo 保留 | shader annotation 驱动 slot type 与 ready selection |

## 10. 下一实现顺序

1. **B0 live-property 与首个 generation consumer 已完成**：format 22 binding program、per-surface transaction、atomic state，以及 layer alpha、solid color、direct text、Local Contrast/Opacity consumer 均已闭环；隔离真实样本证明 live 更新不替换 surface/window。
2. 新增任何 live target 时，必须在同一能力切片中补稳定 identity/value semantic、compiler definition/instruction、真实 renderer/runtime consumer、原子失败、fallback 与 identity 运行门；缺一项就保留整场重建。
3. B2 ordered strict scheduler、exact Workshop Shadow 与 stock Opacity `MASK=0` 已完成。`2902406982:[365,372,647,664]` 是 direct-binding live 正门；`2938612768:[165,454,626,629,924]` 是 SceneScript fail-closed 负门。optional mask、未知 fingerprint 或缺 consumer 的部分 live 继续拒绝。
4. B2 同帧 copy/swap foundation、受限 history seed、Precise Blur interleave 与 stock Radial God Rays 双 half RT 已完成；真实 persistent/history consumer、generic compose 与 provider generation/cancel 仍未完成。
5. Timeline 的 IR、绝对 scene-time evaluator 和 28/48 typed target 子集已接入；`relative`、Combined、tangent、其余 target 与 event crossing 继续 fail closed。SceneScript 只有在 source/binding IR 和沙箱成立后接入同一 target 层。
6. 16/32/64 档 audio provider 已有 consumer 驱动、失败归零和 teardown 门；当前只开放 stock effect 与三个 exact Workshop Audio Bars profile。新增 renderer consumer、SceneScript `AudioBuffers` bridge/`average` 或 media provider仍须同批补作者未启用反例、fallback、generation/cancel 和 stop teardown。
