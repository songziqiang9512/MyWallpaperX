# Scene 运行时系统语义

> 覆盖：Particle、Text、Timeline、SceneScript、User Properties、Cursor、Audio、Media、Puppet/3D，以及实时与离线共用的时钟和资源生命周期。
>
> 官方合同优先参考 Designer 文档与 `lib.sceneScript.d.ts` v2.8；raw JSON 字段来自真实样本观察，需按证据等级使用。

## 1. 统一 Frame Context

所有动态能力应消费同一帧快照，避免每个 effect/particle/script 自己读系统时间和输入：

```text
SceneFrameContext
  frameIndex
  runtime / daytime / frameTime
  canvasSize / screenSize / texelSize
  pointerCurrent / pointerPrevious / buttons
  cameraParallaxPosition
  audio16 / audio32 / audio64 (left/right/average)
  mediaSnapshot / thumbnail generation
  userPropertyGeneration
  deterministicRandomSeed
```

实时播放使用 display timing 和真实 provider；离线烘焙使用固定 timestep、可重放 provider 与固定 seed。二者必须走同一 simulation/update/render 入口。

MyWallpaperX 当前已落地第一阶段 `SceneFrameTiming` / `SceneFrameContext`：桌面宿主每帧只采样一次 monotonic host time 与 wall date，并把相同的 frame index、scene time 和 frame delta 广播给所有屏幕；shader time、视频 host time、粒子推进和相机视差平滑已消费该快照。各屏仍保留自己的 viewport、pointer 和 particle simulation。

这只是统一输入底座，不等于完整时钟合同。pause/resume、长帧 delta clamp、dropped-time 诊断、固定 timestep、buttons、audio/media/property generation、deterministic seed 和离线 adapter 尚未接入；Timeline、SceneScript 与动态文字也还没有消费该上下文。

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

### 2.6 Control Points

官方支持索引 0...7。Control Point 可配置：

- relative offset；
- lock to pointer；
- worldspace；
- 从 parent copy，可选 raw value；
- editor gizmo visibility。

Emitter、Initializer、Operator、Collision 和 Children 都可能引用 control point。坐标必须在 scene/object/particle/child spaces 间显式转换；不能把 screen cursor 直接当世界坐标。

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
4. 官方 `ITextLayer` 声明把 `pointsize` 定义为“300 DPI 下的 point”，`padding` 定义为 pixel；先保留这两个 authored 单位，再通过明确的 scene/text raster scale 转换，不能把 macOS 72 DPI point 直接当最终像素；
5. 先在 text-local coordinate 生成 layout，再应用 layer scale 和 scene transform；
6. 保留 authored alignment、background、width/line/ellipsis 等实际出现的 layout 约束和 texture resolution；
7. text texture 作为正常 layer source 进入 effect graph；
8. text 值变化时只重建受影响 texture，并带 generation/cancel 机制。

字体文件与系统字体别名必须可诊断。找不到字体时记录 fallback 的具体字体，不能无声替换。

MyWallpaperX 当前的 `pointsize * 4` 是 E 级样本近似，不是官方换算公式。它已经改善部分静态样本，但 300 DPI、scene unit、raster backing scale 和 Retina 输出之间的精确关系仍需官方 Windows 对照；实现和文档都不能把 `* 4` 提升为完整文字语义。

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

### 5.4 安全和资源边界

- 不提供 DOM、network、Node.js、shell 或任意文件系统 API；
- 每帧 instruction/time budget、timer budget、内存上限和异常隔离；
- wallpaper switch/stop 取消 timer、provider subscription、dynamic layers 和 pending task；
- script error 只降级绑定 property，不能中止整个 renderer；
- `localStorage`、user shortcut 和外部文件动作按 macOS sandbox/TCC 单独设计，不照搬 Windows 行为。

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

官方 UI 文档把这类属性称为 `texture`，真实 Workshop/官方样本族中还会出现 `scenetexture` 序列化名称。MyWallpaperX v17 parser 已把二者归入同一内部 texture-provider 类型并保留原始 runtime type；这只是一项兼容归一化，仍不能宣称两个 raw schema 在所有版本完全等价。

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

### 7.3 Media

官方 SceneScript 提供 status、playback、properties、thumbnail 和 timeline 事件。运行时需要 generation-based snapshot：

- title/artist/album/status/timeline；
- thumbnail texture 与主色等派生数据；
- 缺失 metadata/thumbnail 的 authored fallback；
- track switch 的原子更新，旧封面 decode 不得覆盖新曲目；
- 无 consumer 时解除订阅。

`$mediaThumbnail` 或等价 system texture 是 provider 资源，不是普通文件路径。

### 7.4 Scene Texture

用户 texture、Texture Variant、其他 layer/named target、media thumbnail 和 video frame 都应实现统一 typed texture provider，但来源和生命周期不同。resolver 必须保留：

- provider kind；
- authored fallback；
- security authorization；
- generation/cancel；
- mapped/physical size；
- color/alpha/format；
- consumer slots。

当前 v17 已实现 frame-scoped typed identity、ready/pending/unavailable、generation、完整 named-target variant，以及 property provider 缺失时按有序候选回退 authored layer；下一帧未重新发布的 named target 会清空。文件型第一切片还会把按 wallpaper/property 保存的 PNG/JPEG bookmark 在同步 security scope 内解码为每屏设备的 `MTLTexture`，并由 `SceneMetalView` 发布到 registry；只为当前严格静态 image-blend consumer 暴露控件。它不证明 `$mediaThumbnail`、Texture Variants、视频帧、通用 material consumer、动态 alpha 或 SceneScript 已经可用。

## 8. Puppet、3D 和 Lighting

这些能力不属于当前 P0，但格式和时钟设计不能提前封死：

- Puppet：mesh、bone hierarchy/weights、animation、spring/rigid/rope/wind、animation events；
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

当前事实仍以 [Scene 开发计划](../scene-capability-development-plan-2026-07-22.md) 为准。这里仅列语义边界：

| 系统 | 当前实现状态 | 不能据此宣称 |
|---|---|---|
| Particle | 作者 2D sprite、部分 emitter/initializer/operator、built-in drop、Sprite Trail 子集 | child/rope/control point/collision/audio/全部 preset 完整 |
| Text | CoreText 静态纹理、部分 font/pointsize/padding/scale | 动态时间、完整 alignment/effects/SceneScript |
| Effect graph | v17 继承 v16 EffectDefinition/authored graph，并增加 provider metadata；strict precise 子集有 5 个 layer、standard Blur 默认 profile 有 1 个 layer 的 degraded GPU 执行；非默认 standard 图明确 blocked | 通用 material/pass 已执行、authored shader 语义等价或达到 WE 像素一致 |
| Frame Context | 宿主单一 60 Hz driver；所有屏幕共享 frame index/host/scene/wall time；shader、video、particle、parallax 已迁移 | pause/resume、delta clamp、固定 timestep、离线实时等价已闭环 |
| Timeline | 数据识别不足或空壳 | 任意动画模式可用 |
| SceneScript | 只检测 script | ECMAScript/runtime/API 可用 |
| User Properties | 独立窗口、条件、默认/override、部分 target 与持久化；`texture`/`scenetexture` 内部归一；受限静态 consumer 可选择 PNG/JPEG | 403 个样本属性全部可调、所有 texture target/variant/live value 已闭环 |
| Texture Provider | frame identity/status/generation、named variant 隔离、property absent -> authored fallback、受限 file-backed property source | system media、Texture Variants、视频、通用 material 与 effectful/nested provider 已闭环 |
| Audio/Media | Web 侧已有服务，但 Scene consumer 未闭合 | Scene 音频/媒体可用 |

## 11. 实施顺序

1. 继续扩充已经落地第一阶段的 Frame Context，并建立 typed dynamic target / value snapshot；
2. 以可运行基线为目标横向接通 Timeline、SceneScript core、动态 text、cursor/audio/media 输入，不先在单项视觉细节上反复打磨；
3. 同批补齐高命中 built-in particle、Texture Variants、system/media/video provider 与通用 material consumer；
4. 让上述 live/provider 能力进入 authored graph，再闭合 copy/swap/compose/history 和更多 shader/material/pass backend；
5. 用固定、扩展和新下载样本矩阵集中暴露语义冲突，再按共享根因纵向校准 effect、text、particle 和动态值精度；
6. 最后扩 Puppet/3D/Lighting、离线固定步进与编码产品层。

每一步都同时需要正向样本和默认关闭/未声明反例。
