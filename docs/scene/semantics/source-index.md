# Scene 资料来源与证据索引

> 核验日期：2026-08-01
>
> 网络核验使用系统代理 `http://127.0.0.1:7897`。
>
> 本索引只记录可追溯资料。没有公开或无法验证的内部行为保持 unknown，不用第三方猜测补成“官方规则”。

## 1. 官方公开资料

### 1.1 总入口

| 资料 | 链接 | 用途 |
|---|---|---|
| Designer Documentation | https://docs.wallpaperengine.io/en/ | 官方作者行为总入口 |
| Scene Overview | https://docs.wallpaperengine.io/en/scene/overview.html | Scene 能力边界 |
| Sitemap | https://docs.wallpaperengine.io/sitemap.xml | 枚举所有现役官方页面 |
| SceneScript Type Declaration v2.8 | https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts | property-bound API、类型和事件合同 |
| SceneScript Type Declaration v2.8 本地参考快照 | [lib.sceneScript-v2.8.d.ts](../reference/official/lib.sceneScript-v2.8.d.ts)（SHA-256 `d9ccc5cd1383bbb91c8a589a34874833d13798d163f2b427117023ea2bfac3f4`） | 2026-07-28 从官方 URL 下载归档的 API diff/fixture 参考；仅用于研究，不进入 App bundle 或运行时输入。下次刷新前应与上行 URL 比对。 |
| Official docs source | https://github.com/Wallpaper-Engine-Team/wallpaper-engine-docs | 文档 Markdown、声明与官方 sample 的可审计来源 |

本轮固定官方文档 revision：[`b26412295cbfd0ee5cdceff67e2c95069527aa1b`](https://github.com/Wallpaper-Engine-Team/wallpaper-engine-docs/commit/b26412295cbfd0ee5cdceff67e2c95069527aa1b)，也是 2026-07-22 核验时的远端 `HEAD`。线上页面与源码发生漂移时，先对比该 revision，不从记忆猜改动。

2026-07-22 sitemap 中 Scene 页面按首级目录计数：

| 目录 | 页面数 | 主题 |
|---|---:|---|
| `scenescript` | 58 | API、events、classes、modules、tutorials |
| `effects` | 48 | overview/introduction/Bloom + 45 个用户 effect |
| `puppet-warp` | 13 | mesh/bone/physics/clipping 等 |
| `particles` | 10 | 组件模型和教程 |
| `userproperties` | 9 | property types、condition、texture variants |
| `models` | 8 | 3D camera/model/animation/lighting/shader |
| `shader` | 6 | syntax、variables、headers、mobile、tutorial |
| `first` | 5 | 基础编辑/发布流程 |
| `timeline` | 4 | animation、modes、events |
| `performance` | 3 | texture 等性能要求 |
| `parallax` | 3 | camera/oversized/depth parallax |
| `image-preparation` | 3 | 图像/透明度等准备 |
| `audiovisualizer` | 3 | audio、media info、album cover |
| `lighting` | 2 | lights/reflection |
| `assets` | 2 | asset creation/sharing |
| `rgb` | 1 | RGB composition |

另有 Scene 根 `overview.html` 1 页，合计 179 个 `/en/scene/` 页面。完整可点击清单见 [官方页面全目录](official-page-catalog.md)，逐页分类与本地合同见 [官方页面逐页表](official-page-map.md)；`lib.sceneScript.d.ts` 不计入 sitemap 的 Scene 页面数。

### 1.2 Effects

官方入口：

- https://docs.wallpaperengine.io/en/scene/effects/introduction.html
- https://docs.wallpaperengine.io/en/scene/effects/overview.html
- https://docs.wallpaperengine.io/en/scene/effects/bloom.html

45 个官方 effect 专页已逐项核验 HTTP 200，并整理在 [Effects 语义全集](effects-reference.md)。不要在这里复制第二份效果表。

### 1.3 Parallax

- Camera Parallax：https://docs.wallpaperengine.io/en/scene/parallax/introduction.html
- Oversized Image：https://docs.wallpaperengine.io/en/scene/parallax/oversized.html
- Depth Parallax：https://docs.wallpaperengine.io/en/scene/parallax/depthparallax.html
- Depth Parallax effect 页面：https://docs.wallpaperengine.io/en/scene/effects/effect/depthparallax.html

已确认官方合同：scene 显式启用 Camera Parallax；逐层 depth 可按轴限制或以 0 关闭；Depth Parallax 是另一个依赖 depth map 的 effect。

### 1.4 Shader

| 页面 | 链接 | 关键合同 |
|---|---|---|
| Overview | https://docs.wallpaperengine.io/en/scene/shader/overview.html | effect shader 兼容承诺与系统 shader 边界 |
| Syntax | https://docs.wallpaperengine.io/en/scene/shader/syntax.html | 自定义 preprocessor、GLSL/HLSL macros、attributes/varyings |
| Variables | https://docs.wallpaperengine.io/en/scene/shader/variables.html | combo、uniform annotation、T0...T7、built-ins |
| Headers | https://docs.wallpaperengine.io/en/scene/shader/headers.html | common/header/blending helpers |
| Mobile | https://docs.wallpaperengine.io/en/scene/shader/mobile.html | language/platform variants |
| Tutorial | https://docs.wallpaperengine.io/en/scene/shader/tutorials/desaturation.html | 最小自定义 effect 示例 |

官方公开的 built-in 变量应直接以 Variables 页面为准。第三方播放器遗漏某个变量只代表该播放器不完整。

### 1.5 Particles

- https://docs.wallpaperengine.io/en/scene/particles/introduction.html
- https://docs.wallpaperengine.io/en/scene/particles/component/general.html
- https://docs.wallpaperengine.io/en/scene/particles/component/emitter.html
- https://docs.wallpaperengine.io/en/scene/particles/component/initializer.html
- https://docs.wallpaperengine.io/en/scene/particles/component/operator.html
- https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html
- https://docs.wallpaperengine.io/en/scene/particles/component/control_point.html
- https://docs.wallpaperengine.io/en/scene/particles/component/children.html
- https://docs.wallpaperengine.io/en/scene/particles/tutorial/getting_started.html
- https://docs.wallpaperengine.io/en/scene/particles/tutorial/spritesheet.html

2026-08-01 复核 Emitter 页：官方明确列出 Sphere Random、Box Random 与 Layer Image 三类 emitter；Speed Min/Max 与 Movement operator 共同定义粒子的最小/最大初始速度。Random periodic emission 会周期性停止并重新开始发射，公开参数为最小/最大 periodic duration 与最小/最大 periodic delay。Layer Image 可使用普通纹理、text 或 puppet source，并另有复制 layer color、周期 bitmap update、继承 layer motion 与 random offset 选项。公开页不定义私有 JSON dependency wire、字段缺省值、速度随机序列、像素采样中心、alpha threshold、更新 generation、周期 RNG/边界 fixed-step 规则或随机分布公式，因此当前 bounded executor 只把这些公开事实用于准入边界，不据此宣称数值或时序等价。组件目录和关键参数已经进入 [运行时系统语义](runtime-systems-reference.md)。

2026-08-01 复核 Control Point 页：官方公开 CP 索引为 0...7，CP 0 固定代表 system origin；Control Point 可提供 position、angles、pointer/world-space 行为，child 可选择 Copy from parent，Raw value 会跳过 child coordinate adjustment。Emitter 页另明确 Sphere/Box emitter 可附着到 Control Point。公开页不定义 `parentcontrolpoint`、raw-copy flag 等私有 JSON wire，也不公开 parent/child 坐标变换顺序、动态更新时相或角度复制细节；项目只用公开行为约束能力边界，wire identity 由合法 authored 资产交叉确认，执行与负例使用项目自有 fixture。

### 1.6 Timeline

- https://docs.wallpaperengine.io/en/scene/timeline/introduction.html
- https://docs.wallpaperengine.io/en/scene/timeline/combined.html
- https://docs.wallpaperengine.io/en/scene/timeline/modes.html
- https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html

### 1.7 User Properties

- Overview：https://docs.wallpaperengine.io/en/scene/userproperties/overview.html
- Color：https://docs.wallpaperengine.io/en/scene/userproperties/color.html
- Slider：https://docs.wallpaperengine.io/en/scene/userproperties/slider.html
- Checkbox：https://docs.wallpaperengine.io/en/scene/userproperties/checkbox.html
- Combo：https://docs.wallpaperengine.io/en/scene/userproperties/combo.html
- Text：https://docs.wallpaperengine.io/en/scene/userproperties/text.html
- Texture：https://docs.wallpaperengine.io/en/scene/userproperties/texture.html
- Texture Variants：https://docs.wallpaperengine.io/en/scene/userproperties/texturevariant.html
- User Shortcut：https://docs.wallpaperengine.io/en/scene/userproperties/usershortcut.html

Group 与 display condition 在 Overview 中定义。Texture Variants 不能由 SceneScript 切换。

官方可下载的 [user property sample](https://docs.wallpaperengine.io/samples/user_property_sample.zip) 提供 `project.json`、`scene.json` 与 SceneScript 实例；本轮只通过管道静态读取，未运行其中的 shader 或二进制。它证明用户属性 raw instance 的一种当前形态，不构成完整版本化 schema。

### 1.8 Audio 与 Media

- Audio Visualizer：https://docs.wallpaperengine.io/en/scene/audiovisualizer/overview.html
- Media Information：https://docs.wallpaperengine.io/en/scene/audiovisualizer/mediainformation.html
- Album Cover：https://docs.wallpaperengine.io/en/scene/audiovisualizer/albumcover.html
- SceneScript Audio tutorial：https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/audio.html
- AudioBuffers：https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html
- Media event：https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/media.html

### 1.9 SceneScript API

入口：

- https://docs.wallpaperengine.io/en/scene/scenescript/introduction.html
- https://docs.wallpaperengine.io/en/scene/scenescript/reference.html
- https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts

官方类型文件当前列出的主要 class/interface：

```text
Vec2 Vec3 Vec4 Mat3 Mat4 CameraTransforms
AnimationEvent CursorEvent
MediaPropertiesEvent MediaThumbnailEvent MediaPlaybackEvent
MediaTimelineEvent MediaStatusEvent AudioBuffers
IObject IThisPropertyObjectBase IMaterial IEffect
ITextureAnimation IVideoTexture IAnimationLayer
ISoundLayer IEffectLayer ITextLayer
IParticleSystemInstance IParticleSystem
IImageLayer IModelLayer ICamera IModelData ILayer IScene
IConsole IRenderContext IInput ILocalStorage IEngine IAnimation
```

官方 globals/modules：

```text
thisLayer thisScene console renderContext input localStorage engine shared
WEMath WEVector WEColor
```

Sitemap 还为大多数 class/event/module 提供独立页面，路径规则为：

```text
https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/<Name>.html
https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/<Name>.html
https://docs.wallpaperengine.io/en/scene/scenescript/reference/module/<Name>.html
```

注意：Timeline 官方页面定义 `animationEvent`，但 v2.8 d.ts 的 `IComponent` 事件列表未包含它。这是官方资料间可见差异，应保留兼容测试，不能任选一边后把另一边删掉。

### 1.10 Puppet、3D、Lighting、RGB

| 主题 | 入口 |
|---|---|
| Puppet Warp | https://docs.wallpaperengine.io/en/scene/puppet-warp/introduction.html |
| 3D Camera | https://docs.wallpaperengine.io/en/scene/models/camera.html |
| 3D Lighting | https://docs.wallpaperengine.io/en/scene/models/lighting.html |
| 2D Lights | https://docs.wallpaperengine.io/en/scene/lighting/lights.html |
| RGB | https://docs.wallpaperengine.io/en/scene/rgb/introduction.html |
| Texture performance | https://docs.wallpaperengine.io/en/scene/performance/texture.html |

本轮只建立能力边界，没有把这些高级模块错误提升为当前 P0。

### 1.11 2.8.42 客户端快照静态取证资料组

Wallpaper Engine 2.8.42 / Steam build `23967692` 是一个固定版本证据快照。文档会继续维护，但结论不能自动外推到其他客户端版本。按下面顺序查阅，避免把旧审计快照、深层静态证据和项目现状混为一体：

| 需要回答的问题 | 维护入口 | 定位 |
|---|---|---|
| 当时检查了哪些随包资产、默认工程和格式缺口 | [Windows 官方客户端取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) | 2026-07-25 的版本化审计快照；保留 census 和当时的开发映射，不是当前能力入口 |
| 二进制模块、第三方库和官方动态预览来自哪里 | [客户端二进制与第三方依赖取证](client-binary-dependency-forensics.md) | 模块与公开上游导航；依赖存在不等于数值或视觉等价 |
| resolver、RenderGraph、SceneScript、媒体和 surface 的内部结构如何分层 | [官方客户端运行机制静态取证](client-runtime-static-forensics.md) | Ghidra clean-room 结构证据的正式维护入口；不记录地址、伪代码或私有算法表达 |
| MyWallpaperX 当前实现到哪一级 | [覆盖台账](coverage-ledger.md)、各专项覆盖表与 [运行证据索引](runtime-evidence-index.md) | 唯一当前状态入口；静态取证本身不升级 `L0-L4` |

按专题继续查：

- **SceneScript**：[运行时实现层合同](scenescript-runtime-implementation-contract.md) 记录 Vec/Mat、宿主桥、用户属性转换、自定义 script property builder、官方 JS module 和 engine/owner 生命周期；[binding target 取证](scenescript-binding-target-forensics.md) 记录 13 处内联脚本 wrapper、owner/target、authored value 与导出 hook。
- **随包输入 corpus**：[官方默认工程 corpus](official-default-projects-fixture-inventory.md) 记录 19 个工程入口与 16 个 scene-shaped 工程；[stock 资产包](stock-asset-bundle.md) 记录项目自有资源对应关系。物理文件存在不升级 consumer 等级。
- **Shader 与兼容记录**：[Shader source 前置合同](shader-prelude-and-backend-abstraction.md) 记录 source token、format branch 与 uniform census；[zcompat 取证](zcompat-backward-compatibility-forensics.md) 记录 patch record schema。未闭合的注入者、矩阵/NDC/Metal 映射、匹配方向和运行时机继续保持 unknown。
- **编辑器与版本线索**：[客户端 changelog 取证](client-changelog-forensics.md) 记录内嵌 REV 3943-4401 的版本事实；[编辑器字符串表取证](editor-string-table-forensics.md) 记录 Scene wire 字段对应的官方名称和说明。

`.codex` 中 2026-07-30 的草稿已经由上述正式文档取代，不是长期维护入口。原始 Ghidra project、地址、伪代码、函数体、字节、一次性脚本与日志不进入仓库。

结构化客户端文档可由 `script/extract_wallpaper_engine_client_evidence.py` 针对同版本输入重新提取 changelog、locale 与 binary manifest；Ghidra 结论则按运行机制文档登记的方法和输入哈希独立复核。历史证据覆盖 `assets`、default projects/templates、声明文件、`locale` 字符串表、`ui/dist` 类型库与 `bin` 模块清单；不覆盖用户项目、配置或缓存。静态取证可以作为结构证据，但仍不能代替运行时 event order、history lifecycle、shader 数学或 Windows pixel golden。

深层 executable 证据可进一步确认 resolver、binder、frontend 与生命周期结构；它仍不能代替颜色空间/alpha、性能、精确事件顺序或 Windows 视觉/声音 golden。静态结论不更新 [覆盖台账](coverage-ledger.md) 的任何能力等级。

## 2. 真实样本证据

真实 Workshop 根：

```text
~/Movies/MyWallpaperX/创意工坊/Scene
```

规则：真实目录只读。解析、注入属性、清缓存、benchmark 和截图都使用隔离 Workshop root 与临时 HOME。

当前样本事实入口：

- [21 个用户样本首轮评估（历史截图基线）](../scene-sample-assessment-2026-07-22.md)
- [Scene 开发计划](../scene-capability-development-plan-2026-07-22.md)
- v16 结构基线：`.codex/scene-effect-graph-canonical-final-20260723/report.json`（canonical graph 身份，不等于 GPU 执行）
- 运行证据分固定回归门与完整快照门；仓库矩阵 `script/scene_wallpaper_full_sample_matrix.json` 固定真实目录中 45 个具备 package 的可运行样本，`3770500543` 因缺 package 只记录在 source manifest。`.codex/scene-builtin-textures-full45-20260725/report.json` 与 `.codex/scene-builtin-textures-fixed13-v2-20260725/report.json` 只保留为 13-key built-in 阶段证据，不能覆盖现役结果。Puppet 定向正向门与 v24 对照分别为 `.codex/scene-puppet-animation-20260725/targeted-v1/report.json`、`.codex/scene-puppet-animation-20260725/control-v24-v1/report.json`。当前实现基线、两层报告/矩阵哈希、App 身份、聚合缺口与测试数统一见 [运行证据索引](runtime-evidence-index.md)。
- ordered scheduler 的 Shadow 前阶段证据：`.codex/scene-effect-chain-gated-final13-20260723/report.json`（基线 `b541867`、8 stage、0 real chain、legacy blocked 3）。该报告只说明当时 all-or-nothing chain 负门，不能反向覆盖上述 current Shadow 正门。
- `.codex/scene-user-texture-final13-r2-20260723/report.json` 降为 format 17 file-property 阶段证据，不能反向覆盖上述当前矩阵或 App 身份。
- file-backed property 定向门：`.codex/scene-user-texture-293-20260723-r1/`（隔离 `2938612768` 向 `newproperty25/26` 注入 200×200 PNG；两张纹理加载、image 44/44、static image blend 5/5，截图变化证明进入 renderer；不证明 system media、动态 current/previous thumbnail 或 WE 像素 parity）
- provider fallback 定向门：`.codex/scene-texture-fallback-293-v3-20260723/report.json`（空 `scenetexture` 时 layers 775/875 回退作者 890/1174；775 只使用 authored-initial alpha）与 `.codex/scene-texture-fallback-290-20260723/report.json`（290 既有 graph/dependency 无回归）
- standard Blur 正向门：`.codex/scene-standard-blur-alpha-290-20260723/report.json`（`2902406982` layer 530 GPU succeeded，utility capture layers 410/530）
- standard Blur 负向门：`.codex/scene-standard-blur-alpha-negative-20260723/report.json`（`3723344874:348` 与 `3750813609:358` 阻断 legacy fallback）
- precise 阶段证据：`.codex/scene-authored-precise-final13-20260723/report.json` 与 `.codex/scene-authored-precise-failclosed-related-20260723/report.json`（5 个成功层、layer 20 fallback 阻断与隐藏层不执行）

样本可证明 instance 如何引用 effect、texture、particle、script 和 user property。它们不能单独证明内置 shader 的全部默认算法。

## 3. 开源播放器对照

本地参考项目的两份只读审查记录（研究记录，不是现役能力状态）：[全量参考项目审查](../../reviews/scene-reference-project-audit-2026-07-24.md)（HEAD `31ae557` 时）与 [effect/runtime 专题审查](../../reviews/scene-reference-audit-effects-runtime-2026-07-24.md)（有序 effect 链、X-Ray、water、时间/文字、视频纹理主题）。Puppet MDLV mesh、受限 MDLS/MDAT 静态 attachment、三来源 MDLA/full-TRS/skin weights 与严格单 clip LBS，以及 BC 解码的可执行合同已收敛到 [场景格式与 Render Graph](scene-format-and-render-graph.md) 第 11 节；第三方审查记录不再是这些现役能力的事实来源。

### 3.1 `Almamu/linux-wallpaperengine`

- 仓库：https://github.com/Almamu/linux-wallpaperengine
- 本轮固定 revision：[`b016d7d1fdcf4e5fd2f9c9fa420a8aaa07fee02d`](https://github.com/Almamu/linux-wallpaperengine/commit/b016d7d1fdcf4e5fd2f9c9fa420a8aaa07fee02d)
- 定位：OpenGL educational/compatibility project。
- 资产边界：该 revision 的源码树不附带 `.json`、`.material`、`.frag` 或 `.vert` stock effect 资产；README `85-118` 也明确要求用户另行安装或指定官方 assets。因此源码只能交叉核对通用 parser/executor 结构，不能独立证明 45 个 stock effect 的逐参数、默认值、pass 数或 shader 算法。

高价值源码入口：

| 主题 | 文件 |
|---|---|
| VFS/项目加载 | `src/WallpaperEngine/Application/WallpaperApplication.cpp` |
| Effect model/parser | `src/WallpaperEngine/Data/Model/Effect.h`、`Data/Parsers/EffectParser.cpp` |
| Material model/parser | `src/WallpaperEngine/Data/Model/Material.h`、`Data/Parsers/MaterialParser.cpp` |
| nullable texture slots | `src/WallpaperEngine/Data/Parsers/TextureParser.cpp` |
| Scene frame loop | `src/WallpaperEngine/Render/Wallpapers/CScene.cpp` |
| Image effect graph | `src/WallpaperEngine/Render/Objects/CImage.cpp` |
| Pass binding/uniforms | `src/WallpaperEngine/Render/Objects/Effects/CPass.cpp` |
| Shader preprocessing | `src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp` |
| Particle/Text | `src/WallpaperEngine/Render/Objects/CParticle.cpp`、`CText.cpp` |

确认的非官方偏差：

- Effect parser 只覆盖 metadata、dependencies、基础 FBO 和 material/bind/command/source/target；未实现 `compose`、condition、function、gizmo 与扩展 FBO 字段；
- parser 把任何非 `copy` command 都映射为 `swap`（`EffectParser.cpp:67-68`），但 image runtime 又只执行 `copy`（`CImage.cpp:663-683`），不能用它确认 swap 语义；
- FBO `format/unique` 解析后没有完整执行；
- blend mode 只覆盖少数枚举；
- effect visibility 主要在 setup 阶段过滤，代码明确留下逐帧 visibility TODO（`CImage.cpp:643-646,797-799`）；
- shader 预处理是 string/regex 路径；sampler slot 只提取一位数字、combo 只接受整数，`#require` 只实现返回零 lighting 的 `LightingV1` stub；
- binder 暴露了一组额外 uniform 名称，但左右声道复用同一 mono spectrum，部分 effect matrix 固定为现有 matrix/identity，且多个官方 built-in uniforms 未上传；
- parallax 公式会让 depth 0 仍移动，违背官方行为；
- Scene camera 最终仍强制 orthographic；所谓 Puppet 只加载静态 mesh，没有 bone/weight/deformation；
- particle/text/SceneScript 存在大量 TODO 和启发式，仓库也没有覆盖上述 generic contract 的完整 fixture 测试。

因此它只用于理解结构和查踩坑，不能作为 golden runtime。

### 3.2 其他同名/关联项目

| 项目 | 结论 |
|---|---|
| https://github.com/wqLouis/linux-wallpaperengine | 2026 年 Rust/wgpu 同名项目；effect slot 有硬编码，particle/text/script 等大幅缺失，不是语义标准 |
| https://github.com/jipika/open-wallpaper-engine | C++/Vulkan 方向的独立 GPL 项目/分支，可交叉检查 parser/render graph，不等同 WaifuX 当前 renderer |
| `WaifuX-main` 本地源码快照 | Swift 只负责进程/屏幕/属性；Scene 核心是无源码的预编译 `wallpaper-wgpu`，不能源码审计 |

## 4. WaifuX 本地对照边界

本轮只读快照：

```text
Reference Project/WaifuX-main
```

确认事实：

- 实时每屏一个 `wallpaper-wgpu` 进程；属性和 wallpaper 可通过 JSON control file 热更新；
- bake 调用同一二进制的 `bake` 子命令；
- Swift 宿主不解释 effect/material/particle/text；
- renderer Rust/Cargo 源码不在仓库；build script 从开发者私有路径复制预编译 binary；
- `zip_data.o` 内有 WE-compatible effects/materials/shaders，但版本不可从仓库验证；
- 项目 GPL-3.0，README 与实际 binary/backend/assets 存在漂移。

可借鉴：实时/离线共核、control file、属性 cache key、队列/checkpoint 和诊断思路。

不可借鉴：二进制、内嵌资源、未说明的 DXC/FFmpeg 打包、无 bookmark 的 file property、Workshop ID heuristic 和不透明兼容声明。

## 5. 研究安全边界

前一轮为了查看 WaifuX `--pipeline-debug`，fresh shader cache 曾尝试启动未签名/未公证的 `dxc`，触发 macOS Gatekeeper 弹窗。本轮已终止相关进程，并执行以下约束：

- 不再启动 WaifuX `wallpaper-wgpu`、`dxc` 或任何下载/内嵌二进制；
- 不解除 quarantine、不修改 Gatekeeper、不要求用户降低系统安全设置；
- 网络研究只用 `curl`/GitHub API/官方 HTML；
- 开源项目只静态 clone/read，不 build/run。

## 6. 尚未有官方公开合同的部分

以下内容目前只能由合法官方 assets、真实样本与黑盒对照继续确认：

1. `project.json`、`scene.json`、`effect.json`、material/model/particle JSON 的完整、版本化 schema；官方 UI 类型 `texture` 与样本 raw type `scenetexture` 需兼容但不能无证据视作全版本同义；Texture Variants 的原始序列化形状、匹配优先级和混合细节也未公开；
2. `previous`、`original`、named RT、full-frame aliases 的全部内部命名和默认 binding precedence；
3. FBO `unique/fit/uv/conditions` 的跨版本稳定性，以及 alias、clear 颜色解释和 device-loss/history 的完整生命周期；
4. PKG/TEX/TEXB/MDL/Puppet 的完整版本矩阵；
5. 内置 shader 数学、浮点/颜色空间和 DirectX sampling edge behavior；官方公开 `[COMBO]`，但没有给出 stock asset 中 `[COMBO_OFF]` / `[OFF_COMBO]` / `[COMBO_DISABLED]` 三种拼写与 `[PASS]` 的合同，随包普查见 [Shader source 前置合同审查](shader-prelude-and-backend-abstraction.md) §8；
6. SceneScript VM 的全部 ECMAScript edge cases、module runtime、全局 event order、未闭合的同帧冲突、异常传播和 resource limits；2.8.42 已恢复的 timer/owner 局部顺序见实现层合同，不能外推为全部运行语义；
7. 粒子每个 component 的随机分布、seed、重复 module order、spawn debt、默认值和精确 integration method；
8. text renderer 的 Windows 栅格化、系统字体 fallback、hinting、复杂 layout、ellipsis 与 color-font 行为；300 DPI point 的公开声明和当前受限换算已记录在运行输入覆盖表，但仍不是 Windows 像素 golden；
9. 官方实时与屏保/移动端/低质量模式的降级策略；
10. `displaycondition` 的完整表达式语法、类型转换和跨版本兼容规则；
11. 离线 bake 不是 Wallpaper Engine 官方公开能力，必须作为 MyWallpaperX 自有合同设计。

未知项进入实现时必须先建最小 fixture 和证据，不得从第三方 TODO 或当前视觉结果猜默认值。

## 7. 资料刷新命令

只读刷新官方页面列表：

```bash
curl -x http://127.0.0.1:7897 -L --fail --silent --show-error \
  https://docs.wallpaperengine.io/sitemap.xml
```

读取官方 SceneScript declaration：

```bash
curl -x http://127.0.0.1:7897 -L --fail --silent --show-error \
  https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts
```

禁止把这两条刷新扩展成运行 WaifuX renderer/DXC。要验证最终画面时，另开有明确安全边界的 Windows Wallpaper Engine 对照流程。
