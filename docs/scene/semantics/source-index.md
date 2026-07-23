# Scene 资料来源与证据索引

> 核验日期：2026-07-23
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

组件目录和关键参数已经进入 [运行时系统语义](runtime-systems-reference.md)。

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

## 2. 真实样本证据

真实 Workshop 根：

```text
~/Movies/MyWallpaperX/创意工坊/Scene
```

规则：真实目录只读。解析、注入属性、清缓存、benchmark 和截图都使用隔离 Workshop root 与临时 HOME。

当前样本事实入口：

- [21 个用户样本评估](../scene-sample-assessment-2026-07-22.md)
- [Scene 开发计划](../scene-capability-development-plan-2026-07-22.md)
- v16 结构基线：`.codex/scene-effect-graph-canonical-final-20260723/report.json`（canonical graph 身份，不等于 GPU 执行）
- 最新正式 13 样本运行门：`.codex/scene-workshop-shadow-final13-20260723-1540/report.json`（实现基线 `809b75e`、format 20、13/13；四个 strict backend 合计 10 stage、真实 multi-effect strict chain 1、Workshop Shadow 1、GPU failed 0、legacy blocked 2、route-only 34；`3724289844` 为 stages 4/chains 1/succeeded `[20,28,36]`/blocked 为空；签名 App `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `e4c25d85cb1b878019ec6a7b9e334fd6caaef098`、可执行文件 SHA-256 `bd02f455de2e5e11cbc365dabee5063afa4c32ab28d959abcd8c8bb77746a8c0`）。定向门 `.codex/scene-workshop-shadow-targeted-20260723-1536/report.json` 为 1/1；Scene tests 为 258 total / 257 pass / 1 skip。下一门为 stock Opacity `MASK=0` strict profile，并让 alpha 经既有 binding program/per-surface snapshot live 消费；完整边界见 [运行证据索引](runtime-evidence-index.md)。
- ordered scheduler 的 Shadow 前阶段证据：`.codex/scene-effect-chain-gated-final13-20260723/report.json`（基线 `b541867`、8 stage、0 real chain、legacy blocked 3）。该报告只说明当时 all-or-nothing chain 负门，不能反向覆盖上述 current Shadow 正门。
- `.codex/scene-user-texture-final13-r2-20260723/report.json` 降为 format 17 file-property 阶段证据，不能反向覆盖上述当前矩阵或 App 身份。
- file-backed property 定向门：`.codex/scene-user-texture-293-20260723-r1/`（隔离 `2938612768` 向 `newproperty25/26` 注入 200×200 PNG；两张纹理加载、image 44/44、static image blend 5/5，截图变化证明进入 renderer；不证明 system media、动态 current/previous thumbnail 或 WE 像素 parity）
- provider fallback 定向门：`.codex/scene-texture-fallback-293-v3-20260723/report.json`（空 `scenetexture` 时 layers 775/875 回退作者 890/1174；775 只使用 authored-initial alpha）与 `.codex/scene-texture-fallback-290-20260723/report.json`（290 既有 graph/dependency 无回归）
- standard Blur 正向门：`.codex/scene-standard-blur-alpha-290-20260723/report.json`（`2902406982` layer 530 GPU succeeded，utility capture layers 410/530）
- standard Blur 负向门：`.codex/scene-standard-blur-alpha-negative-20260723/report.json`（`3723344874:348` 与 `3750813609:358` 阻断 legacy fallback）
- precise 阶段证据：`.codex/scene-authored-precise-final13-20260723/report.json` 与 `.codex/scene-authored-precise-failclosed-related-20260723/report.json`（5 个成功层、layer 20 fallback 阻断与隐藏层不执行）

样本可证明 instance 如何引用 effect、texture、particle、script 和 user property。它们不能单独证明内置 shader 的全部默认算法。

## 3. 开源播放器对照

### 3.1 `Almamu/linux-wallpaperengine`

- 仓库：https://github.com/Almamu/linux-wallpaperengine
- 本轮固定 revision：[`b016d7d1fdcf4e5fd2f9c9fa420a8aaa07fee02d`](https://github.com/Almamu/linux-wallpaperengine/commit/b016d7d1fdcf4e5fd2f9c9fa420a8aaa07fee02d)
- 许可证：GPL-3.0
- 定位：OpenGL educational/compatibility project，需要用户合法安装的 Wallpaper Engine assets。

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
| Shader preprocessing | `src/WallpaperEngine/Render/Shader/ShaderUnit.cpp` |
| Particle/Text | `src/WallpaperEngine/Render/Objects/CParticle.cpp`、`CText.cpp` |

确认的非官方偏差：

- parser/model 未实现 `compose`；
- FBO `format/unique` 解析后没有完整执行；
- blend mode 只覆盖少数枚举；
- 多个官方 built-in uniforms 未上传；
- parallax 公式会让 depth 0 仍移动，违背官方行为；
- particle/text/SceneScript 存在大量 TODO 和启发式。

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
/Users/songziqiang/Documents/Development/WaifuX-main
```

确认事实：

- 实时每屏一个 `wallpaper-wgpu` 进程；属性和 wallpaper 可通过 JSON control file 热更新；
- bake 调用同一二进制的 `bake` 子命令；
- Swift 宿主不解释 effect/material/particle/text；
- renderer Rust/Cargo 源码不在仓库；build script 从开发者私有路径复制预编译 binary；
- `zip_data.o` 内有 WE-compatible effects/materials/shaders，但来源、版本与分发许可不可从仓库验证；
- 项目 GPL-3.0，README 与实际 binary/backend/assets 存在漂移。

可借鉴：实时/离线共核、control file、属性 cache key、队列/checkpoint 和诊断思路。

不可借鉴：二进制、内嵌资源、未说明的 DXC/FFmpeg 打包、无 bookmark 的 file property、Workshop ID heuristic 和不透明兼容声明。

## 5. 本轮安全记录

前一轮为了查看 WaifuX `--pipeline-debug`，fresh shader cache 曾尝试启动未签名/未公证的 `dxc`，触发 macOS Gatekeeper 弹窗。本轮已终止相关进程，并执行以下约束：

- 不再启动 WaifuX `wallpaper-wgpu`、`dxc` 或任何下载/内嵌二进制；
- 不解除 quarantine、不修改 Gatekeeper、不要求用户降低系统安全设置；
- 网络研究只用 `curl`/GitHub API/官方 HTML；
- 开源项目只静态 clone/read，不 build/run。

## 6. 许可证和 clean-room 规则

- Wallpaper Engine 官方 assets 不随 MyWallpaperX 分发；未来只从用户合法安装位置读取。
- GPL-3.0 项目只用于研究概念、数据关系和已知缺陷，不复制代码、shader、fixtures 或注释表达。
- WaifuX 的内嵌 asset payload 只用于本轮语义对照，不复制进仓库。
- 文档对官方页面只做摘要和链接，不镜像整页内容。
- MyWallpaperX 需要独立的 Swift/Metal 实现、自己的 fixtures、测试和运行证据。

## 7. 尚未有官方公开合同的部分

以下内容目前只能由合法官方 assets、真实样本与黑盒对照继续确认：

1. `project.json`、`scene.json`、`effect.json`、material/model/particle JSON 的完整、版本化 schema；官方 UI 类型 `texture` 与样本 raw type `scenetexture` 需兼容但不能无证据视作全版本同义；Texture Variants 的原始序列化形状、匹配优先级和混合细节也未公开；
2. `previous`、`original`、named RT、full-frame aliases 的全部内部命名和默认 binding precedence；
3. FBO `unique/fit/uv/conditions` 在所有版本中的精确生命周期；
4. PKG/TEX/TEXB/MDL/Puppet 的完整版本矩阵；
5. 内置 shader 数学、`[COMBO_OFF]`、浮点/颜色空间和 DirectX sampling edge behavior；官方公开 `[COMBO]`，但没有给出 stock asset 中 `[COMBO_OFF]` 的合同；
6. SceneScript VM 的全部 ECMAScript edge cases、module loader、timer/re-entrancy、event ordering、异常策略和 resource limits；
7. 粒子每个 component 的随机分布、seed、重复 module order、spawn debt、默认值和精确 integration method；
8. text renderer 的 300 DPI point 到 scene/raster unit 换算、系统字体 fallback、hinting、layout、ellipsis 与 color-font 行为；
9. 官方实时与屏保/移动端/低质量模式的降级策略；
10. `displaycondition` 的完整表达式语法、类型转换和跨版本兼容规则；
11. 离线 bake 不是 Wallpaper Engine 官方公开能力，必须作为 MyWallpaperX 自有合同设计。

未知项进入实现时必须先建最小 fixture 和证据，不得从第三方 TODO 或当前视觉结果猜默认值。

## 8. 下次会话的资料刷新命令

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
