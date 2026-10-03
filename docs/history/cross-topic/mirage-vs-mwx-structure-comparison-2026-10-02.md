# Mirage HEAD 77e4886e 与 MyWallpaperX Scene 结构对比

> **历史证据 — 非现役入口**
>
> 截止日期：2026-10-02
>
> 对比基准：Mirage 仓库（`Reference Project/MirageWallpaper`）最新提交 HEAD `77e4886e619514391f3f0ebd9433cce525eb261b`（2026-10-01，用户指定以最新提交为准；与 `da4fa7b3` 历史考证的漂移已在条目核实行标注）。Mirage 侧全部为只读静态源码审查（`git show HEAD:` / 工作树读即 HEAD），未构建、未运行、无像素或时序对照。
>
> 来源分类：`third-party-reference-pattern`（独立 GPL-3.0 第三方播放器的静态结构对照）。只取职责分层/状态传递/顺序/结构模式；语义矛盾时裁决序=官方证据 > 我方文档 > Mirage；不复制算法表达、私有伪代码或数值常量（结构描述除外），数值仅作隔离记录不升格合同。
>
> 我方基准：当前工作树现状（约 30 文件未提交改动属并行批次，按现状审查、不当发现）；在案能力缺口一律引用[能力台账](../../scene/capabilities/coverage-ledger.md)的 L0/L1 登记，本文不重复登记。
>
> 三方材料：[Mirage 显示链路参考](../../scene/development/reference/miragewallpaper-rendering-reference.md)（快照 `8893b25b`/`443777e`/`f5049582`，本文条目在其上按 HEAD 重核）、[六域考证裁决](../../scene/history/mirage-da4fa7b3-six-domain-forensics-verdict-2026-10-01.md)（钉定 `da4fa7b3`，59 条四分类结论为已裁决事实，本文不与其矛盾；其待收编清单条目直接引用不重复考证）、[运行时架构](../../scene/architecture/runtime-architecture.md)、[事实架构地图](../../scene/architecture/runtime-as-built-map.md)。

## 一、结论摘要

stats：

| 维度 | 数值 |
|---|---|
| 对比条目总数 | 43 条（render 16 / particle 4 / clock 5 / property 5 / camera 7 / modules 6） |
| corroborated（结构互证，互证点逐条指名） | 31 条 |
| 合同同向（非 as-built 互证） | 1 条（Ca2：我方侧仅合同级证据） |
| gap（我方在案缺口，引用裁决/台账不重复登记） | 7 条（render 1 / particle 1 / clock 1 / property 2 / modules 2） |
| mirage-specific（隔离，不出借） | 4 条（particle 1 / clock 1 / camera 1 / modules 1） |
| HEAD 行为漂移（相对 `da4fa7b3` 考证/参考文档快照） | 3 处（render-13 HDR RT、camera-5 hit-test、particle-2 振荡时序）＋ 1 处参考文档未载新能力（clock-3 按需渲染静帧停帧） |
| 引用六域裁决条目 | gap 7 条对应裁决 render-0/1、particle-1、clock-4、property-1/6、camera-8、modules-3 与待收编清单 ②-1/②-5/②-6/②-8/②-11/②-13/②-15（每条 gap 的裁决/清单对应关系见其 verdict 栏；②-3 另见第四节待取证清单第 2 条，不属 gap 引用） |
| 引用有效性漂移 | M5 的 SteamService 行级引用经重查确认 `da4fa7b3`→HEAD 已漂移（Program.cs +232、SteamSession.cs +596 等），裁决行号已降级为不作行号引用（见 M5 核实行）；不构成裁决行为结论矛盾 |

globalAssessment：

**两侧在"职责分层、prepare-once、声明顺序即次序权威、脚本先于提交、draw 前一切就绪、pause 冻结全部私有累积器、最终呈现只搬运已合成结果"这些主链结构原则上高度同构（31/43 corroborated＋1 条合同同向），Mirage 提供的是我方架构合同的独立第三方旁证，而非行为规格来源。** 我方在案 gap 全部已由六域裁决登记或列入待收编清单，7 条逐一闭合对应：官方语义命名空间（`_rt_` 前缀全集，R2）、对象级粒子播放门（P4）、暂停两条生命周期线（C5）、用户属性 key 归一（Pr2）、visible 字段双职责（Pr4）、daemon→client 反向生命周期（M3）、多屏职责切分（M6），本文仅引用不重复考证。Mirage HEAD 相对历史考证出现 3 处行为漂移（新增 RGBA16F HDR RT 分支、hit-test 升级为投影解析器优先的真实局部坐标、粒子振荡时序重写）与 1 处参考文档未载的按需渲染静帧停帧能力；按用户定调以 HEAD 现读为准记录，均标注「与 da4fa7b3 考证存在漂移」，且不因此把 Mirage 做法当官方真值——HDR 分支与 hit-test 升级的官方语义仍须按官方客户端行为研究工作流另行定案。双方各自独立的实现选择（Vulkan vs Metal、进程模型、数值常量、RNG/噪声/混合因子）保持隔离；Mirage 自身静态风险（sampler V 轴、AABB 兜底路径、1920×1080 texel/bloom 基准）在 HEAD 复核仍存在，只作反例不作借鉴。

## 二、逐域对比

行号约定（三种来源，逐条标注）：①**@77e4886e**＝本次会话 HEAD 现读（grep/sed/git show 实际执行）；②**未漂移沿用**＝`git diff --stat da4fa7b3..HEAD` 实测该文件不在变更清单，`da4fa7b3` 裁决行号在 HEAD 仍有效（核查命令与结果记录在各域条目核实行）；③**裁决/快照沿用**＝未在本次 HEAD 重读，行号与结论以六域裁决或参考文档快照原文为准（C5、R11、R15、Pr4 及 M5 行级细节，各条已注明）。我方代码行号属 2026-10-02 工作树现状。verdict 词汇沿用六域裁决口径：`corroborated`=结构互证（互证点逐条指名，范围收窄时注明）；`gap`=我方在案缺口（只引用）；`mirage-specific`=Mirage 特有实现（隔离）。「核：」开头为本次会话实际执行的核实行。

### 1. render 域（覆盖参考文档 §3、§5、§6、§7、§8、§12）

| # | 主题 | Mirage 做法（HEAD 引用） | 我方做法（引用） | verdict |
|---|---|---|---|---|
| R1 | parse 分阶段与编译入口（§3/§1.1） | 四阶段签名 `ExpandObjects/BuildContext/ProcessObjects/FinalizeScene`（`SceneRenderer/Sources/SceneRenderer/Wallpaper/Compiler/CompilePipeline.cppm:165/:175/:184/:189`@77e4886e），实现集中 `SceneCompiler.cpp`（`FinalizeScene` :6860@77e4886e，grep 现读） | launch 队列一次构建 IR/RenderDescriptor/资产目录→admission/catalog 编译（`docs/scene/design/runtime-as-built-map.md:28-34`）；catalog 不可变、token 寻址（同文件 :101） | corroborated（六域裁决 render-5 同向） |
| R2 | 特殊纹理 `_rt_` 前缀准入（§5.3） | `SemanticTextures.cppm:26-48` 14 前缀全集＋sr 自造二分类（未漂移）；`ParseSpecTexName` 单点分派（`SceneCompiler.cpp:1916-1954`，调用点 :2240）@77e4886e | 官方语义面收编挂靠裁决待收编 ②-1（`scene-format-and-render-graph.md` §5.3）；`_rt_link_<id>` 等零散断言已收敛进参考文档 §5 | gap（裁决 render-0/render-1＋②-1，不重复考证） |
| R3 | 物理/映射尺寸与 UV 分离（§5.1） | TEX 保留物理尺寸、mip 链与映射信息（`TextureDecoder.cppm:43-45` mip 结构；`TextureDecoder.cpp` texb v2/v3 扩展@77e4886e），binder 按 slot 上传 resolution（`SceneUniformBinder.cpp`，未漂移文件） | 准备期 source product extent contract（`docs/scene/design/runtime-architecture.md:130`）；offscreen 尺寸只消费 `effectSourceExtent`，无纹理物理尺寸回退（`MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift:75-85`） | corroborated（参考文档 §15 P0-1 候选已结构性收敛） |
| R4 | sampler 穿透中间目标（§5.2/§5.4） | point sampling 传播到 ping-pong RT（参考文档 §5.2 快照）；2D sampler V 轴读 `wrapS` 的风险在 HEAD 仍在（`Gpu/Vulkan/TextureCache.cpp:76/:423`@77e4886e） | typed `SceneTextureSampling` 随 candidate 消费（`Resources/Textures/SceneTextureSampling.swift:45`；`SceneImageLayerCompositor+Uniforms.swift:70`）；渲染管线 4 采样变体索引（`Rendering/Metal/SceneMetalPipeline.swift:25`） | corroborated（逐链完备性仍按参考文档 P1 继续核实；§5.4 风险为反例不借鉴） |
| R5 | 声明顺序即 z-order（§6.1） | `FinalizeScene` 按 `node_id_order` 单遍 attach，注释自述 "child lists at every depth match scene.json declaration order, which is what WE treats as z-order"（`SceneCompiler.cpp:6860-6868`@77e4886e）——注释属 Mirage 对自身实现的结构描述，其中「官方 WE 如此对待」成分系 Mirage 对官方的解读、未经官方取证（见第四节⑦） | identity/作者顺序唯一权威=launchContext.renderDescriptor+catalog（`runtime-as-built-map.md:43`），运行期只读不再排序；我方「声明顺序即权威」合同独立于该注释成立 | corroborated（互证点=双方都以作者声明顺序为 layer 次序权威；官方语义成分待取证） |
| R6 | effect 私有工作空间与 ping-pong（§6.2/§6.3） | 运行态 `ResolveEffect` 重定向 A/B、中间 blend 归一、末跳恢复 final state（`Domain/Scene/LayerEffectStack.cpp:47` 起@77e4886e） | GraphProduct 有序执行＋effect-local current（`runtime-architecture.md:215` GraphExecutor 行）；唯一 compositor 消费 | corroborated |
| R7 | graph 资源逻辑版本（§6.4） | 同一 logical texture 连续写入产生新版本＋reader-before-writer 依赖（`Frame/Graph/FrameGraph.cpp:380/:393`@77e4886e，未漂移文件） | lease/publication/completion 语义承载版本概念（`Rendering/Targets/SceneGraphRenderTargetLease.swift`；`runtime-as-built-map.md:51` SubmissionCoordinator per surface） | corroborated |
| R8 | clear/preserve 与 load op（§6.5） | blend/preserve/force-clear 合成 `VkAttachmentLoadOp`（`Gpu/Pipeline/MaterialPass.cpp:549-573`），透明私有目标清 `(0,0,0,0)`（:787）@77e4886e | main pass `loadAction` 显式推进（`Rendering/Composition/SceneMainPassEncoder.swift:73/:78`）；首次写入/空源首次采样前透明初始化合同（`runtime-architecture.md:182`） | corroborated |
| R9 | mask/puppet 两步图（§6.6） | mask 预写 RT＋克隆材质 CLIPPINGTARGET combo＋`g_Texture8` 绑定绘制 clipped parts（`SceneCompiler.cpp:3371-3707`@77e4886e） | Puppet 单一 geometry owner、atlas 只是采样源（`runtime-as-built-map.md` 不变量 13）；mask 用途由准备期 profile 裁决（`runtime-architecture.md:190` slot2 `.mask`） | corroborated（范围收窄：互证点=双方都不把 mask 当作 fragment 采样开关、而走专用消费路径；实现结构不对应——Mirage 为 mask RT 预写两步图，我方为准备期用途裁决，能力深度查[能力台账](../../scene/capabilities/coverage-ledger.md) Puppet/mask 条目） |
| R10 | 材质/pass 合并 identity（§7.1） | clone 保留 blending/state/combos/binding，pass override 只覆盖非空槽（`Wallpaper/Schema/MaterialSpec.cpp`，未漂移） | Program finalizer `prepareUniformBindings` 在 variant 准备期固定参数来源（`runtime-as-built-map.md:73`） | corroborated（范围收窄：互证点=材质真实执行身份由 slot/combo/state/常量共同决定、在准备期一次性固化为不可变合同，不以 shader 文件名单一身份；Mirage clone/override 合并与我方 prepareUniformBindings 非同一结构层，两侧细节均未逐行对表） |
| R11 | shader 编译与 reflection（§7.2） | 兼容前端→glslang SPIR-V→反射绑定只绑声明 slot（参考文档 §7.2；注释前端三层见裁决 render-6） | 同型职责拆分：子进程 glslang→SPIR-V→SPIRV-Cross MSL＋三重预算 kill（`runtime-architecture.md:226-238`；`runtime-as-built-map.md:61`） | corroborated（`MaterialShaderCompiler.cpp` 自 `da4fa7b3` +225 行未逐行复核，结构结论引用快照） |
| R12 | blend/depth/cull 映射（§7.3） | translucent/additive 不写 depth、less-or-equal、按材质写 alpha（`Gpu/Pipeline/PipelineShared.cppm:12-87`，未漂移） | blend mode 进 PSO function constants（`SceneMetalPipeline.swift:58`）；depth 结构本次核实：2D image/effect 管线无 depth attachment（grep depth 零命中），3D 为 reverse-Z `.greaterEqual`＋写/不写两态（`Rendering/Metal/SceneStaticModelPipeline.swift:285/:290`） | corroborated（仅职责分层：blend/depth 状态由材质映射为 PSO/depth-stencil 状态；混合因子与 depth 规则不同族——Mirage straight source-alpha＋normal-Z less-or-equal，我方 premultiplied one/1-srcAlpha＋reverse-Z greaterEqual，不得互证或移植） |
| R13 | Bloom/global post-process（§8.1/§8.2） | `BuildBloomPostProcess`（`SceneCompiler.cpp:6996`）、`__bloom`（:7022）、mip 目标按 `g.hdr` 条件声明（:7009）@77e4886e | bloom 链作为完成合成后的独立 pass（quarter 分辨率 bright-pass＋13-tap separable blur，`Rendering/Composition/SceneBloomPostProcess.swift:44-57`）；HDR 保留原始颜色归 target pool/显示映射唯一 owner（`runtime-architecture.md:190`） | corroborated。**与 da4fa7b3 考证存在漂移：HEAD 已实现 RGBA16F HDR RT 格式分支（`RenderResources.cppm:180`；`SceneCompiler.cpp:1577-1600` `ApplyEffectRenderTargetFormat`），参考文档 §8.2/§13「screen RT 仍为 RGBA8 UNORM」不再适用于 HEAD**；其官方语义待取证（见第四节） |
| R14 | planar reflection（§8.3） | 主遍历前单独发射 reflection view，仅 reflected 且不自采样的节点；reflection camera 镜像 Y（`Gpu/Pipeline/SceneRenderPlanner.cpp:510-556`；`Domain/Scene/CameraRig.cpp:46/:95`）@77e4886e | 默认 2D 环境反射：首次消费前同帧前缀 copy＋完整 mip，typed 资源直入当次提交（`runtime-architecture.md:192`；`Rendering/Frame/SceneMetalRenderer.swift:150-310`） | corroborated（范围收窄：互证点=反射输入在消费它的材质之前同帧生产、且不构成第二 compositor 输出；机制不同族——Mirage 独立 reflection view＋镜像相机 vs 我方同帧前缀 copy＋完整 mip；我方 D3 F5 合同独立设计、非 Mirage 复刻，官方 parity 均未宣称） |
| R15 | lighting/shadow/volumetrics（§8.4） | 最多四灯 uniform 已接线；无 shadow atlas、`castvolumetrics` 无闭合 pass（参考文档 §8.4/§13，HEAD 未复核反转证据） | 三类 Definition→SceneLightSnapshot 最多四灯；bounded spotlight 投影；2D lighting/Scene HDR 整体 L0（[能力台账](../../scene/capabilities/coverage-ledger.md):1098） | corroborated（同位缺口互证：字段接线≠支持，双方均不宣称官方 parity） |
| R16 | surface 与最终呈现（§12） | `CAMetalLayer` BGRA8Unorm、drawableSize 用 backing 转换（`Host/macOS/MacDesktopHost.mm:444-445/:727`）；尺寸/格式一致 copy 否则 blit（`Gpu/Pipeline/PresentPass.cpp:539-577`）@77e4886e | 每屏独立 encode/seal→present，唯一 surface 输出（`runtime-architecture.md:442`；`Rendering/Frame/SceneMetalView.swift:47/:155`） | corroborated |

条目核实行（render 域）：

- 核（R1/R5/R13）：`grep -n "ExpandObjects\|BuildContext\|ProcessObjects\|FinalizeScene" CompilePipeline.cppm`；`sed -n '6860,6890p' SceneCompiler.cpp`（声明顺序注释逐行读取）；`grep -n "BuildBloomPostProcess\|__bloom\|_rt_bloom_mip"`。
- 核（R2）：`grep -n "ParseSpecTexName\|ignoring unsupported special tex"`（HEAD :1916/:1954/:2240）；`SemanticTextures.cppm` 未漂移（`git diff --stat da4fa7b3..HEAD` 不含该文件）。
- 核（R4）：`grep -n "addressModeU" TextureCache.cpp`（:76 直读 `wrapS`、:423 同型）。
- 核（R7/R8/R14）：`grep -n "addNewVersion\|reader before"`（FrameGraph.cpp:380/:393）；`sed -n '549,573p' MaterialPass.cpp`；`grep -n "EmitPlanarReflectionNode\|SamplesPlanarReflection"`（SceneRenderPlanner.cpp:510/:522）。
- 核（R16）：`grep -n "BGRA8Unorm\|contentsScale\|drawableSize"`（MacDesktopHost.mm）；`grep -n "CopyImage\|BlitImage"`（PresentPass.cpp:557/:577）。
- 核（未漂移依据，R7/R10/R12/R4 引用）：2026-10-02 重跑 `git diff --stat da4fa7b3ee33… HEAD -- <逐文件相对路径>`，输出不含 MaterialSpec.cpp、PipelineShared.cppm、SemanticTextures.cppm、FrameGraph.cpp、SceneUniformBinder.cpp（路径经 `git cat-file -e HEAD:<path>` 逐一验证存在，排除 pathspec 静默不匹配）。
- 核（R12 我方 depth）：`grep -rn "depthWrite\|depthCompare\|depthAttachmentPixelFormat\|MTLCompareFunction" Rendering/Metal/*.swift` → 2D image/effect 管线零命中；`sed -n '270,295p' SceneStaticModelPipeline.swift` → reverse-Z `.greaterEqual`＋writing/nonwriting 两态、shadow `.lessEqual`（:315）。
- 未核：R6/R10/R12 未逐行重读（`LayerEffectStack.cpp` +51 行；`MaterialSpec.cpp`/`PipelineShared.cppm` 未漂移故 `da4fa7b3` 引用行号有效，但内容未逐行重读）；R15 引用快照结论，未在 HEAD 反查反转证据；R3 的 `TextureDecoder.cpp` 内部仅核 mip 结构注释（+197 行未逐行）。
- 我方核：`offscreenDimensions` 现要求 `effectSourceExtent?.pixelSize`（P0-1 回退已不存在）；`SceneTextureSampling`/4 采样变体/`prepareUniformBindings`/`SceneMainPassEncoder.swift:73` 均为本次实际读取。

### 2. particle 域（覆盖参考文档 §11.5）

| # | 主题 | Mirage 做法（HEAD 引用） | 我方做法（引用） | verdict |
|---|---|---|---|---|
| P1 | 组件编译为有序 ops＋预热 | 两种 emitter（box/sphere，`Wallpaper/Compiler/ParticleCompiler.cpp:659-701`@77e4886e）、operator 分支 `sizechange/alphafade/oscillate*/turbulence/vortex`（:503-600 附近） | DefinitionParser→prepared plan→Simulator 固定步进＋作者顺序（`Systems/Particles/SceneParticleSimulator.swift:110/:191` 预热 budget 240/3600） | corroborated（参考文档 §11.5 表主干互证；两实现选择差异不互证公式） |
| P2 | 振荡算子时序（§11.5 oscillate 行） | `FrequencyValue::Advance` 每粒子 `elapsed` 累加、按 `lifetime` 归一、`GetMove=scale·(value−previous)`、phase 随机不再 +2π（`ParticleCompiler.cpp:281-353`@77e4886e） | 自有 ScalarOscillationPlan/OscillationCache（`Systems/Particles/SceneParticleOscillationCache.swift:37-64`，phase 默认 0..2π） | mirage-specific（数值/时序不互证）。**与 da4fa7b3 考证存在漂移：HEAD 提交 `77e4886e` 本身重写振荡时序（去 +2π phase 扩展、改每粒子 elapsed 累计），参考文档 §11.5「随机 phase 上界额外加 2π」不再适用于 HEAD** |
| P3 | host-pause 冻结粒子 | 帧停即 `Emitt()`=Tick 不执行，粒子私有累积器全部停摆、无专用暂停钩子（`AppRuntime/Controller/WallpaperEngineRuntime.cpp:1362-1527` 帧体@77e4886e；`Domain/Particles/ParticleSystem.cpp:235`@77e4886e） | 共享 clock pause 冻结、resume 首帧 delta 0（`runtime-architecture.md:435`；裁决 particle-0 三处我方互证） | corroborated（裁决 particle-0） |
| P4 | 对象级播放门 | `ParticlePlaybackState`（`Domain/Scene/World.cppm:2263/:2425-2426`@77e4886e）＋`SyncPlayback` reset_sequence→Refresh（`ParticleSystem.cpp:237-261`@77e4886e） | 待收编清单 ②-5（`particle-component-coverage.md` G18/X10 边界注记，我方 `SceneParticlePlaybackState` 同名异义须防误判已覆盖） | gap（裁决 particle-1＋②-5，Mirage 单源不升格，不重复考证） |

条目核实行（particle 域）：核（P2）`git show HEAD --stat`（提交即振荡修复）＋ `sed -n '281,360p' ParticleCompiler.cpp` ＋ HEAD 提交 diff 逐行读取；核（P3）`grep -n "void Tick\|Emitt\|SyncPlayback…" ParticleSystem.cpp`（HEAD :235 `Emitt()`、:237/:261 `SyncPlayback`）；核（P4）同型 `grep -n "ParticlePlaybackState\|SyncPlayback"` 在 `World.cppm`（HEAD :2263/:2425-2426）与 `ParticleSystem.cpp`（HEAD :237-261）；核（P1）`sed -n '540,600p'`/`grep -n "genParticleEmittOp"`。schema 缺省（subdivision 3/ropetrail→1/segments 4）在 HEAD 逐行确认未变（`ParticleLayerSpec.cpp:57-64`），与裁决 particle-3 一致、无漂移。

### 3. clock 域（覆盖参考文档 §4、§11.2）

| # | 主题 | Mirage 做法（HEAD 引用） | 我方做法（引用） | verdict |
|---|---|---|---|---|
| C1 | 一帧有序工作（§4） | `on(RenderDraw)` 单函数持有全帧序：pointer→script inputs（音频 250ms stale 归零）→node field anim→SceneScript→CommitDynamicTopology→CommitNodeVisibilityChanges→camera/material/transform tick→graph rebuild→粒子 Emitt→text atlas→video→font atlas→drawFrame→elapsed 推进（`WallpaperEngineRuntime.cpp:1362-1527`@77e4886e） | §8.3 九相位有序工作与可见时间（`runtime-architecture.md:433-443`）：冻结输入→属性快照→回调→admission 提交→provider/模拟→encode→每屏提交→completion | corroborated（同构：脚本后提交、draw 前一切就绪） |
| C2 | 帧时钟家族（§11.2） | FrameTimer 内持 ThreadTimer；busy CAS 不重叠；FrameTime（5 帧滑窗实测）/IdeaTime 双帧时；默认 15 FPS（`AppRuntime/Timing/FrameClock.cpp:11-60`，未漂移）；SetInterval 原子 revision 即刻生效＋不补帧（`WorkerTimer.cpp:20-58`@77e4886e） | `SceneClock.maximumSimulationFrameTime=0.25` clamp（`Runtime/Frame/SceneFrameContext.swift:71/:200`）；FrameDriver 快照→guard→discard（`runtime-as-built-map.md` 不变量 9） | corroborated（「不追补积压周期」方向一致；数值隔离） |
| C3 | 按需渲染静帧停帧 | `SceneCanRenderOnDemand` 按 prepared 事实证明（无脚本/音频/粒子/camera path/post-process/仅默认 RT）可停表 idle，事件唤醒 `wakeIdleFrame`（`WallpaperEngineRuntime.cpp:1078+`、`wakeIdleFrame` 调用点 :1551/:1690@77e4886e） | cadence 至多推进一次＋暂停冻结（`runtime-architecture.md:435`）；无静帧停帧能力条目（台账未登记，不在本文新增缺口） | mirage-specific（隔离记录；参考文档未载，属 HEAD 新观察） |
| C4 | pause/power 职责分层（§1.1） | "The app is the sole judge of occlusion, lock, sleep, battery and thermal"（`SceneRenderer/Tools/SceneWallpaper/ControlChannel.cpp:115-116`），pause/resume/play/power 分发（:110-127）@77e4886e | 不变量 16：控制面单一通道、Host 归属、App 持久化播放意图（`runtime-as-built-map.md:102`） | corroborated（裁决 clock-3/modules-0＋待收编 ②-14 引用） |
| C5 | 暂停两条生命周期线 | 帧停同步立即 vs 音频延迟 fade＋generation 门作废（裁决 clock-4，`da4fa7b3` 行号） | `runtime-architecture.md:491` 暂停合同空位＋待收编 ②-6 | gap（裁决 clock-4＋②-6，不重复考证） |

条目核实行（clock 域）：核（C1）`sed -n '1362,1520p' WallpaperEngineRuntime.cpp` 全帧体逐行读取（含 250ms stale 注释、`TickNodeFieldAnimations`→`drawFrame` 顺序）；核（C2）`grep -n "SetInterval\|busy\|FrameTime\|IdeaTime"`；核（C3）`grep -n "SceneCanRenderOnDemand"`＋`sed -n '1078,1090p'`（排除条件逐条读取）；核（C4）`sed -n '110,127p' ControlChannel.cpp`。C5 未在 HEAD 重读（属裁决已裁决事实）。

### 4. property 域（覆盖参考文档 §4.1、§11.6、live property）

| # | 主题 | Mirage 做法（HEAD 引用） | 我方做法（引用） | verdict |
|---|---|---|---|---|
| Pr1 | live property 分级更新（§4.1） | `on(RenderSetUserProperty)`：canonical key→逐字段 applier（uniform/clear/纹理刷新/combo/文字/粒子/相机）→纹理 refresh 失败或 combo/visibility/postprocess 变化才 `rebuildRenderGraph` 兜底（`WallpaperEngineRuntime.cpp:1682-1755`@77e4886e） | 五类变化最小失效域（value-only/resource-generation/geometry-extent/program-variant/topology），失效域声明优先于逐字段枚举（`runtime-architecture.md:316-324`） | corroborated（同向分级；我方按失效域且禁止「结构没变时兜底重建」的反向面） |
| Pr2 | canonical key 归一 | `CanonicalUserPropertyKey`＋`NormalizeUserProperties`（显式 canonical 键终胜/归一键间首键胜出，`WallpaperEngineRuntime.cpp:1042-1076`@77e4886e） | 待收编清单 ②-8（`runtime-input-property-coverage.md` 5.2 schemecolor 行缺口栏；无官方对照单源） | gap（裁决 property-1＋②-8，不重复考证） |
| Pr3 | parse 前注入用户值 | `ApplyUserPropertyBeforeFirstGraph` 首图前逐键应用（可见性剪枝＋保持首图单次构建）（`WallpaperEngineRuntime.cpp:998-1021`@77e4886e） | 加载时 `SceneUserPropertyDocumentResolver().resolve` 解析期生效（`MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift:111-116`） | corroborated（裁决 property-2＋②-9） |
| Pr4 | visible 双职责（§11.6） | visible=布尔初值（含 object.value-boolean）＋user 绑定载体（裁决 property-6@da4fa7b3，未在本次 HEAD 重读） | 我方 `visibleValue`（Bool 直取/`{value:…}`，`Format/SceneDocument.swift:300-308`）与 binding 载体（`Systems/Properties/SceneUserPropertyBindings.swift:81-88`）同语义互证 | gap（裁决 property-6＋②-11；互证已足够，收编归 Scene 会话） |
| Pr5 | PKGV 版本语义 | `pkg_version` 贯穿 DocumentModel 解析（`Wallpaper/Schema/DocumentModel.cpp:319-363`@77e4886e） | 已收敛登记于[资料来源索引](../../scene/development/source-index.md) §1.2（裁决 property-5） | corroborated（已登记） |

条目核实行（property 域）：核（Pr1/Pr2/Pr3）`sed -n '995,1085p'`/`sed -n '1682,1760p'` 逐行读取（含 canonical key 规则与 rebuild 兜底链）；我方核 `SceneDocument.swift:96-120`（解析期 resolve＋script IR 读作者原 wrapper 注释）。Pr4/Pr5 为裁决已裁决事实＋我方文件本次实读。

### 5. camera 域（覆盖参考文档 §9、§10、§11.6）

| # | 主题 | Mirage 做法（HEAD 引用） | 我方做法（引用） | verdict |
|---|---|---|---|---|
| Ca1 | 三类 camera context（§9.1） | `scene.cameras["effect"/"global"/"global_perspective"]` 三类＋per-layer effect camera（`SceneCompiler.cpp:2966/:2974/:2997/:3827-3849`@77e4886e） | 最终 MVP 由 canonical world/camera 链决定，source/effect/final 消费同阶段结果（`runtime-architecture.md:469`；`Rendering/Frame/SceneMetalRenderer+Camera.swift`） | corroborated（mvp 非全局唯一） |
| Ca2 | fill mode 改 viewport（§9.3） | 不在 blit 裁 UV，改 global ortho viewport 并同步 linked cameras（`Gpu/Pipeline/VulkanFrameEngine.cpp:1058-1062/:1821+`@77e4886e） | 合同级：新相机/fill 行为落 canonical world/camera resolver（`runtime-architecture.md:463-469`）；未逐行核实现状映射 | 合同同向（非 as-built 互证：Mirage 侧为 as-built 实现，我方侧仅目标合同、现状映射未逐行核实，不足以支撑结构互证；现状深度留参考文档 P1 清单） |
| Ca3 | parallax uniform（§7.4/§9.4） | `g_ParallaxPosition` 中心 0.5＋平滑鼠标×mouseinfluence、关闭时 {0.5,0.5}（`SceneUniformBinder.cpp:433-441`，未漂移，裁决 camera-3 行号有效） | NDC→0..1 上传同名声明驱动（`Rendering/Bindings/SceneResolvedMaterialUniformEncoder.swift:87-95`；`SceneAuthoredShaderFrameInputs+FrameContext.swift:21`） | corroborated（代数等价，裁决 camera-3） |
| Ca4 | shake（§9.4） | 作用于 active camera VP、canvas 最小边缩放、`AllowCameraShake()` 可抑制（`SceneUniformBinder.cpp:237-262`@77e4886e，未漂移） | 与官方 2.8.42 projection-height/XYZ 定案对齐（参考文档 §9.4 官方冲突段；裁决 camera-0） | mirage-specific（幅度/维度/admission 不出借） |
| Ca5 | hit-test 与局部坐标（§10.2/§10.4） | 双路径：cursor projection resolver 优先（四角投影→NDC 透视除法→屏幕空间多边形内外测试→unproject 反求 world/local），无 resolver 回退 world AABB；新增 `Solid()` 与祖先可见门（`AppRuntime/Scripting/ScriptRuntime.cpp:1301-1420`、:4790-4791@77e4886e） | canonical world frame＋camera VP×model 逆投影到 layer local，命中域 local∈[-0.5,0.5]²，solid 门＋作者世界换算（`Rendering/Frame/SceneMetalView+SceneScriptCursorInteraction.swift:219-240`） | corroborated（结构同向）。**与 da4fa7b3 考证存在漂移：HEAD hit-test 已从纯 world AABB＋local=world 升级为投影解析器优先的真实局部坐标，参考文档 §10.2/§13「cursorLocalPosition 等于 world position」「仅 world AABB」不再适用于 HEAD** |
| Ca6 | 全局轮询输入（§10.1） | wallpaper window `ignoresMouseEvents`、轮询 `NSEvent.mouseLocation/pressedMouseButtons`、NSTimer input_hz 上限（`Host/macOS/MacDesktopHost.mm:607-637/:716/:744-758`@77e4886e） | 帧边界冻结输入快照、独立投影（`runtime-architecture.md:425`/:436；`SceneFrameContext.swift:14` pointer state） | corroborated（裁决 camera-7/camera-9） |
| Ca7 | visibility 判定链与 linked layer（§11.6） | `visibility_elidable_layer_ids`＋`m_pending_node_visibility_changes`→Commit 顺序提交（`Domain/Scene/World.cpp:1314-1379`@77e4886e）；隐藏 linked source 只写私有 target（裁决 render-4/camera-4/camera-5） | 显隐准备收敛＋脚本 visibility mutation 事务（[能力台账](../../scene/capabilities/coverage-ledger.md) 2026-09-27 条目；`runtime-architecture.md:302`） | corroborated（语义同裁决；HEAD 行号自 :1070-1124 漂移至 :1314-1379，行为无漂移） |

条目核实行（camera 域）：核（Ca4）`sed -n '215,262p' SceneUniformBinder.cpp`（min(ortho0,ortho1)、仅 activeCamera、z=0）；核（Ca5）`sed -n '1301,1420p'`＋`sed -n '4760,4840p'`（双路径、Solid、ancestors_visible、captured_buttons 逐行）；核（Ca6）`grep -n "PollInput\|ignoresMouseEvents\|input_hz"`；核（Ca7）`grep -n "CommitNodeVisibilityChanges\|visibility_elidable"`（HEAD 行号重定位）；核（Ca3）`grep -n "g_ParallaxPosition"`（未漂移文件确认）＋我方 `SceneResolvedMaterialUniformEncoder.swift:87-95`。Ca1/Ca2 为 HEAD 符号定位＋我方合同引用，未逐行读实现体。

### 6. modules 域（覆盖参考文档 §3、§10.1、§12.1 及裁决 modules 域）

| # | 主题 | Mirage 做法（HEAD 引用） | 我方做法（引用） | verdict |
|---|---|---|---|---|
| M1 | 进程模型 | App＋三类壁纸独立 tool＋per-display 渲染进程九相位事务（裁决 modules-1/2，`RendererController.swift:539-549` TransitionPhase 九 case@77e4886e 现读确认仍九相） | 单二进制 `--mwx-scene-daemon` accessory＋`SceneDaemonRuntime` 私有持有唯一 Host（`Runtime/IPC/SceneDaemonRuntime.swift:139`；`runtime-as-built-map.md:38`） | mirage-specific（裁决 modules-1/2：反路线已显式裁决） |
| M2 | app-owns-policy | 同 C4（`ControlChannel.cpp:115-116`@77e4886e） | 不变量 16（`runtime-as-built-map.md:102`，明文禁止 Host 反向监听） | corroborated（裁决 modules-0＋②-14） |
| M3 | 父进程 watchdog 与事件分帧 | `EVFILT_PROC/NOTE_EXIT`＋`getppid()` 轮询兜底（`VideoRenderer/Tools/VideoWallpaper/VideoWallpaper.mm:43-75`@77e4886e） | daemon→client 反向生命周期与事件行分帧完整性未定义（裁决 modules-3＋②-15，需 owner 裁决） | gap（引用裁决，不重复考证） |
| M4 | Web 输入转发/资源 serving/频谱 producer（§10.1） | `WebRenderer/Sources/WebRenderer/WRDesktopInputForwarder.mm` 全局 monitor＋`WebRendererEngine.mm` 注入（未漂移，核查见条目核实行；裁决 camera-6/modules-7 行号在 HEAD 有效） | `SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding{,Monitors,HitTesting}.swift` 三文件同构（本次实读存在）；`Core/Playback/SystemAudioSpectrumService.swift` 唯一系统 tap producer | corroborated（裁决 modules-7） |
| M5 | Steam 服务 | SteamService 常驻进程＋WebAPI 单例（裁决 modules-8/9@da4fa7b3；**该目录 HEAD 已漂移**——Program.cs +232、SteamSession.cs +596 等，裁决行号不得当 HEAD 行号引用） | scene-steamkit 迁移计划同构互证；key 路由已显式弃用（裁决 modules-8/9） | corroborated（范围收窄：互证点=常驻 Steam 服务进程＋协议交互的职责分层，引用裁决结论；行级细节随 HEAD 漂移不作行号引用；＋mirage-specific 内置 key 隔离） |
| M6 | surface/多屏职责切分（§12.1） | App 层 DisplayRegistry 唯一屏 registry、渲染层单 config→display_id（`Mirage/Mirage Wallpaper/Services/DisplayRegistry.swift`，未漂移，裁决 camera-8） | 多屏为开放边界（[能力台账](../../scene/capabilities/coverage-ledger.md):396/:1050；裁决 camera-8＋②-13） | gap（引用裁决，不重复考证） |

条目核实行（modules 域）：核（M1）`grep -n "TransitionPhase"`＋`sed -n '539,553p' RendererController.swift`（九 case 逐行）；核（M2）同 C4；核（M3）`grep -n "EVFILT\|NOTE_EXIT\|getppid"`（HEAD :43-75）；核（M4）`ls SteamWorkshopWeb/Host/`＋`find SystemAudioSpectrumService`；未漂移核查=2026-10-02 重跑 `git diff --stat da4fa7b3ee33… HEAD -- <逐文件相对路径>`，`WebRenderer/Sources/WebRenderer/` 两 mm 文件不在变更清单（实际路径经 `find` 校正、`git cat-file -e` 验证）；`SteamService` **在变更清单内**（Program.cs/Protocol.cs/SteamSession.cs/WorkshopDownloader.cs 共 +885/−38）→ M5 已按漂移降级；`DisplayRegistry.swift`（正确路径 `Mirage/Mirage Wallpaper/Services/`）不在变更清单。M5 的裁决行为结论（同构互证/内置 key）为 da4fa7b3 考证事实，本文不因行级漂移翻案，仅停止行号引用。

## 三、可借鉴模式清单

以下全部为 `third-party-reference-pattern`（独立 GPL-3.0 第三方实现）、版本=HEAD `77e4886e`；只描述结构模式，不复制算法表达、常量或实现细节；任何落点仍须按 AGENTS.md 设计门与官方证据优先级定案。

1. **全帧次序单点 owner**：一帧的全部系统推进（输入→脚本→拓扑/显隐提交→相机/材质→graph 重建→粒子/文字/视频/字体→draw）集中在一个显式函数体内按固定顺序执行（`WallpaperEngineRuntime.cpp:1362-1527`），与我方 §8.3 九相位合同同构；可借鉴其「脚本提交必须先于同帧 draw 计算矩阵」的 happens-before 显式化。
2. **live property 按影响层级分流**：字段→效果映射显式枚举，资源刷新失败或执行形状变化才升级 graph 重建（`WallpaperEngineRuntime.cpp:1682-1755`）；我方五类失效域合同已更严，可借鉴的是「纹理刷新失败显式回退到 rebuild」的失败升级路径表达。
3. **按 prepared 事实证明的静帧停帧**：无脚本/音频订阅/粒子/camera path/post-process/仅默认 RT 时停表 idle、事件唤醒（`WallpaperEngineRuntime.cpp:1078+`）；若我方未来立项省电播放，准入应同样「从 prepared 内容证明可停」，禁止按连续相同像素猜测。
4. **graph 逻辑版本与 reader-before-writer 依赖**：同一 logical texture 连续写入产生显式版本边（`FrameGraph.cpp:380/:393`）；我方 publication/generation 语义可对照检查依赖闭包完整性。
5. **脚本故障不拖死 render thread**：脚本 watchdog 超时后永久停止调用、actuator 保留最后值、渲染继续（参考文档 §11.1，HEAD 未复核反转）；与我方「exception/timeout/OOM 按最小失败合同」同向。
6. **hit-test 双路径（投影解析器优先＋AABB 兜底）**：HEAD 已升级为投影优先、局部坐标反求、Solid/祖先可见门（`ScriptRuntime.cpp:1301-1420`）；结构模式（先精确后兜底＋显式准入门）可借鉴，谓词细节不迁移。
7. **parse 前注入用户值**：首图构建前逐键应用用户属性，供可见性剪枝并保持首图单次构建（`WallpaperEngineRuntime.cpp:998-1021`）；与我方解析期 resolve 同构，可在②-9 收编时作外部互证引用。
8. **host-pause 冻结全部私有累积器**：暂停冻结帧时钟后，粒子/emitter/trail 各私有累积器自然停摆、恢复无跳变，无需各系统自带暂停钩子（裁决 particle-0）；印证我方共享 clock「pause 冻结、resume 首帧 delta 0」合同。

## 四、不可比与待官方取证清单

不可比（结构或平台根本不同，不出借；对应裁决 mirage-specific 隔离记录）：

- Vulkan 三级 GPU 资源缓存键字节格式（裁决 render-8）——我方为 Metal，无对应物。
- std140/packoffset HLSL 前端装配 workaround（裁决 render-7）——绑定 Mirage glslang HLSL 源路径。
- per-display 渲染进程＋九相位事务＋IPC 指令流（裁决 clock-6/modules-1/2）——我方单二进制 daemon 已显式裁决反路线。
- 视频转码管线（裁决 modules-4）、playlist 轮换（裁决 clock-8）、编辑器侧 JS 条件求值（裁决 property-8）——我方产品无对应职责。
- 粒子振荡时序/数值（本文 P2）与 shake 查表（本文 Ca4）——HEAD 现读仍为 Mirage 自有实现，公式与常量不迁移。

待官方取证（Mirage 行为不得升格官方真值；须按官方客户端行为研究工作流定案）：

1. `_rt_` 前缀全集官方行为规格（裁决待收编 ②-1；本文 R2 只记录 Mirage 分派结构）。
2. 官方 g_Texture3 hidden uniform 缺省绑定 `_rt_MipMappedFrameBuffer` 生产职责（裁决 render-9＋②-3）。
3. `scenerenderer.scheme_color` key 归一的官方拼写与生产者（裁决 property-1＋②-8，Mirage 仓库无生产者）。
4. 对象级粒子播放门（play/pause/reset_sequence 语义）官方对照（裁决 particle-1＋②-5，Mirage 单源）。
5. daemon→client 反向生命周期职责归属（裁决 modules-3＋②-15，需 owner 裁决）。
6. **新增（因 HEAD 漂移产生）**：HEAD 的 RGBA16F HDR RT 格式分支（`ApplyEffectRenderTargetFormat`）与投影解析器 hit-test 的官方对应语义——历史取证未覆盖 HEAD 新行为，若要引用须重新按官方固定版本取证；本文仅作 Mirage HEAD 隔离记录。
7. **新增（本次修订）**：Scene 声明顺序=官方 z-order 的语义（R5 中 Mirage 注释 "what WE treats as z-order" 的官方成分）——该注释只是 Mirage 对官方行为的解读，官方语义须按官方客户端行为研究工作流定案；我方「声明顺序即权威」的合同独立于该注释成立，不受其取证结果影响。

## 五、覆盖与未覆盖声明

- 覆盖：静态源码结构对比。43 条条目覆盖参考文档 §3-§12 各大节主体内容（§1/§2/§13-§17 为方法论/缺口表/审计清单/维护约定，其结论按条目并入对应域，不单列对比）；Mirage 侧行号分三种来源（见行号约定）：①HEAD 现读（标 @77e4886e）、②未漂移沿用（`git diff --stat` 实测该文件不在 `da4fa7b3..HEAD` 变更清单，核查命令记录在各域条目核实行）、③裁决/快照沿用（C5、R11、R15、Pr4 与 M5 行级细节，未在本次 HEAD 重读，以裁决/快照原文为准）。漂移处已逐条尾注；M5 的 SteamService 行级引用经 2026-10-02 重查确认 HEAD 已漂移，已降级为不作行号引用（不翻案裁决行为结论）。
- 未覆盖：运行时行为、像素/时序结果、性能数字、内存占用、构建可行性均不在范围——双方本次均未构建未运行；Mirage 缺口表（参考文档 §13）在 HEAD 的反转可能性只在 R13/R15/P2/Ca5 涉及处现读，其余沿用快照结论。
- 我方侧：按 2026-10-02 工作树现状审查，约 30 文件未提交改动（并行批次，含粒子方向阴影与 RT 池文件）按现状引用、不作为本文发现；在案能力缺口一律以能力台账 L0/L1 为准，本文未新增任何缺口登记。
- 治理：本文为 `historical-evidence`，登记于 `docs/document-role-index.json`；现役事实按 AGENTS.md 第 2 节顺序核对，不得从本文续接任务。
