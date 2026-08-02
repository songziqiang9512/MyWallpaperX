# Scene 运行时系统语义

> 覆盖：Particle、Text、Timeline、SceneScript、User Properties、Cursor、Audio、Media、Puppet/3D，以及实时与离线共用的时钟和资源生命周期。
>
> 官方合同优先参考 Designer 文档与 `lib.sceneScript.d.ts` v2.8；raw JSON 字段来自真实样本观察，需按证据等级使用。
>
> 实现基线、当前 45 样本完整快照门与固定 13 样本回归门、签名 App 身份及聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)；本表不复制基线 commit，避免随代码演进失真。文内出现的 commit 号是该项能力的**历史落地提交**，不是当前基线。

## 1. 统一 Frame Context

所有动态能力应消费同一 host frame 的输入，但最终求值结果必须按 surface 隔离，避免每个 effect/particle/script 自己读系统时间，也避免不同屏幕共用 pointer、resolution 或脚本状态：

```text
HostFrameInputs
  frameIndex / runtime / daytime / rawFrameTime / simulationFrameTime / droppedFrameTime / discontinuity
  audio16 / audio32 / audio64 (host left/right; bounded consumers may derive average)
  mediaSnapshot / thumbnail generation
  userPropertyGeneration / deterministicRandomSeed
    -> SurfaceFrameContext
       canvasSize / screenSize / texelSize
       pointerCurrent / pointerPrevious / buttons
       cameraParallaxPosition / matrices / surface providers
         -> Surface EvaluationTransaction
         -> immutable SurfaceDynamicSnapshot
```

实时播放使用 display timing 和真实 provider；离线烘焙使用固定 timestep、可重放 provider 与固定 seed。二者必须走同一 simulation/update/render 入口。

MyWallpaperX 当前已落地第一阶段 `SceneFrameTiming` / `SceneFrameContext`：桌面宿主每帧只采样一次 monotonic host time 与 wall date，并把相同的 frame index、scene time、raw/simulation/dropped delta 和 discontinuity 广播给所有屏幕。particle 与相机视差平滑消费最大 0.25 秒的 simulation delta；shader time、内嵌视频 item-time 与 Timeline 继续使用既有 raw/absolute time。0.25 秒是项目从旧 particle 私有保护上移的 clean-room policy，不是官方客户端常量。各屏仍保留自己的 viewport、pointer 和 particle simulation。

`36bfef0` 建立了六类 `SceneDynamicValue`、主要 target、固定覆盖顺序和不可变 snapshot。当前 v22 已完成 property binding program、per-surface transaction/generation，以及 layer alpha、solid color、direct text content/point-size/color、bounded Timeline text width、Local Contrast/Opacity producer/consumer。dynamic text 按 layer signature 异步生成：普通并发拒绝 stale completion，连续 Timeline 则限制每层一个任务在途、合并为最新 generation，并以 last-ready 保持可见输出。SceneScript 除 exact native text/audio profiles 外，现有 property-bound text `update(value)` 的无循环 Date/string AST 子集；它只产生 String target，不能外推为通用脚本、particle、system/media text 或其他 effect constant。

这仍不等于完整时钟和动态系统合同。16/32/64 host audio 与 bounded consumers 已接入；Scene pause/resume 已在共享 clock、frame driver 与 embedded video provider 上形成受限状态合同；共享 clock 已明确 raw/simulation/dropped delta 与 discontinuity。真实系统 pause/sleep/hot-plug、seek/history、其他 simulation consumer、不同 FPS、buttons、media producer、完整 seed、离线 adapter、通用 SceneScript 与其余 Timeline/particle target 仍未闭合。

### 1.1 Frame timing、wall date 与 readiness 分离

2.8.42 客户端的 Ghidra 静态执行路径支持以下结构事实：

- frame delta 来自高分辨率单调计时；
- local/daytime 是另一类输入，不从 frame index 推导；
- resource/video readiness 与等待状态会影响调度。

MyWallpaperX 的公共合同应保持 monotonic delta、wall date、scene time 与 surface readiness 分离。本文不保存客户端等待常数；pause/resume、掉帧或 rebuild 后采用 clamp、freeze 还是显式 discontinuity，必须由项目自有 policy 和 fixture 定义。

### 1.2 Reset 与 interruption 是跨资源事务

静态路径显示 device loss/scene rebuild 会跨 render target、material/resource cache、provider 与 scene state 执行显式释放和重建，不是等待各对象被动 `deinit`。目标应有 `reset(reason, generation)` 或同等事务：

- 覆盖 render-target pool、material/shader cache、texture/provider、video、sound、particle、script 与异步任务；
- 旧 generation 的异步完成不得重新注入新场景；
- reset 后按确定顺序重建，失败保持可诊断状态。

用户暂停、screen lock、system sleep 与 display sleep 则由一个 reason-set interruption coordinator 管理：重复通知幂等，所有原因清除后才恢复。Frame driver、SceneClock、video、sound、provider、SceneScript、particle 与 history 必须同步冻结或遵循明确 discontinuity 规则，避免巨大 delta、视频相位和历史资源分叉。

### 1.3 Surface 策略是请求合同

Windows 客户端的 clone 扩展只证明存在独立 surface/window/swapchain 生命周期，不要求 macOS 复制 DirectComposition。Scene request 应显式选择 clone、span、per-display 或 selected/disabled display；公共层维护稳定 surface identity、共享 host time/只读资产，以及 surface-local viewport、pointer、history 和 teardown。

## 2. Particle System

官方 Particle 文档把系统明确拆成 General、Emitter、Initializer、Operator、Renderer、Control Point 和 Children。它不是“生成一些 sprite 然后向下移动”的单一算法。

官方入口：[Introduction](https://docs.wallpaperengine.io/en/scene/particles/introduction.html)、[General](https://docs.wallpaperengine.io/en/scene/particles/component/general.html)、[Emitter](https://docs.wallpaperengine.io/en/scene/particles/component/emitter.html)、[Initializer](https://docs.wallpaperengine.io/en/scene/particles/component/initializer.html)、[Operator](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html)、[Renderer](https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html)、[Control Point](https://docs.wallpaperengine.io/en/scene/particles/component/control_point.html)、[Children](https://docs.wallpaperengine.io/en/scene/particles/component/children.html)。

### 2.1 General

General 层至少包含：

- material/albedo/normal、cutout、lighting、refraction、overbright 和 blend；
- `max count`、start time、worldspace、perspective rendering；
- color/count/lifetime/size/speed override 是否允许；
- sprite sheet animation、frame blending 与 sequence multiplier；
- author instance overrides。

这些设置决定资源、simulation budget 和 renderer variant。一个粒子层可见不代表它立刻发射；start time、emitter delay/rate、max count 和 parent visibility 都要参与。

### 2.2 Emitters

官方当前文档列出：

| Emitter | 语义 |
|---|---|
| Sphere random | 围绕 origin/control point 在球/圆范围内随机生成 |
| Box random | 在矩形/盒范围内随机生成 |
| Layer image | 从 image、text 或 puppet layer 的有效像素生成，可继承颜色和 motion |

Sphere/Box 共享的高价值字段包括 offset、direction/sign、distance min/max、control point、rate、instantaneous、duration、delay、periodic emission、speed min/max 和 audio response。

Layer Image 的 emission bitmap 可以按需更新；官方特别说明只有动态纹理确实变化时才周期更新。时钟 text 是需要更新的例子，puppet 动画本身不要求每帧重建 emission bitmap。

### 2.3 Initializers

Initializer 只在粒子创建时设定初值。官方目录：

1. Lifetime random
2. Size random
3. Color random
4. HSV color random
5. Color list
6. Alpha random
7. Velocity random
8. Inherit control point velocity
9. Turbulent velocity random
10. Rotation random
11. Position offset random
12. Angular velocity random
13. Position around control point
14. Position between control points
15. Remap initial value
16. Inherit value from event

Random min/max 常带 exponent bias。固定值应通过 min=max 得到，不能另造默认分支。Velocity initializer 本身不推进位置；没有 Movement operator 时粒子不会移动。

### 2.4 Operators

Operator 在粒子存活期间逐步更新状态。官方目录：

| 组 | Operators |
|---|---|
| 基础运动 | Movement、Angular movement、Cap velocity |
| 生命周期曲线 | Alpha fade、Size change、Color change、Alpha change |
| 振荡 | Oscillate position、Oscillate alpha、Oscillate size |
| Control Point | Control point force、Maintain distance to control point、Maintain distance between control points、Reduce movement near control point |
| 场 | Turbulence、Vortex、Boids |
| 数据 | Remap value、Inherit value from event |
| 碰撞 | plane、sphere、bounds、quad、model |

很多 operator 有 blending window：blend-in start/end 与 blend-out start/end 都是相对单粒子 lifetime 的 0...1 进度，不是秒数。实现时应统一计算 normalized age，再让每个 operator 读取同一权重。

Movement 的 gravity、worldspace、drag；Vortex/Boids 的邻域；Collision 的 bounce/slide/stop/delete 和 death event 都是独立语义。未知 operator 应记录 unsupported，不能静默忽略后仍统计该粒子系统完整支持。

### 2.5 Renderers

| Renderer | 官方语义 |
|---|---|
| Sprite | 绘制独立 sprite，可有 orientation/worldspace 与 sprite sheet |
| Sprite Trail | 沿速度方向拉伸；length 乘 speed，并受 min/max length 限制 |
| Rope | 连续连接粒子；subdivision、UV scale/smoothing/scroll |
| Rope Trail | 按长度保留轨迹；segments/subdivision、UV scale/scroll |

只解析第一个 renderer 或把 Rope 映射成 Sprite Trail 都不是兼容实现。Rope 的连接拓扑、UV continuity 和 lifetime 约束需要单独 simulation/render data。

当前 `36b9775a` 让 root 与 strict child 共用同一 bounded Sprite Trail plan：显式 finite/nonnegative `length` 继续按作者值计算；省略或 `null` 时使用项目默认 `1`，再与缺省 `minlength=1` / `maxlength=1` 形成不伸缩、仅沿速度定向的有界形态。这个 `1` 来自官方 stock 多个合法 omitted-length definition 与公开 `length/min/max=1` 的 orientation-only 描述交叉约束，官方页面没有公布缺省数值，因此它仍是 clean-room 项目合同。任何已填写但 malformed 的 renderer 字段、非有限/负 length 或反序 min/max 继续失败关闭；真实 `3770444459` 的三组 water-impact child 与官方 stock `previewwaterimpact` 只证明执行和多相位运动，不证明 Windows 像素等价。

当前 `319214c5` 开放 bounded Rope 公共子集：单一 Rope renderer、Screen/nil orientation、静态纹理、`maxcount 2...512`，按单调 birth ID 连接相邻存活粒子；subdivision `0...7` 用 Catmull-Rom/Hermite position 曲线生成独立 quad，size/color/alpha 在细分端点线性插值，root 每帧最多 4,096 段。UV 支持 finite scale `1/1024...1024`、equal-lifetime smoothing 与 simulation-time scrolling；scrolling 按官方优先级覆盖 smoothing，具体每秒一轮是项目 bounded 解释。strict child Rope 为每个 child system 独立建链以避免跨系统连接，保留 General world-space 的 birth-time origin，并受 8,192 生成段聚合预算约束。Emitter one-per-frame 只准 stock corpus 对应的 raw bit 2；无已知 consumer、零 transform/flags 且没有未知组件的 parent CP mapping 可透明忽略，其他 CP 形态仍失败关闭。animated texture、root world orientation、多个 renderer、length/segments/fades 与 malformed/未知字段也继续拒绝。官方 stock subdivision 样本可见曲线和运动，但急弯处独立 quad 仍有三角/明暗接缝；这证明 bounded clean-room 执行，不是官方 ribbon join 或像素等价。

当前 `7cce5fde` 还让 root Sphere/Box emitter 消费 bounded static CP angle frame：只准完整 finite definition/instance vector3、local non-parent profile 与受控 flags，instance 当前值替换 definition 默认角；项目自有 X→Y→Z authored-radian 约定一致旋转 emitter local origin、shape sample 与 initializer velocity。dynamic user/script/animation、pointer/world/raw/parent、Layer Image 和其他 consumer 仍失败关闭。客户端 clean-room 静态资料只证明 CP position/angle 是并列 typed property family，且 emitter/Vortex/Map Sequence 可依赖 CP angle；它不证明项目旋转顺序、覆盖规则或数值等价。

### 2.6 Control Points

官方支持索引 0...7。Control Point 可配置：

- relative offset；
- lock to pointer；
- worldspace；
- 从 parent copy，可选 raw value；
- editor gizmo visibility。

Emitter、Initializer、Operator、Collision 和 Children 都可能引用 control point。坐标必须在 scene/object/particle/child spaces 间显式转换；不能把 screen cursor 直接当世界坐标。

官方 Control Point Force 允许正 scale 向 CP 吸引、负 scale 从 CP 排斥，并以 Maximum distance 限定范围；pointer 示例使用 CP 1 或更高索引并启用 Lock to pointer。官方把近中心减速与删除列为独立 operator，因此播放器不能把它们静默合并进 force。当前项目只执行 non-world、non-perspective、exact pointer-lock CP 与 bounded `controlpointattract` 的 local constant-radial-acceleration 子集；它是 clean-room 数值合同，不是官方 falloff 或轨迹公式。

### 2.7 Children 与事件

官方 child type：

| Type | 触发语义 |
|---|---|
| Static | 在 particle system origin 创建一次 |
| Event follow | 为 parent particle 创建并持续跟随的 child instance |
| Event spawn | parent particle 创建时在其位置生成 child |
| Event death | parent particle 生命周期结束/被 delete event 时生成 child |

Child 还可配置 offset、angles、scale、max count、probability 和 set control points。`Inherit value from event` 可传递 color/size/alpha 等 parent 值。

### 2.8 正确的粒子执行顺序

```text
resolve layer + parent visibility
  -> resolve general and instance overrides
  -> advance emitter schedules
  -> spawn particles
  -> run initializers once in authored order
  -> run operators in authored order with normalized age
  -> process collision/death/spawn/follow events
  -> update child systems and control points
  -> build renderer-specific instance/rope geometry
  -> draw with authored material/blend/camera mode
```

### 2.9 确定性和预算

- 随机数必须能按 wallpaper/system/particle seed 重放；不能每次使用不可控 `random_device` 后要求截图一致。
- simulation 使用明确 dt；离线固定 dt，实时可 clamp catch-up，但必须记录 dropped time。
- `max count`、child max count、prewarm、rope segments、collision 和 layer-image bitmap update 都进入性能预算。
- pause/resume 不应继续发射；恢复是否 catch up 必须由统一时钟策略决定。
- wallpaper switch/stop 后 particle、child、texture 和 GPU buffers 必须归零。

## 3. Text

### 3.1 Text 是 Scene object

Text 不是播放器 UI overlay。真实样本中的 text object 同时具有：

- layer origin/size/scale/angles、alpha/color、parent 和 parallax；
- font、point size、horizontal/vertical alignment、padding、background/copy-background/perspective 等 style；
- `text.value` 静态 fallback；
- `text.script` 与 `text.scriptproperties`；
- 与 image layer 相同的 ordered effect stack；
- 用户属性、Timeline 和 SceneScript 动态绑定。

`3750813609` 的 Clock 是直接证据：text fallback 为 `12:34`，实际值由 `Date` SceneScript 每帧生成；layer 还带 Blur 和 Clouds effects。只绘制静态 `12:34` 或只修 point size，都不可能复刻最终时钟。

### 3.2 macOS 文本运行时合同

建议以 CoreText/CoreGraphics 为主，而不是 SwiftUI `Text` 或手工字符宽度估算：

1. 根据作者 font family/file 建 CTFont，建立明确 fallback chain；
2. 使用 shaping、glyph advances、baseline、ascent/descent/leading；
3. 支持 CJK、combining marks、emoji/color glyph、缺字 fallback；
4. 官方 `ITextLayer` 声明把 `pointsize` 定义为“300 DPI 下的 point”，并说明 pixel `padding` 会增加字形周围 geometry、供越界 effect 使用；真实语料进一步证明序列化 `size` 已是含 padding 的外框，不能再加一次 padding。边对齐时 origin 对齐去掉 padding 后的内容边，center 仍对齐外框/内容共同中心；
5. 先在 text-local coordinate 生成 layout，再应用 layer scale 和 scene transform；
6. 保留 authored alignment、background、width/line/ellipsis 等实际出现的 layout 约束和 texture resolution；
7. text texture 作为正常 layer source 进入 effect graph；
8. text 值变化时只重建受影响 texture，并带 generation/cancel 机制。

字体文件与系统字体别名必须可诊断。找不到字体时记录 fallback 的具体字体，不能无声替换。

MyWallpaperX 当前按 alias → 包内文件 → 客户端自带（stock）→ 缺失四层解析，路径安全判定优先于后三层。官方 `systemfont_*` 别名共 8 个，缺失家族退到形态最接近的系统家族（`consolas` 必须落回等宽，否则语料引用最多的别名会从等宽退化成比例字体）；客户端 `assets/fonts` 的 15 个 stock 名字全部物理位于 `SceneStockAssets.bundle/assets/fonts`：8 个原版报 `stockBundled`；7 个替代字体按官方文件名读取并报 `stockSubstituted`。只有 app 包缺失或损坏时才落回系统家族近似并报 `stockApproximation`。替代字形不是官方字形等价，见 [E-TEXT-FONTREF](runtime-evidence-index.md#e-text-fontref)。

MyWallpaperX 当前的 `pointsize * 300 / 72` 直接来自官方 typings 对 `ITextLayer.pointsize` 的 300 DPI 说明，并由随包 `dino_run` 两个记分标签的作者 size 逐位复现，见 [E-TEXT-POINTSIZE](runtime-evidence-index.md#e-text-pointsize)。但 scene unit、raster backing scale 和 Retina 输出之间的精确关系仍需官方 Windows 对照，本地还对像素字号做了 1024 的夹取；实现和文档都不能把这一个换算提升为完整文字语义。

第 6 条里的 width/line/ellipsis 约束现在按作者开关执行：`limitwidth`/`maxwidth` 压窄换行宽度、`limitrows`/`maxrows` 丢弃多余行、`limituseellipsis` 在末行补省略号并回退到不越界，两个数值在开关关闭时必须完全不生效（本机语料 393 个关闭态 layer 都带着编辑器默认 `maxwidth: 500`，其中 79 个作者宽度已超过 500）。absolute 单 lane Timeline `maxwidth` 仅在 `limitwidth=true` 且作者、关键帧和实际消费的 Bézier control values 都位于有限 `1...16384` 像素预算时驱动同一 CoreText consumer；relative、Combined、越界与非文字形态失败关闭。省略号的回退粒度和被裁断点仍未与 Windows 逐像素对照，见 [E-TEXT-LIMITS](runtime-evidence-index.md#e-text-limits)。

### 3.3 Text 验收

- 同一字体、字号、画布下比较 baseline、bounding box 和 glyph 位置；
- 使用官方 user-property sample 的 20pt/32px padding text 与 Windows 官方输出校准 DPI/scene-unit 换算；
- 12/24 小时、seconds、delimiter 等 script properties 正确；
- 100-layer text 压力下无布局抖动或资源泄漏；
- Blur/Clouds/Blend 等 effects 在 text output 上按相同 graph 执行；
- 动态值变化不产生上一帧残影。

## 4. Timeline

官方说明 Timeline 可绑定任意 component property，且与 effect animation 是不同系统。

官方入口：[Introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html)、[Combined](https://docs.wallpaperengine.io/en/scene/timeline/combined.html)、[Modes](https://docs.wallpaperengine.io/en/scene/timeline/modes.html)、[Animation Events](https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html)。

### 4.1 播放合同

| 项 | 语义 |
|---|---|
| Loop | 到末尾后跳回开头 |
| Mirror | 到末尾后反向播放，再循环 |
| Single | 播放一次，停在最后状态 |
| Seconds / Frames | 总时长和 author keyframe 离散网格 |
| Start paused | 由 SceneScript 显式启动 |
| Wrap loop frames | 自动平滑首尾过渡 |
| Bézier | 默认平滑，可分别启用 left/right tangent 或关闭为 linear |
| Combined animation | 多个不同 property 可共享同一 animation timeline |

### 4.2 Animation Events

事件绑定到特定 animation frame，并发送给同一 layer 的 SceneScript `animationEvent`。事件本身不直接播放声音、切换 layer 或创建 effect；脚本决定后续动作。

### 4.3 求值与 FPS

Timeline 由 runtime time 求值，不应按“每渲染帧加一个 keyframe step”。高低 FPS 下同一 wall-clock time 必须得到相同 property value。离线固定 timestep 也必须走相同曲线求值器。

当前 `77883809` 的公共 evaluator 对每段消费 `start.front` / `end.back`：X 解释为 segment span 的归一化 offset，Y 解释为 property value offset，再按绝对 frame progress 二分反求 cubic parameter。缺失或禁用侧退化到对应端点，两侧禁用严格线性；enabled front/back X 分别只准 `0...1` / `-1...0`。该单位来自 44 份合法抽取场景中 48 animations / 180 keyframes / 112 segments 的 clean-room 机械定标，官方页面只确认默认 Bézier smoothing 和 left/right/none handle，不公开私有 JSON 单位。bounded text width 与 camera 另按实际消费的 control-value convex hull 守住预算；无 Windows 同相位数值或像素 golden。

## 5. SceneScript

### 5.1 官方合同

官方将 SceneScript 定义为基于 ECMAScript、移除 Web API、加入 wallpaper API 的 property-bound 系统。当前官方类型文件头标记 `VERSION 2.8`。

官方入口：[Introduction](https://docs.wallpaperengine.io/en/scene/scenescript/introduction.html)、[Reference](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html)、[`lib.sceneScript.d.ts`](https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts)。

脚本绑定一个具体 property：

- `init(value)` / `update(value)` 接收该 property 当前 typed value；
- 返回兼容类型则写回绑定 property；不返回则不修改；
- 脚本也可以通过 layer/effect API 同时修改其他 property；
- `update` 每个渲染帧调用，动画必须乘 `engine.frametime`；
- 应优先使用事件而不是把所有逻辑塞进 `update`。

### 5.2 生命周期和事件

官方 v2.8 声明及页面确认的事件集合：

| 组 | 事件 |
|---|---|
| 生命周期 | `init`、`update`、`destroy`、`resizeScreen` |
| 配置 | `applyUserProperties`、`applyGeneralSettings` |
| Cursor | `cursorEnter`、`cursorLeave`、`cursorMove`、`cursorDown`、`cursorUp`、`cursorClick` |
| Media | `mediaStatusChanged`、`mediaPlaybackChanged`、`mediaPropertiesChanged`、`mediaThumbnailChanged`、`mediaTimelineChanged` |
| Animation | `animationEvent`（官方 Timeline 页面确认；当前 d.ts 的 `IComponent` 列表未列出，作为官方资料间差异记录） |

`applyUserProperties` 首次加载调用一次；后续参数只包含变化键，脚本必须用 `hasOwnProperty` 检查。

### 5.3 对象/API 面

官方 d.ts 暴露的主要类型：

- math/value：`Vec2`、`Vec3`、`Vec4`、`Mat3`、`Mat4`、`CameraTransforms`；
- layer/content：`ILayer`、`IImageLayer`、`ITextLayer`、`ISoundLayer`、`IModelLayer`；
- effect/material：`IEffectLayer`、`IEffect`、`IMaterial`；
- particle：`IParticleSystem`、`IParticleSystemInstance`；
- animation/video：`IAnimation`、`IAnimationLayer`、`ITextureAnimation`、`IVideoTexture`；
- scene/global：`IScene`、`IEngine`、`IInput`、`IRenderContext`、`ILocalStorage`、`IConsole`；
- globals：`thisLayer`、`thisScene`、`engine`、`input`、`renderContext`、`localStorage`、`console`、`shared`；
- modules：`WEMath`、`WEVector`、`WEColor`。

实现不能只嵌入一个通用 JavaScript VM。必须先有 typed layer/effect/text/particle/material target 和确定生命周期，否则大部分脚本即使能执行也没有可写对象。

当前实现把文档级 inline property binding 的 scene/object/effect/pass owner、完整 JSON target path、source、properties、authored fallback 与 JSON value type 保真进 IR（`L1`），正式取证五类位置有 13-shape 自建门；nested/未知 owner 不提升，`script + user` 冲突 fail-closed。七个 exact text source profile与两个 64-band audio source profile被编译为严格失败关闭的 native `L3 bounded` consumer；property-bound text 另可按公共语法准入唯一 `update(value)` 的无循环 AST，以 primitive property、Date getter 与 string operations 产生 typed String。audio profile 的 64 次 Metal draw 是 renderer instance，不产生动态 Scene layer、`ILayer` handle 或 topology；file/module、schema-resolved non-String value type、通用 ECMAScript VM、`registerAudioBuffers`、`AudioBuffers` object、`createLayer`、事件和实例生命周期仍全部为 `L0`。

### 5.4 安全和资源边界

- 不提供 DOM、network、Node.js、shell 或任意文件系统 API；
- 每帧 instruction/time budget、timer budget、内存上限和异常隔离；
- wallpaper switch/stop 取消 timer、provider subscription、dynamic layers 和 pending task；
- script error 只降级绑定 property，不能中止整个 renderer；
- `localStorage`、user shortcut 和外部文件动作按 macOS sandbox/TCC 单独设计，不照搬 Windows 行为。

### 5.5 SceneScript 模块边界静态互证

2.8.42 的 32/64 位主程序与 SceneScript module 的有界 Ghidra 路径补充确认：

- 主程序先做精确版本握手，匹配后才执行 module init 和 engine creation；版本不符失败关闭；
- engine 使用固定事件槽、timer、watchdog 与每回调耗时统计，不是 renderer draw 中的一次无预算 `eval`；
- host 侧两条独立 lifecycle path 都会主动派发 `destroy` 事件；DLL 的 record/engine 清理不会自行合成该事件；
- 因此 owner removal 前 exactly-once `destroy` 是宿主职责。`destroy -> record removal -> engine teardown` 的完整相对顺序仍不能由静态 vtable 无歧义恢复，需最小 fake-VM fixture 或 Windows dynamic trace；
- interval 由 frame delta 驱动，到期每帧至多执行一次，不追补积压周期；项目应把 drift/catch-up 行为写成显式 timer policy。
- 两个架构的 module 都公开 init/factory/version/shutdown；`thisLayer`、engine、scoped storage、audio registration 和 timeout/interval 形成相同 host registration 邻域。它证明关键 owner bridge 结构对应，不证明逐函数、ABI、事件顺序或性能等价；输入身份与限制见 [官方客户端运行机制静态取证](client-runtime-static-forensics.md)。

独立 module、engine instance、owner script instance 与 host event bridge 是四个生命周期层。官方 API、事件与 ECMAScript 版本仍以 §5.1–5.3 的公开资料为准；本节不改变当前 Generic VM/Event 的覆盖等级。

## 6. User Properties

官方类型：

| 类型 | UI/值 | 关键合同 |
|---|---|---|
| `color` | color picker | 颜色空间和 Vec/string 转换明确 |
| `slider` | number | min/max、整数/小数模式、default |
| `bool` | checkbox | 只控制绑定 target，不推断同名 effect |
| `combo` | options label + hidden value | 传实际 option value，不传显示文本 |
| `textinput` | string | 动态 text/script property 常用 |
| `texture` | image/video replacement | 授权、bookmark、fallback、decode lifecycle |
| `usershortcut` | 系统快捷方式 | macOS 默认安全降级或明确授权 |
| group | UI 分组 | 不是运行时值 |
| display condition | 条件显示 | 只影响面板显示，不应销毁未显示属性值 |

Texture Variants 可由 Checkbox/Combo 选择；官方明确不能由 SceneScript 切换。macOS 的自定义文件需要 security-scoped bookmark、持久化恢复、替换失败回退和资源 generation，不能只把绝对路径字符串传入 renderer。

官方 UI 文档把这类属性称为 `texture`，真实 Workshop/官方样本族中还会出现 `scenetexture` 序列化名称。MyWallpaperX v20 继承 v17 parser 的归一化：二者进入同一内部 texture-provider 类型并保留原始 runtime type；这只是一项兼容归一化，仍不能宣称两个 raw schema 在所有版本完全等价。

属性窗口读取 `project.json` 定义；shader editor uniform 不能自动冒充 Wallpaper 用户属性。MyWallpaperX 继续保留独立、可拖动属性窗口这一产品设计。

## 7. Cursor、Audio、Media 与动态纹理

### 7.1 Cursor

应同时维护 screen-normalized、canvas/world、object-local 和 effect-local 坐标。Camera Parallax 使用 scene-level normalized input；cursor effect、control point 和 SceneScript 使用各自转换后的坐标。上一帧 pointer 也是 shader built-in，不能永远等于当前值。

### 7.2 Audio

Scene 与 Web 音频合同不同：

- SceneScript `engine.registerAudioBuffers()` 选择 16、32 或 64 bins；
- 提供 left、right、average，并按每个 render frame 更新；
- shader 侧公开 16/32/64 left/right arrays；
- effect/particle 自己定义 frequency min/max、channel、bounds 和 exponent；
- 无消费者时应停止 capture，静音/无权限时提供稳定零输入而不是假波形。

测试必须区分 provider 注册、频谱数值正确和最终 visual consumer 生效三层。

MyWallpaperX 当前状态（见 [E-AUDIO-INPUT](runtime-evidence-index.md#e-audio-input)、[E-AUDIO-EFFECT](runtime-evidence-index.md#e-audio-effect)）：host-shared snapshot 同一次 FFT 生成 16/32/64 档 left/right 并每帧广播给所有 surface；采集按 consumer 存在性驱动，无消费者/暂停/锁屏/休眠停采并归零，失败输出稳定全零。consumer 包括 stock Shake/Pulse、三个 exact Workshop Audio Bars，以及两个 exact native property-script 64-band Audio Bars。后者仅在 geometry consumer 内按 `(left + right) / 2` 派生 average；没有 JS `AudioBuffers` object、Float32Array identity 或脚本订阅。粒子 audio 声明已保真解析但未执行，effect 与粒子两套 schema 不能互推。

三处未知必须继续标注：频率边界、幅度归一化与平滑策略官方均未公开；当前的 32 Hz→16 kHz 对数划分与 -60 dB 映射是工程选择，与 Web 侧的 64+64 合同互不适用；采集 30 Hz 与渲染 60 Hz 之间不插值。

Scene `Sound` 对象与 host spectrum provider 是两条合同。`mediaextensions64.dll` 的静态边界覆盖 source/device/context、play/pause/stop/rewind、buffer queue、capture、device pause/resume 和线程化 teardown，但它不代表项目必须实现完整 OpenAL。最小公共 Sound 生命周期应先覆盖 owner-scoped prepare/play/pause/resume/stop/dispose、one-shot/loop/volume、decoder/buffer budget 和 device reset；Scene 自己的声音是否回馈到 spectrum 必须显式定义。

### 7.3 Media

官方 SceneScript 提供 status、playback、properties、thumbnail 和 timeline 事件。运行时需要 generation-based snapshot：

- title/artist/album/status/timeline；
- thumbnail texture 与主色等派生数据；
- 缺失 metadata/thumbnail 的 authored fallback；
- track switch 的原子更新，旧封面 decode 不得覆盖新曲目；
- 无 consumer 时解除订阅。

`$mediaThumbnail` 或等价 system texture 是 provider 资源，不是普通文件路径。

2.8.42 的 `winrtutil64.exe` 静态边界进一步支持“异步系统媒体 snapshot producer”：

- provider identity、status、metadata、timeline 与 thumbnail 必须共享 generation；
- track/stream switch 原子更新，stale thumbnail decode 必须取消或丢弃；
- scene pause/switch/rebuild 要与 start/pause/resume/seek/reset/current-frame 同步；
- last-ready/authored fallback、图像尺寸/格式/方向和资源上限是 provider 合同；
- stop 后 observer、pending task、临时资源与 texture 全部释放。

这是跨平台设计依据，不要求 macOS 复制 WinRT 类、进程拓扑或图像处理表达。A→B→C（B 故意延迟）的自有 fixture 必须证明 B 永不覆盖 C。

### 7.4 Scene Texture

用户 texture、Texture Variant、其他 layer/named target、media thumbnail 和 video frame 都应实现统一 typed texture provider，但来源和生命周期不同。resolver 必须保留：

- provider kind；
- authored fallback；
- security authorization；
- generation/cancel；
- mapped/physical size；
- color/alpha/format；
- consumer slots。

当前 v22 继承 typed registry 的 identity/status/resource generation/frame epoch。文件型第一切片仍只服务静态 image-blend；dynamic text 以 per-layer signature/generation、串行异步 raster、stale cancellation 和 last-ready fallback 消费同一生命周期边界。embedded MP4 已有 launch-scoped publication generation；bounded media cover 另以 current/previous content generation、旧 request 协作取消、pending last-ready、clear/failure fallback 和严格 transition consumer 验证动态 provider。它们尚未抽成所有 provider 共用的 status/metadata/cancel/teardown，也不证明 Texture Variants、通用 video/material consumer、live system-media adapter 或 SceneScript 可用。

## 8. Puppet、3D 和 Lighting

Puppet 已有第一个受限执行子集：MDLV mesh block 在加载时把图集重组为 bind-pose 纹理（`8bac86e`，`executed-degraded`），下游 mask/effect/blend 无感消费；MDLS 骨骼、MDLA 动画、MDAT attachment 只解析边界不消费。其余能力不属于当前 P0，但格式和时钟设计不能提前封死：

- Puppet：bone hierarchy/weights、animation、spring/rigid/rope/wind、animation events、attachment-relative child 定位；
- 3D：model/node/material、skeletal animation、attachments、camera、physics；
- Lighting：2D PBR maps、point/spot/tube/directional light、shadow、reflection、volumetric；
- 与 2D layer/effect/particle/text 使用同一 scene order、camera、provider 和 post process。

官方文档提示实时灯光、体积光和复杂物理开销显著，必须与 quality/performance policy 同步实现。

## 9. 实时播放与离线烘焙

WaifuX 的可取经验是实时和 bake 调用同一 renderer，不是其二进制或实现细节。MyWallpaperX 的目标结构：

```text
Shared Scene Core
  Scene IR
  Resource Registry
  Typed Property Runtime
  SceneClock + RNG
  Particle/Timeline/SceneScript update
  Render Graph

Realtime Adapter              Offline Adapter
  display time                  fixed dt/frame index
  live cursor/audio/media       recorded/synthetic providers
  drawable present              texture readback -> PNG/video
```

离线第一阶段先输出 PNG/readback，用相同 sample/property/time/seed 与实时捕获做像素对照；确认等价后再增加编码、缓存和队列。没有显式 provider replay 时，不应声称动态媒体/音频 bake 与实时一致。

## 10. 当前实现映射

当前事实以 [总覆盖台账](coverage-ledger.md) 与 [运行证据索引](runtime-evidence-index.md) 为准。这里仅列语义边界：

| 系统 | 当前实现状态 | 不能据此宣称 |
|---|---|---|
| Particle | 作者 2D sprite、部分 emitter/initializer/operator、bounded initial emitter delay、bounded static CP-angle emitter frame、bounded classic Vortex、bounded Cap Velocity、root/strict-child 共用的 bounded Sprite Trail、bounded root/strict-child Rope 与 strict child 子集；initial delay 只准有限 `0...3600 s`，Sphere/Box/Layer Image 共用 fixed-step gate，duration 从 delay 后计时并可与已准入 periodic profile 组合；static CP angles 只准 root Sphere/Box 的有限 local vector3，并以项目自有 X→Y→Z frame 旋转 origin/shape/velocity；classic Vortex 只准 finite non-audio v1 axis/distance/speed 与 standard/infinite-axis flags，使用项目自有 fixed-step 切向加速度；Cap Velocity 只准显式 finite max speed、strict normalized-age blend 与无扩展 profile，并按项目自有 weight 保持方向地移除超速比例；Sprite Trail 对 omitted/`null` length 使用项目默认 `1` 并保留 malformed fail-closed，Rope 按 birth ID 建隔离 topology，支持 bounded subdivision、UV scale/equal-lifetime smoothing/scrolling 与 child birth-time world origin；exact pointer-lock CP 1...7 可驱动 bounded local Control Point Force；Particle slot 0 可按 exact identity 消费 bundle 内 164 项 TEX，22-key 程序纹理只作缺失回退 | 路径存在或程序 fallback 等于官方视觉资产，或 child/Rope/world-space/control point/collision/audio/全部 preset 完整；CP-angle 没有 Windows Euler/trajectory/pixel golden，dynamic angle 与其他 consumer 仍失败关闭；initial delay 没有 Windows fixed-step/组合 timing golden；classic Vortex 没有 Windows 数值/轨迹 golden，audio/CP/center force 与 `vortex_v2` ring 仍失败关闭；Cap Velocity 没有 Windows blend/clamp/轨迹 golden；Sprite Trail 默认值没有 Windows golden，Rope 仍不含 animated/root-world/multi-renderer、official curve/scroll/ribbon join 等高级语义且急弯有接缝；pointer force 没有 previous pointer、其他 consumer、world/perspective、官方 falloff/轨迹 golden，粒子 audio 声明虽已保真解析但 simulation 仍不消费 |
| Text | CoreText 静态纹理、direct property 与 bounded Timeline width 动态重栅格、部分 font/pointsize/padding/scale | system/media、完整 alignment/effects/SceneScript、Windows 排版等价 |
| Effect graph | 内存 `SceneRuntimeInput` 保存 EffectDefinition/authored graph/provider metadata、ShaderContract 与 binding program；十四类 strict backend 及 ordered chain 已执行，包含 stock Radial God Rays 五 pass / 双 half RT。Debug evidence schema 1 只作结构验证 | dynamic effect、generic compose/history、通用 material/pass、authored shader 语义等价、未知/Directional God Rays 或官方 Shadow/lighting；精确当前门见 [运行证据索引](runtime-evidence-index.md) |
| Frame Context | 宿主单一 60 Hz driver；所有屏幕共享 frame index/host/scene/wall time 及 raw/simulation/dropped delta/discontinuity；particle/parallax 消费受控 simulation delta，shader/video/Timeline 保持 raw/absolute time；pause 冻结 scene time/frame index，resume 首帧不补 host gap | 真实系统 pause/sleep、seek/history、其他 simulation consumer、不同 FPS、离线实时等价或 Windows timing 已闭环 |
| Dynamic target snapshot | 六类 typed value、主要 target 族、固定优先级、binding program、per-surface evaluation transaction/snapshot/generation；layer alpha、纯 solid color、direct text、bounded text width、exact Local Contrast/Opacity、受限 X-Ray target，以及 Timeline 的 effect constant/layer alpha/bounded relative layer transform/root particle scalar/camera 子集有真实 producer/consumer | 非 layer-transform `relative`、generic Combined/其他 target、SceneScript 与多数 particle dynamic target 仍未 live；unsupported host 留诊断 |
| Timeline | IR、绝对 scene-time evaluator、bounded 作者 Bézier handle、9 条 Loop wrap 闭合段与 **48/48** typed authored-host 子集已执行，覆盖 Loop/Single/Mirror/start-paused、effect constant/layer alpha、9 条 relative layer transform、7 条 root particle scalar override、2 条 bounded text `maxwidth` 及 camera `origin/zoom` 两成员；5 条普通 transform 走共享 world-frame，4 条 `lspot` 保持 strict consumer，camera 组共享 owner clock 并原子进入 projection | 私有 `relative` 合成与 handle/wrap 单位均是 bounded clean-room 校准；generic Combined、multiple path/3D camera、event crossing、其他 target 与 Windows 同相位 golden 未完成，不能宣称任意 Timeline 可用 |
| SceneScript | 顶层 layer binding IR 为 `L1`；七个 exact text、两个 exact 64-band audio profile和 property-bound text Date/string update subset 为 `L3 bounded` | 通用 ECMAScript VM/API、`registerAudioBuffers`/`AudioBuffers`、`createLayer`/`ILayer` handles 可用 |
| User Properties | 独立窗口、条件、默认/override、部分 target 与持久化；`texture`/`scenetexture` 内部归一；受限静态 consumer 可选择 PNG/JPEG；已注册 B0/direct text/X-Ray target 可无重建更新 | 全部样本属性可调、所有 texture target/variant/live value 已闭环 |
| Texture Provider | frame identity/status/generation、named variant 隔离、property absent -> authored fallback、受限 file-backed property source；direct text/embedded MP4 使用显式 content generation，视频有 launch-scoped pause/rebuild/stop 合同；bounded current/previous media cover 还有旧 request 协作取消、last-ready/fallback 与一个严格 transition consumer | live system-media adapter、Texture Variants、generic video/material、effectful/nested provider、其余 provider cancellation 与单次 decode 抢占尚未闭环 |
| Audio | Scene 16/32/64 host left/right、既有 effect consumers 与两个 native 64-band average profiles 已闭合 | JS `AudioBuffers`、Sound/self-play、粒子 audio 或任何数值/视觉 parity |
| Media | Scene 已有 bounded current/previous cover provider、严格 current Blend 与 previous gradient transition consumer；只有隔离 debug producer | live macOS producer、metadata/status/timeline snapshot、通用 event/SceneScript、其他 transition/variant 与真实切歌 lifecycle |

## 11. 实施顺序

1. D1-D4 的 property 子集已完成：稳定 target、v22 binding program、per-surface evaluation transaction/snapshot、原子 generation，以及 B0/direct text/X-Ray 真实 consumer；未迁移 target 继续使用 rebuild fallback。
2. D6 ordered strict effect-chain 与十四类 strict backend 已完成受限执行，包含 `Blur Precise -> Shadow`、Water chain、pointer-driven X-Ray 与 `[Blur Precise, God Rays]` 正门；这些 profile 不升级通用 graph、Directional/COPYBG God Rays、官方 Shadow/lighting 或 authored shader。
3. Provider Core 已为 dynamic text 与 bounded media cover闭合局部 generation/cancellation/last-ready；继续补通用 metadata/cancellation/teardown。nested/effectful provider 和通用 material consumer 放在 B1/B2 集成层，不能互相形成前置环。
4. Direct dynamic text、bounded Timeline text width、X-Ray pointer、Timeline 的 **48/48** authored-host typed target 与作者 Bézier handle、16/32/64 audio 输入、两个 exact native 64-band profiles 与 bounded media cover 已完成；SceneScript core、Sound、通用 media、generic Combined/multiple camera path/3D camera 与其余 particle 动态能力继续按 D10 的真实依赖接入。粒子 audio 在拿到官方求值公式证据前不接执行。
5. exact stock Opacity、Tint mask 与 stock Radial God Rays 子集已完成；下一批从能力开发计划按公共依赖、真实样本收益和 fail-closed 边界重新选择，不新增 effect-name 或样本 ID 近似。
6. 广度闭合后用固定、扩展和新下载样本矩阵暴露冲突，再用 Windows golden 校准 effect、text、particle 和动态值精度；最后扩 Puppet/3D/Lighting 与离线编码产品层。

每一步都同时需要正向样本和默认关闭/未声明反例。
