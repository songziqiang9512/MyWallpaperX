# Scene 官方语义与实现覆盖台账

> 状态：现役、唯一能力表
>
> 最近核对：2026-07-23
>
> Scene 实现基线：`8f55f44`
>
> 运行基线：`.codex/scene-particle-builtins-final13-r2-20260723/report.json`

本表把已收集的 Wallpaper Engine 作者语义逐项映射到 MyWallpaperX 当前代码、运行证据和下一道验收门。详细语义仍以同目录专题文档为准；这里回答三个问题：官方是否有这项能力、当前播放器走到哪一级、下一步补什么公共能力。

## 1. 口径

| 等级 | 含义 | 允许的结论 |
|---|---|---|
| `L0 absent` | 当前 Scene 管线没有结构或运行入口 | 未实现 |
| `L1 recognized/preserved` | 能识别声明、保留部分字段或输出诊断 | 已识别，不能宣称可播放 |
| `L2 wired/routed` | 已进入 IR、资源或 Render Graph 路由，但没有可靠执行结果 | 已接线，不能宣称有效果 |
| `L3 executed-degraded` | 有受限执行器和正反测试，仍有明确语义或视觉偏差 | 可用子集，必须同时写明边界 |
| `L4 semantics-verified` | 作者启用、输入、顺序、生命周期和视觉/数值门均与 WE 基准核验 | 该合同可宣称语义兼容 |

系统等级取 schema 保留、作者启用、运行消费、生命周期和语义/视觉门中的最低值，不做平均。某一子集达到 `L3` 不会把同名系统整体升级；`13/13` 只代表当前固定矩阵通过运行门，不是样本兼容率或 WE 还原率。

当前没有任何完整系统达到 `L4`。官方公开的作者能力已经建立完整索引，但 Wallpaper Engine 没有公开完整稳定的私有 Scene/PKG/TEX 序列化规范，也没有公开 Windows 渲染器实现；未知字段仍须用合法样本、官方 assets 或 Windows golden 继续核验。

## 2. 官方资料覆盖

| 资料面 | 收集状态 | 权威入口 | 仍未知 |
|---|---|---|---|
| Scene 官方页面 | 179 个 `/en/scene/` 页面已建目录，2026-07-22 经代理核验 | [官方页面全目录](official-page-catalog.md) | 官方未来页面变化 |
| 官方 Effect | 45 个用户可见 effect + `_empty` 内部占位已整理 | [内置 Effects 语义全集](effects-reference.md) | 私有 shader 精确算法和全部历史版本 |
| SceneScript | 官方 `lib.sceneScript.d.ts` VERSION 2.8 已索引 | [运行时系统语义](runtime-systems-reference.md) | Windows VM 的非公开行为和预算细节 |
| Scene/Effect/Material/Shader/RT | 作者合同与观察格式已分级记录 | [场景格式与 Render Graph](scene-format-and-render-graph.md) | 完整私有 schema、默认值和所有 combo |
| Particle/Text/Timeline/属性/输入 | 官方作者语义与执行顺序已整理 | [运行时系统语义](runtime-systems-reference.md) | 未公开 preset 资产内容和平台精确视觉 |
| 来源与许可证 | 官方、样本、WaifuX、linux-wallpaperengine、当前代码分级 | [资料来源与证据索引](source-index.md) | 第三方实现不能替代官方真值 |

因此，后续一般不再猜“这个能力是什么”；实现前先查上述合同。仍需研究的部分应明确标为私有格式/算法未知，不能用视觉近似反向定义官方语义。

## 3. 系统总表

| 系统 | 当前级别 | 当前真实能力 | 主要缺口 / 升级门 | 批次 |
|---|---|---|---|---|
| PKG/TEX/资源索引 | `L3` | loose/PKG 查找、常见 TEX、内嵌 MP4、诊断式失败 | case/symlink/duplicate/多格式边界与完整 VFS golden | B1 |
| Scene IR 与层级 | `L3` | 基础对象、顺序、父子 transform/visibility、常见 image/text/solid/particle | composition、模型、复杂 object component 和全部动态字段 | B1 |
| 画布/cover/背景 | `L3` | cover 投影和非默认视差门，已避免以灰底填未覆盖区域 | 多比例、多屏和 Windows 像素基准 | B4 |
| Frame Context | `L3` | host 单一 60 Hz driver；shader/video/particle/parallax 同帧 timing | pause/resume、delta clamp、fixed step、目标 FPS、离线 adapter | B0 |
| Dynamic target snapshot | `L2` | 部分用户属性可绑定；更新通过受控 Scene 重建 | typed target registry、同帧不可变快照、优先级、无重建更新 | **B0** |
| Timeline | `L1` | 只有未消费的 duration 类占位；没有 Timeline IR | keyframe/mode/tangent/event、确定性 evaluator、target 写回 | **B0** |
| SceneScript | `L1` | 只检测 inline/`.js` 存在 | source IR、安全 ECMAScript、生命周期、API/events、预算隔离 | **B0** |
| Cursor 输入 | `L3` | current/previous pointer、screen/canvas/layer local 坐标和声明驱动 camera parallax 子集 | buttons/down/up/click、effect/control-point/script 坐标 golden | B0/B3 |
| Audio 输入 | `L1` | 声明和部分粒子参数可保留；Scene 不消费频谱 | 16/32/64 双声道 snapshot、consumer、停采集与设备生命周期 | B0 |
| 内嵌视频纹理 | `L3` | TEX 内嵌 MP4 image-layer 播放，消费共享 host time | seek/pause/switch/loop 精确合同及更多容器 | B1 |
| 系统媒体 provider | `L1` | `$mediaThumbnail` typed 引用存在；无 producer/consumer | provider snapshot、事件、缩略图 generation、脚本/文字/纹理消费 | B1 |
| Particle | `L3` 子集 | 作者 sprite、常见 emitter/initializer/operator、Sprite Trail、9 个精确 built-in key；正式可见层 `14/27` | atlas/multi-texture、child/world/control point/rope/collision/audio/preset | **B2** |
| Text/Font | `L3` 子集 | CoreText 静态栅格、部分 font/pointsize/padding/scale；结构门 `79/108` | 动态 text、Windows size/baseline、fallback、outline/shadow/effect | B0/B4 |
| Camera Parallax | `L3` 子集 | 仅作者开启且非零 depth 时启用，含层级传播/阻断 | WE 幅度/delay、camera shake/zoom、3D camera | B4 |
| User Properties | `L3` 子集 | 独立窗口、条件、持久化、部分 target、PNG/JPEG `sceneTexture`；21 样本为 424 definitions/952 bindings | 199 个 unsupported target、Texture Variants、live update、shortcut、跨重启 UI 门 | **B0/B1** |
| Typed texture provider | `L3` 子集 | layer/named/property identity、status/generation、authored fallback | system/media/video/variant、通用 material、nested/effectful/child provider | **B1** |
| EffectDefinition/Material IR | `L2` | definition/pass/RT/material/slot hole/combo/constant 可保留，v16 graph-built | 完整 schema、shader identity/content、全部 condition/function | B3 |
| Effect executor | `L3` 极窄子集 | 两个严格 Blur 图和若干受限手写/单 pass executor | 45 类逐项 executor、variant、mask、visual golden | B3 |
| Current/named RT | `L2-L3` | bounded current-frame/named target 已执行；通用 FBO/command 仍只建图 | 通用 bind/copy/swap/compose、格式/尺寸/预算 | B3 |
| History RT | `L0` | 无跨帧通用 ping-pong/history 生命周期 | read-before-write、reset、resize/switch/stop、确定性门 | B3 |
| 任意 shader 执行 | `L0` | 只保留部分 shader/material 数据并运行自有受限 Metal shader | 官方 shader family 翻译/映射、render state、uniform、golden | B3/P3 |
| Puppet Warp/2D rig | `L1` 资源 | 可发现部分 model/material/puppet 资产；无 mesh/bone/physics runtime | mesh/bone/weight、animation、spring/rope/wind/events | P2 |
| 2D lighting/HDR | `L0` | 局部 Bloom 近似不等于官方 lighting/HDR pipeline | PBR maps、light types、shadow/reflection/volumetric、scene post | P2 |
| 3D model/camera/physics | `L0` | 无 Scene 3D runtime | model/node/material/skeleton/attachment/camera/physics | P3 |
| RGB device integration | `L0` | 无 Scene RGB provider/output | 明确平台策略、授权和 fail-closed | P3 |
| Offline bake | `L0` | Debug PNG readback 仅为测试证据；无固定步进产品 adapter | fixed clock、deterministic seed、audio/media fixture、编码器 | P3 |
| 生命周期/性能预算 | `L2-L3` | stop 后 surface=0 和部分资源释放门 | pause/sleep/display change、长稳、GPU/内存预算、泄漏门 | B0-B4 |

## 4. 官方 Effect 覆盖表

所有 45 类都已写入语义手册并可由通用 definition parser 保留。只有 renderer 明确进入 route-only 的项记 `L2`；仅保留 file/pass/value 的项记 `L1`。`L3` 只表示表中明确写出的受限路径，均未达到官方视觉等价。

| 官方 Effect / ID | 当前级别 | 当前执行边界 | 下一道门 |
|---|---|---|---|
| Foliage Sway / `foliagesway` | `L3` | 单一 UV 模式、受 mask/作者声明约束的自有近似 | Vertex、noise/weight/bounds、WE golden |
| Iris Movement / `iris` | `L3` | 有 mask 时的 inline 局部缩放近似 | background/variant、完整参数与像素门 |
| Pulse / `pulse` | `L1` | 仅保留 definition | time/audio 两驱动和 mask/color/blend executor |
| Cloud Motion / `cloudmotion` | `L1` | 仅保留 definition | Perlin、mapped resolution、mask executor |
| Scroll / `scroll` | `L1` | 仅保留 definition | UV repeat/wrap、边界负向门 |
| Shake / `shake` | `L1` | shader 有 dormant 近似代码，但 planner 从未设置 flag | flow/time-offset/mask/audio 和局部变形门 |
| Spin / `spin` | `L1` | 仅保留 definition | effect-local center/mask/ellipse executor |
| Swing / `swing` | `L1` | 仅保留 definition | p0/p1 铰链、mask/noise、局部形变门 |
| Twirl / `twirl` | `L1` | 仅保留 definition | center/size/feather/ellipse/mask executor |
| Water Flow / `waterflow` | `L1` | 只参与 unsupported composite 的 fail-closed 判断 | flow/time-offset/phase/mask executor |
| Water Ripple / `waterripple` | `L3` | 无 mask normal-map 子集；另有 legacy 单 pass 近似 | mask/specular/perspective/双 normal 与 WE golden |
| Water Waves / `waterwaves` | `L3` | 声明驱动的 inline 单波近似 | dual waves/time-offset/perspective/mask 精度 |
| Blur / `blur` | `L3` | stock default 严格 4 pass/2 quarter RT 子图 | kernel/composite/blend/alpha/mask 变体、像素等价 |
| Blur Precise / `blurprecise` | `L3` | 严格 2 pass/1 full RT Gaussian 子图 | authored shader、mask/variant、颜色空间和像素等价 |
| Motion Blur / `motionblur` | `L2` | material-copy-material graph 可路由；无 history，只做 identity bounce | history copy/ping-pong/reset 生命周期 |
| Radial Blur / `blurradial` | `L1` | 仅保留 definition | center/aspect/mask executor |
| Cursor Ripple / `cursorripple` | `L3` | pointer + mask 的无 history inline 近似 | 3 pass/2 RT 波场、碰撞和 lifecycle |
| Advanced Fluid / `fluidsimulation` | `L2` | 约 20 节点和 swap 可保留/路由；condition/function 仍 blocker | 9 RT/8 history、float formats、emitter 与真实 simulation |
| Depth Parallax / `depthparallax` | `L1` | 不与 Camera Parallax 混用；无执行器 | depth map、local pointer、quality variants |
| X-Ray / `xray` | `L1` | 仅保留 definition | local cursor、blend/halo/sprite/mask executor |
| Blend / `blend` | `L3` | 单 image dependency、有限 blend mode/静态 consumer | 6 slots、hole、各槽 UV/amount、mask/write-alpha |
| Blend Gradient / `blendgradient` | `L1` | 仅保留 definition；不是已执行的 `gradient_color` | blend/gradient/opacity 三输入和 edge glow |
| Chromatic Aberration / `chromaticaberration` | `L3` | hand-written 径向通道偏移子集 | directional/barrel/expansion/mask/aspect variants |
| Clouds / `clouds` | `L1` | 仅保留 definition；不冒充粒子 | albedo/mask/shading/blend/perspective executor |
| Color Key / `colorkey` | `L1` | 仅保留 definition | tolerance/feather/invert/flatten 和 alpha 门 |
| Film Grain / `filmgrain` | `L1` | 仅保留 definition | frame time/noise/mask/greyscale/blend |
| Glitter / `glitter` | `L2` | 明确 offscreen route-only | 256x256 R8 repeat RT + combine |
| Shimmer / `shimmer` | `L1` | 仅保留 definition | gradient/mask/time-offset/style/blend |
| Fire / `fire` | `L1` | 仅保留 definition | flow/albedo/refract/blend executor |
| Light Shafts / `lightshafts` | `L1` | 仅保留 definition；粒子 `light_shafts_6` 不是此 effect | combo-dependent slot layout 和 direct draw |
| Nitro / `nitro` | `L1` | 仅保留 definition | cloud/mask/time/repeat/color/blend |
| Opacity / `opacity` | `L3` | mask inline 与严格 Perspective->Opacity 组合子集 | 独立 pass、全部顺序/alpha/premultiply 情况 |
| Reflection / `reflection` | `L1` | 仅保留 definition | dynamic UV/mask/direction/perspective |
| Tint / `tint` | `L1` | 仅保留 definition；现有 layer tint 不是该 effect | blend modes、mask 和 source alpha |
| VHS / `vhs` | `L1` | 仅保留 definition | time/noise/scan/artifact/channel/variant |
| Water Caustics / `watercaustics` | `L1` | 仅保留 definition | 五类输入、style/blend/perspective |
| Fisheye / `fisheye` | `L1` | 仅保留 definition | center/aspect/background/clamp |
| Perspective / `perspective` | `L3` | 严格 Perspective->Opacity 组合的受限四边映射 | 独立 effect、裁切、全部 combo 与像素门 |
| Refraction / `refraction` | `L1` | raw compose 可保留并 fail closed，无 scene background executor | background/source/final 分离、normal/mask |
| Skew / `skew` | `L1` | 仅保留 definition | Vertex/UV、四边、repeat variant |
| Transform / `transform` | `L1` | 仅保留 definition；object transform 不是该 effect | effect-local transform、clamp/repeat、层级反例 |
| Edge Detection / `edgedetection` | `L1` | 仅保留 definition | Sobel/texel/threshold/color/blend |
| God Rays / `godrays` | `L2` | 明确 offscreen route-only | 5 pass、half RT、COPYBG/mask/noise variants |
| Local Contrast / `localcontrast` | `L2` | 多 pass 实例进入 route-only identity | 4 pass、quarter RT、source/blur/mask |
| Shine / `shine` | `L2` | 多 pass 实例进入 route-only identity | 5 pass、half RT、kernel/edge/COPYBG variants |

汇总为 `L1=28`、`L2=6`、`L3=11`、`L4=0`。内部 `_empty` 只作为 passthrough 占位记录为 `L1`，未知 effect 不得映射到它后宣称成功。另有不属于这 45 项的手写 Bloom 和 Workshop `gradient_color` L3 子集，不能拿它们替代 Clouds 或 Blend Gradient。

## 5. Particle 子系统覆盖

| 官方组件 | 当前级别 | 当前边界 | 升级门 |
|---|---|---|---|
| General/maxcount/starttime/flags | `L3` 子集 | max count、prewarm、perspective、frame blend flag 可消费；world-space fail closed | 全字段、runtime change、压力门 |
| Emitter schedule | `L3` 子集 | rate、instantaneous、duration、one-per-frame | delay/periodic 和 WE 时间门 |
| Sphere Random emitter | `L3` | 可执行子集 | 全参数、distribution golden |
| Box Random emitter | `L3` | 可执行子集 | 全参数、distribution golden |
| Layer Image/其他 emitter | `L1` | 名称可诊断，字段和执行不足 | 独立 fixture 和作者条件 |
| Lifetime/Size/Velocity/Color/Alpha | `L3` | 常见 initializer 子集 | range/distribution/seed 与 preset golden |
| Rotation/Angular Velocity | `L3` | 常见 initializer 子集 | local/world orientation 和 renderer 联动 |
| Turbulent Velocity | `L1` | 明确 unsupported | noise field、time/seed、参数合同 |
| Movement/Angular Movement | `L3` | 可执行子集 | timestep 与 WE 数值门 |
| Alpha/Size/Color Change | `L3` | 可执行子集 | curve/remap/边界行为 |
| Oscillate Alpha/Size/Position | `L3` | 可执行子集 | phase/random/曲线 golden |
| Attract/Turbulence/Vortex | `L1` | 明确 unsupported | control-point/world-space 力场 |
| Sprite renderer | `L3` | 作者纹理和程序化静态遮罩子集 | 全 material/blend/lighting/atlas |
| Sprite Trail | `L3` | 受限 trail 执行 | orientation/length/atlas/曲线精度 |
| Rope/Rope Trail | `L1` | 结构/诊断不足 | topology、constraint、renderer |
| Control Points | `L1-L3` 极窄 | static local offset/instance override 可执行；无正式动态 runtime | object/cursor/script binding 与空间转换 |
| Children/Event | `L2` 结构 / `L0` 执行 | asset graph 可递归发现，runtime 报 `childSystemsUnsupported` | spawn/death/collision 事件和生命周期 |
| Built-in textures | `L3` | 9 个精确 key；程序图形只保证确定性，不等于官方资产 | 剩余高频 key、atlas metadata、多纹理 material |
| World space | `L1` | 明确 `worldSpaceUnsupported` | transform、camera、多屏和 parent 语义 |
| Collision | `L1` | 无 solver | shape/depth/response/events |
| Audio response | `L1` | 参数可见但 simulation 不消费 | 频谱 snapshot、mapping 和确定性 fixture |
| Sprite Sheet | `L3` 子集 | Sequence/Random frame/frame blend 可执行 | 全 atlas metadata、loop/edge 和多纹理 material |
| Instance overrides | `L3` 静态 / `L1` 动态 | 静态 override 可应用；动态 wrapper 只诊断 | typed live target、generation 和逐帧应用 |
| Material/blend | `L3` 子集 | `genericparticle` 首纹理、additive/translucent | 多纹理、完整 material/combo/render state |
| Fixed step/seed/budget | `L3` 子集 | fixed simulation step、deterministic seed、maxcount/prewarm 有界 | pause/discontinuity、压力与 WE 数值 golden |

当前正式矩阵可见粒子为 `14/27`；`3750813609` 是 `7/9`，另外两层因 world-space 不支持而保持 fail closed。这个数字只度量被固定矩阵实际加载的 layer，不代表粒子组件覆盖率。

## 6. 动态运行系统覆盖

### 6.1 Timeline 与 SceneScript

| 能力 | 当前级别 | 升级门 |
|---|---|---|
| Timeline object/property target | `L1` | typed target ID 与完整 authored base value |
| Keyframe/value/tangent | `L0` | 当前不保留内容；需保真 IR、Bézier/step/linear evaluator |
| Loop/Mirror/Single/paused | `L0` | 绝对 scene time、wrap、seek/pause tests |
| Animation Events | `L0` | frame crossing、loop、同 layer script dispatch |
| Script presence | `L1` | source path/inline 内容进入 descriptor |
| ECMAScript VM | `L0` | 安全隔离、确定性 budget、异常处理 |
| `init`/`update` 生命周期 | `L0` | 每屏实例、同帧 snapshot、stop teardown |
| `engine` globals/Date/Math | `L0` | frame context 和受控 host API |
| user/cursor/audio/media events | `L0` | generation queue、顺序、异常隔离 |
| component/object/particle API | `L0` | typed handles、只允许作者目标、失效语义 |
| timer/timeout/interval | `L0` | scene-time scheduler、pause/resume/预算 |

### 6.2 User Properties

| 类型/行为 | 当前级别 | 当前边界或升级门 |
|---|---|---|
| Catalog/bindings | `L3` 子集 | 21 样本 424 definitions、952 bindings；199 targets unsupported |
| `color` | `L3` 子集 | UI/持久化/部分 target；补颜色空间和全部 target |
| `slider` | `L3` 子集 | min/max/default/step/fraction/precision UI 和部分 target；补 live snapshot |
| `bool` | `L3` 子集 | 条件/部分 target；不得按名称自动启用 effect |
| `combo` | `L3` 子集 | option value/条件；补全部 authored target |
| `textinput` | `L3` 子集 | 可编辑/持久化；动态 text 仍以重建应用 |
| `texture`/`scenetexture` | `L3` 极窄 | PNG/JPEG picker/bookmark/static consumer；补 video/variant/general material |
| `usershortcut` | `L1` | 明确 macOS 授权和安全降级 |
| group/order/condition | `L3` 子集 | 独立窗口已支持；补嵌套/全条件和负向门 |
| reset/default/override | `L3` 子集 | 已有 authored fallback；补 live generation 和跨重启 UI 门 |
| Texture Variants | `L0` | 补 schema、checkbox/combo 选择和 provider identity；脚本不得切换 |
| property update event | `L0` | typed snapshot 后再派发给 SceneScript |

### 6.3 Text、Audio、Media 与 Provider

| 能力 | 当前级别 | 当前边界或升级门 |
|---|---|---|
| 静态文字内容 | `L3` | CoreText 可见；结构样本 `79/108` |
| 字体解析/fallback | `L3` 子集 | macOS 字体近似；补 Windows family/weight/CJK/emoji golden |
| point size/baseline/alignment | `L3` 子集 | `pointsize * 4` 为经验近似；需官方/Windows 标定 |
| outline/shadow/text effects | `L1-L2` | 字段或 effect 可保留，未形成完整绘制链 |
| property-driven text | `L2` | 通过 Scene 重建应用；需 per-frame target 和按 layer 纹理 generation |
| SceneScript clock/text | `L0` | 先有 VM、Date 和 typed text target |
| Audio 16/32/64 bins | `L0-L1` | Scene 无可注入 frame snapshot |
| Audio effect/particle/script consumer | `L0-L1` | 每个 consumer 正反 fixture |
| Sound layer | `L0` | 补 sound content IR、播放、volume 和生命周期 |
| Embedded MP4 frame | `L3` | image-layer 子集；不同于系统媒体 provider |
| Media status/metadata/timeline | `L0` | injectable snapshot 和 lifecycle |
| Media thumbnail | `L0` | typed texture provider/generation/fallback |
| Layer/named target provider | `L3` 子集 | bounded current-frame graph；补 nested/effectful/child |
| Named secondary variant | `L1` | `_b` 可解析但执行器拒绝；需独立 identity 和数据流 |
| Property file provider | `L3` 极窄 | PNG/JPEG 静态 consumer；补通用 material/video/variant |
| Video/system provider | `L0-L1` | 现有 enum/identity 脚手架不算可用 provider |
| Generic material slots 0...7 | `L2` | 保留 hole/候选；补按 shader combo 的通用 consumer |

## 7. 高级对象与输出覆盖

| 能力族 | 当前级别 | 最小可用门 |
|---|---|---|
| Puppet mesh/bones/weights | `L0-L1` | 可解析 fixture、GPU skinning、层级/遮罩 |
| Puppet spring/rigid/rope/wind | `L0` | fixed timestep solver、events、确定性 golden |
| 2D PBR maps | `L0-L1` | normal/roughness/metalness/emissive slot 与 color space |
| Point/spot/tube/directional light | `L0` | light IR、排序、坐标和至少一条渲染路径 |
| Shadow/reflection/volumetric | `L0` | RT graph、depth/occlusion、预算和像素门 |
| HDR/Bloom scene post | `L1-L3` | 只有 layer bloom 近似；需 HDR targets、tone mapping、scene ordering |
| 3D model/node/material | `L0` | asset loader、scene graph、camera、PBR material |
| Skeleton/attachment/animation | `L0` | animation evaluator、skin/attachment 生命周期 |
| 3D physics | `L0` | fixed timestep、collision、determinism |
| Custom shader | `L0-L2` | 数据可保留；需受控编译/映射、uniform/slot/render-state 合同 |
| RGB device | `L0` | macOS 产品策略、授权、设备 adapter |
| Debug PNG readback | `L2` 工具 | 可生成 benchmark 截图证据；不得标成 offline bake |
| Offline bake | `L0` | 与实时共用 IR/evaluator/render graph，固定时钟和编码输出 |

## 8. Coverage-first 实施批次

| 批次 | 目标 | 完成判据 |
|---|---|---|
| **B0 Live Runtime** | DynamicValue/typed target/snapshot；Timeline core；SceneScript core；动态 text；cursor/audio/media 输入合同 | 同一 frame context 和 target 优先级；变化无需重建；pause/resume/stop 可测 |
| **B1 Provider/Media** | Texture Variants、video/system/media provider、通用 material consumer、nested/effectful source | 每种 provider 有 ready/pending/unavailable、generation、fallback 和 teardown |
| **B2 Particle Breadth** | 高频 atlas/multi-texture、world/child/control point/rope/audio/collision 最小闭环 | 每类一组正向、默认关闭、unsupported 和确定性门；矩阵覆盖上升 |
| **B3 Graph Breadth** | 通用 material、copy/swap/compose、RT history；45 effect 按共同 shader/graph family 批量接入 | graph 身份、slot/combo、lifecycle 和像素门；不再靠 effect 名称手写猜测 |
| **B4 Fidelity** | 字体、视差、粒子、常用 effect 与 WE Windows golden 对齐 | 固定输入逐像素/数值阈值、性能预算、长稳和多屏门 |
| **P2/P3 Advanced** | Puppet、2D light/HDR、3D、custom shader、RGB、offline bake | 每个系统有完整 IR/runtime/lifecycle/product gate 后再升级 |

批次之间允许并行，但依赖不能倒置：Timeline、SceneScript、动态文字、音频和媒体先共用 B0；effect history 先共用 B3 RT；不再为单个样本创建旁路。样本 ID 只出现在测试门和证据里，不能进入产品分派逻辑。

## 9. 更新规则

1. 每次 Scene 能力提交必须更新本表对应行和精确边界；只更新开发流水账不算完成。
2. 升级到 `L2` 必须有结构/路由测试；升级到 `L3` 必须有实际执行正例、作者关闭反例、失败降级和生命周期门；升级到 `L4` 必须有官方行为或 Windows golden。
3. 新发现的官方能力先补 [官方页面全目录](official-page-catalog.md) 和专题语义，再进入本表；私有字段按 [资料来源与证据索引](source-index.md) 标证据等级。
4. 最新矩阵报告、测试总数、签名 App 身份只在现役计划/路线图和本表头维护；历史评估不得反向覆盖。
5. 开发开始顺序：先看本表选择最低公共依赖，再查专题合同和 source index，最后查看样本命中；不得先凭截图写视觉特判。
