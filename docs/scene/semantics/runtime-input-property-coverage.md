# Scene 运行输入、Timeline 与属性覆盖表

> 状态：现役专项表
>
> 最近核对：2026-08-15
>
> 本页维护当前能力与缺口；精确运行身份见 [运行证据索引](runtime-evidence-index.md)，唯一实现顺序见 [Scene 兼容执行路线](../scene-compatibility-roadmap.md)。旧 R/B 批次只作证据 provenance。
>
> `311115e3` 新增的hover/click、shared alpha、audio-scaled value、property→Vec3、media colors/title/artist已有产品接线与自动测试，但没有该接线后的真实可见证据；本页统一标为`S2 wired / visible unknown`。

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

高优先级输入无效时保留最近一个合法低优先级值；未知目标、重复定义和非有限数值 fail-closed。这条规则只适用于普通 value 通道；现役纹理 provider 使用 explicit-absent-only 合同，missing、pending、unavailable、incomplete 或 identity mismatch 都不得回退低优先级纹理。纹理内容不进入普通 value 字典，只传 provider identity、状态和 generation。共享时间、用户属性、音频和媒体可以在 host 捕获一次；viewport、pointer、矩阵、surface provider、SceneScript 实例和最终 dynamic snapshot 必须按 surface 隔离。

## 2. Frame Context 与动态目标

| 能力 | 等级 | 当前证据 | 当前边界 / 下一门 |
|---|---|---|---|
| 宿主单一 frame driver | `L3` | [`SceneDesktopWallpaperHost.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift)、[`test_scene_frame_context.py`](../../../script/tests/test_scene_frame_context.py)、[E-FRAME](runtime-evidence-index.md#e-frame) | 固定 60 Hz Timer；补屏幕刷新率/目标 FPS |
| 同帧 host/scene/wall time | `L3` | [`SceneFrameContext.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift)、[E-FRAME](runtime-evidence-index.md#e-frame)；同帧发布 raw/simulation/dropped delta 与 discontinuity，pause 冻结 scene time，resume 首帧丢弃 host gap | 真实系统 pause/sleep、seek/history 与跨 consumer discontinuity 合同 |
| shader/video/particle/parallax/camera shake 共用 timing | `L3` | [`SceneMetalView.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift)、[E-FRAME](runtime-evidence-index.md#e-frame)；particle/parallax smoother消费受控simulation delta，shader/video保持raw/absolute time，Camera Shake直接消费absolute `sceneTime`且同一frame只构造一个camera frame | 其他simulation consumer、不同FPS、离线adapter、官方pause/seek事件策略与Windows timing golden |
| typed value 六类 | `L2` | `bool/scalar/vector2/vector3/vector4/string`；[`SceneDynamicSnapshot.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift) | texture/provider 不属于普通值；新增类型仍需 wire/type/finite 门 |
| typed target 族 | `L2` | scene/camera/layer/effect/text/particle/script instance 已定义；layer alpha/color、exact stock Local Contrast strength/Opacity alpha、bounded Blend multiply 与 particle CP position/angles 进入 compiler | particle 仅 absolute CP position 有 consumer；其他 effect target 不得直接开放 live，SceneScript 计算值与 direct binding 分开准入 |
| 固定 source priority | `L3` | authored -> property -> Timeline -> SceneScript；property、受限Timeline、bounded text Date、time-of-day Blend、media placeholder fade与launch-origin startup producer已执行，后四者复用`.sceneScript` source | generic SceneScript、同target多脚本和live事件mutation尚未接入；launch-origin与direct property/Timeline target碰撞时整项launch producer失败关闭，不抢占优先级 |
| property binding program persistence | `L3` | format 22 持久化 definitions、instructions、rebuild-required keys 与 effective values；严格 decode/validation | layer alpha/solid color、direct text 三字段、Local Contrast strength 与 Opacity alpha 均有真实 consumer |
| host-shared / surface-local scope | `L3` | property输入由host捕获，每个surface有独立transaction/snapshot/generation；placeholder-fade与bounded launch-origin mutable state为scene/host scope，每host frame在surface循环前只推进一次并广播同帧值。launch-origin在scene activate时按编译计划重置、teardown/新scene清空，普通surface rebuild不重启动画；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-MEDIA-PLAYBACK-PLACEHOLDER-FADE](runtime-evidence-index.md#e-media-playback-placeholder-fade)、[E-BOUNDED-LAUNCH-ORIGIN-TRANSITION](runtime-evidence-index.md#e-bounded-launch-origin-transition) | pointer/matrix/provider与真正surface-local script instance接入后继续补双屏隔离门；launch-origin不是script instance或mutable shared object |
| target invalidation domain | `L3` | alpha/color/effect scalar 为 value-only；direct text 为 per-layer texture generation；mixed/hidden/no-consumer/SceneScript/unsupported key 标记 rebuild | visibility/topology、通用 provider 和 simulation target 继续登记 |
| per-surface evaluation transaction | `L3` | property、Timeline与bounded text/time-of-day/fade/launch-origin producer的validation、同帧合并及atomic commit已闭环；fade与launch-origin runtime先在host推进一次，再向各surface definitions/effective values合并同帧`.sceneScript`值。launch-origin cohort任一值非法即整cohort冻结，target collision在launch admission时整项拒绝；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-TIMELINE](runtime-evidence-index.md#e-timeline)、[E-MEDIA-PLAYBACK-PLACEHOLDER-FADE](runtime-evidence-index.md#e-media-playback-placeholder-fade)、[E-BOUNDED-LAUNCH-ORIGIN-TRANSITION](runtime-evidence-index.md#e-bounded-launch-origin-transition) | generic VM event/mutation、同target多脚本执行与live media ingress尚未接入 |
| changed-target generation | `L3` | 每 surface 持有 generation，相同 payload 不增加；跨 surface 不共享 owner | local input/script/provider 接入后继续验证独立 diff |
| live consumer | `L3` | layer alpha、solid-only color、visible direct text content/point-size/color、bounded Timeline text width、strict Local Contrast/Opacity、bounded time-of-day Blend multiply、bounded launch-origin layer origin、23 处 Timeline effect constant typed binding、5 处 ordinary relative layer transform、bounded 2D camera Combined projection，以及 absolute Timeline particle CP position/root emitter 读取 per-surface snapshot；`3769688830:157` 另有首条真实 Tint alpha Timeline consumer，4 处 relative `lspot` angles 继续由 strict spotlight consumer 执行。297的launch-origin近白卡片区域有启动/稳态bbox位置证据，但没有逐origin target GPU/publication声明；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-TIMELINE](runtime-evidence-index.md#e-timeline)、[E-EFFECT-TINT](runtime-evidence-index.md#e-effect-tint)、[E-EFFECT-BLEND-TRANSFORM](runtime-evidence-index.md#e-effect-blend-transform)、[E-BOUNDED-LAUNCH-ORIGIN-TRANSITION](runtime-evidence-index.md#e-bounded-launch-origin-transition) | typed binding 不等于对应renderer/effect完整执行；297的inverse4、click、封面/其他卡片内容与effects仍不在该bounded producer内。particle angles/relative/其他 field/consumer、hidden/no-consumer text、container/non-solid color、generic Combined/3D camera 与 generic SceneScript 仍重建或 fail closed |
| Scene pause/resume | `L3 bounded` | 统一播放控制冻结 SceneClock、停止 frame driver 并暂停 video provider；重复 pause/resume 幂等，resume 首帧 raw/simulation/dropped delta 均为 0、scene time 连续；[E-FRAME](runtime-evidence-index.md#e-frame)、[E-VIDEO](runtime-evidence-index.md#e-video) | 系统 focus/fullscreen/sleep/lock 的真实运行门、粒子 pause 视觉门和 seek/history |
| delta clamp / dropped-time | `L3 bounded` | shared clock 保留 raw delta，把 simulation delta 限为项目 policy 0.25 秒，并发布 dropped delta/discontinuity；纯 clock fixture 有 1 秒长帧数值门，Debug performance 记录次数、累计 dropped 与最大 raw；[E-FRAME](runtime-evidence-index.md#e-frame) | 0.25 秒不是官方常量；真实长卡顿、不同 FPS、其他 simulation consumer、离线/Windows timing golden 仍缺 |
| offline fixed-time adapter | `L0` | Debug PNG readback 不是离线 adapter | 注入 frame index/time/seed/provider replay |

当前 live-property 路径已让 direct text content/point-size/color 等 value-only target 进入真实 producer/consumer。文本 consumer 按 layer signature 去重、异步生成、拒绝 stale completion 并保留 last-ready texture；缺少 compiler mapping、有效可见 consumer 或 direct user binding 时继续走 `requestSceneRender` fallback。

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
| camera shake | `L3 bounded` | Scene general作者开关、默认值与amplitude/roughness/speed静态准入进入唯一camera-frame evaluator；当前2D orthographic renderer、particle/pointer/parallax消费同一shake-adjusted camera，User Property经rebuild生效；[E-CAMERA-SHAKE](runtime-evidence-index.md#e-camera-shake) | 真正perspective Scene XYZ、3D camera、live/SceneScript写入、官方pause/seek策略、Windows同相位golden与整景视觉 |
| bounded 2D camera path origin/zoom | `L3 bounded` | 单一 default path 的 reciprocal Combined `origin` owner + `zoom` child 共用 owner clock，原子进入 image/particle/pointer projection；zoom 只准 `0.01...100`，作者 Bézier control-value convex hull 也必须保持 origin/zoom/near/far 预算 | 多 path selection/lifecycle、generic setter、3D camera 与 Windows golden |
| 3D camera / perspective runtime control | `L0` | 2D bounded path 不外推 3D Eye/Center/Up/FOV | 3D path identity、queue/lifecycle、typed projection 与运行门 |
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

<a id="op-camera-shake"></a>
### 3.4 Scene Camera Shake 官方客户端合同

Scene Camera Shake 是Scene级全局相机行为，不是对象effect `Shake`。Wallpaper Engine 2.8.42的哈希匹配客户端静态证据给出以下可测试合同；项目只实现其中可证明的2D orthographic子域：

- 作者默认关闭；缺省amplitude/roughness/speed分别为`0.5 / 1 / 3`。同版本editor作者范围为amplitude `0...1`、roughness `0...2`、speed `0...5`；项目用它们做静态准入，不声称player会运行时clamp。
- evaluator由absolute scene time决定，没有RNG、seed或逐帧积分状态；同一时间输入必须得到同一结果。项目pause通过冻结共享`SceneClock`自然冻结结果，这不等于已经证明官方pause/seek事件政策。
- amplitude 0是identity；speed 0停在起始相位而不是关闭；roughness 0保留基础周期向量，roughness 1保持基础轨迹，roughness只重塑径向长度。起始相位为X正峰、Y为0，X/Y采用不同固定频率。
- evaluator给camera eye和center加同一个位移，因此不产生rotation、roll、zoom或FOV变化。base/default/path camera与shake先形成唯一working camera；parallax只读取它的XY并与pointer组合，shared view也只由该shake后状态构建，不得回读pre-shake camera。
- orthographic Scene先丢弃Z、只对XY做roughness整形，最后以作者`orthogonalprojection.height`缩放；不能改用drawable或canvas最小边。真正perspective Scene使用XYZ分支且不会因某个explicit camera禁用，但该分支当前项目尚未准入。
- 分支选择来自Scene全局投影类型，不来自particle `flags=4`。因此正交Scene中的perspective particle仍与普通层共享同一个height-scaled XY shake，只在下游选择perspective VP。
- 当前property wrapper只通过整场rebuild重新解析；没有live snapshot consumer，也没有SceneScript scene-property bridge。

项目正负数值门覆盖author-off、amplitude/speed/roughness的0/1/2边界、absolute-time往返、projection-height缩放、无效投影/范围失败关闭、base/path + shake + parallax顺序，以及正交层和下游perspective particle共用同一camera origin。正式运行见[E-CAMERA-SHAKE](runtime-evidence-index.md#e-camera-shake)。

## 4. Timeline

<a id="op-timeline-introduction"></a>
### 4.1 [Introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html)：identity、timebase 与 target axes

Timeline 是带预定义时长的 component-property 动画，不是 Effect animation。官方创建合同包含 mode、从首帧到末帧的 `Seconds`、关键帧槽数量 `Frames`、可选 `Name`、`Start paused` 和 `Wrap loop frames`。目标必须保存 component/object、property 以及 vector axis；例如 `Origin.x` 可以单独动画，隐藏 graph 中的 Y/Z lane 只改变编辑视图，不会把 lane 从 animation 删除。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| dynamic `animation` wrapper presence | `L2` | 粒子 CP position/angles nested wrapper 已保留完整 Timeline IR；随包 7 处 particle Timeline 是其他 scalar override，仍只记 presence 并诊断 | 不得把 CP 子集外推为 generic particle Timeline |
| animation identity / optional name | `L1` | 身份由宿主 JSON 路径（layer + host 属性名、layer + `instanceoverride.controlpoint*`，或 layer/effect/pass/constant 名）决定；官方 optional name 在随包 48 处中未出现，未保存 | 出现合法 fixture 后补 name 与 owner scope |
| duration seconds / authored frame slots | `L2` | `fps`/`length` 原样保存，时长按 `length / fps` 换算（随包三例交叉验证 1.0s / 0.5s / 0.5s）；`smoothing`/`stiffness` 随包 16 处全为 null，只保真不解释 | 异常值（`length` 与末帧不符）无反例可依 |
| component/property/axis target | `L3` | lane 以 `c0/c1/c2/c3` 对应 component 下标，必须从 `c0` 起连续否则 fail-closed；已 typed 编译为 `.camera(.origin/.zoom)`、`.layer(.alpha/.origin/.angles/.scale)`、`.effectConstant`、`.text(.maxWidth)` 与 particle `.controlPoint`/`.controlPointAngles`。effect constant 从完整作者 raw value 严格形成 1–4 维 scalar/vector shape，缺失、空、畸形、非有限、超过四维或 lane 数与 shape 不一致时整条 target 拒绝；合法普通值经同一 per-surface transaction 写入 snapshot。layer transform 仅在 `relative=true` 时准入 additive composition；唯一 camera 组按 relative origin + absolute zoom 准入，组内共用 owner clock；text width 仅准 `limitwidth=true`、absolute 单 lane，且实际 Bézier segment 的端点/control values 全部位于有限 `1...16384` 像素 | vector3 representative Tint color 已经 shared MaterialProgram/GPU/compositor/next-frame 可见，lane mismatch 只局部 passthrough；真实 `3748311238:728` 两个 vector2 Shake consumer 也已执行并通过 frame fault 局部恢复门，但不证明其余 effect constant/vector occurrence、整个 Shake owner、generic Combined、absolute layer transform 或其他非 layer-transform `relative`，后者继续拒绝或待验 |
| `relative` composition | `L3 bounded` | 9 处 layer transform 以“作者基值 + 动画偏移”形成 typed additive binding：5 条 ordinary + 4 条 `lspot`；camera origin 另以相同 composition 进入 bounded Combined camera target。公开官方页只定义 property animation/modes 与 layer transform，不定义私有 serialized `relative` wire 或合成公式 | 合同来自合法语料、既有 black-box 校准与项目自有正反门；其他非 layer target、非有限基值或形态不完整均 fail closed，仍需 Windows golden |
| keyframe frame/time/value | `L3 bounded` | `frame`/`value`/`front`/`back`/`lockangle`/`locklength` 六个键在 180 个真实 keyframe 上全部保真；帧号严格递增；缺失/`null` tangent 合法，非 object 报 `invalidTangent`。enabled front X 只准 `0...1`、back X 只准 `-1...0`，已消费 control value 必须有限；普通动画的首 back/末 front 仅保真，wrap-loop 会把它们作为闭合段 control handles 消费 | 同 frame 多 lane 与异常顺序目前只有负例门；handle 单位与范围无 Windows wire 对照 |
| scene-time evaluation | `L3` | 纯函数 evaluator，同一 `sceneTime` 必得同一结果，不持播放状态、不逐帧累加；host 每帧算一次后经 per-surface transaction 写回；Scene pause 通过冻结共享 scene time 保持结果 | 未接 seek/discontinuity |
| wrap-loop frames | `L3 bounded` | 9 条 Workshop + 2 条随包 stock 声明均把末关键帧留在 `length` 前；Loop 周期尾部以末 keyframe `front` / 下一周期首 keyframe `back` 构造普通 cubic，所有现役 typed consumer 共用。Mirror+wrap、关键帧越出 `[0,length)` 与 bounded target 闭合 control 越界均失败关闭；fixed13 25 bindings / 0 diagnostics | 官方只说明编辑器自动创建到首帧的平滑过渡，不公开私有 JSON 与数值算法；无 Windows 同相位 golden |

<a id="op-timeline-combined"></a>
### 4.2 [Combined Animations](https://docs.wallpaperengine.io/en/scene/timeline/combined.html)

Combined Animation 会把新的 property lane 加入一个已有 animation，并复用已有 animation 的 mode、时长和其他设置；它可以同步不同 property 类型和不同 axis。lane 必须保留作者 membership 与稳定顺序。官方页面没有定义两个 lane 写入同一最终 target 时的冲突优先级，因此在取得合法 fixture 前应拒绝歧义，而不是按 dictionary 顺序猜值。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| existing-animation membership | `L3 bounded` | 双向 key 引用已保真；唯一 default 2D camera `origin` owner + `zoom` child 组验证 reciprocal membership，并把两成员归一到 owner mode/fps/length/start-paused/wrap clock。坏引用、多 path、未知 camera/queue 和普通 Combined 整组 fail closed | generic Combined 的 owner identity、任意 property/axis 组合与 lifecycle |
| authored lane order | `L2` | lane 按 `c0/c1/c2` 下标顺序保真；同一 target 被多条 Timeline 写入时全部拒绝并报 `duplicateTarget`，不按声明序或字典序猜 | 官方未定义冲突优先级，维持 fail closed |
| atomic multi-target commit | `L3` | 全部 Timeline 值在同一帧算出后一次性送进 `SceneSurfaceEvaluationTransaction`，与 property 输入同一次原子提交；camera origin/zoom 有 owner-clock 与同 snapshot 正门 | generic Combined 冲突、seek/重启与多 surface lifecycle |

<a id="op-timeline-modes"></a>
### 4.3 [Playback](https://docs.wallpaperengine.io/en/scene/timeline/modes.html) 与 Bézier modes

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| Loop | `L3` | 按 `length` 取模，跨周期同相位；普通 Loop 与 9 条 wrap-loop 都执行，后者在末 keyframe 后连续插值到下一周期首帧 | 无 Windows 同相位 golden |
| Mirror | `L3` | 周期 `2*length` 的三角波，端点不重复采样；单测覆盖折返段与上行段同值。随包 6 处均为 relative layer transform，现已执行；`2938612768` 的 ordinary origin 有共享 world-frame 隔离正门，`3768903841` 的四束 `lspot` 有既有 strict 真实门 | 端点是否重复采样官方未定义，仍无 Windows 同相位 golden |
| Single | `L3` | 到末帧后保持末值不回绕；真实执行 21 处 | — |
| start paused | `L3` | 恒停首帧，真实执行 6 处；`2067939514` 为负门（同级脚本在 `mediaThumbnailChanged` 里调 `play()`，无 VM 时不得自动播放）；Scene pause 只冻结全局 clock，不改变 animation-local start-paused 状态 | animation-local play/stop/seek 仍需 VM/API |
| Bézier `both/left/right/none` | `L3 bounded` | 每 keyframe 左右 handle 与 `enabled` 独立保真；普通段以 `start.front` / `end.back` 构造 cubic，wrap 闭合段以末 `front` / 首 `back` 构造；X 作为各自 segment span 归一化 offset、Y 作为 property value offset，按 frame progress 二分反求 curve parameter。一侧关闭退化到对应端点，两侧关闭严格线性。44 场景 **48 animations / 180 keyframes / 112 adjacent + 9 wrap segments** 中 178 个 enabled front/back 全部满足范围，自定义 handle 分布于四个样本；定向与 fixed13 见 [E-TIMELINE](runtime-evidence-index.md#e-timeline) | 单位来自合法语料机械定标而非公开私有 wire；无 Windows 同相位数值/像素 golden |

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
| PNG/JPEG picker/bookmark/provider | `L3` | security scope、decode、per-screen upload，以及由现役authored-effect catalog授权的bounded Blend/property texture consumer；B22已删除独立ImageBlend plan/runtime及其额外property execution授权，见[E-PROVIDER](runtime-evidence-index.md#e-provider)与[E-R4-B22-INDEPENDENT-IMAGE-BLEND-RETIREMENT](runtime-evidence-index.md#e-r4-b22-independent-image-blend-retirement) | cancellation、更多格式和通用 material；普通authored Blend不外推generic consumer |
| authored texture fallback | `L3 bounded` | 现役受限 consumer与R3 material contract只在选中property identity被生产者**显式发布为absent**时回退作者纹理；missing state、pending、unavailable、ready publication不完整或identity不匹配均失败关闭，不能把故障解释成“用户未选择”；[E-PROVIDER](runtime-evidence-index.md#e-provider)、[E-MATERIAL-PROGRAM](runtime-evidence-index.md#e-material-program) | 推广至image albedo/effect mask/particle/material GPU consumer，并补更多provider lifecycle门 |
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
| cursor-triggered open | `L0 generic` | 已有 launch-origin 专用 primary-button hit-test，但没有通用 pointer event queue、SceneScript VM 或 `openUserShortcut` host API | 单事件单命令、click propagation 和 invalid key 门 |
| shortcut icon provider | `L0` | 无 shortcut provider | bound/unbound generation、square icon fallback 和取消 |
| `isbound` / `file` change payload | `L0` | 无 `applyUserProperties` event | first/full 与 change-only payload、隐私与屏保策略 |

下表沿用 21 样本 target census 快照：424 definitions、952 bindings、195 条 conditional bindings。它只用于解释既有 target 分布，数字不是当前 corpus fingerprint、产品支持率或开发顺序；当前能力以每行代码/运行证据和[总台账](coverage-ledger.md)为准。

## 6. User Property target 矩阵

| target 族 | 观察数量 | 当前分类/执行 | 等级 | 下一门 |
|---|---:|---|---|---|
| layer visibility | 230 | 可分类；受支持 key 通过文档改写和整场重建生效；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | 编译 target program；visibility graph invalidation |
| text content/point size/color | 267 | direct binding 编译为 typed text target；有效可见层经 per-layer generation 无重建更新，hidden/no-consumer 整 key 重建；[E-DYNAMIC-TEXT](runtime-evidence-index.md#e-dynamic-text) | `L3` | SceneScript/system/media producer与 Windows layout golden |
| camera binding family | 5 | 字段名可识别；整族没有统一 executor | `L1` | typed compiler 分出可执行与 unsupported |
| camera parallax actionable subset | 3 | 当前白名单经重建生效；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | live camera target 和无重建门 |
| camera shake subset | 2 | 旧target-census中的binding已由2D orthographic bounded consumer执行；四个字段只在有效正交projection时可操作，修改触发rebuild且没有fake live consumer；[E-CAMERA-SHAKE](runtime-evidence-index.md#e-camera-shake) | `L3 bounded` | 重新按同口径统计binding；真正perspective/3D、live/SceneScript与Windows golden |
| effect visibility family | 129 | target path 可识别；原 20 条白名单加 2 条 exact stock Local Contrast visibility target 可操作 | `L1` | authored effect ID 和完整 compiler |
| effect visibility actionable subset | 22 | 20 条旧白名单经重建生效；`2902406982` layers `167/177` 的 Local Contrast visibility 始终保留在面板，关闭后仍可重开；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | topology invalidation 和完整条件门 |
| shader constant family | 122 | UserPropertyBindings census 保留 target path/value；v22 继承 Local Contrast/Opacity strict target | `L1` | typed uniform/pass identity 和完整 compiler |
| shader constant actionable subset | 20 + 4 strict | census 的 19 条旧白名单经重建进入受限 executor，Local Contrast strength 与 `2902406982:[365,372,647,664]` stock Opacity alpha live 消费 snapshot；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | generic executor、SceneScript 与通用 live uniform |
| layer alpha | 73 | 编译为 `.layer(.alpha)`；image/solid/text 读取 per-surface snapshot，当前 census 没有 particle/utility alpha binding；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | 扩展到新 layer kind 前先补对应 consumer；mixed/no-consumer 继续重建 |
| layer color | 73 | 全部目标为 solid；25 条纯 color key 由 snapshot/tint live 消费并在属性面板开放，48 条 `basecolor` 因同键含未支持目标整场重建；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | 补颜色空间/premultiply golden；non-solid/mixed target 继续 fail closed |
| Puppet animation visibility | 2（`3769688830`） | `objects[].animationlayers[].visible` 解析为稳定 layer/animation-layer identity，direct bool User Property 编译为 typed target，并由 bounded Puppet playback 每帧 snapshot 消费；[E-PUPPET-BC](runtime-evidence-index.md#e-puppet-bc) | `L3 bounded` | condition/SceneScript、无稳定 ID、冲突 mixing 与 topology mutation 继续 fail closed |
| script instance properties | 43 | 路径存在；不保存源码/绑定程序 | `L1` | 编译 `.scriptInstanceProperty`，等待 VM consumer |
| particle instance override | 6 | authored 静态 override 可消费；动态 binding 未分类 | `L1` | alpha/count/size/speed/color typed target |
| Scene bloom/threshold target identity | 2 | `.scene(.bloomEnabled/.bloomThreshold)` 已定义，binding 尚未分类 | `L1` | 稳定 authored path、type 与 scope |
| Scene bloom/threshold binding/runtime | 2 | 无 binding compiler、producer 或 Scene post consumer | `L0` | target program + HDR post chain |
| layer scale | 1 | binding 未分类；静态 transform 可执行 | `L1` | typed transform target 与 frame geometry |
| sound volume target identity | 1 | `.layer(.volume)` 已定义，binding 未分类 | `L1` | binding compiler 和 sound owner identity |
| sound volume runtime | 1 | 无 sound IR/player | `L0` | playback/lifecycle 后再开放 |

该 census 的 unsupported 总数没有按当前 schema 重算，因此不得引用其聚合数量。当前已确认 alpha/color、Local Contrast、Opacity 与 direct text target 进入 binding program；mixed、hidden/no-consumer、non-solid color、其他 shader constant 和 unsupported key 仍由 rebuild/fail-closed 路径处理。

## 7. Text

| 能力 | 等级 | 当前边界 | 下一门 |
|---|---|---|---|
| static content raster | `L3` | CoreText 启动时栅格；[E-TEXT](runtime-evidence-index.md#e-text) | dynamic layer texture store |
| package/system font resolution | `L3` | 包内字体、8 个官方 `systemfont_*` 别名，15 个客户端 stock 名字全部随包真实字体（8 原版 `stockBundled` / 7 替代 `stockSubstituted`；stock 41/alias 19/包内 184/未知 0）；[E-TEXT-FONTREF](runtime-evidence-index.md#e-text-fontref) | 7 个替代字形非官方轮廓；原版无 Windows 栅格化逐像素对照；family/weight/CJK/emoji golden |
| point size | `L3` | authored `pointsize * 300 / 72` 官方 300 DPI 换算；[E-TEXT-POINTSIZE](runtime-evidence-index.md#e-text-pointsize) | Windows 逐像素对照、去掉本地 1024 px 字号夹取 |
| alignment/padding geometry | `L3` | left/center/right × center/top/bottom 同时进入 CoreText 和 quad pivot；作者 `size` 是含 padding 外框，边对齐以内容边钉住 origin，动态扩框使用当前 render size 归一化 padding；[E-TEXT-PIVOT](runtime-evidence-index.md#e-text-pivot) | Windows 字体/像素 golden、effect 越界裁剪对照 |
| baseline/`blockalign` | `L1` | 字段可见但未形成独立 baseline/block alignment 执行合同 | parser + CoreText baseline/块对齐正反门 |
| row/width overflow limits | `L3` | `limitrows`/`maxrows`/`limitwidth`/`maxwidth`/`limituseellipsis` 进 IR 并由 CoreText 消费，两个数值只在对应开关打开时生效（语料 393 个关闭态带默认 `maxwidth: 500`，79 个已超宽）；bounded Timeline `maxwidth` 复用同一 CoreText consumer，端点与实际消费的 Bézier controls 均需在预算内，并以每层单在途任务合并连续重栅格；[E-TEXT-LIMITS](runtime-evidence-index.md#e-text-limits) | Windows 逐像素对照省略号回退与断点、多屏连续宽度压力门 |
| color/alpha | `L3` | 静态 descriptor 和 direct color generation consumer；[E-DYNAMIC-TEXT](runtime-evidence-index.md#e-dynamic-text) | premultiplied alpha 与 Windows golden |
| outline/shadow/text effects | `L1` | 可见字段/effect 可能被保留 | 独立 style IR 与执行器 |
| property-driven dynamic text | `L3` | 只更新变化 layer，重复值不生成；并发旧 generation/失败结果不覆盖 last-ready，连续 Timeline 则每层只保留一个在途任务、发布单调中间结果后只追最新 generation；真实 `2134765860` 三字段与 `2902406982` 两条 width Timeline 正门 | 长文本/emoji/多语言布局与多屏压力门 |
| fixed native clock/day/date/greeting text | `L0 product owner / historical` | 七个exact source/property profile已于R4-B18删除；B18前报告只作历史，不证明现役Text owner、输出或视觉 | 现役只看下一行bounded AST；`clockWithPeriod`、greeting与其他未准入语法保留authored fallback |
| bounded property-bound text update | `L3 bounded` | B18后唯一现役Text脚本合同：唯一exported `update(value)`解析为无循环AST；primitive property、变量/条件/赋值、`new Date()` getter、string拼接/`slice`由三层预算执行，不依赖sample/layer/source hash；compile/evaluate失败不覆盖作者文字 | 完整ECMAScript/coercion/scope/exception、init/engine/event/module、live script-property event、locale/DST/离线clock adapter |
| fixed native delayed-loop/day-night texture animation | `L0 product owner / historical` | B19已删除两个source SHA profile、compiler、playback plan、专用clock与wall-date sprite plumbing；TextureAnimation SceneScript仍保真但不执行 | 旧delayed-loop/time-of-day报告只作历史，不证明现役owner、当前时序或视觉；通用handle、cursor click、persisted override与Windows timing仍未实现，见 [E-R4-B19](runtime-evidence-index.md#e-r4-b19-fixed-texture-animation-profile-retirement) |
| bounded media placeholder fade | `L3 bounded` | 严格stopped-rise/active-fall结构把effect alpha写入既有Opacity consumer；真实两样本共5层首帧/下一帧GPU与compositor完成，293三个局部区域出现此前缺失的封面/标题/歌手内容 | 无live provider；逆向fade、metadata/text/colors、shared/cursor/angles、其他effect constant与通用VM失败关闭 |
| generic SceneScript/media text | `L0` | bounded text update与placeholder fade分别复用现有typed consumer，但仍无VM、通用source/module loader、media snapshot/provider或任意target | 扩展typed producer时保持syntax/value/budget/lifecycle fail-closed |
| dynamic Layer Image particle source | `L0` | 无 emission bitmap refresh | 只在 text texture 变化时更新 emission source |

## 8. Cursor、Audio 与 Media

| 输入/provider | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| current pointer bounded projection | `L3` | view-normalized -> scene world，以及忽略 parent/rotation/scale/parallax 的 axis-aligned authored layer UV；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | 完整层级逆矩阵前不得宣称通用 layer-local |
| full layer/effect/control-point local pointer | `L0` | 无 parent/world inverse 或 effect/control-point 投影 | hierarchy/rotation/scale/parallax 正反 golden |
| previous pointer storage | `L2` | Frame Context 保存；renderer 未消费 | shader built-in 和 event delta consumer |
| pointer buttons/down/up/click | `L2 bounded wiring；generic L0` | AppKit down/up更新per-surface primary-button state；admitted launch-origin master在button edge使用实际camera/world-frame/quad UV hit-test并toggle cohort。只有代码与自动测试证据 | generic有序event queue、multi-button、capture/drag、VM dispatch与fresh visible门 |
| bounded hover-origin projection | `L2 wired` | AppKit move/enter/exit与同一camera/world/UV hit-test驱动已准入hover cohort；不是SceneScript `cursorEnter/Leave` | fresh surface-local可见门、generic callback/event ordering、完整坐标空间 |
| audio declarations | `L3` | effect 与粒子两套 schema 分别保真解析（字段名不同，粒子无 `audioamount`）；[E-AUDIO-EFFECT](runtime-evidence-index.md#e-audio-effect) | 粒子声明保真不等于可执行 |
| 16 stereo buffers | `L3` | left/right host-shared 快照每帧广播给所有 surface，静音/无权限稳定归零；stock effect 与统一Program中的relocated Simple Audio Bars stereo up/down作者shader已消费；旧Simple专用consumer已删除；[E-AUDIO-INPUT](runtime-evidence-index.md#e-audio-input) | 频段划分与归一化是工程选择，无官方数值合同；采集 30 Hz 与渲染 60 Hz 之间不插值 |
| 32/64 stereo buffers | `L3 bounded` | 与 16 档由同一次 FFT 生成并进入 host-shared snapshot；供统一Program中的Simple Audio Bars 32/64-band作者shader、Workshop Audio Hue已证作者Program及其他现役effect consumer；旧Simple、Audio Hue与fixed SceneScript Audio Bars专用consumer均已删除；[E-AUDIO-INPUT](runtime-evidence-index.md#e-audio-input) | 其他 Workshop shader 与通用 SceneScript `registerAudioBuffers` 尚无 consumer/bridge，不外推 |
| SceneScript `AudioBuffers` / `average` API | `L0` | host snapshot 只有 left/right；两个 bounded native consumer 在 renderer geometry 内按 `(left + right) / 2` 逐 bin 派生 average，但没有 JS object、Float32Array identity 或订阅 lifecycle | 由通用 SceneScript bridge 建立逐帧受控数组，并验证对象/数组生命周期 |
| audio consumer registration/lifecycle | `L3` | 采集由 consumer 存在性驱动，launch 声明/teardown 撤销，暂停/锁屏/休眠停采并归零；统一Program按实际反射出的audio host uniform声明需求，Simple Audio Bars、Workshop Audio Hue与既有effect consumer共用同一次host snapshot，专用Audio Hue owner删除后需求不丢失 | 新增 consumer 必须同批扩充判定，否则采集不会启动 |
| Scene Sound layer / self-playback | `L0` | `3743305891` authored FLAC 尚未解码/播放；当前 system tap 排除本进程，不会把该声音回送成 Scene 频谱 | sound content IR、提取/解码、状态/volume/teardown，以及 wallpaper-local 频谱源的独立合同 |
| media playback/colors/title/artist snapshot | `L2 wired` | producer-agnostic inbox保存playback、artwork colors、title/artist及独立generation；bounded fade/color/text consumer已接到同一frame transaction。当前无新runtime/ROI | live producer、missing-field/clear语义、fresh visible门 |
| media status/album/timeline | `L0` | 无完整typed snapshot或consumer | 可注入 provider、原子 generation与generic event/VM bridge |
| generic media thumbnail identity | `L3 bounded current cover` | `$mediaThumbnail`是现役system identity；replacement pending保留last-ready current/generation，ready后原子发布current。B20删除`$mediaPreviousThumbnail`产品identity/publication与gradient transition | live platform producer、previous/transition/variant、通用media event与SceneScript lifecycle |
| media events | `L0` | 无 SceneScript dispatch | 每屏队列、顺序和异常隔离 |

Scene 不复用 Web 的固定 FFT 频段/频率合同；SceneScript 按作者选择 16、32 或 64 bins，并在 render frame 更新。

官方 [IEngine.registerAudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) 只接受 16/32/64 三档，[AudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) 的 `left`/`right`/`average` 等长数组按帧自动更新、由低频排到高频，数值通常在 0...1 但允许超过 1；shader 侧 [Audio globals](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 同样明确为正值且不归一化。当前16/32/64 host snapshot满足effect renderer consumer的输入形状；B21已删除曾逐bin求average的两个fixed native audio profile。项目没有SceneScript VM、engine method、`average`数组对象或脚本订阅，因此不能据此升级任何SceneScript API。

<a id="op-media-overview"></a>
### 8.1 [Audio Visualizer](https://docs.wallpaperengine.io/en/scene/audiovisualizer/overview.html) 资料边界

官方 Audio Visualizer overview 明确仍在建设，目前只公开 Album Cover 和 Media Playback 两篇作者指南。这两个页面不能反向证明完整 audio visualization、FFT 映射或 Windows media backend 私有行为；Scene 的频谱、媒体和 Web audio 合同继续分开建账。

<a id="op-media-information"></a>
### 8.2 [Media Information](https://docs.wallpaperengine.io/en/scene/audiovisualizer/mediainformation.html) 与动态文字

官方通过 SceneScript media events 提供 title、album title、artist、playback/status、timeline 和 thumbnail 派生颜色，但媒体播放器或文件可能不提供某些 metadata。作者必须允许字段缺失。动态媒体文字可能很长，官方要求用 text `Point size` 调字号，不用 layer `Scale` 降低清晰度，并配置 left alignment、`Max width`、`Max rows` 和可选 overflow ellipsis。Playback `stopped` 与 `paused` 不同；官方隐藏示例只在 stopped 时隐藏，paused 仍显示。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| playback/colors/title/artist snapshot | `L2 wired` | inbox与frame driver已有typed generation和bounded consumer；没有fresh runtime evidence | 可注入同host-frame原子更新、clear/missing、stale与多surface门 |
| status/album/timeline snapshot | `L0` | 尚无完整producer/consumer | typed optional fields与原子generation |
| media property events | `L0 generic` | bounded native title/artist projection不是SceneScript event | title/albumTitle/albumArtist等typed event和逐surface queue |
| missing metadata fallback | `L2 wiring incomplete` | title/artist snapshot可为空，但没有fresh切歌/clear证据 | 缺字段不得保留上一首错误文本；作者fallback/空值策略可测 |
| media text layout constraints | `L2 wired` | typed title/artist可进入bounded text runtime；尚无fresh可见门 | point size、max width/rows、ellipsis和长Unicode title golden |
| stopped versus paused visibility | `L2 bounded wiring` | bounded playback-state fade consumer已存在；没有live provider与fresh event门 | 枚举映射、初始stopped、paused保持可见和恢复顺序 |
| thumbnail derived colors | `L2 wired` | artwork color snapshot与bounded transition consumer已接线；不等于generic `MediaThumbnailEvent` | primary/text/其他公开色值、无thumbnail fallback与fresh ROI |
| authored color transition | `L2 bounded wiring` | bounded native projection按simulation delta更新；不是通用作者SceneScript | VM event/update链、作者数学、fresh dynamic ROI与Windows timing |

<a id="op-media-album-cover"></a>
### 8.3 [Current / Previous Album Cover](https://docs.wallpaperengine.io/en/scene/audiovisualizer/albumcover.html)

官方 Album Cover binding 明确区分 `Current album cover` 和 `Previous album cover`。没有媒体或封面时作者 placeholder 必须继续可见；建议封面使用方形 `100x100...256x256`，不把高分辨率封面当作可靠输入。平滑换封面不是 provider 自动效果：官方配方是 current cover 作为当前图，previous cover 绑定到 Blend/Blend Gradient 输入，再由 `Single`、`Start paused` 的 Timeline 控制 Blend amount，并在 `mediaThumbnailChanged` 中播放 animation。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| `$mediaThumbnail` generic reference | `L3 bounded current` | frame registry对显式current publication执行generation前进、同代换纹理和stale拒绝；严格normal/full-strength Blend source replacement与通用visibility binding消费同一typed current identity | generic material、previous/transition/variant与通用event consumer |
| current cover identity/provider | `L3 bounded` | producer-agnostic current-only inbox原子发布encoded current；共享store为每代建立可取消request，新代使排队旧任务在ImageIO前退出，并在current decode/upload边界协作停止已开始的旧任务；publication继续以request identity + requested generation拒绝过期completion。replacement decode未完成时发布last-ready current/content generation，最长边限制256，ready后换代广播所有surface；当前只有隔离debug producer，见 [E-MEDIA-THUMBNAIL](runtime-evidence-index.md#e-media-thumbnail) | 单次ImageIO调用不可抢占；macOS live producer、权限/播放器lifecycle、结构化decode status telemetry与真实切歌门仍缺失 |
| previous cover identity/provider | `L0 product owner / historical` | B20已删除previous payload、identity、publication、decode及所有transition输出；旧A→B→C previous与per-surface transition报告只作历史 | 重新实现需公共typed previous provider与统一graph/event consumer，不得恢复fixed source/profile |
| authored placeholder fallback | `L3 bounded` | 首次没有 current、显式 clear 完成或 replacement decode 最终失败时不覆盖作者 image/solid；已有 current 的 replacement pending 继续显示 last-ready，不再瞬时闪回 placeholder。只为 normal/full-strength、单纹理 current Blend 和通用 `mediaThumbnailChanged(event){ thisObject.visible=event.hasThumbnail; }` 可见性合同准入 layer-source replacement | 其他 Blend mode/强度/transform/mask、多纹理、任意脚本或 generic effect consumer |
| authored cover transition graph | `L0 product owner / historical` | B20删除fixed source/SHA compiler、gradient loader、pipeline、renderer、per-surface encode与layer-source replacement；旧Single/Start paused/stop-play/gradient wipe报告仅描述B20前实现 | generic Blend Gradient、typed previous provider、统一graph/event调度、真实平台切歌与Windows timing/pixel golden |
| recommended cover extent policy | `L2` | encoded input 限 16 MiB，ImageIO thumbnail 保持比例且最长边限 256；只接受可解码 PNG/JPEG 路径作为隔离证据输入 | 非方形/异常 profile 的 GPU 几何门、色彩空间/orientation 与 Windows decode golden |
| live platform media producer | `L0` | 公共 inbox 已提供 producer 边界，但产品没有读取其他 macOS app 当前播放封面的系统 adapter | 选择可公开/可授权的系统来源，定义 start/pause/stop、缺封面、切歌和多播放器仲裁 |

## 9. Texture / Video provider

| provider 能力 | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| layer/named/graph/asset/property/system identity/status/generation | `L3 bounded；generic carrier L2` | R3统一`SceneFrameTextureIdentity`与`SceneTextureProviderPublication(requestIdentity,candidate,contentGeneration)`；immutable frame snapshot同时冻结frame index、ready/incomplete/absent/pending/unavailable，字典missing仍可区分。candidate的identity/generation/purpose/content、physical/mapped、UV、sampler raw flags必须同代，stale、purpose/identity不匹配与半publication均拒绝；既有direct text、embedded MP4和bounded current-cover生命周期不变，previous/transition identity已由B20删除；[E-PROVIDER](runtime-evidence-index.md#e-provider)、[E-MATERIAL-PROGRAM](runtime-evidence-index.md#e-material-program) | graph FBO/effectOutput在command边界的publication、其他provider主动取消、device loss、platform producer/consumer生命周期与通用GPU consumer |
| authored fallback chain | `L3 bounded` | 受限static Blend现与R3 material resolver共用explicit-absent-only规则；missing/pending/unavailable/incomplete不能落回较低优先级作者候选；[E-PROVIDER](runtime-evidence-index.md#e-provider)、[E-MATERIAL-PROGRAM](runtime-evidence-index.md#e-material-program) | 推广至material/effect/nested GPU consumer，并逐类证明producer的absent语义 |
| property PNG/JPEG | `L3` | bookmark/security scope/decode/per-screen upload；[E-PROVIDER](runtime-evidence-index.md#e-provider) | cancellation、更多格式、通用 material |
| multi-image TEX sprite playback | `L3 bounded` | 普通单图atlas及BC1/2/3、axis-aligned/integer/same-extent的cross-image multi-image按scene time与作者frame duration循环；source按file generation/device跨surface去重，destination按实例计费并随playback释放，设备allocation聚合预算384 MiB。B19撤销fixed TextureAnimation profile不删除该公共autoplay能力；[E-PUPPET-BC](runtime-evidence-index.md#e-puppet-bc) | dynamic replacement、旋转/trimmed/fractional/异尺寸frame、通用SceneScript handle/detach/join/rate/pause/seek/command/timer、Windows timing/color/alpha golden；B19未刷新运行或视觉证据 |
| embedded MP4 image layer | `L3 bounded` | TEX payload 由 launch-scoped registry 管理，按共享 SceneClock 映射 item time；同 frame 去重、成功帧换代，pause 保帧、resume/rebuild 连续、stop 释放；[E-VIDEO](runtime-evidence-index.md#e-video) | 真实系统 pause/hot-plug、seek、loop 首帧/黑场、codec/device-loss 与 Windows parity |
| video as generic material provider | `L0` | typed frame publication 已有，但没有 material/effect slot consumer | slot purpose/UV/sampler/format、fallback、动态尺寸与 generation 原子绑定 |
| named primary variant producer | `L3` | bounded `_a` current-frame publication；[E-UTILITY](runtime-evidence-index.md#e-utility) | 通用 target/extent/format |
| named secondary variant identity | `L2` | registry identity 保留 `_b` | producer/consumer flow 尚未执行 |
| Texture Variant provider | `L0` | 无 variant schema/selection | property selection + authored fallback |
| system/media provider identity | `L2 carrier` | Template保留exact system demand；production snapshot缺少唯一purpose、publication不完整或lifecycle未证时明确发布/解释为unavailable，不伪造absent。current `$mediaThumbnail` bounded producer仍走独立typed合同；previous/transition已撤权 | 统一live producer、purpose仲裁、generic consumer、pause/rebuild/stop与teardown |
| generic material slots `0...7` | `L3 bounded execution；arbitrary S0` | Template固定保留8项及hole；Program原子携带variant/reflection、purpose/readiness、candidate metadata、uniform/state/color与identity，bounded子集已由唯一GraphExecutor完成GPU/publication/compositor/next-frame | ordinary arbitrary authored stage仍缺通用backend；继续补unproven purpose、state/color/helper、FBO command publication，不在consumer重做优先级 |

## 10. 现役路线与完成门

输入能力不再按旧B/R批次排序；唯一优先级见[Scene兼容执行路线](../scene-compatibility-roadmap.md)。

- V0/V1只补普通Program/graph当前真实消费的value、resource和topology invalidation，不为输入另建renderer状态。
- V2由per-scene QuickJS-NG VM接管generic script property、shared、handle、cursor/media/audio event与timer。
- V4逐项把property、pointer、audio、media、text和provider接入现有typed snapshot/publication/mutation；一个native bounded projection不升级对应generic SceneScript API。
- 每个新输入必须明确属于value-only、resource-generation、geometry/extent、program-variant或topology变化，只使最小owner失效。
- `311115e3`新接线在取得fresh产品运行和预定义ROI/事件证据前保持`S2 / visible unknown`；自动测试存在、formal matrix或非黑截图都不能替代。

普通material slots现已有bounded GPU consumer，旧`R3 gpuEncoded=0 / 下一步R4`已退役。arbitrary authored shader、generic VM、live media producer和完整event queue仍是明确待办。
