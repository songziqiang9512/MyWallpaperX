# Scene Render Graph 与 Shader 覆盖矩阵

> 核验日期：2026-07-23
>
> 范围：Effect definition、material、render graph、FBO 与 Wallpaper Engine shader 合同。
>
> 结论：当前 graph 已有较完整的保真 IR，且 Blur Precise 与 stock Blur 默认 profile 有严格、失败关闭的 Metal 执行器；当前没有通用 authored graph executor，也没有 GLSL/HLSL 前端或通用 shader executor。因此本页没有任何 `L4` 项。

## 1. 证据与使用方式

本页把以下资料压成一张可执行的开发清单，不替代原始语义文档：

- [Scene 格式与 Render Graph](scene-format-and-render-graph.md)：字段、资源身份、pass 顺序和目标执行合同；
- [Effects 语义全集](effects-reference.md)：45 个公开 effect 的输入、pass/RT 和正确空间；
- [官方页面全目录](official-page-catalog.md)：官方 Shader/Effects 页面无遗漏入口；
- [运行证据索引](runtime-evidence-index.md)：IR、strict Blur 与 GPU 证据包；
- [资料来源与证据索引](source-index.md)：官方、样本、第三方和当前运行证据的可信边界。

这里的等级只描述 **MyWallpaperX 当前实现成熟度**，不是官方语义的可信等级，也不是某个 effect 的视觉相似度。

| 等级 | 唯一含义 |
|---|---|
| `L0` | 当前代码没有识别或承载该语义；只有文档需求不算实现。 |
| `L1` | 能发现资源、路径、blob、raw token 或给出诊断，但没有可执行的结构化语义。 |
| `L2` | 已进入 typed/loss-preserving IR 或 typed host carrier，并有结构/失败关闭测试；没有 GPU 执行承诺。 |
| `L3` | 至少一个**明确注册的 strict executor 子集**精确消费该语义，并有正向、负向及运行/GPU 证据；只对表中边界负责。 |
| `L4` | generic runtime 能直接按 authored graph/shader 合同执行该语义，不依赖 effect ID、shader path 或固定 profile 手写分派，并覆盖资源生命周期和回归矩阵。 |

每行只能有一个等级。**通用 primitive 取全部已知 authored 形态的共同最低状态**：某个 strict profile 能执行，只能在该 profile 自己的行和 [Effect 执行覆盖表](effect-execution-coverage.md) 记 `L3`，不能反向把通用 definition、pass、FBO、slot、combo、uniform 或 render state 抬到 `L3`。辅助设施存在也不能把官方语义抬级。

## 2. 三条实现通道

| 通道 | 当前含义 | 当前事实 |
|---|---|---|
| IR | 读取并保真保存 definition/material，再编译资源身份、节点、slot 和 blocker | [SceneEffectDefinition.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneEffectDefinition.swift)、[SceneAuthoredEffectRenderPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlan.swift)、[SceneAuthoredEffectRenderPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner.swift) |
| generic runtime | 可复用的 frame context、texture registry、offscreen allocation、Metal encoder 等基础设施 | 它们提供时钟、pointer、尺寸、纹理和命令编码能力，但**不会自动解释 authored graph node 或 shader source** |
| strict executor | 先匹配完整 graph/material/profile，再调用独立手写 Metal backend；任何未知 shape/state/combo 均拒绝 | 目前只有 2-pass Blur Precise 和 4-pass stock Blur 默认 profile；入口见 [SceneAuthoredEffectExecutionPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectExecutionPlan.swift) 与 [SceneAuthoredStandardBlurPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredStandardBlurPlanner.swift) |

`SceneMetalPipeline.swift` 中 Foliage/Shake/Water/Cursor 等手写 MSL 是 legacy/profile approximation。它们证明宿主能上传纹理、time、pointer 和矩阵，不证明 WE shader source、annotation、macro 或 built-in 名称已经兼容，也不属于 generic authored shader executor。

## 3. Render Graph 覆盖

| 语义项 | 等级 | IR | generic runtime | strict executor | 代码/测试证据 | 执行边界 | 下一门 |
|---|---|---|---|---|---|---|---|
| `EffectDefinition` | `L2` | JSON5 loader 保留 metadata、dependencies、FBO、ordered pass、functions/gizmos、extra fields 和 unknown paths | 没有按任意 definition 驱动 GPU 的执行循环 | 两个 Blur profile 从同一 authored plan 进入执行，未知字段/blocker 一律拒绝 | [定义 loader](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneEffectDefinition.swift)、[定义测试](../../../script/tests/test_scene_effect_definition.py)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | strict Blur 只证明两个完整 profile；通用 definition 仍停在 IR | 建立 graph executor capability registry；每种 node/resource semantic 显式声明并逐项放行 |
| ordered pass / material ordinal | `L2` | definition pass 顺序、definition index、material ordinal 与 instance pass index 分离 | 没有任意 node list 执行循环 | strict Blur 要求完整顺序；copy/swap 不消耗 material ordinal | [graph planner](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner.swift)、[graph 测试](../../../script/tests/test_scene_effect_render_graph.py)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | 只有两个固定 material-only 序列进入 GPU；generic scheduler 不存在 | 增加统一 node scheduler，并以 read/write hazard 验证 pass 顺序 |
| `Material` | `L2` | 保留 shader path、8 个 nullable slots、user texture、combo、constant 和 render state；instance override 与 explicit bind 有 provenance | 有 texture loader/pipeline primitives，但没有任意 material consumer | strict Blur 按 shader path、slot、combo、constant、state 全量匹配 | [asset catalog](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAssetCatalog.swift)、[material resolver](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredMaterialResolver.swift)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | shader defaults/annotation 未进入 resolver；strict profile 不等于 generic material | 先产出 `ShaderContract`，再让 material resolver 合并 annotation default、provider readiness 与 variant key |
| FBO declaration | `L2` | effect-scoped identity、extent、format、unique、clear、UV、condition 均进入 `RenderTarget` | `SceneGraphRenderTargetPlan/Table` 已提供 input/scale 尺寸、lifetime、checked budget 与整组 Metal allocation；尚未接 compositor/cache | precise 仍由旧 pool 分配 1 个 full RT；standard 仍由旧 pool 分配 2 个 quarter RT | [target plan](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetPlan.swift)、[allocation table](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetTable.swift)、[plan 测试](../../../script/tests/test_scene_graph_render_target_plan.py)、[table 测试](../../../script/tests/test_scene_graph_render_target_table.py) | 基础表存在不等于任何 authored graph 已通过它执行；通用 FBO 仍未执行 | 迁移 strict Blur，闭合 effect/size cache、resize/reset/stop，再扩 scheduler |
| `target` | `L2` | 区分 layer source、effect output、effect-scoped framebuffer 和 unresolved；同名 FBO 不跨 effect 共享 | 新 table 按完整 identity 映射且一次 allocation 内不 alias；每个 surface 仍由自己的 pool 隔离，named layer target namespace 保持独立 | strict Blur 尚未消费新 table | [target identity](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlan.swift)、[target plan](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetPlan.swift)、[table 测试](../../../script/tests/test_scene_graph_render_target_table.py) | 非 Blur authored target 不会分配或发布；named layer target 不能冒充 effect FBO/history | 由 pool 以 effect identity + plan + extent 缓存，验证同名跨 effect 不串用和 resize 换代 |
| `previous` | `L2` | 每个 effect 开始时固定为 chain input；同一 effect 内不会随 pass target 前进 | 无通用 effect-chain executor | 两个 Blur strict shape 都验证 `previous` slot 和 final output | [binding resolution](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner+Resolution.swift)、[graph 测试](../../../script/tests/test_scene_effect_render_graph.py)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | strict Blur 证明固定输入；original、scene background、full-frame alias、history 仍未接 | 为全部 source kind 建显式 identity/provider，不以当前 framebuffer 猜 `previous` |
| `bind` | `L2` | sparse index、authored name、conditions 和 texture identity 均保留；slot 不压缩 | material candidate resolver 能保留来源优先级，但尚无通用 ready-provider 消费 | strict Blur 精确验证 slot 0/1/2 和 source identity | [binding resolver](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner+Resolution.swift)、[material resolver](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredMaterialResolver.swift)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | 只解析 `previous` 与当前 effect FBO；original、scene alias、named layer/system/media/history 未覆盖 | 补齐 source-kind 表、candidate-to-frame selection 和逐 slot physical/mapped metadata |
| `compose` | `L2` | raw value 保留在 node；`true` 生成 blocker | 没有 scene-behind-layer capture identity | 无 strict executor；不会猜成当前屏幕或 full framebuffer | [planner blocker](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner.swift)、[compose 负向测试](../../../script/tests/test_scene_effect_render_graph.py) | 官方 Refraction 行为已知，但 private raw `compose` 的通用输入合同仍不足 | 先为已验证 definition 注册 scene-background provider，再测 capture 时序、遮挡和重复背景 |
| `copy` | `L2` | 独立 command node，保留 source/target，校验 storage compatibility；不占 material ordinal | Metal 可 blit/render-copy，但没有 authored copy scheduler | 无 strict executor | [command planning](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner.swift)、[copy 测试](../../../script/tests/test_scene_effect_render_graph.py) | Motion Blur 的 copy 只被建图，不更新 history | 增加无 read/write alias 的 copy executor，并覆盖 resize/switch/seek/stop history 初始化 |
| `swap` | `L2` | 独立 command node；要求 extent/format 相容，并额外比较 unique/UV/clear/condition | 没有 resource-handle swap 或跨帧 ownership | 无 strict executor | [command compatibility](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner+Resolution.swift)、[swap 测试](../../../script/tests/test_scene_effect_render_graph.py) | Fluid pass/swap 顺序保真，但整图因 function/condition blocker 不可执行 | 用 identity/handle swap 实现，不做像素 copy；先闭合 allocation scope 与 persistent lifecycle |
| `condition` | `L2` | FBO/pass/bind 各位置保留 raw `SceneJSONValue` 并产生显式 blocker | 无表达式环境或逐帧 evaluator | strict Blur 要求所有 condition 为 nil | [definition IR](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneEffectDefinition.swift)、[planner blocker](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner.swift)、[graph 测试](../../../script/tests/test_scene_effect_render_graph.py) | 没有 AST、类型转换、combo/runtime variable 绑定或分支资源分析 | 从合法 fixture 建最小 condition AST/evaluator，并验证 false 分支不分配 RT/不占 material ordinal |
| `function` | `L2` | definition 顶层 functions 原样保留并阻断执行 | 无 live function executor 或 reset hook | strict executor 只接受 functions 缺失 | [definition loader](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneEffectDefinition.swift)、[保真测试](../../../script/tests/test_scene_effect_definition.py)、[planner blocker](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner.swift) | Fluid reset 等函数不会运行 | 先确认 function schema、调用时机和资源副作用，再实现 resize/reset/initialization fixture |
| extent (`scale`/`fit`/absolute/input) | `L2` | 规范化为 `input`、`scale`、`fit`、`absolute`、`unsupported` | pools 能按请求尺寸分配/限额，但不解释完整 authored extent | precise 只接受 input extent；standard 只接受 scale=4 | [extent resolver](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner+Resolution.swift)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir)、[strict GPU 证据](runtime-evidence-index.md#e-effect-blur) | input/scale-4 只是两个 strict profile；generic extent 仍未执行 | 定义基于 source/effect/canvas 的尺寸算法，逐类测试 fit/fixed/scale、rounding 和 resize |
| `format` | `L2` | 已识别 `r8`、`rg88`、`r16f`、`rg1616f`、`rgba8888`、`rgba_backbuffer`，未知值阻断 | 通用 target pool 当前固定 `bgra8Unorm` | strict Blur 只执行 `rgba_backbuffer` 对应的 BGRA8 路径 | [format gate](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner+Resolution.swift)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir)、[strict GPU 证据](runtime-evidence-index.md#e-effect-blur) | whitelist 中其他 format 只是 graph 可结构化；generic allocation/采样未实现 | 建 format-to-Metal 表，逐项验证通道、精度、filter/write 和 byte budget |
| `clear` | `L2` | string/array 四分量被校验并保真 | 当前 offscreen pass 固定透明清屏，与 authored clear 无关 | strict Blur 要求 clear 为 nil | [clear validation](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner+Resolution.swift)、[畸形值测试](../../../script/tests/test_scene_effect_render_graph.py)、[fixed clear backend](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneOffscreenEffectRenderer.swift) | 不能把“backend 总是 clear”记成 authored clear 支持；persistent RT load/reset 未定义 | 将 clear 映射到 load action 与生命周期事件，覆盖首次分配、每帧、reset 三种时机 |
| `unique` | `L2` | bool 声明和 effect-scoped identity 已保留；非 bool 阻断 | 没有按 unique 管理实例/跨帧资源；所有 authored FBO identity 本就含 effect key | strict Blur 只接受 false | [definition/graph IR](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlan.swift)、[copy/unique 测试](../../../script/tests/test_scene_effect_render_graph.py)、[strict 负向测试](../../../script/tests/test_scene_authored_effect_execution.py) | `unique` 不等于 history，当前也不会让资源跨帧常驻 | 以 read-before-write/copy/swap/function 数据流判定 persistence，再让 unique 只控制实例隔离 |
| FBO `UV` / wrap | `L2` | raw `uvs` 保留；当前只允许识别到的 `repeat` 通过结构门，其他值阻断 | image texture/mask 有独立 UV transform，但不是 FBO sampler contract | strict Blur 要求 uvs 为 nil | [UV gate](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner.swift)、[mapped mask GPU 测试](../../../script/tests/test_scene_framebuffer_capture.py) | repeat 即使未产生 blocker，也未被 authored graph executor 设置为 sampler address mode | 建 texture view/sampler/UV projection 合同，区分 physical size、mapped size、rotation/translation 与 wrap |

## 4. 官方 Shader 六页合同

以下六个 anchor 与 [官方逐页映射](official-page-map.md) 一一对应。这里记录官方公开语义，不把编辑器操作步骤误算成运行时能力。

<a id="op-shader-overview"></a>
### 4.1 Overview

| 官方合同 | 当前级别 | 当前边界 / 实现门 |
|---|---|---|
| effect shader 使用类 GLSL source，并在需要时翻译为 HLSL | `L1` | 只能发现 source/path；没有 source frontend、translation 或 compile contract。先完成 [D7](capability-dependency-map.md#d7) `ShaderSource` 和 canonical hash。 |
| 官方向 effect shader 提供向后兼容承诺 | `L0` | MyWallpaperX 尚无能承接该承诺的 generic executor；strict MSL 不能冒充 source compatibility。 |
| 3D 自定义 shader 必须兼容 `generic2.vert` / `generic2.frag` | `L0` | 无 3D model/runtime，也未取得这两个 stock contract 的合法本地 schema。 |
| 不应替换 particle 等 system shader；官方不保证其向后兼容 | `L0` | 产品门：即使未来能读取，也必须默认拒绝 system-shader override，不能把它纳入首期 arbitrary shader。 |

<a id="op-shader-syntax"></a>
### 4.2 Syntax

| 官方合同 | 当前级别 | 当前边界 / 实现门 |
|---|---|---|
| custom preprocessor 支持布尔/逻辑条件，但不是完整 C preprocessor；不支持字符串化、拼接和 `#elif` | `L0` | 无 directive/token/condition stack；实现必须保留 source map，并对 unsupported directive 失败关闭。 |
| 环境 define：`GLSL`、`HLSL`、`HLSL_SM40`、`HLSL_GS40` | `L0` | 无环境 variant；必须进入 normalized shader variant key。 |
| 跨语言函数：`texSample2D`、`texSample2DLod`、`mix`、`frac`、`saturate`、`atan2`、`ddx`、`ddy` | `L0` | 手写 MSL 中相似函数不构成兼容；需在 source frontend/translator 逐符号验证。 |
| 构造/转换：`CAST2`、`CAST3`、`CAST4`、`CAST3X3` | `L0` | 无 macro frontend 或类型检查。 |
| legacy stage IO：`attribute`、`varying`、`uniform`、`gl_FragColor` | `L0` | 无 stage-link/type/location/output contract。 |
| image/text vertex 只用 `a_Position`、`a_TexCoord`；完整输入集合还包括 `a_PositionVec4`、`a_Normal`、`a_Tangent4`、`a_TexCoordVec3/Vec4`、`a_TexCoordC1...C5` 的 vec2/vec3/vec4 变体及 `a_Color` | `L0` | 自有 quad/particle layout 不算 authored attribute；需按对象类型注册 vertex source。 |

<a id="op-shader-variables"></a>
### 4.3 Variables

| 官方合同 | 当前级别 | 当前边界 / 实现门 |
|---|---|---|
| `[COMBO]` checkbox/options：`material`、`combo`、`type`、`default`、`options` | `L0` | material combo dictionary 仅有值，没有 annotation schema/preprocessor permutation；先建 annotation AST。 |
| General：`g_Time`、`g_Daytime`、`g_Frametime`、current/last pointer、texel/half-texel、screen、alpha/color/color4、parallax | `L2` | 部分 typed carrier 已有，但没有官方名称、单位、作用域和更新频率 binder；逐项状态见下表。 |
| View：eye/view/orientation 三轴、model/inverse、view-projection、model-view-projection/inverse | `L2` | 部分自有矩阵存在；缺官方坐标系、转置、inverse 和 object/surface scope 合同。 |
| Effect/Layer：effect model/MVP/inverse、effect texture projection/inverse、layer model | `L0` | 无完整 effect-space binder；这也是 cursor effect 投影和局部摆动不能靠整层位移代替的公共依赖。 |
| 每个 `T0...T7`：`g_TextureNResolution.xy` physical / `.zw` mapped、Rotation、Translation | `L2` | runtime 知道部分 physical/mapped 数据，但没有随最终 candidate/slot/generation 更新的统一 binder。 |
| Audio：16/32/64 bin、left/right、低到高、正值且不归一化 | `L0` | 只有声明诊断；无 host snapshot、静音/暂停策略或 shader consumer。 |
| sampler `g_Texture0...7` annotation：`material`、`label`、`hidden`、`default`、`mode`、`combo`、`paintdefaultcolor` | `L0` | 无 sampler annotation AST；slot 中 `null` 必须继续保留，不能压缩。 |
| paint mode：`opacitymask`、`rgbmask`、`flowmask`；flow idle 以 127/255 为中心；optional texture 仅在实际绑定时定义 combo | `L0` | mask 解码、paint metadata、candidate readiness 与 permutation 尚未形成一个原子事务。 |
| user uniform：slider (`default/range`)、color (`type=color`)、UV (`position=true`)；名字应以 `u_` 开头 | `L0` | `constantshadervalues` 只保留 raw value；无 reflected layout、editor schema 或 user/script live binding。 |

<a id="op-shader-headers"></a>
### 4.4 Headers

| 官方模块 | 公开合同 | 当前级别 / 实现门 |
|---|---|---|
| `common.h` | `M_PI`、`M_PI_HALF`、`M_PI_2`、`SQRT_2`、`SQRT_3`；`hsv2rgb`、`rgb2hsv`、`rotateVec2`、`greyscale` | `L0`：无 include graph/module identity；未来实现需锁定常量精度与函数 golden。 |
| `common_fragment.h` | `DecompressNormal`、`DecompressNormalWithMask`、`ConvertSampleR8`、`ConvertTexture0Format` | `L0`：依赖 texture format/通道合同，不能用普通 RGBA sample 近似。 |
| `common_vertex.h` | 两种 `BuildTangentSpace` | `L0`：依赖完整 vertex attribute、model transform 与 handedness。 |
| `common_blending.h` | `BLENDMODE` imageblending combo + `ApplyBlending(BLENDMODE, colorA, colorB, blend)`；首参为兼容性保留 | `L0`：无 stock header 或 blend-mode oracle；Metal fixed-function blend 不能替代 shader 内颜色混合。 |

<a id="op-shader-mobile"></a>
### 4.5 Mobile

| 官方合同 | 当前级别 | 当前边界 / 实现门 |
|---|---|---|
| 目标为 DirectX 11 HLSL 4.0 与 OpenGL ES GLSL 3.00 ES；官方会自动改写 source | `L0` | MyWallpaperX 目标是 Metal，不宣称移动端编译 parity；但 source parser 必须保留这些条件分支。 |
| 类型 alias：`vec2/3/4`、`mat2/3/4x3/4`；函数 alias 另含 `mul`、`mod`、`fmod` | `L0` | 与 Syntax 中 alias 一并进入可版本化 symbol table。 |
| 整数字面量默认尝试改成 float；`WEMOBILE_DISABLE_INTEGER_CONVERSION` 可关闭 | `L0` | 不能靠文本替换；需 token-aware rewrite 和 before/after fixture。 |
| 平台分支用独立 `#ifdef HLSL` / `#ifdef GLSL`；`#elif` 不支持，`#else` 对未来 API 不稳 | `L0` | preprocessor 需与官方限制一致并输出明确诊断。 |
| 移动端编译失败时移除所属 effect，壁纸继续运行 | `L0` | 对应 MyWallpaperX 的产品策略应是 per-effect fail-closed passthrough，而非整幅 wallpaper 黑屏。 |

<a id="op-shader-desaturation"></a>
### 4.6 Desaturation Tutorial

官方教程给出了首个 generic shader executor 的最小合法 fixture：hidden framebuffer `g_Texture0`、`v_TexCoord`、`texSample2D`、`CAST3(dot(...))`、`gl_FragColor`，再加入 `u_DesaturationAmount` slider 与 `mix`。当前为 `L0`：现有色彩近似/手写 pipeline 没有执行这份 authored source。只有这份 fixture 能经 source parse、annotation、material/slot、variant、uniform upload、GPU 编译和像素门端到端通过后，才能把对应 primitive 升级。

## 5. 当前 Shader primitive 覆盖

| 语义项 | 等级 | IR / host carrier | generic runtime | strict executor | 代码/测试证据 | 执行边界 | 下一门 |
|---|---|---|---|---|---|---|---|
| GLSL-like source | `L1` | 能把 `shaders/` 文件归类并保留 material shader path；不读取 source AST | 无 source loader、preprocessor、translator 或 compiler | strict Blur 只匹配 shader path 后调用手写 MSL | [resource index](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneResourceIndex.swift)、[material IR](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAssetCatalog.swift)、[strict path gate](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectExecutionPlan.swift) | shader path 命中不等于执行 GLSL；当前没有一行 WE GLSL 进入 Metal compiler | 建只读 `ShaderSource` loader 与 language/directive tokenizer，先做 canonical source/include hash |
| HLSL / DirectX blob | `L1` | 能发现 `blobssm/*.dxs` 并报告数量 | 无 DXIL/DXBC 反射、HLSL frontend 或 Metal translation | 无 strict HLSL executor | [blob 分类](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneResourceIndex.swift)、[未实现诊断](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDiagnostics.swift) | 不运行或捆绑不可信 `dxc`；blob 存在只算诊断 | 先确定合法 source 优先级和 blob metadata；任何编译器路线另做签名、许可、缓存和 sandbox 设计 |
| preprocessor / 跨语言宏 | `L0` | 无 directive/macro token model | 无 `GLSL`/`HLSL`/`HLSL_SM40`/`HLSL_GS40` 条件或 `texSample2D` 等宏展开 | strict MSL 完全绕过 authored preprocessor | [语义需求](scene-format-and-render-graph.md#8-shader-语义)；代码树无对应 frontend | combo dictionary 不是 macro processor | 做条件栈、object/function macro、source map 和错误定位；以官方最小 shader fixture 锁定行为 |
| `combo` / permutation | `L2` | material 与 instance combo 字典合并，key/value 保留 | 无按 combo 编译/缓存 shader variant 的通用系统 | 两个 Blur planner 精确白名单 combo、默认值和方向，未知组合拒绝 | [material resolver](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredMaterialResolver.swift)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir)、[strict 证据](runtime-evidence-index.md#e-effect-blur) | strict profile 只消费白名单值；没有 authored permutation 或 annotation 联动 | 建 normalized variant key，并由 annotation、实际 slot readiness 与 preprocessor 共同决定 permutation |
| shader annotation | `L0` | 未解析 sampler/uniform 的 default、mode、combo、paint/UI metadata | resolver 不知道 shader default 或 optional-slot annotation | 无 strict annotation consumer | [官方入口索引](source-index.md#14-shader)、[material resolver](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredMaterialResolver.swift) | material 自带的值不能替代 shader annotation；属性面板也不能由 uniform 扫描自动生成 | 建 annotation AST 与 typed schema，分别输出 runtime default、combo dependency 和 editor-only metadata |
| uniform / `constantshadervalues` | `L2` | number/vector/string/binding raw value 与 components 被保存；material/instance override 合并 | 手写 pipelines 有固定 Swift/MSL uniform structs，没有按 name/type 通用上传 | precise/standard Blur 严格读取 `scale` 及默认 composite constants | [value parser](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDocument.swift)、[material resolver](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredMaterialResolver.swift)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | strict Blur constant 是固定字段读取；通用 name/type/upload/binding 不存在 | 建 reflected `UniformLayout`、typed conversion 与 dynamic snapshot binding，未知/重复/type mismatch 失败关闭 |
| include / header | `L0` | 没有 include graph 或 canonical module identity | 无 VFS include resolver、cycle detection、cache invalidation | 手写 MSL 的 `<metal_stdlib>` 与 WE header 无关 | [官方 Headers 入口](official-page-catalog.md#11-shader6)、[resource index](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneResourceIndex.swift) | common/header/blending helpers 均未加载 | 在只读 VFS 上实现 include resolver，记录 dependency hash、cycle、missing/escape-root 诊断 |
| vertex attribute | `L0` | 未解析 authored attribute declaration/semantic/location | 只有 MyWallpaperX 自有 quad/particle vertex layout | strict Blur 使用自有 `vertex_id` quad，不消费 authored attribute | [手写 Blur MSL](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGaussianBlurPipeline.swift)、[主手写 MSL](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalPipeline.swift) | 自有 MSL vertex struct 不算 WE attribute 支持 | 由 shader frontend 产出 attribute contract，再映射 2D quad/model/particle vertex sources |
| varying / fragment output | `L0` | 未解析 authored varying、interpolation 或 output contract | 只有手写 MSL stage IO | strict Blur 使用自有 varyings | [手写 standard Blur MSL](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneStandardBlurPipeline.swift) | 无跨 stage 类型/location 校验，也无 authored fragment output/颜色空间合同 | 增加 stage-link validation、interpolation 与 output format/alpha contract |
| built-in time (`g_Time`/`g_Daytime`/`g_Frametime`) | `L2` | `SceneFrameContext` 有 monotonic scene/frame time 与 wall date | legacy 手写 effect 消费单个 `time`；没有官方 built-in 名称/单位 binder | Blur strict executor 不需要也不绑定这些 built-ins | [frame context](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneFrameContext.swift)、[clock 测试](../../../script/tests/test_scene_frame_context.py)、[legacy time MSL](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalPipeline.swift) | typed clock carrier 不等于 `g_Time` family parity；daytime、pause/seek/reset 语义未映射到 shader | 定义官方名称到 frame snapshot 的单位/更新频率表，并用确定性 clock fixture 验证 |
| built-in pointer (`g_PointerPosition*`) | `L2` | frame context 有 current/previous 与 camera parallax position | legacy cursor ripple 接收当前 effect-local `cursorUV`；无通用 global-to-effect projection binder | Blur strict executor不消费 pointer | [frame context](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneFrameContext.swift)、[context 测试](../../../script/tests/test_scene_frame_context.py)、[legacy pointer MSL](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalPipeline.swift) | previous pointer、screen/canvas/local space 和 hover/outside policy 未按官方变量闭合 | 建 coordinate-space transform 与 current/last snapshot，分别验证 camera、object、effect local 三条路径 |
| built-in audio spectra | `L1` | project `supportsaudioprocessing` 只产生 capability 诊断；frame context 没有频谱 | Scene shader 无 16/32/64-bin left/right provider | 无 strict executor | [project diagnostic](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDiagnostics.swift)、[frame context](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneFrameContext.swift) | 粒子定义中保存 audio 参数也不代表 shader audio 输入可用 | 增加 audio frame snapshot、bin mapping、silence/focus/pause policy，再接 uniform binder |
| built-in matrices | `L2` | renderer 计算并上传自有 MVP/camera matrices | 可供手写 pipeline 使用，但无官方 model/inverse/view/projection/effect/layer 名称表 | Blur strict executor使用 fullscreen quad 自有矩阵，不验证 WE matrix semantics | [matrix helpers](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMatrix.swift)、[renderer](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalRenderer.swift)、[geometry 测试](../../../script/tests/test_scene_capture_geometry.py) | 没有 inverse/orientation/effect texture projection 的通用 binding，坐标系和转置约定未系统锁定 | 建 `BuiltinMatrixSet` 与空间命名，做 identity/translation/rotation/inverse 和 stage parity fixtures |
| built-in resolution / texel size | `L2` | frame context 有 canvas/screen；Metal 路径知道 physical texture/RT size；部分 mask 保存 mapped-to-physical scale | 无逐 slot `g_TextureNResolution.xyzw` binder | strict Blur 用实际 RT width/height 算 step，但不是通用 built-in 暴露 | [frame context](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneFrameContext.swift)、[standard Blur renderer](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneStandardBlurRenderer.swift)、[GPU size/UV 测试](../../../script/tests/test_scene_framebuffer_capture.py) | mapped `.zw`、sprite rotation/translation、压缩/POT padding 和每 slot 更新尚未统一 | 让 texture binding 产出 physical/mapped/transform metadata，并与 slot replacement、resize 同步更新 |
| render state (blend/depth/write/cull) | `L2` | 四项按 material pass 保存并进入 resolved node | Metal pipeline state 可表达这些状态，但没有通用 authored state translator/cache | 两个 Blur strict executor只接受 `normal/disabled/disabled/nocull`；其他值拒绝 | [material IR](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAssetCatalog.swift)、[E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir)、[strict 证据](runtime-evidence-index.md#e-effect-blur) | 固定 profile 默认状态不代表 authored state translator 或枚举兼容 | 建显式 enum 与 Metal descriptor 映射，先覆盖 alpha convention，再逐枚举做 source/destination 像素门 |
| MyWallpaperX 手写 MSL profile（非 WE 语言语义） | `L3` | 由 effect/runtime plan 转成固定 Swift uniform struct | Metal compiler 可编译 repo 内 MSL | Blur Precise/stock Blur 有 strict path；其他 legacy effect 多为 bounded approximation | [Gaussian pipeline](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGaussianBlurPipeline.swift)、[standard pipeline](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneStandardBlurPipeline.swift)、[E-EFFECT-BLUR](runtime-evidence-index.md#e-effect-blur) | 只说明当前自有 backend 可交付；不能给任何 WE source/macro/annotation primitive 升级 | 保留 strict backend 作为 generic executor 的 oracle/fallback，并为每个 profile 记录输入合同和 parity 预算 |

## 6. 当前开发门序

1. **Shader contract IR**：只读加载 shader source，建立 language/directive、macro、combo、annotation、uniform、include、stage IO 的 loss-preserving AST 与 canonical hash。此阶段不运行外部编译器，也不声称 GPU 支持。
2. **Graph resource executor**：统一 effect-instance target table，执行 target/bind/copy/swap、extent/format/clear/UV，加入 read/write hazard、budget、resize/reset/device-loss 测试；compose、condition、function 继续失败关闭，直到各自合同有 fixture。
3. **Built-in 与 render-state binder**：从同一 frame snapshot 提供 time/pointer/audio/matrix/resolution，按最终 texture candidate 更新 slot metadata，并将已验证 state 映射到 Metal pipeline descriptor。
4. **Generic shader execution**：以严格 Blur backend 为对照，接入可审计、可缓存、可诊断的 shader translation/compilation 路线；只有不依赖固定 effect/shader path 且通过正负、生命周期和像素矩阵后，相关行才可升 `L4`。
5. **按效果扩面**：优先选择能复用已闭合 graph/shader primitive 的 effect；Motion Blur 用于 copy/history，Refraction 用于 compose，Fluid 用于 swap/condition/function/format 压力测试。不得用显示名或视觉近似绕开 authored contract。

## 7. 本轮验证

本轮只读取仓库文件，未联网，也未访问真实 Workshop。以下隔离测试于 2026-07-23 运行，共 `37/37` 通过：

```text
python3 script/tests/test_scene_effect_definition.py          # 4
python3 script/tests/test_scene_effect_render_graph.py        # 6
python3 script/tests/test_scene_authored_effect_execution.py  # 5
python3 script/tests/test_scene_framebuffer_capture.py        # 13
python3 script/tests/test_scene_frame_context.py              # 4
python3 script/tests/test_scene_named_render_target_pool.py    # 5
```

其中 `test_scene_framebuffer_capture.py` 提供当前 strict Blur 的真实 Metal encode、RT 尺寸、alpha 与像素证据；其余测试证明 parser/IR/planner/失败关闭和基础设施合同。既有真实样本运行记录只从 [资料来源与证据索引](source-index.md#2-真实样本证据) 引用，本轮没有重跑，因此不得用本页把其他 graph-built effect 升级为 executed。
