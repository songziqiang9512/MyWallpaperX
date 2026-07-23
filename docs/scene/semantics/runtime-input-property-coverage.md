# Scene 运行输入、Timeline 与属性覆盖表

> 状态：现役专项表
>
> 最近核对：2026-07-23
>
> 实现基线：`95e0d58`

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
| 宿主单一 frame driver | `L3` | [`SceneDesktopWallpaperHost.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDesktopWallpaperHost.swift)、[`test_scene_frame_context.py`](../../../script/tests/test_scene_frame_context.py)、[E-FRAME](runtime-evidence-index.md#e-frame) | 固定 60 Hz Timer；补屏幕刷新率/目标 FPS |
| 同帧 host/scene/wall time | `L3` | [`SceneFrameContext.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneFrameContext.swift)、[E-FRAME](runtime-evidence-index.md#e-frame) | 未排除暂停时间，未标 discontinuity |
| shader/video/particle/parallax 共用 timing | `L3` | [`SceneMetalView.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalView.swift)、[E-FRAME](runtime-evidence-index.md#e-frame) | 补 pause、delta clamp、fixed step |
| typed value 六类 | `L2` | `bool/scalar/vector2/vector3/vector4/string`；[`SceneDynamicSnapshot.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDynamicSnapshot.swift) | texture/provider 不属于普通值；新增类型仍需 wire/type/finite 门 |
| typed target 族 | `L2` | scene/camera/layer/effect/text/particle/script instance 已定义；layer alpha/color 进入 compiler | effect 等尚未持久化稳定 authored identity，不得直接开放 live |
| 固定 source priority | `L2` | authored -> property -> Timeline -> SceneScript；property producer 已执行 | Timeline/SceneScript 尚无 producer，接入后必须复用同一 resolver |
| property binding program persistence | `L3` | format 18 持久化 definitions、instructions、rebuild-required keys 与 effective values；严格 decode/validation | 当前只证明 alpha/color 编译，不能替代真实 consumer |
| host-shared / surface-local scope | `L3` | property 输入由 host 捕获，每个 surface 有独立 transaction/snapshot/generation；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | pointer/matrix/provider/script 接入后继续补双屏隔离门 |
| target invalidation domain | `L2` | layer alpha 为 value-only；mixed/invalid/unsupported key 标记 rebuild | geometry/text/topology/provider/simulation target 逐项集中登记 |
| per-surface evaluation transaction | `L3` | property evaluation、validation 与 atomic commit 已闭环；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | event/Timeline/SceneScript mutation 尚未接入 |
| changed-target generation | `L3` | 每 surface 持有 generation，相同 payload 不增加；跨 surface 不共享 owner | local input/script/provider 接入后继续验证独立 diff |
| live consumer | `L3` | image/solid/text 与 `shouldCapture` utility 的 layer alpha、solid-only color 读取 snapshot；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | particle/container/non-solid color/mixed/unsupported/no-consumer 均整场重建 |
| Scene pause/resume | `L0` | 播放控制未控制 Scene clock | pause 冻结 scene time；resume 不补长帧 |
| delta clamp / dropped-time | `L0` | `frameTime` 只做单调差值 | 同时保留 raw delta 和 simulation delta |
| offline fixed-time adapter | `L0` | Debug PNG readback 不是离线 adapter | 注入 frame index/time/seed/provider replay |

B0 live-property 子阶段已从空 snapshot 脚手架合龙到真实 producer/consumer：binding program 以 format 18 持久化，host 对每个 surface 独立求值，属性更新原子提交，支持的 layer alpha 与纯 solid color 不再触发整场重建。这个结论不扩张到 non-solid/mixed color、particle、container、Timeline 或 SceneScript；其中任一 target 缺少 compiler mapping 或真实 consumer 时必须继续走 `requestSceneRender` fallback。

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
| Scene enable 是全局前置条件 | `L3` | [`SceneLayerParallax.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneLayerParallax.swift) 先检查 `configuration.enabled`；有 author-off 门 | 保持默认关闭，补 cache/重建后的反例 |
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
| dynamic `animation` wrapper presence | `L1` | 部分粒子值记录 `hasAnimation` 并诊断 | 不得冒充 Timeline IR |
| animation identity / optional name | `L0` | 未保存正式 Timeline identity 或 name | 稳定 animation ID、作者名称和 owner scope |
| duration seconds / authored frame slots | `L0` | 未保存 | seconds、frame count、首末 frame 和异常值保真 |
| component/property/axis target | `L0` | 未保存 Timeline target | 编译成 object + component + property + optional axis typed target |
| keyframe frame/time/value | `L0` | 未保存 | 保真 parse/encode、同 frame 多 lane 和异常顺序门 |
| scene-time evaluation | `L0` | Frame Context 有 scene time，但 Timeline 未消费 | 按绝对 scene time 求值；不得按显示刷新逐步前进 |
| wrap-loop frames | `L0` | 无 loop shaping IR | 首尾平滑过渡和关闭时允许瞬时回跳的数值门 |

<a id="op-timeline-combined"></a>
### 4.2 [Combined Animations](https://docs.wallpaperengine.io/en/scene/timeline/combined.html)

Combined Animation 会把新的 property lane 加入一个已有 animation，并复用已有 animation 的 mode、时长和其他设置；它可以同步不同 property 类型和不同 axis。lane 必须保留作者 membership 与稳定顺序。官方页面没有定义两个 lane 写入同一最终 target 时的冲突优先级，因此在取得合法 fixture 前应拒绝歧义，而不是按 dictionary 顺序猜值。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| existing-animation membership | `L0` | 无 animation/lane identity | 多 property 共用一份 clock/settings，lane 仍有独立 target/keyframes |
| authored lane order | `L0` | 无 Combined IR | 保真顺序和 canonical encode；重复 target 先 fail closed |
| atomic multi-target commit | `L0` | 无 Timeline producer | 同一 frame 的全部 lane 一次写入 SurfaceDynamicSnapshot |

<a id="op-timeline-modes"></a>
### 4.3 [Playback](https://docs.wallpaperengine.io/en/scene/timeline/modes.html) 与 Bézier modes

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| Loop | `L0` | 无 evaluator | 运行到末尾后立即回到开头；与 wrap-loop 平滑开关分别测试 |
| Mirror | `L0` | 无 evaluator | 到末尾后按相同速度反向，端点不得重复或跳帧 |
| Single | `L0` | 无 evaluator | 只播放一次并永久保持最后状态 |
| start paused | `L0` | 无 Timeline state | 初始不推进，必须由 SceneScript 手动播放；与 Scene pause 分离 |
| Bézier `both/left/right/none` | `L0` | 无 tangent IR/evaluator | 每 keyframe 独立保存左右 handle；`none` 产生直线匀速段 |

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
| one key -> multiple authored targets | `L3` | binding program 保留 fan-out；layer alpha 多 target 原子提交，混合 target 整 key 重建 | 其他 target 逐项补真实 consumer 与 failure isolation |
| linear Group boundary | `L3` | [`SteamWorkshopSceneService+SceneProperties.swift`](../../../MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift) 按下一个 Group 截止 | 大型表单和空 group UI 门 |
| `key.value == bool/comboValue` condition | `L3` | 复用受控 condition evaluator；隐藏不删除值；[E-PROPERTY](runtime-evidence-index.md#e-property) | 只承诺已测 equality 子集，不扩张成任意表达式 |
| default / override / reset | `L3` | authored fallback 与 wallpaper-scoped override/reset；纯 layer alpha 可 live，texture bookmark 或非 live key 重建；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | 跨重启 UI 自动门 |
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
| numeric target update | `L2` | layer alpha slider 已 typed/clamp/live；其余 numeric target 仍重建 | 每个 target 分别补 compiler semantic 与 consumer 后才能升级 |

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
| real-time text target update | `L2` | 180 ms debounce 后整场重建可见 | per-layer texture generation、cancel 和同帧 snapshot |
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
| text content/point size/color | 267 | 可分类；受支持 key 重建 text texture；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | per-layer texture generation，无整场重建 |
| camera binding family | 5 | 字段名可识别；整族没有统一 executor | `L1` | typed compiler 分出可执行与 unsupported |
| camera parallax actionable subset | 3 | 当前白名单经重建生效；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | live camera target 和无重建门 |
| camera shake subset | 2 | 可识别但 renderer 不消费 | `L1` | shake state/evaluator 和 author-off |
| effect visibility family | 129 | target path 可识别，只有 20 条白名单 actionable | `L1` | authored effect ID 和完整 compiler |
| effect visibility actionable subset | 20 | 当前白名单经重建生效；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | topology invalidation 和完整条件门 |
| shader constant family | 122 | target path/value 可保留，只有 19 条白名单 actionable | `L1` | typed uniform/pass identity 和完整 compiler |
| shader constant actionable subset | 19 | 当前白名单经重建进入受限 executor；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | generic executor 与 live uniform |
| layer alpha | 73 | 编译为 `.layer(.alpha)`；image/solid/text 读取 per-surface snapshot，当前 census 没有 particle/utility alpha binding；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | 扩展到新 layer kind 前先补对应 consumer；mixed/no-consumer 继续重建 |
| layer color | 73 | 全部目标为 solid；25 条纯 color key 由 snapshot/tint live 消费并在属性面板开放，48 条 `basecolor` 因同键含未支持目标整场重建；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | 补颜色空间/premultiply golden；non-solid/mixed target 继续 fail closed |
| script instance properties | 43 | 路径存在；不保存源码/绑定程序 | `L1` | 编译 `.scriptInstanceProperty`，等待 VM consumer |
| particle instance override | 6 | authored 静态 override 可消费；动态 binding 未分类 | `L1` | alpha/count/size/speed/color typed target |
| Scene bloom/threshold target identity | 2 | `.scene(.bloomEnabled/.bloomThreshold)` 已定义，binding 尚未分类 | `L1` | 稳定 authored path、type 与 scope |
| Scene bloom/threshold binding/runtime | 2 | 无 binding compiler、producer 或 Scene post consumer | `L0` | target program + HDR post chain |
| layer scale | 1 | binding 未分类；静态 transform 可执行 | `L1` | typed transform target 与 frame geometry |
| sound volume target identity | 1 | `.layer(.volume)` 已定义，binding 未分类 | `L1` | binding compiler 和 sound owner identity |
| sound volume runtime | 1 | 无 sound IR/player | `L0` | playback/lifecycle 后再开放 |

当前 53 个 unsupported bindings 的构成为 script properties 43、particle override 6、Scene Bloom 2、scale 1、volume 1。alpha 73 与 color 73 均已进入 binding program；alpha 和 25 条纯 solid color 指令已有真实 consumer 并可 live。旧 resolver/rebuild 继续覆盖 `basecolor` 的 48 条 mixed 指令、non-solid color、unsupported 和无活动 consumer 的 key，不能因 compiler 已识别 target 就删除。

## 7. Text

| 能力 | 等级 | 当前边界 | 下一门 |
|---|---|---|---|
| static content raster | `L3` | CoreText 启动时栅格；[E-TEXT](runtime-evidence-index.md#e-text) | dynamic layer texture store |
| package/system font resolution | `L3` | 包内字体与 macOS alias/fallback；[E-TEXT](runtime-evidence-index.md#e-text) | Windows family/weight/CJK/emoji golden |
| point size | `L3` | authored `pointsize * 4` 经验近似；[E-TEXT](runtime-evidence-index.md#e-text) | WE/Windows 标定公式 |
| alignment/baseline/padding | `L2` | 部分字段/geometry 进入链路 | 每种 alignment 正反像素门 |
| color/alpha | `L3` | 静态 descriptor 和 layer compositor；[E-TEXT](runtime-evidence-index.md#e-text) | live target 与 premultiplied alpha golden |
| outline/shadow/text effects | `L1` | 可见字段/effect 可能被保留 | 独立 style IR 与执行器 |
| property-driven dynamic text | `L2` | 当前通过 180 ms debounce 后整场重建 | 只更新变化 layer，旧 generation 不覆盖新值 |
| SceneScript clock/date/media text | `L0` | 无 VM 或 media snapshot | Date/media producer -> text target -> texture generation |
| dynamic Layer Image particle source | `L0` | 无 emission bitmap refresh | 只在 text texture 变化时更新 emission source |

## 8. Cursor、Audio 与 Media

| 输入/provider | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| current pointer bounded projection | `L3` | view-normalized -> scene world，以及忽略 parent/rotation/scale/parallax 的 axis-aligned authored layer UV；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | 完整层级逆矩阵前不得宣称通用 layer-local |
| full layer/effect/control-point local pointer | `L0` | 无 parent/world inverse 或 effect/control-point 投影 | hierarchy/rotation/scale/parallax 正反 golden |
| previous pointer storage | `L2` | Frame Context 保存；renderer 未消费 | shader built-in 和 event delta consumer |
| pointer buttons/down/up/click | `L0` | 无状态或事件队列 | 同帧 event snapshot 与坐标空间 |
| audio declarations | `L1` | 部分 effect/particle 字段可见 | 不能据此宣称 audio response |
| 16/32/64 stereo buffers | `L0` | Scene 无 producer/snapshot | left/right/average、每渲染帧更新、零输入 |
| audio consumer registration/lifecycle | `L0` | 无 Scene consumer | 无 consumer 停采集，设备/权限恢复 |
| media status/playback/properties/timeline | `L0` | 无 snapshot | 可注入 provider 和原子 generation |
| generic media thumbnail identity | `L1` | `$mediaThumbnail` runtime reference 可分类 | current/previous typed identity、producer、decode cancellation、authored fallback |
| media events | `L0` | 无 SceneScript dispatch | 每屏队列、顺序和异常隔离 |

Scene 不复用 Web 的固定 FFT 频段/频率合同；SceneScript 按作者选择 16、32 或 64 bins，并在 render frame 更新。

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
| authored cover transition graph | `L0` | 缺 current/previous、Blend 通用 consumer、Timeline 和 SceneScript | 新 thumbnail event -> restart Single animation；缺封面不误触发 |
| recommended cover extent policy | `L0` | 无 media decode/resize policy | 保持 aspect、方形目标、<=256 建议与异常输入预算门 |

## 9. Texture / Video provider

| provider 能力 | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| layer/named/property identity/status/generation | `L3` | 受限 provider 有 ready/pending/unavailable 与 generation；[E-PROVIDER](runtime-evidence-index.md#e-provider) | 通用 producer/consumer 生命周期 |
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

1. **B0 live-property 已完成**：format 18 binding program、per-surface transaction、atomic state、Host/Service/UI 路由和 layer alpha consumer 均已闭环；两个隔离真实样本证明更新不替换 surface/window。
2. 新增任何 live target 时，必须在同一能力切片中补稳定 identity/value semantic、compiler definition/instruction、真实 renderer/runtime consumer、原子失败、fallback 与 identity 运行门；缺一项就保留整场重建。
3. 下一主线按 [公共能力依赖图](capability-dependency-map.md) 进入 B1 Provider Core 与 B2 Graph Resource Runtime；color 不因已编译而抢在颜色空间/premultiply/material consumer 前开放。
4. visibility 只有在 render/dependency/text/particle topology invalidation 一起处理后才能取消整场重建；dynamic text 需要 per-layer texture generation 和 stale cancellation。
5. Timeline 完整保存后接 evaluator；SceneScript 只有在 source/binding IR 和沙箱成立后接入同一 target 层。
6. audio/media provider 必须有作者未启用反例、失败 fallback、generation/cancel 和 stop teardown。
