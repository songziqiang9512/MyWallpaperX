# Wallpaper Engine Scene 官方页面逐页映射

> 状态：现役逐页索引
>
> 官方快照：`b26412295cbfd0ee5cdceff67e2c95069527aa1b`
>
> 页面范围：`official-page-catalog.md` 中 179 个唯一 `/en/scene/` URL；`lib.sceneScript.d.ts` v2.8 另列，不计入 179
> 最近核对：2026-07-23

本表只回答每个官方页面落到哪个本地合同，以及该页面对 MyWallpaperX 播放器是否适用。当前实现等级、代码和测试证据仍由链接的专项表维护；页面被列入本表不代表能力已经实现。

分类沿用 [`official-page-crosswalk.md`](official-page-crosswalk.md)：

- `runtime-required`：作者产物会改变播放结果；必须有作者启用、执行或 fail-closed 合同。
- `ingest-required`：编辑器导出资源或配置会影响输入；播放器读取产物，不复刻制作流程。
- `editor-only`：只属于 Wallpaper Engine 编辑器、发布或教程操作；播放器明确不实现该 UI。
- `platform-decision`：依赖 Windows、移动端、设备、权限或宿主集成；macOS 必须明确支持、替代或关闭。
- `research-boundary`：公开页面没有给出完整私有格式或算法；不得把近似或第三方行为写成官方真值。

## 1. Overview 与入门（6）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| START-001 | [Scene Overview](https://docs.wallpaperengine.io/en/scene/overview.html) | `editor-only` + `research-boundary` | [系统总表](coverage-ledger.md#3-系统总表) | 官方能力导航；不实现编辑器首页，运行能力分别进入专项合同。 |
| START-002 | [Getting Started](https://docs.wallpaperengine.io/en/scene/first/gettingstarted.html) | `ingest-required` + `editor-only` | [文件与资源层级](scene-format-and-render-graph.md#1-文件与资源层级) | 不复刻导入教程；消费其生成的 project、scene 和资源。 |
| START-003 | [Assets](https://docs.wallpaperengine.io/en/scene/first/assets.html) | `ingest-required` + `editor-only` | [文件、资源和基础对象](advanced-object-coverage.md#1-文件资源和基础对象) | 不复刻资产添加与 gizmo；保留对象类型、层级和 transform。 |
| START-004 | [Effects](https://docs.wallpaperengine.io/en/scene/first/effects.html) | `runtime-required` + `editor-only` | [Effect definition](scene-format-and-render-graph.md#5-effect-definition) | 教程操作 N/A；作者显式 effect、顺序、mask 和参数必须进入运行合同。 |
| START-005 | [Properties](https://docs.wallpaperengine.io/en/scene/first/properties.html) | `runtime-required` + `ingest-required` + `editor-only` | [User Property 定义与面板](runtime-input-property-coverage.md#5-user-property-定义与面板) | 不复刻作者创建 UI；消费定义、binding、condition 和用户选择。 |
| START-006 | [Publishing](https://docs.wallpaperengine.io/en/scene/first/publishing.html) | `editor-only` | [文件与资源层级](scene-format-and-render-graph.md#1-文件与资源层级) | 上传、预览图和 Workshop 更新流程不属于播放器；只读取已发布产物。 |

## 2. Assets（2）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| ASSET-001 | [Assets Overview](https://docs.wallpaperengine.io/en/scene/assets/overview.html) | `ingest-required` + `editor-only` | [文件、资源和基础对象](advanced-object-coverage.md#1-文件资源和基础对象) | gizmo 与编辑操作 N/A；对象身份、transform 和依赖必须保留。 |
| ASSET-002 | [Sharing Assets](https://docs.wallpaperengine.io/en/scene/assets/sharing.html) | `ingest-required` + `editor-only` | [文件与资源层级](scene-format-and-render-graph.md#1-文件与资源层级) | 不实现资产发布 UI；共享 effect、layer、script 仍按普通只读资源解析。 |

## 3. Image Preparation（3）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| IMAGE-001 | [Character Sheet](https://docs.wallpaperengine.io/en/scene/image-preparation/character-sheet.html) | `ingest-required` + `editor-only` | [Puppet Warp](advanced-object-coverage.md#3-puppet-warp) | 素材分片制作 N/A；运行时只消费导出的 Puppet mesh、bone、weight 和纹理。 |
| IMAGE-002 | [External Editor](https://docs.wallpaperengine.io/en/scene/image-preparation/external-editor.html) | `editor-only` | [文件、资源和基础对象](advanced-object-coverage.md#1-文件资源和基础对象) | 外部编辑器快捷入口与文件回写不属于播放器。 |
| IMAGE-003 | [Foreground Separation](https://docs.wallpaperengine.io/en/scene/image-preparation/foreground-separation.html) | `ingest-required` + `editor-only` | [文件、资源和基础对象](advanced-object-coverage.md#1-文件资源和基础对象) | 抠图工具 N/A；播放器消费最终图像、alpha 和层级。 |

## 4. Effects（48）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| EFFECT-001 | [Effects Introduction](https://docs.wallpaperengine.io/en/scene/effects/introduction.html) | `runtime-required` + `ingest-required` | [显式启用与 ordered passes](scene-format-and-render-graph.md#5-effect-definition) | 只执行作者挂载且可见的 effect；保留 layer 类型、stack 顺序和依赖。 |
| EFFECT-002 | [Effects Overview](https://docs.wallpaperengine.io/en/scene/effects/overview.html) | `runtime-required` + `research-boundary` | [Effects 语义全集](effects-reference.md#2-动画类) | 45 类目录入口；每类按独立作者合同和共享 graph primitive 执行。 |
| EFFECT-003 | [Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) | `runtime-required` + `platform-decision` | [Lighting、HDR 与全局后处理](advanced-object-coverage.md#5-lightinghdr-与全局后处理) | Scene post、普通 Bloom 与 Ultra HDR 分开；服从作者开关和用户 post-processing 等级。 |
| EFFECT-004 | [Advanced Fluid Simulation](https://docs.wallpaperengine.io/en/scene/effects/effect/advancedfluidsimulation.html) | `runtime-required` + `research-boundary` | [交互类](effects-reference.md#4-交互类) | 依赖 pointer、float RT、history、swap、condition 和 emitter；缺任一项 fail-closed。 |
| EFFECT-005 | [Blend](https://docs.wallpaperengine.io/en/scene/effects/effect/blend.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 仅按作者 texture slot、mode、amount、mask 和 write-alpha 执行。 |
| EFFECT-006 | [Blend Gradient](https://docs.wallpaperengine.io/en/scene/effects/effect/blendgradient.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | blend、gradient、opacity 三输入不得合并或凭名称替代。 |
| EFFECT-007 | [Blur](https://docs.wallpaperengine.io/en/scene/effects/effect/blur.html) | `runtime-required` + `research-boundary` | [模糊类](effects-reference.md#3-模糊类) | 按 authored 4-pass、quarter RT 和 composite profile；未知 variant 拒绝。 |
| EFFECT-008 | [Blur Precise](https://docs.wallpaperengine.io/en/scene/effects/effect/blurprecise.html) | `runtime-required` + `research-boundary` | [模糊类](effects-reference.md#3-模糊类) | 按 authored 2-pass、full RT profile；不能复用 coarse Blur slot/layout。 |
| EFFECT-009 | [Chromatic Aberration](https://docs.wallpaperengine.io/en/scene/effects/effect/chromaticaberration.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 服从方向、中心、aspect、variant 和 mask；未声明不得默认启用。 |
| EFFECT-010 | [Cloud Motion](https://docs.wallpaperengine.io/en/scene/effects/effect/cloudmotion.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 只在作者 mask 区域按 noise 与 mapped resolution 做 UV 流动。 |
| EFFECT-011 | [Clouds](https://docs.wallpaperengine.io/en/scene/effects/effect/clouds.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | image effect，不得冒充粒子；服从 albedo、mask、blend 和 perspective。 |
| EFFECT-012 | [Color Key](https://docs.wallpaperengine.io/en/scene/effects/effect/colorkey.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | key、tolerance、feather、invert、flatten 和 alpha convention 必须成组验证。 |
| EFFECT-013 | [Cursor Ripple](https://docs.wallpaperengine.io/en/scene/effects/effect/cursorripple.html) | `runtime-required` + `research-boundary` | [交互类](effects-reference.md#4-交互类) | 作者 effect + local pointer 才启用；依赖波场 history、collision mask 和 reset。 |
| EFFECT-014 | [Depth Parallax](https://docs.wallpaperengine.io/en/scene/effects/effect/depthparallax.html) | `runtime-required` + `research-boundary` | [交互类](effects-reference.md#4-交互类) | 依赖 Scene Camera Parallax、depth map 和 effect-local pointer；不等于 layer parallax。 |
| EFFECT-015 | [Edge Detection](https://docs.wallpaperengine.io/en/scene/effects/effect/edgedetection.html) | `runtime-required` + `research-boundary` | [增强类](effects-reference.md#7-增强类) | 按 source texel size、threshold、color 和 blend 执行。 |
| EFFECT-016 | [Film Grain](https://docs.wallpaperengine.io/en/scene/effects/effect/filmgrain.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 只在作者声明时消费 frame time、noise、mask 和 blend variant。 |
| EFFECT-017 | [Fire](https://docs.wallpaperengine.io/en/scene/effects/effect/fire.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | flow 与 albedo 是不同 provider；未声明资源不得生成全屏火焰。 |
| EFFECT-018 | [Fisheye](https://docs.wallpaperengine.io/en/scene/effects/effect/fisheye.html) | `runtime-required` + `research-boundary` | [畸变类](effects-reference.md#6-畸变类) | 使用局部中心、aspect 和作者越界策略，不能露灰或无条件 repeat。 |
| EFFECT-019 | [Glitter](https://docs.wallpaperengine.io/en/scene/effects/effect/glitter.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 依赖固定 tile RT 和 combine；不能降成普通静态噪声。 |
| EFFECT-020 | [God Rays](https://docs.wallpaperengine.io/en/scene/effects/effect/godrays.html) | `runtime-required` + `research-boundary` | [增强类](effects-reference.md#7-增强类) | 依赖 threshold、half RT、ray cast、blur、combine 与 full-frame variant。 |
| EFFECT-021 | [Iris Movement](https://docs.wallpaperengine.io/en/scene/effects/effect/iris.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 只变形作者 mask 区域；不能替换为全层或相机位移。 |
| EFFECT-022 | [Light Shafts](https://docs.wallpaperengine.io/en/scene/effects/effect/lightshafts.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | texture slot 由 combo 决定；不能固定一套绑定表。 |
| EFFECT-023 | [Local Contrast](https://docs.wallpaperengine.io/en/scene/effects/effect/localcontrast.html) | `runtime-required` + `research-boundary` | [增强类](effects-reference.md#7-增强类) | 依赖 quarter RT、两向 blur、source/low-frequency combine 和 final mask。 |
| EFFECT-024 | [Motion Blur](https://docs.wallpaperengine.io/en/scene/effects/effect/motionblur.html) | `runtime-required` + `research-boundary` | [模糊类](effects-reference.md#3-模糊类) | current/history/copy/combine 和 resize、switch、seek、stop reset 缺一不可。 |
| EFFECT-025 | [Nitro](https://docs.wallpaperengine.io/en/scene/effects/effect/nitro.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 服从 cloud、mask、time、repeat、color 和 blend 作者参数。 |
| EFFECT-026 | [Opacity](https://docs.wallpaperengine.io/en/scene/effects/effect/opacity.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 只调整目标 alpha，保留 RGB、mask、effect 顺序和 premultiply 合同。 |
| EFFECT-027 | [Perspective](https://docs.wallpaperengine.io/en/scene/effects/effect/perspective.html) | `runtime-required` + `research-boundary` | [畸变类](effects-reference.md#6-畸变类) | 执行四点 projective 变换与裁切；不能用 affine 近似。 |
| EFFECT-028 | [Pulse](https://docs.wallpaperengine.io/en/scene/effects/effect/pulse.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 作者可选 time 或 audio；两条输入和 mask、color、alpha、blend 分开。 |
| EFFECT-029 | [Radial Blur](https://docs.wallpaperengine.io/en/scene/effects/effect/radialblur.html) | `runtime-required` + `research-boundary` | [模糊类](effects-reference.md#3-模糊类) | 当前帧局部多采样，不得错误依赖 Motion Blur history。 |
| EFFECT-030 | [Reflection](https://docs.wallpaperengine.io/en/scene/effects/effect/reflection.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 服从动态 UV、mask、方向、速度、比例和 perspective；算法未知部分保持 unknown。 |
| EFFECT-031 | [Refraction](https://docs.wallpaperengine.io/en/scene/effects/effect/refraction.html) | `runtime-required` + `research-boundary` | [畸变类](effects-reference.md#6-畸变类) | 依赖 scene-behind-layer compose、normal 和 mask；背景、source、final 必须分离。 |
| EFFECT-032 | [Scroll](https://docs.wallpaperengine.io/en/scene/effects/effect/scroll.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 滚动 UV 且服从 repeat/wrap；不能移动 layer bounds 后露底。 |
| EFFECT-033 | [Shake](https://docs.wallpaperengine.io/en/scene/effects/effect/shake.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 依赖 flow、time-offset、mask、audio 和局部 bounds；不能整层晃动。 |
| EFFECT-034 | [Shimmer](https://docs.wallpaperengine.io/en/scene/effects/effect/shimmer.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | gradient、mask、time-offset、style 和 blend 是独立作者输入。 |
| EFFECT-035 | [Shine](https://docs.wallpaperengine.io/en/scene/effects/effect/shine.html) | `runtime-required` + `research-boundary` | [增强类](effects-reference.md#7-增强类) | 依赖 threshold/noise、cast、blur、combine 和 COPYBG variant。 |
| EFFECT-036 | [Skew](https://docs.wallpaperengine.io/en/scene/effects/effect/skew.html) | `runtime-required` + `research-boundary` | [畸变类](effects-reference.md#6-畸变类) | Vertex/UV 两模式、四边偏移和 repeat variant 分开。 |
| EFFECT-037 | [Spin](https://docs.wallpaperengine.io/en/scene/effects/effect/spin.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 围绕 effect-local center 与 mask 旋转；不得写回 object angles。 |
| EFFECT-038 | [Foliage Sway](https://docs.wallpaperengine.io/en/scene/effects/effect/sway.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | UV/Vertex 模式分开，受 mask、weight、bounds 和作者参数限制。 |
| EFFECT-039 | [Swing](https://docs.wallpaperengine.io/en/scene/effects/effect/swing.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 只扭曲作者定义铰链区域；不能旋转整个头发或衣物层。 |
| EFFECT-040 | [Tint](https://docs.wallpaperengine.io/en/scene/effects/effect/tint.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 按作者 blend mode 和 mask 着色；普通 layer color 不等价。 |
| EFFECT-041 | [Transform](https://docs.wallpaperengine.io/en/scene/effects/effect/transform.html) | `runtime-required` + `research-boundary` | [畸变类](effects-reference.md#6-畸变类) | effect-local center、offset、rotation、scale 与 object transform 分离。 |
| EFFECT-042 | [Twirl](https://docs.wallpaperengine.io/en/scene/effects/effect/twirl.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 使用 effect-local center、size、feather、ellipse、mask 和 noise。 |
| EFFECT-043 | [VHS](https://docs.wallpaperengine.io/en/scene/effects/effect/vhs.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | 消费 time、noise、texel size 和 variant；不能输出静态占位噪声。 |
| EFFECT-044 | [Water Caustics](https://docs.wallpaperengine.io/en/scene/effects/effect/watercaustics.html) | `runtime-required` + `research-boundary` | [色彩与叠加类](effects-reference.md#5-色彩与叠加类) | mask、Voronoi、uniform/noise、offset noise、glow 五输入分开。 |
| EFFECT-045 | [Water Flow](https://docs.wallpaperengine.io/en/scene/effects/effect/waterflow.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | flow/time-offset/phase/scale/feather/repeat 只作用于作者区域。 |
| EFFECT-046 | [Water Ripple](https://docs.wallpaperengine.io/en/scene/effects/effect/waterripple.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | normal、mask、两组滚动和 Perspective combo 由作者资源决定。 |
| EFFECT-047 | [Water Waves](https://docs.wallpaperengine.io/en/scene/effects/effect/waterwaves.html) | `runtime-required` + `research-boundary` | [动画类](effects-reference.md#2-动画类) | 单/双波、time-offset、mask、Perspective 默认关闭，按作者声明启用。 |
| EFFECT-048 | [X-Ray](https://docs.wallpaperengine.io/en/scene/effects/effect/xray.html) | `runtime-required` + `research-boundary` | [交互类](effects-reference.md#4-交互类) | 依赖 local cursor、source/blend、radius、halo/sprite 和 mask。 |

## 5. Parallax（3）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| PARALLAX-001 | [Camera Parallax](https://docs.wallpaperengine.io/en/scene/parallax/introduction.html) | `runtime-required` | [Camera Parallax](runtime-input-property-coverage.md#op-parallax-camera) | 只有 Scene 开启、mouse influence 非零且 layer 对应轴 depth 非零时运行。 |
| PARALLAX-002 | [Oversized Image](https://docs.wallpaperengine.io/en/scene/parallax/oversized.html) | `runtime-required` + `ingest-required` + `editor-only` | [Oversized Image](runtime-input-property-coverage.md#op-parallax-oversized) | 导入/调参教程 N/A；运行时保留原图尺寸、canvas、裁切和边界覆盖。 |
| PARALLAX-003 | [Depth Parallax](https://docs.wallpaperengine.io/en/scene/parallax/depthparallax.html) | `runtime-required` + `ingest-required` + `editor-only` + `research-boundary` | [Depth Parallax](runtime-input-property-coverage.md#op-parallax-depth) | depth generator/DLC N/A；消费导出 depth map、Scene 开关、quality 和局部参数。 |

## 6. Particles（10）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| PARTICLE-001 | [Particles Introduction](https://docs.wallpaperengine.io/en/scene/particles/introduction.html) | `runtime-required` + `research-boundary` | [执行顺序、事件与生命周期](particle-component-coverage.md#12-执行顺序事件与生命周期) | 粒子是独立模拟系统；必须按作者组件、事件、子系统和固定步进运行，不能用通用屏幕特效替代。 |
| PARTICLE-002 | [General](https://docs.wallpaperengine.io/en/scene/particles/component/general.html) | `runtime-required` + `ingest-required` | [General](particle-component-coverage.md#3-general) | 解析并执行最大数量、生命周期、排序、bounds、start time 与实例级覆盖。 |
| PARTICLE-003 | [Emitter](https://docs.wallpaperengine.io/en/scene/particles/component/emitter.html) | `runtime-required` + `ingest-required` | [Emitters](particle-component-coverage.md#4-emitters) | 发射形状、速率、距离、方向与 control point 坐标系由组件定义；不得统一成点发射器。 |
| PARTICLE-004 | [Initializer](https://docs.wallpaperengine.io/en/scene/particles/component/initializer.html) | `runtime-required` + `ingest-required` | [Initializers](particle-component-coverage.md#5-initializers) | 只在粒子出生时按声明顺序写初值；随机性必须可复现并服从实例参数。 |
| PARTICLE-005 | [Operator](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html) | `runtime-required` + `ingest-required` | [Operators](particle-component-coverage.md#6-operators) | 每步按声明顺序执行力、轨迹、颜色、大小、寿命和控制点运算，不以全局动画代替。 |
| PARTICLE-006 | [Renderer](https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html) | `runtime-required` + `ingest-required` | [Renderers](particle-component-coverage.md#7-renderers) | renderer 决定 sprite、rope、trail 等几何和排序；材质、blend、frame animation 必须保持。 |
| PARTICLE-007 | [Control Point](https://docs.wallpaperengine.io/en/scene/particles/component/control_point.html) | `runtime-required` + `ingest-required` | [Control Points](particle-component-coverage.md#8-control-points) | control point 是可被对象、鼠标、脚本和父子系统驱动的具名空间输入，不是固定原点。 |
| PARTICLE-008 | [Children](https://docs.wallpaperengine.io/en/scene/particles/component/children.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Children 与事件](particle-component-coverage.md#9-children-与事件) | 子系统创建、死亡、碰撞等事件必须进入确定性队列，并继承作者指定的位置和实例参数。 |
| PARTICLE-009 | [Getting Started](https://docs.wallpaperengine.io/en/scene/particles/tutorial/getting_started.html) | `ingest-required` + `editor-only` | [执行顺序、事件与生命周期](particle-component-coverage.md#12-执行顺序事件与生命周期) | 编辑器创建流程 N/A；运行时只消费已导出的粒子定义、资源和组件顺序。 |
| PARTICLE-010 | [Sprite Sheet](https://docs.wallpaperengine.io/en/scene/particles/tutorial/spritesheet.html) | `runtime-required` + `ingest-required` + `editor-only` | [Particle Material、纹理与 Blend](particle-component-coverage.md#11-particle-material纹理与-blend) | 导入 UI N/A；播放器必须消费 atlas 帧布局、序列、速率、随机起始帧和材质混合。 |

## 7. Timeline（4）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| TIMELINE-001 | [Timeline Introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html) | `runtime-required` + `ingest-required` | [Timeline Introduction](runtime-input-property-coverage.md#op-timeline-introduction) | 解析轨道、关键帧、插值、局部时间和目标属性；不能只识别动画存在。 |
| TIMELINE-002 | [Combined Animations](https://docs.wallpaperengine.io/en/scene/timeline/combined.html) | `runtime-required` | [Combined Animations](runtime-input-property-coverage.md#op-timeline-combined) | 同一 animation 可组合不同 property lanes 并复用 settings；官方未公开 weight/additive/override，不能据此推断。 |
| TIMELINE-003 | [Playback Modes](https://docs.wallpaperengine.io/en/scene/timeline/modes.html) | `runtime-required` | [Playback Modes](runtime-input-property-coverage.md#op-timeline-modes) | 支持 Loop、Mirror、Single 作者模式及速度、起点、结束边界；切换和跳帧不能重复触发。 |
| TIMELINE-004 | [Animation Events](https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html) | `runtime-required` + `research-boundary` | [Animation Events](runtime-input-property-coverage.md#op-timeline-events) | 帧跨越事件进入同层脚本队列；依赖 Timeline、Puppet animation 和 SceneScript 生命周期统一时钟。 |

## 8. User Properties（9）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| PROPERTY-001 | [Overview](https://docs.wallpaperengine.io/en/scene/userproperties/overview.html) | `runtime-required` + `ingest-required` | [User Properties Overview](runtime-input-property-coverage.md#op-user-overview) | 从项目定义生成属性模型和独立调节窗口，并把变更送入绑定目标与脚本事件。 |
| PROPERTY-002 | [Color](https://docs.wallpaperengine.io/en/scene/userproperties/color.html) | `runtime-required` + `ingest-required` | [Color Property](runtime-input-property-coverage.md#op-user-color) | 保持官方公开的 RGB 默认值、绑定目标和颜色值转换；该页未定义 alpha，不能自行扩展。 |
| PROPERTY-003 | [Slider](https://docs.wallpaperengine.io/en/scene/userproperties/slider.html) | `runtime-required` + `ingest-required` | [Slider Property](runtime-input-property-coverage.md#op-user-slider) | 保持 min/max/step/default、整数/浮点语义及目标域；面板值与脚本值必须一致。 |
| PROPERTY-004 | [Checkbox](https://docs.wallpaperengine.io/en/scene/userproperties/checkbox.html) | `runtime-required` + `ingest-required` | [Checkbox Property](runtime-input-property-coverage.md#op-user-checkbox) | bool 同时驱动 visibility、effect、script 等作者目标；不得用能力检测自动打开。 |
| PROPERTY-005 | [Combo](https://docs.wallpaperengine.io/en/scene/userproperties/combo.html) | `runtime-required` + `ingest-required` | [Combo Property](runtime-input-property-coverage.md#op-user-combo) | 展示标签与协议值分离；按作者顺序和默认项求值，未知值 fail-closed。 |
| PROPERTY-006 | [Text](https://docs.wallpaperengine.io/en/scene/userproperties/text.html) | `runtime-required` + `ingest-required` | [Text Property](runtime-input-property-coverage.md#op-user-text) | 这里只定义动态 string 值及其绑定；font、size、alignment、transform 属于 Text layer 合同，不能混写。 |
| PROPERTY-007 | [Texture](https://docs.wallpaperengine.io/en/scene/userproperties/texture.html) | `runtime-required` + `platform-decision` | [Texture Property](runtime-input-property-coverage.md#op-user-texture) | 支持图片/视频选择、目标作用域、权限、解码与 fallback；macOS 通过安全作用域资源持久化。 |
| PROPERTY-008 | [Texture Variants](https://docs.wallpaperengine.io/en/scene/userproperties/texturevariant.html) | `runtime-required` + `ingest-required` | [Texture Variants](runtime-input-property-coverage.md#op-user-texture-variants) | 变体须同类型/尺寸并受 bool/combo 驱动；实现 Replace/Alpha 语义，不臆造 SceneScript 回调。 |
| PROPERTY-009 | [User Shortcut](https://docs.wallpaperengine.io/en/scene/userproperties/usershortcut.html) | `runtime-required` + `platform-decision` | [User Shortcut](runtime-input-property-coverage.md#op-user-shortcut) | 快捷方式是每台机器的外部动作且预设不携带；需明确权限、点击触发和 fail-closed，不静默执行。 |

## 9. Audio / Media（3）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| MEDIA-001 | [Audio Visualizer](https://docs.wallpaperengine.io/en/scene/audiovisualizer/overview.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Audio Visualizer](runtime-input-property-coverage.md#op-media-overview) | 音频采集与授权采用 macOS 合法路径；官方概览不足以推断完整频带、平滑和无音频语义。 |
| MEDIA-002 | [Media Information](https://docs.wallpaperengine.io/en/scene/audiovisualizer/mediainformation.html) | `runtime-required` + `platform-decision` | [Media Information](runtime-input-property-coverage.md#op-media-information) | 提供元数据、颜色、播放状态/进度事件及动态文本更新；不可用时输出稳定空状态。 |
| MEDIA-003 | [Album Cover](https://docs.wallpaperengine.io/en/scene/audiovisualizer/albumcover.html) | `runtime-required` + `platform-decision` | [Album Cover](runtime-input-property-coverage.md#op-media-album-cover) | provider 支持当前/上一封面、占位图、异步 generation 与取消，避免旧封面覆盖新媒体。 |

## 10. SceneScript（58）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| SCRIPT-001 | [Introduction](https://docs.wallpaperengine.io/en/scene/scenescript/introduction.html) | `runtime-required` + `research-boundary` | [Property-bound 核心合同](scenescript-api-coverage.md#2-property-bound-核心合同) | SceneScript 是作者选择性绑定到属性/对象的运行逻辑；未绑定脚本不得影响壁纸。 |
| SCRIPT-002 | [Reference](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html) | `runtime-required` + `research-boundary` | [实施依赖与完成门](scenescript-api-coverage.md#13-实施依赖与完成门) | 以官方声明和页面共同建立 API 清单；recognized 不等于对象、事件和副作用已执行。 |
| SCRIPT-003 | [Tutorials](https://docs.wallpaperengine.io/en/scene/scenescript/tutorials.html) | `runtime-required` + `editor-only` | [实施依赖与完成门](scenescript-api-coverage.md#13-实施依赖与完成门) | 编辑器编写流程 N/A；教程示例保留为可执行 fixture 和行为预期。 |
| SCRIPT-004 | [AnimationEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AnimationEvent.html) | `runtime-required` + `research-boundary` | [Property value 与事件 DTO](scenescript-api-coverage.md#101-property-value-与事件-dto) | 按官方字段构造跨帧动画事件 DTO；事件顺序、重复和边界跳转必须确定。 |
| SCRIPT-005 | [AudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 提供官方形状、频带和更新时序；macOS 音频源与权限单独决策，无权限时稳定归零。 |
| SCRIPT-006 | [CameraTransforms](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/CameraTransforms.html) | `runtime-required` + `research-boundary` | [Render / scene property API](scenescript-api-coverage.md#7-render--scene-property-api) | 返回当前帧相机/view/projection 语义的快照；2D/3D 坐标和矩阵方向须与官方一致。 |
| SCRIPT-007 | [CursorEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/CursorEvent.html) | `runtime-required` + `research-boundary` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 构造位置、按钮和事件阶段；先完成 screen-to-scene/layer 坐标转换再派发。 |
| SCRIPT-008 | [IAnimation](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimation.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 句柄操作真实 Timeline/Puppet clip 的播放、停止、速率和状态，不能只返回占位对象。 |
| SCRIPT-009 | [IAnimationLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimationLayer.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 暴露动画层作者允许的属性与 clip 查找，并保持对象 identity 和销毁语义。 |
| SCRIPT-010 | [IAssetHandle](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAssetHandle.html) | `runtime-required` + `research-boundary` | [Asset handles 与动态资源](scenescript-api-coverage.md#11-asset-handles-与动态资源) | 动态资源加载必须异步、有生命周期和失败状态，并受安全路径与 provider 约束。 |
| SCRIPT-011 | [IConsole](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IConsole.html) | `runtime-required` + `research-boundary` | [Globals 与 engine 状态](scenescript-api-coverage.md#5-globals-与-engine-状态) | 映射官方日志方法到受控诊断通道；不允许脚本访问宿主终端或隐式吞错。 |
| SCRIPT-012 | [IEffect](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEffect.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | effect 句柄指向真实 effect instance，并按官方字段读写 visibility、参数或材质。 |
| SCRIPT-013 | [IEffectLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEffectLayer.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | effect-layer 访问遵守作者层级、索引和生命周期；不能跨对象误绑定同名 effect。 |
| SCRIPT-014 | [IEngine](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Globals 与 engine 状态](scenescript-api-coverage.md#5-globals-与-engine-状态) | 仅暴露官方 engine 状态、资源和调度能力；宿主文件、网络、进程能力默认不可见。 |
| SCRIPT-015 | [IImageLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IImageLayer.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 读写映射到实际 image layer、texture animation 和材质；更新进入同帧 render graph。 |
| SCRIPT-016 | [IInput](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IInput.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 输入订阅只在作者脚本请求时启用；坐标、按钮、音频/媒体与平台权限明确分层。 |
| SCRIPT-017 | [ILayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILayer.html) | `runtime-required` + `research-boundary` | [通用 layer / scene](scenescript-api-coverage.md#41-通用-layer--scene) | 通用 transform、visibility、color、opacity 和 child 查询作用于真实 scene graph 节点。 |
| SCRIPT-018 | [ILocalStorage](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILocalStorage.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Storage 与 timers](scenescript-api-coverage.md#8-storage-与-timers) | 以壁纸/脚本作用域隔离持久化，定义容量、序列化和失败；不可暴露任意文件访问。 |
| SCRIPT-019 | [IMaterial](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IMaterial.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 材质 uniform/texture 操作绑定真实 pass 和 variant；未知字段 fail-closed 并可诊断。 |
| SCRIPT-020 | [IModelData](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IModelData.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 模型数据句柄返回实际 node/bone/animation 数据，identity 与坐标空间保持稳定。 |
| SCRIPT-021 | [IModelLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IModelLayer.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 操作真实 3D layer、模型节点和动画；必须与 camera、lighting、simulation 同帧同步。 |
| SCRIPT-022 | [IParticleSystem](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystem.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 系统句柄控制定义级参数并创建真实实例；不能把所有实例共享成单一全局状态。 |
| SCRIPT-023 | [IParticleSystemInstance](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystemInstance.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 实例句柄维护独立 transform、control points、override、start/stop 和销毁状态。 |
| SCRIPT-024 | [IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html) | `runtime-required` + `research-boundary` | [通用 layer / scene](scenescript-api-coverage.md#41-通用-layer--scene) | scene 查询必须遵守层级、名称/索引、对象类型与生命周期，并返回稳定句柄。 |
| SCRIPT-025 | [ISoundLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ISoundLayer.html) | `runtime-required` + `platform-decision` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 播放、暂停、音量和状态映射真实音频层；遵守静音策略、设备变化和资源生命周期。 |
| SCRIPT-026 | [ITextLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ITextLayer.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 文本修改触发布局、字体 fallback、bounds 和 render 更新，不能仅替换缓存字符串。 |
| SCRIPT-027 | [ITextureAnimation](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ITextureAnimation.html) | `runtime-required` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 控制真实 atlas/frame animation 的时间、frame、速率和播放模式，并与 layer time 同步。 |
| SCRIPT-028 | [IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html) | `runtime-required` + `research-boundary` | [官方声明自身的边界](scenescript-api-coverage.md#12-官方声明自身的边界) | `this` 绑定和可用成员由当前属性/对象上下文决定；声明未公开处不得凭猜测扩权。 |
| SCRIPT-029 | [IVideoTexture](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IVideoTexture.html) | `runtime-required` + `platform-decision` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 视频纹理句柄驱动真实解码、播放、seek、loop 和状态；线程与 generation 防止旧帧回写。 |
| SCRIPT-030 | [Mat3](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Mat3.html) | `runtime-required` + `research-boundary` | [Matrices](scenescript-api-coverage.md#103-matrices) | 精确实现构造、索引、乘法、逆和向量变换；先锁定 row/column-major 与乘法方向。 |
| SCRIPT-031 | [Mat4](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Mat4.html) | `runtime-required` + `research-boundary` | [Matrices](scenescript-api-coverage.md#103-matrices) | 精确实现 4x4 运算、transform 和 camera 矩阵交互；禁止用外部库默认约定代替官方约定。 |
| SCRIPT-032 | [MediaPlaybackEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/MediaPlaybackEvent.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 按官方字段派发播放状态变化，去重并保持与媒体 generation 一致。 |
| SCRIPT-033 | [MediaPropertiesEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/MediaPropertiesEvent.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 映射标题、艺术家、专辑等元数据和空值规则，不从文件名猜测缺失字段。 |
| SCRIPT-034 | [MediaStatusEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/MediaStatusEvent.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 提供官方 status 枚举和变更顺序；不可用、无会话与停止状态分开。 |
| SCRIPT-035 | [MediaThumbnailEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/MediaThumbnailEvent.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 封面更新携带稳定资源引用或空状态，并用 generation 取消过期异步结果。 |
| SCRIPT-036 | [MediaTimelineEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/MediaTimelineEvent.html) | `runtime-required` + `platform-decision` + `research-boundary` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 进度、时长和 seek 状态按官方单位与节流频率派发，暂停时不漂移。 |
| SCRIPT-037 | [Shared](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Shared.html) | `runtime-required` + `research-boundary` | [Globals 与 engine 状态](scenescript-api-coverage.md#5-globals-与-engine-状态) | 实现官方 shared state 的可见范围和初始化/销毁顺序，不能变成跨壁纸全局变量。 |
| SCRIPT-038 | [Vec2](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Vec2.html) | `runtime-required` + `research-boundary` | [Vectors](scenescript-api-coverage.md#102-vectors) | 实现官方字段、运算和返回类型，保持不可变/可变及归一化零向量边界。 |
| SCRIPT-039 | [Vec3](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Vec3.html) | `runtime-required` + `research-boundary` | [Vectors](scenescript-api-coverage.md#102-vectors) | 实现三维运算、cross/dot/normalize 与模型坐标交互，避免坐标轴猜测。 |
| SCRIPT-040 | [Vec4](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Vec4.html) | `runtime-required` + `research-boundary` | [Vectors](scenescript-api-coverage.md#102-vectors) | 实现四维/齐次运算和颜色/矩阵边界，精确保留分量与返回类型。 |
| SCRIPT-041 | [init](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/init.html) | `runtime-required` + `research-boundary` | [生命周期与事件](scenescript-api-coverage.md#3-生命周期与事件) | 对象和依赖就绪后恰好一次调用；重载/重建时先遵守 destroy 顺序。 |
| SCRIPT-042 | [update](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/update.html) | `runtime-required` + `research-boundary` | [生命周期与事件](scenescript-api-coverage.md#3-生命周期与事件) | 每个有效帧按官方 delta/time 语义和确定顺序调用；暂停与后台节流明确。 |
| SCRIPT-043 | [destroy](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/destroy.html) | `runtime-required` + `research-boundary` | [生命周期与事件](scenescript-api-coverage.md#3-生命周期与事件) | 在句柄、timer、资源和对象失效前调用一次，并取消后续异步回写。 |
| SCRIPT-044 | [resizeScreen](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/resizeScreen.html) | `runtime-required` + `research-boundary` | [生命周期与事件](scenescript-api-coverage.md#3-生命周期与事件) | 屏幕/canvas 真正变化时按官方参数调用；不能把每帧 parallax 当 resize。 |
| SCRIPT-045 | [applyGeneralSettings](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/applyGeneralSettings.html) | `runtime-required` + `research-boundary` | [生命周期与事件](scenescript-api-coverage.md#3-生命周期与事件) | 首次和设置变更时派发规范化 general settings；事件顺序先于依赖它的 update。 |
| SCRIPT-046 | [applyUserProperties](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/applyUserProperties.html) | `runtime-required` + `research-boundary` | [生命周期与事件](scenescript-api-coverage.md#3-生命周期与事件) | 批量提交作者属性键和值，保留类型、默认与差量语义；未知 key 不伪造目标。 |
| SCRIPT-047 | [cursor](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/cursor.html) | `runtime-required` + `research-boundary` | [生命周期与事件](scenescript-api-coverage.md#3-生命周期与事件) | 只对注册/绑定对象派发，使用正确坐标和 hit-test，事件相位与按钮状态一致。 |
| SCRIPT-048 | [media](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/media.html) | `runtime-required` + `platform-decision` + `research-boundary` | [生命周期与事件](scenescript-api-coverage.md#3-生命周期与事件) | 将平台媒体适配器事件规范化后派发；无权限或无会话时 fail-closed。 |
| SCRIPT-049 | [WEColor](https://docs.wallpaperengine.io/en/scene/scenescript/reference/module/WEColor.html) | `runtime-required` + `research-boundary` | [Math、颜色与 ECMAScript 基础](scenescript-api-coverage.md#9-math颜色与-ecmascript-基础) | 实现官方颜色转换、混合和边界；明确 linear/sRGB 与 0..1/0..255 域。 |
| SCRIPT-050 | [WEMath](https://docs.wallpaperengine.io/en/scene/scenescript/reference/module/WEMath.html) | `runtime-required` + `research-boundary` | [Math、颜色与 ECMAScript 基础](scenescript-api-coverage.md#9-math颜色与-ecmascript-基础) | 方法、常量、clamp/interpolation/random 行为按官方声明；随机种子可重放。 |
| SCRIPT-051 | [WEVector](https://docs.wallpaperengine.io/en/scene/scenescript/reference/module/WEVector.html) | `runtime-required` + `research-boundary` | [Math、颜色与 ECMAScript 基础](scenescript-api-coverage.md#9-math颜色与-ecmascript-基础) | 模块函数与 Vec 类型返回值、维度提升和异常边界严格一致。 |
| SCRIPT-052 | [Basics](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/basics.html) | `runtime-required` + `editor-only` | [Property-bound 核心合同](scenescript-api-coverage.md#2-property-bound-核心合同) | 编辑器绑定流程 N/A；示例作为 property-bound 编译、init/update 和返回值 fixture。 |
| SCRIPT-053 | [Audio](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/audio.html) | `runtime-required` + `editor-only` + `platform-decision` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 教程 UI N/A；示例验证音频 buffer 输入、平滑、无音频和权限降级。 |
| SCRIPT-054 | [Colors](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/colors.html) | `runtime-required` + `editor-only` | [Math、颜色与 ECMAScript 基础](scenescript-api-coverage.md#9-math颜色与-ecmascript-基础) | 教程 UI N/A；示例锁定颜色协议、转换和属性返回值。 |
| SCRIPT-055 | [Cursor](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/cursor.html) | `runtime-required` + `editor-only` | [Input、Audio 与 Media](scenescript-api-coverage.md#6-inputaudio-与-media) | 教程 UI N/A；示例验证注册、坐标转换、按钮状态和仅按作者声明交互。 |
| SCRIPT-056 | [Local Storage](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/localstorage.html) | `runtime-required` + `editor-only` + `platform-decision` | [Storage 与 timers](scenescript-api-coverage.md#8-storage-与-timers) | 教程 UI N/A；示例验证壁纸作用域、重载持久化、容量和损坏值恢复。 |
| SCRIPT-057 | [Models](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/models.html) | `runtime-required` + `editor-only` + `research-boundary` | [内容、effect、动画和高级句柄](scenescript-api-coverage.md#42-内容effect动画和高级句柄) | 教程 UI N/A；示例验证 model/bone/animation 句柄操作进入真实 3D graph。 |
| SCRIPT-058 | [Time of Day](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/timeofday.html) | `runtime-required` + `editor-only` + `platform-decision` | [Globals 与 engine 状态](scenescript-api-coverage.md#5-globals-与-engine-状态) | 教程 UI N/A；本地时钟作为显式 engine 输入，时区/睡眠/跳时语义可测试。 |

## 11. Shader（6）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| SHADER-001 | [Overview](https://docs.wallpaperengine.io/en/scene/shader/overview.html) | `runtime-required` + `editor-only` + `research-boundary` | [Shader Overview](render-graph-shader-coverage.md#op-shader-overview) | 编辑器创建 N/A；播放器范围是 effect shader 与 generic2-compatible 3D 路径，不据此宣称 custom system/particle shader 兼容。 |
| SHADER-002 | [Syntax](https://docs.wallpaperengine.io/en/scene/shader/syntax.html) | `runtime-required` + `research-boundary` | [Shader Syntax](render-graph-shader-coverage.md#op-shader-syntax) | 精确转换/执行官方 GLSL 方言、预处理、pass 与 attribute/varying 约定；编译失败必须可诊断。 |
| SHADER-003 | [Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html) | `runtime-required` + `research-boundary` | [Shader Variables](render-graph-shader-coverage.md#op-shader-variables) | 内建 uniform、sampler、time、texel、matrix 和 author parameter 必须绑定真实帧上下文。 |
| SHADER-004 | [Headers](https://docs.wallpaperengine.io/en/scene/shader/headers.html) | `runtime-required` + `research-boundary` | [Shader Headers](render-graph-shader-coverage.md#op-shader-headers) | 实现官方 include/header 解析、宏与版本边界；未知 header 不得静默替换。 |
| SHADER-005 | [Mobile](https://docs.wallpaperengine.io/en/scene/shader/mobile.html) | `platform-decision` + `editor-only` | [Shader Mobile](render-graph-shader-coverage.md#op-shader-mobile) | Android/mobile 发布优化 N/A；保留作者 shader 语义，不以移动降级规则改变 macOS 输出。 |
| SHADER-006 | [Desaturation Tutorial](https://docs.wallpaperengine.io/en/scene/shader/tutorials/desaturation.html) | `runtime-required` + `editor-only` | [Shader Desaturation fixture](render-graph-shader-coverage.md#op-shader-desaturation) | 编辑教程 N/A；作为最小 custom shader 端到端 fixture，验证 source、uniform、texture、compile 和 pass output。 |

## 12. Puppet Warp（13）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| PUPPET-001 | [Introduction](https://docs.wallpaperengine.io/en/scene/puppet-warp/introduction.html) | `runtime-required` + `ingest-required` + `editor-only` | [Puppet Introduction](advanced-object-coverage.md#op-puppet-introduction) | 编辑网格/骨骼 N/A；播放器消费导出 mesh、bones、weights、animations 和作者参数。 |
| PUPPET-002 | [Character Sheet](https://docs.wallpaperengine.io/en/scene/puppet-warp/charactersheet.html) | `ingest-required` + `editor-only` | [Puppet Character Sheet](advanced-object-coverage.md#op-puppet-charactersheet) | 角色拆图与导入工作流 N/A；只消费生成的纹理、mesh、骨骼和层级，不重新推导。 |
| PUPPET-003 | [Extending](https://docs.wallpaperengine.io/en/scene/puppet-warp/extending.html) | `ingest-required` + `editor-only` | [Puppet Extending](advanced-object-coverage.md#op-puppet-extending) | 编辑器扩展网格 N/A；导入时保留作者 mesh topology、weights 与 bounds。 |
| PUPPET-004 | [Attachments](https://docs.wallpaperengine.io/en/scene/puppet-warp/attachments.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Attachments](advanced-object-coverage.md#op-puppet-attachments) | 区分 child-layer attachment 与 property point 两种机制，继承骨骼 transform 且不误带整层。 |
| PUPPET-005 | [Clipping Masks](https://docs.wallpaperengine.io/en/scene/puppet-warp/clippingmasks.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Clipping Masks](advanced-object-coverage.md#op-puppet-clipping-masks) | 按层级执行可嵌套 clipping mask，定义 alpha/transform/排序并拒绝引用环。 |
| PUPPET-006 | [Texture Channels](https://docs.wallpaperengine.io/en/scene/puppet-warp/texturechannels.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Texture Channels](advanced-object-coverage.md#op-puppet-texture-channels) | 同尺寸 channel 按作者顺序写入纹理/alpha，并支持 opacity 动画；不能当普通叠图。 |
| PUPPET-007 | [Bone Constraints](https://docs.wallpaperengine.io/en/scene/puppet-warp/boneconstraints.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Bone Constraints](advanced-object-coverage.md#op-puppet-bone-constraints) | spring、rigid、rope、wind 等约束按骨骼局部空间固定步进求解，不能整块位移替代。 |
| PUPPET-008 | [Inverse Kinematics](https://docs.wallpaperengine.io/en/scene/puppet-warp/inversekinematics.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Inverse Kinematics](advanced-object-coverage.md#op-puppet-inverse-kinematics) | 按作者 chain、target、orientation 和约束迭代 IK；与关键帧/约束的求值顺序固定。 |
| PUPPET-009 | [Interactive](https://docs.wallpaperengine.io/en/scene/puppet-warp/interactive.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Interactive](advanced-object-coverage.md#op-puppet-interactive) | 仅作者指定骨骼/目标响应 cursor 或 SceneScript，并在动画后按官方顺序应用。 |
| PUPPET-010 | [Perspective](https://docs.wallpaperengine.io/en/scene/puppet-warp/perspective.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Perspective](advanced-object-coverage.md#op-puppet-perspective) | 实现 mesh depth、extrusion、camera/perspective 和裁切；不能用全层 parallax 近似。 |
| PUPPET-011 | [Blend Shapes](https://docs.wallpaperengine.io/en/scene/puppet-warp/blendshapes.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Blend Shapes](advanced-object-coverage.md#op-puppet-blend-shapes) | 按作者 shape delta 与 weight 混合顶点/表情，并与骨骼 deformation 顺序一致。 |
| PUPPET-012 | [Blend Rules](https://docs.wallpaperengine.io/en/scene/puppet-warp/blendrules.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Blend Rules](advanced-object-coverage.md#op-puppet-blend-rules) | 动态 parent 和多源权重遵守作者规则、范围与求值顺序，避免双重 transform。 |
| PUPPET-013 | [Animation Mixing](https://docs.wallpaperengine.io/en/scene/puppet-warp/animationmixing.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Puppet Animation Mixing](advanced-object-coverage.md#op-puppet-animation-mixing) | 多 clip 的播放时间、速率、权重、层级和 additive/override 顺序必须可复现。 |

## 13. 3D Models（8）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| MODEL-001 | [Introduction](https://docs.wallpaperengine.io/en/scene/models/introduction.html) | `runtime-required` + `ingest-required` + `editor-only` | [Model Introduction](advanced-object-coverage.md#op-model-introduction) | 模型导入/编辑 N/A；消费导出的 FBX/OBJ 派生资源、2D/3D mode、轴向、材质与 PBR 参数。 |
| MODEL-002 | [Camera](https://docs.wallpaperengine.io/en/scene/models/camera.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Model Camera](advanced-object-coverage.md#op-model-camera) | bottommost visible camera 生效；支持 path sequence/random 及 center/eye/up/FOV，未声明不自动游动。 |
| MODEL-003 | [Animation](https://docs.wallpaperengine.io/en/scene/models/animation.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Model Animation](advanced-object-coverage.md#op-model-animation) | 解析 clips、skeleton、offset/root motion、播放与混合；与 SceneScript/Timeline 使用统一时钟。 |
| MODEL-004 | [Attachment](https://docs.wallpaperengine.io/en/scene/models/attachment.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Model Attachment](advanced-object-coverage.md#op-model-attachment) | layer/model attachment 绑定真实 node/bone transform，保持 local offset、排序和生命周期。 |
| MODEL-005 | [Fog](https://docs.wallpaperengine.io/en/scene/models/fog.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Model Fog](advanced-object-coverage.md#op-model-fog) | 实现 distance/height fog、颜色/密度和 material opt-out；进入同一 depth/camera 空间。 |
| MODEL-006 | [Lighting](https://docs.wallpaperengine.io/en/scene/models/lighting.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Model Lighting](advanced-object-coverage.md#op-model-lighting) | 支持 per-light/per-model shadow；volumetric 只按官方支持的 point/spot 路径启用。 |
| MODEL-007 | [Shader](https://docs.wallpaperengine.io/en/scene/models/shader.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Stock Model Shaders](advanced-object-coverage.md#op-model-shader) | stock Fur/Vegetation/Chroma 等模型 shader 是独立合同，不等于任意 custom shader 已兼容。 |
| MODEL-008 | [Simulation](https://docs.wallpaperengine.io/en/scene/models/simulation.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Model Simulation](advanced-object-coverage.md#op-model-simulation) | 骨骼物理按作者参数固定步进并具确定 lifecycle；暂停、重载和长帧不发散。 |

## 14. Lighting（2）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| LIGHT-001 | [Introduction](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) | `runtime-required` + `ingest-required` + `editor-only` | [Lighting Introduction](advanced-object-coverage.md#op-light-introduction) | 编辑器 normal/specular/reflection map 生成 N/A；消费 per-material lighting、reflection、maps 和 author-off。 |
| LIGHT-002 | [Lights](https://docs.wallpaperengine.io/en/scene/lighting/lights.html) | `runtime-required` + `ingest-required` + `research-boundary` | [Lights](advanced-object-coverage.md#op-light-lights) | 按官方类型/参数、最多四灯、shadow 和 point/spot 投影纹理执行；允许 Timeline、Script、audio 驱动。 |

## 15. Performance（3）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| PERF-001 | [Optimization](https://docs.wallpaperengine.io/en/scene/performance/optimization.html) | `ingest-required` + `editor-only` | [Performance Optimization](advanced-object-coverage.md#op-performance-optimization) | 作者优化工作流 N/A；导入保留作者资源格式、分辨率和质量选择，不以兼容名义改写。 |
| PERF-002 | [Resolution](https://docs.wallpaperengine.io/en/scene/performance/resolution.html) | `runtime-required` + `ingest-required` + `editor-only` | [Performance Resolution](advanced-object-coverage.md#op-performance-resolution) | 编辑器分辨率建议 N/A；消费 canvas/aspect/crop/stretch 与屏幕变化，始终覆盖目标屏幕而不露灰底。 |
| PERF-003 | [Texture](https://docs.wallpaperengine.io/en/scene/performance/texture.html) | `ingest-required` + `platform-decision` + `editor-only` | [Performance Texture](advanced-object-coverage.md#op-performance-texture) | 编辑器压缩 UI N/A；支持 RGBA/DXT1/DXT5、POT physical/mapped size，并以 macOS GPU 能力制定 VRAM/解码策略。 |

## 16. RGB（1）

| Page ID | 官方页面 | 分类 | 本地合同 | 播放器决策 / N/A 原因 |
|---|---|---|---|---|
| RGB-001 | [RGB Introduction](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html) | `runtime-required` + `platform-decision` | [RGB Introduction](advanced-object-coverage.md#op-rgb) | macOS 用可替换 adapter 且无设备 fail-closed；默认镜像壁纸，作者 limit-to-layer 时取最上层目标及其合成结果。 |

## 17. 独立权威声明（不计入 179 页）

| Resource ID | 权威资源 | 分类 | 本地合同 | 使用决策 |
|---|---|---|---|---|
| DECL-001 | [lib.sceneScript.d.ts v2.8](https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts) | `runtime-required` + `research-boundary` | [官方声明自身的边界](scenescript-api-coverage.md#12-官方声明自身的边界) | SceneScript API 的权威声明快照；作为页面语义和黑盒样本之外的独立证据，不计入 `/en/scene/` 179 页。 |
