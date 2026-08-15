# Shader source/prelude 固定客户端与语料研究

> 本文只记录 source/prelude/backend 语义合同与固定客户端观察，不决定现役开发顺序。shader compiler 的语言职责、生产后端与迁移准入由[技术栈与架构路线边界](../../architecture/technology-stack-boundaries.md#6-shader-compiler-路线)与[兼容运行时架构](../runtime-architecture.md#41-作者-shader-的推荐后端)统一决定。
>
> - `official-public-contract`：官方 Shader Syntax/Variables/Headers 页只定义作者可见的 GLSL-like source、自定义 preprocessor、combo、uniform、sampler 和 built-in 表面；它们没有公开内部 translator 或 Metal 后端。
> - `official-client-static-observation`：本文的 Wallpaper Engine 2.8.42/build `23967692` 快照只观察到随包 source/prelude，以及 normal DirectX material-pass 链的“自定义 preparation → WE HLSL translator → 动态 `D3DCompile`”；不外推到其他版本或 Metal。
> - `MyWallpaperX-strategy`：项目现役首选是“小型 dialect normalization/generated prelude → glslang → SPIR-V → SPIRV-Cross MSL/reflection → Metal”。这是项目自有策略，不是官方客户端路径；外部 frontend 可编译也不自动证明 GPU 执行或视觉等价。
>
> **文档角色：`research-context-only`。** 本页混合公开 source 表面、作者语料观察和固定客户端静态观察，不是产品实现输入。implementation agent 不得从本文复制 shader、公式、常量、rewrite 或客户端 translator 细节；当前切片必须先由独立研究任务产出经审查的中性 source/behavior 合同，再由 fresh context 通过项目 fixture 和官方黑盒协议实现。产品 frontend、backend、失败边界和验收门只以本文链接的现役合同为准。

审查日期：2026-07-25
架构角色与后端策略复核：2026-08-15
取证快照：Wallpaper Engine 2.8.42 `assets/shaders`
审查方式：只读静态检查，共 14 个头文件 + 108 个顶层 shader + 7 个 HLSL 专用 shader

> [Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md) 记录了 EffectDefinition、Material、FBO 与 Shader 的 IR 与 executor 实现进度。本文补充一个前置观察：扫描到的官方 shader 源码使用一组在同一 source corpus 中没有定义的 token；它们可能由编译前端、未随包的 include 或其他宿主阶段提供。
>
> 这只建立一个中性输入问题：自研 frontend 对这些 token 是接受、保留还是拒绝；它不证明 token 的官方展开文本、注入模块或 Metal 映射，也不直接规定产品行为。

## 1. 结论先行

1. 扫描得到 **25 个候选 frontend token**，在 `assets/` source corpus 中被使用但没有找到本地定义。缺席是 A 级事实；由哪个 executable/module 注入是 C 级假设。
2. `mul`、`saturate`、`frac`、`clip`、`ddx`/`ddy` 等命名明显受 HLSL 影响，但矩阵上传、转置与各目标语言展开仍需独立 fixture 和 Windows golden。
3. 源码存在 `HLSL`、`GLSL`、`HLSL_SM30`、`PLATFORM_ANDROID` 条件分支；本观察只形成“哪些 authored branches 会改变固定输入结果”的黑盒区分问题。项目 backend identity、normalization 和通用编译链只由[兼容运行时架构](../runtime-architecture.md)规定，本页不授权复制官方分支或 translator 细节，也不能把 `HLSL` 路径等同于 Metal。
4. 存在 **13 个纹理格式枚举**，通过 `TEX0FORMAT`/`TEX1FORMAT` 等 combo 注入，直接决定法线解压和通道 swizzle。
5. 同一安装包内**两个灰度函数使用相反的 R/B 权重**。统一实现会产生偏色。

## 2. 候选 frontend token 表（25 个符号）

以下符号在已扫描的 `assets/` source corpus 中无本地 `#define`，等级 A（可重复验证的缺席事实）。其来源和展开语义除非另行标注，均为 C 级。

**计数口径**：下列出现次数统计范围为 `assets/shaders` 的 `.h`/`.frag`/`.vert`，**排除 `HLSL/` 子目录**（该目录是 §10 说明的 D3D11 专用回退路径）。`assets/effects` 下的 stock effect shader 另有独立用量（如 `texSample2D` 828 次、`mul` 175 次），不计入本表。换口径会得到不同数字，引用时须同时引用口径。

### 2.1 纹理采样族（7）

| 符号 | 用法 | 出现次数 |
|---|---|---:|
| `DECLARE_SAMPLER2D_PARAMETER(name)` | **函数形参位置**声明一个 sampler2D 参数 | — |
| `MAKE_SAMPLER2D_ARGUMENT(name)` | 调用点传递 sampler 实参 | — |
| `texSample2D(s, uv)` | 基础采样 | **200** |
| `texSample2DLod(s, uv, lod)` | 指定 mip 级采样 | 30 |
| `texSample2DCompare(s, uv, ref)` | 阴影比较采样 | 27 |
| `texSample3D(s, uvw)` | 3D 纹理采样 | 2 |
| `texSample2DBackBuffer(s, uv)` | 采样 back buffer | 1 |

`DECLARE_SAMPLER2D_PARAMETER` / `MAKE_SAMPLER2D_ARGUMENT` 成对出现在形参与调用点，支持“跨语言 sampler 参数适配”的 C 级解释。Metal 端可用自有 typed IR 表达 texture 与 sampler，但静态 token 不能证明官方宏在任一后端的确切展开，也不能直接规定 MSL 必须展开成几个形参。

### 2.2 类型转换族（6）

| 符号 | 语义 | 出现次数 |
|---|---|---:|
| `CAST3(x)` | 标量广播/转换到 `vec3` | 102 |
| `CAST3X3(m)` | `mat4` → `mat3` 截取 | **62** |
| `CASTU(x)` | 转换到 `uint` | 69 |
| `CAST2(x)` | 转换到 `vec2` | 37 |
| `CAST4(x)` | 转换到 `vec4` | 15 |
| `CASTF(x)` | 转换到 `float` | 12 |

存在原因是 GLSL 与 HLSL 的构造/转换语法不兼容（如 GLSL `vec3(x)` 广播 vs HLSL `float3(x,x,x)`、`mat3(m)` vs `(float3x3)m`）。

### 2.3 HLSL 风格内建（6）

| 符号 | 常见跨语言候选映射 | 出现次数 | 证据边界 |
|---|---|---:|---|
| `mul(a, b)` | 乘法/矩阵乘 token | **157** | operand shape、顺序与转置待验证 |
| `saturate(x)` | clamp 到 0...1 | 72 | 边界/NaN 行为待验证 |
| `frac(x)` | fractional part | 13 | 负数行为待验证 |
| `clip(x)` | 条件丢弃 | 7 | 向量输入与阈值待验证 |
| `ddx(x)` | x derivative | 1 | stage/quad 语义待验证 |
| `ddy(x)` | y derivative | 1 | stage/坐标方向待验证 |

**`mul` 是本族中最高频的候选 token（157 次；全表最高频是 `texSample2D` 的 200 次）**，也是移植风险最高的一个。HLSL 标准语义能提供候选解释，但官方 frontend 可能同时改写矩阵声明、上传布局或表达式；不能只凭 token 名把所有 `mul(v, M)` 固定翻译为某个转置表达式。需要按 operand shape 建 identity/translation/rotation/normal fixtures，并与 Windows 输出交叉验证。

### 2.4 语言与平台开关（6）

| 符号 | 含义 | 出现次数 |
|---|---|---:|
| `HLSL` | 目标语言为 HLSL | 27 |
| `GLSL` | 目标语言为 GLSL | 11 |
| `HLSL_SM30` | HLSL Shader Model 3.0 路径 | 7 |
| `PLATFORM_ANDROID` | Android 平台 | 6 |
| `VERSION` | 版本号 | 3 |
| `SHADERVERSION` | shader 版本号 | 2 |

源码把 `HLSL` 与 `GLSL` 当作独立条件，并在部分位置使用 `HLSL_SM30` 特化；本地静态文件没有证明所有编译任务中两者必有且仅有一个为真。MSL 变体的 backend identity 与分支准入属于[现役架构策略](../runtime-architecture.md)；本观察仅证明复用 `HLSL` 标志不能被当作 Metal 官方路径证据。

### 2.5 不属于 prelude 的符号

以下符号在 shader 内部有 `#define`，**不需要**注入：

| 符号 | 定义位置 |
|---|---|
| `M_MDL`、`M_NML`、`M_VP`、`M_MVP` | `genericimage{2,3,4}.vert`，按 combo 在 Alt 矩阵组与标准矩阵组间切换 |
| `M_PI`、`M_PI_HALF`、`M_PI_2`、`SQRT_2`、`SQRT_3` | `common.h` |
| `FORMAT_*`（13 个） | `common_fragment.h` |

矩阵别名的两组取值：

| 别名 | Alt 分支 | 标准分支 |
|---|---|---|
| `M_MDL` | `g_AltModelMatrix` | `g_ModelMatrix` |
| `M_NML` | `g_AltNormalModelMatrix` | `g_NormalModelMatrix` |
| `M_VP` | `g_AltViewProjectionMatrix` | `g_ViewProjectionMatrix` |
| `M_MVP` | `mul(g_AltModelMatrix, g_AltViewProjectionMatrix)` | `g_ModelViewProjectionMatrix` |

Alt 分支的 `M_MVP` 在源码中写成矩阵乘 token，而标准分支读取预乘 uniform；两路是否产生可见精度差异需要运行门，不能从静态表达式直接下结论。

## 3. 头文件依赖图

```
common.h ──┬── common_composite.h ── (+ common_blending.h)
           ├── common_pbr.h
           └── common_pbr_2.h

common_fragment.h ── base/model_fragment_v1.h
common_vertex.h   ── base/model_vertex_v1.h

（无依赖）common_blending.h  common_blur.h  common_fog.h
          common_foliage.h  common_particles.h  common_perspective.h
```

顶层 shader 的 include 频次（口径同 §2：`assets/shaders` 顶层 `.frag`/`.vert`，排除 `HLSL/`；合计 62 次）：

| 头文件 | 被 include 次数 |
|---|---:|
| `common_vertex.h` | 13 |
| `common_fragment.h` | 11 |
| `common_pbr_2.h` | 8 |
| `common_fog.h` | 8 |
| `base/model_vertex_v1.h` | 5 |
| `common_blending.h` | 4 |
| `common_pbr.h` | 3 |
| `base/model_fragment_v1.h` | 3 |
| `common_particles.h` | 2 |
| `common_foliage.h` | 2 |
| `common_blur.h` | 2 |
| `common.h` | 1 |

`common_pbr.h`（97 行）与 `common_pbr_2.h`（385 行）并存且都在用，说明存在 **PBR v1 / v2 两代实现**，不是废弃替换关系。

## 4. 纹理格式与后端分支

### 4.1 格式枚举（`common_fragment.h`）

| 常量 | 值 | | 常量 | 值 |
|---|---:|---|---|---:|
| `FORMAT_RGBA8888` | 0 | | `FORMAT_DXT3` | 6 |
| `FORMAT_RGB888` | 1 | | `FORMAT_DXT1` | 7 |
| `FORMAT_RGB565` | 2 | | `FORMAT_RG88` | 8 |
| `FORMAT_ETC1_RGB8` | 3 | | `FORMAT_R8` | 9 |
| `FORMAT_DXT5` | 4 | | `FORMAT_RG1616F` | 10 |
| `FORMAT_ETC2_RGBA8` | 5 | | `FORMAT_R16F` | 11 |
| | | | `FORMAT_BC7` | 12 |

源码通过 `TEX0FORMAT`、`TEX1FORMAT`、`TEX4FORMAT`、`TEX8FORMAT`、`THICKFORMAT` 等 combo 选择分支。sidecar/binary format 与这些枚举存在可对照关系，但 combo 的最终来源、覆盖优先级和缺省值尚未由运行时确认；可交接的问题是 authored、sidecar 与 decoded format 三者如何影响固定客户端的 variant 结果，自研 loader 形态只由现役合同决定。

### 4.2 法线解压按格式分派

`DecompressNormal` 的三条分支：

| 条件 | 解压方式 |
|---|---|
| `FORMAT_ETC1_RGB8 ≤ TEX1FORMAT ≤ FORMAT_DXT1` 或 `== FORMAT_BC7` | `normal.yx = normal.yw * 2.0 - vec2(0.965, 1.0)` |
| `TEX1FORMAT == FORMAT_RG88` | `normal.xy = normal.rg * 2.0 - 1.0` |
| 其他 | `normal.xy = normal.wy * 2.0 - 1.0` |

三条分支后统一 `normal.z = sqrt(saturate(1 - x² - y²))`。

两个需要进入独立行为测试的 source 观察：

1. **`0.965` 而非 `1.0`**。压缩格式分支的 x 分量偏移是 `0.965`，是对块压缩偏移的补偿。用 `1.0` 会产生系统性法线偏斜。
2. **通道来源不同**。压缩分支从 `.yw` 取、RG88 从 `.rg` 取、默认从 `.wy` 取，且赋值目标 swizzle 也不同（`.yx` vs `.xy`）。

`DecompressNormalWithMask` 在压缩分支和默认分支额外做 `normal.xw = normal.wx` 交换后再解压，并保留 `.w` 作为 mask。

### 4.3 `HLSL_SM30` 通道差异

单/双通道格式在 SM3.0 与其他后端下的采样通道不同：

| 函数 | 格式条件 | `HLSL_SM30` | 其他 |
|---|---|---|---|
| `ConvertSampleR8` | — | `.a` | `.r` |
| `ConvertTexture0Format` | `RG88` / `RG1616F` | `.rrra` | `.rrrg` |
| `ConvertTexture0Format` | `R8` / `R16F` | `vec4(1,1,1, .a)` | `vec4(1,1,1, .r)` |

原因是 SM3.0 下 R8 被映射为 A8。Metal 后端应走**非 SM30 分支**（`.r`），但这需要保证纹理加载器把 R8 真的上传为 `r8Unorm` 而非 `a8Unorm`。

`ConvertTextureFormat(format, sample)` 是同逻辑的**运行时分支版本**（`if` 而非 `#if`），用于格式在编译期未知的场合。

### 4.4 存储格式与纹理用途必须分离

2.8.42 随包语料中 272 个无歧义 `.tex-json`/`.tex` 配对证明：

- 普通 `dxt5` 与 packed-normal `dxt5n` 都会写成 TEX numeric format 4；
- `rgba8888`、`rgba8888n` 与 `rgb888` 都可能写成 format 0；
- `rg88`/`rg88n` 共享 format 8。

因此 numeric format 只决定存储布局和可用解码器，不能单独决定 color、mask、flow/data 或 normal 语义。用途必须作为独立 typed identity 贯穿 parser、resolver、cache key、upload 与 sampler：

- color 可按最终 composite 合同执行颜色空间处理和 premultiply；
- data/normal 不得进入颜色 premultiply 或未声明的色彩转换；
- 相同存储格式、不同用途的缓存结果不能复用；
- packed normal 的最终恢复只由项目自有 fixture 与 Windows golden 定标，不从客户端反编译表达直接实现。

`8b06538d` 已落地第一层公共合同：loader cache 与 compressed uploader 共用 typed `.premultipliedColor` / `.preservedChannels` identity。小型单 image BC1/2/3 的 preserved-channel 路径仍执行有界 CPU decode，但不 premultiply 且保留物理 mip extent；大型或多 image 则保留 native BC。自建 BC3 fixture 锁定 `G/A=255/64` 在 color 路径变为 `64/64`、在 data 路径保持 `255/64`，并锁定两种调用顺序、跨用途 cache 隔离与 padding/mapped extent。该实现只证明项目内部用途不会在上传阶段丢失；它没有证明 DXT5n 恢复公式、颜色空间或 Windows 像素等价。

`d432d4d5` 将上述两类扩展为八类穷举 identity，`b623f421` 再加入 Depth Parallax 专用 depth：premultiplied color、straight albedo、generic preserved、mask、noise、flow、phase、normal、depth。33 个 Effect helper 调用按实际 slot 角色拆分；八类非预乘 identity 当前仍共享严格 source-channel policy，但 cache 不再混用。strict Particle REFRACT 的自建 GPU 门让同一 format-4 packed-normal 内容分别走 single-image CPU BC3 decode 与 multi-image native BC3 直传，并与 decoded-byte-equivalent format-0 RGBA 经真实 loader/shader 比较；两条 BC 路径分别与 RGBA 在 2 个字节内一致，G/A swapped 与 neutral normal 均为有效负对照。该门闭合的是项目内部 storage equivalence，不定义官方 DXT5n 恢复公式；Depth Parallax 另只接受 R8 depth，format 5 / BC5、generic Effect/material normal 与 Windows golden 继续在已证合同外。

## 5. 灰度权重冲突

两个函数计算灰度，权重向量的 R/B 分量相反：

| 函数 | 文件 | 权重 | 展开 |
|---|---|---|---|
| `greyscale(color)` | `common.h` | `vec3(0.11, 0.59, 0.3)` | `0.11·R + 0.59·G + 0.30·B` |
| `Desaturate(color, amount)` | `common_blending.h` | `vec3(0.3, 0.59, 0.11)` | `0.30·R + 0.59·G + 0.11·B` |

`Desaturate` 的权重接近标准 Rec.601（`0.299, 0.587, 0.114`）；`greyscale` 的 R 与 B 权重互换，**不符合任何标准亮度公式**。

无论这是否为历史兼容或笔误，静态 source 都显示两个不同 helper identity；是否可合并只能由纯色输入的官方黑盒结果区分。在取得像素证据前，本页把其行为保持为待确认，不授权 parser 合并或移植官方表达式。

同类情况还有 HSV：`common.h` 的 `rgb2hsv`/`hsv2rgb` 是 GLSL 无分支实现（用 `1e-10` 防除零），与 `common_blending.h` 的 `RGBToHSL`/`HSLToRGB` 是**不同色彩空间的不同实现**（HSV vs HSL），不可互换。JS 侧 `WEColor` 模块又是第三套研究观察，见 [SceneScript 2.8.42 静态取证](scenescript-runtime-implementation-contract.md) §7.4。

## 6. PBR 与平台分支边界

随包 PBR helper 包含非平凡的 roughness/metallic 换算、经验常量和非物理衰减曲线。这能确认“通用 Metal PBR”不能自动代表官方 stock shader parity，但本文不保存或要求移植官方算法表达式。实现应从自有 BRDF/lighting IR 出发，以参数 sweep 和 Windows 像素 golden 决定兼容范围。

`base/model_fragment_v1.h` 的 `ApplyReflection` 中平台相关常量：

| 平台 | 屏幕空间反射偏移系数 |
|---|---|
| `PLATFORM_ANDROID` | `vec2(0.20 / g_Screen.z, 0.20)` |
| 其他 | `vec2(0.15, 0.15 * g_Screen.z)` |

同一区域存在 Android 与 HLSL 条件分支，并在 HLSL 分支修改法线 Y。静态源码只能确认分支动作，不能确认其唯一原因，也不能推出 Metal 必须走同一分支：纹理原点、viewport、投影矩阵、render-target 翻转与采样 helper 都可能共同影响方向。MSL 路线必须用非对称法线/反射 fixture 和 Windows golden 判定，不能以 D3D/Metal NDC 的笼统类比代替。

## 7. 全局 uniform 命名空间

跨平台语料（`assets/shaders`，排除 `HLSL/` 子目录）共出现 **146 个 `g_` 符号**，全部有本地声明，无一个属于 §2 的注入类：

| 声明形式 | 数量 |
|---|---:|
| `uniform` 声明 | **141** |
| `#define` 纹理槽别名 | 3 |
| `varying`（逐片元插值量） | 2 |

141 个 uniform 按用途分组（分组可复现，合计等于 141）：

| 组 | 数量 | 代表 |
|---|---:|---|
| 其他 | 49 | `g_Color`…`g_Color4`、`g_Alpha`、`g_UserAlpha`、`g_Brightness`、`g_BlendMap`、`g_Brush*` 等 |
| 纹理与采样 | 23 | `g_Texture0`…`g_Texture8`、`g_Texture0Resolution`、`g_Texture0Texel`、`g_Texture0Rotation`、`g_Texture0Translation` |
| 光照 | 16 | `g_LPoint_*`、`g_LSpot_*`、`g_LTube_*`、`g_LDirectional_*`、`g_LightsColorRadius`、`g_LightSkylightColor` |
| 矩阵与变换 | 12 | `g_ModelViewProjectionMatrix`、`g_NormalModelMatrix`、`g_AltModelMatrix`、`g_EffectModelMatrix`、`g_ViewportViewProjectionMatrices` |
| 植被/毛发 | 9 | `g_FoliageScale`、`g_FoliageUVBounds`、`g_SpeedBase`、`g_FurDetail`、`g_FurDistance`、`g_FurOcclusion` |
| Bloom/HDR | 7 | `g_BloomStrength`、`g_BloomThreshold`、`g_BloomScatter`、`g_BloomTint`、`g_BloomBlendParams`、`g_HDRParams` |
| PBR 材质 | 6 | `g_Roughness`、`g_Metallic`、`g_Reflectivity`、`g_ReflectivityDistance`、`g_SpecularTint`、`g_EmissiveColor` |
| 骨骼/变形 | 6 | `g_Bones`、`g_BonesAlpha`、`g_MorphWeights`、`g_MorphOffsets`、`g_MorphBoneRules`、`g_MorphBoneTransform` |
| 通用渲染变量 | 5 | `g_RenderVar0`…`g_RenderVar4` |
| 雾 | 4 | `g_FogDistanceColor`、`g_FogDistanceParams`、`g_FogHeightColor`、`g_FogHeightParams` |
| 时间与屏幕 | 4 | `g_Time`、`g_Screen`、`g_TexelSize`、`g_TexelSizeHalf` |

`g_RenderVar0`…`g_RenderVar4` 是通用槽位，其含义随 effect 而变，不能按固定语义实现。

### 7.1 varying 不是 uniform

`g_ScreenPosition` 与 `g_TexCoord` 以 `varying` 声明，是**逐片元插值量**，不能按 uniform 绑定。带 `g_` 前缀容易被 binder 误收进 uniform 表，需要在 parser 阶段按声明形式区分而非按命名前缀。

### 7.2 纹理槽别名随文件而变

3 个 sampler 别名由 `#define` 指向具体槽位，**同一别名在不同文件指向不同槽**：

| 别名 | 目标 |
|---|---|
| `g_NormalMapSampler` | `g_Texture1` |
| `g_ReflectionSampler` | `g_Texture3` |
| `g_LightmapMapSampler` | `g_Texture2`（一处）／`g_Texture1`（另一处） |

因此别名到槽位的映射**必须按编译单元解析**，不能建全局别名表。这也再次印证 §4 与手册 §4.2 的结论：不存在「slot N 永远是某语义」的通用规则。

### 7.3 HLSL/ 子目录另有 15 个

`shaders/HLSL/` 的 7 个 dx11 shader 另含 15 个只在该目录出现的 `g_` 符号，以 HLSL `cbuffer` 成员或 `SamplerState` register 形式声明：`g_bufDynamic`、`g_AspectRatio`、`g_Hash`、`g_Hash2`、`g_Progress`、`g_Random`、`g_Width`、`g_Height`、`g_ViewProjection`、`g_ViewProjectionInv`、`g_Texture0SamplerState`、`g_Texture0SamplerStateWrap`、`g_Texture0MipMapped`、`g_Texture1Noise`、`g_Texture2Clouds`。

它们属于 §10 说明的 D3D11 专用回退路径，与上表合并统计会得到 161 这个没有跨平台统计意义的数字。本观察不把这组符号提升为作者公开 schema；项目支持边界只查现役 shader 合同。

官方公开的 built-in 变量应以在线 Variables 页面为准（见 [资料来源与证据索引](source-index.md) §1.4）；本清单包含未公开的内部 uniform，可用于判断某个 workshop shader 引用的是否为合法 built-in。

### 7.4 运行时 slot metadata binder 的静态确认

Ghidra 选择性静态路径确认，2.8.42 运行时为每个内部纹理槽建立同构的 resolution、mapped size、texel/mipmap、rotation 与 translation 元数据族；内部 registry 覆盖 0...9。

官方公开 authored shader 合同仍只有 sampler 0...7，因此：

- 项目现役 shader 合同把公开 schema、兼容声明和作者输入限制在 0...7；该策略不是由本页静态观察授权；
- 内部 8/9 只能作为保留槽或显式 unsupported，不能据此扩宽公开兼容范围；
- 最终 texture candidate/generation 与同槽 metadata 是否原子变化属于黑盒区分问题；per-slot binder 和 strict effect 的产品所有权只查现役 shader/资源合同。

## 8. shader 注解合同

**计数口径**：全 `assets/` 的 `.frag`/`.vert`/`.h`，含 `effects/`、`shaders/`、`zcompat/` 与 `HLSL/`（与 §2/§3/§7 的口径不同，此处不排除任何子目录）。

### 8.1 注解标记共 5 种拼写

| 标记 | 次数 | 作用 |
|---|---:|---|
| `[COMBO]` | 310 | 编译期 shader variant 开关 |
| `[PASS]` | 3 | 声明附加 pass 与其 shader |
| `[COMBO_DISABLED]` | 1 | 被关掉的 combo（`shaders/generic3.frag:7`） |
| `[OFF_COMBO]` | 1 | 同上（`effects/waterflow`） |
| `[COMBO_OFF]` | 1 | 同上（`effects/waterripple`） |

后三个是**同一意图的三种不同拼写**（其中两种只是词序相反），各出现 1 次，且**全部在 stock 官方资产中**，不是作者内容。`[OFF_COMBO]`/`[COMBO_OFF]` 仍带完整 `combo`/`type`/`default` 载荷，`[COMBO_DISABLED]` 无 `type`。

只匹配 `[COMBO]` 的 parser 会把这些拼写当普通注释丢弃；按「包含 COMBO」宽松匹配又会把它们当作启用的 combo。官方未公开这三种拼写的合同，因此静态存在性不能决定项目 parser 或诊断策略；可交接的问题是固定客户端是否消费它们，以及消费时的作者可观察结果，见[资料来源与证据索引](source-index.md) §6。

`projects/defaultprojects` 的 21 个 `[COMBO]` 中没有任何变体拼写。

### 8.2 `[COMBO]` 载荷只有 `combo` 必填

310 条 `[COMBO]` 注解的载荷键：

| 键 | 出现数 | 说明 |
|---|---:|---|
| `combo` | **310** | variant 宏名，唯一恒存在的键 |
| `material` | 297 | 编辑器标签，多为 `ui_editor_properties_*` 本地化 key |
| `default` | 295 | 默认值 |
| `type` | 247 | 属性 UI 控件类型 |
| `options` | 78 | 枚举值字典 |
| `require` | 25 | 对其他 combo 取值的依赖条件 |

`type` 缺 63 条、`default` 缺 15 条、`material` 缺 13 条——三者都不是source格式层的全局必填字段。只有 `combo` + `default` 的形态是「有 variant，不暴露给作者 UI」。这不表示player可在material和active声明都缺值时猜`0`：项目允许material显式值满足无default声明；若本次编译确实需要fallback而任一同名active声明缺default，则失败关闭。

`options` 字典的键既可以是本地化 key（`ui_editor_properties_gradient` 9 次为最高频），也可以是英文字面量（`{"Center":0,"Post":1,"Pre":2}`）。不能假设一律需要查本地化表。

### 8.3 `require` 表达作者/editor中的 combo 关系

25 条 `[COMBO]` 带 `require`，形态为 `{"<其他 COMBO 名>": <取值>}`：

| `require` | 次数 |
|---|---:|
| `{"LIGHTING":1}` | 12 |
| `{"DIRECTDRAW":0}` | 8 |
| `{"WRITEALPHA":0}` | 2 |
| `{"TRANSFORMUV":1}` | 2 |
| `{"RAYMODE":2}` | 1 |

这些字段描述authoring侧的属性关系，例如`RIMLIGHTING`只在`LIGHTING == 1`时对作者有意义；但不能由字段名直接推出player会删除声明或跳过variant。对2.8.42 64位normal material-pass链的clean-room静态复核确认，player汇集active `[COMBO]`声明后，material显式值优先，缺值则把annotation `default`写入compile map，再统一发出`#define`。同一路径没有读取JSON `require/requireany`来剪枝声明或default。因此项目保真保存该metadata作为authoring/editor关系，却不声称已恢复editor消费链，也不让它改变player compile-map definedness；资源sampler/format的require是另一条项目typed合同，仍按bounded fixed point求值。

### 8.4 `[COMBO]` 与 uniform 标注是两类注解

两者的 `type` 值域**不重叠**：

| `type` | `[COMBO]` 注解 | uniform 标注 |
|---|---:|---:|
| `options` | 193 | 2 |
| `imageblending` | 52 | 0 |
| `audioprocessingoptions` | 2 | 0 |
| `color` | **0** | **102** |

`color` 从不出现在 `[COMBO]` 行上，它只是 uniform 标注的控件类型：

```
uniform vec3 g_TintColor; // {"material":"Color", "type": "color", "default":"1 1 1"}
```

uniform 标注侧那 2 条 `options` 正是 §8.1 的 `[OFF_COMBO]`/`[COMBO_OFF]`，并非真正的 uniform 标注。

把两者合并成一张表会直接产生实现错误：**combo 生成 shader variant 与 `#define`，uniform 标注生成作者属性 UI 与 uniform 绑定**，是两条不同通道。按 `type == "color"` 去建 variant，或按 `type == "imageblending"` 去建颜色选择器，都会走错。

`audioprocessingoptions` 只出现在 `effects/shake/shaders/effects/shake.vert:2` 与 `effects/pulse/shaders/effects/pulse.vert:2`，combo 名恒为 `AUDIOPROCESSING`，默认 0。

### 8.5 `[PASS]` 声明附加 pass

3 条，全在 `assets/shaders`：

```
shaders/fur4.frag:2      // [PASS] shadow shadowcasterfur4
shaders/foliage4.frag:2  // [PASS] shadow shadowcasterfoliage4
shaders/chroma4.frag:2   // [PASS] shadow shadowcaster
```

形态是 `[PASS] <pass 名> <shader 名>`，三条全部为 `shadow` + 一个 `shadowcaster*` shader。这说明**shader 源码本身可以声明它需要的附加 pass**，pass 集合不完全由 effect/material JSON 决定。

这提示一个中性研究问题：固定客户端的依赖收集与 pass 枚举是否同时消费 JSON 和 shader 头部注解。三个宿主 shader 都是 3D 模型类（fur/foliage/chroma），与阴影投射用途一致；只有 3 个样本，`[PASS]` 的完整参数形态与官方调度时机无证据（等级 C），因此本页不规定项目 RenderGraph 行为。

### 8.6 固定 2.8.42 DirectX frontend 会消费这些注解

固定 Wallpaper Engine 2.8.42/build `23967692` 的 Ghidra 静态执行路径确认，normal DirectX material-pass frontend 会识别多位数字的 `g_TextureN`、`uniform` inline metadata，以及 `[COMBO]`、`[PASS]`。inline metadata 至少包含 `material`、`default`、`components` 和 `formatcombo` 族。对该链的后续单点复核又闭合了当时 default/override 优先级：compile map 已有 material 显式值时保留，缺少时读取 active 声明的 `default`；两者随后进入同一 define emitter、WE HLSL translator 和动态加载的 `D3DCompile`。项目 variant identity 与 provenance 策略只查现役 shader 合同；本静态顺序仅提供“相同最终宏值是否产生相同可观察结果”的黑盒问题。

这把上述注解从“随包 source 中存在”推进为“固定客户端的运行时 frontend 会读取”；它仍不能推出其他客户端版本/backend、editor UI 状态、完整预处理错误恢复、未公开 slot 的作者可用性或官方私有 translator 算法。缺失、冲突或畸形 default 的产品失败边界只由现役合同规定，不由该静态路径授权。

## 9. 已撤权的历史规格映射

旧版本文曾把下表直接写成产品规格与验收门；该规范权现已撤销。表中只保留 source/静态观察与可由独立研究区分的问题，不能直接进入 implementation backlog。项目 frontend/backend、失败边界与验收门只查[兼容运行时架构](../runtime-architecture.md)、[Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md)和[唯一现役路线](../scene-compatibility-roadmap.md)。

| 项 | source/静态候选观察 | 中性行为问题 |
|---|---|---|
| frontend token | §2 扫描到 25 个候选 token，但没有闭合 provider 与展开语义 | 哪些 token 在哪些 operand/stage 中被固定客户端接受；未知形态的作者可观察失败结果是什么 |
| `mul` 约定 | source 中存在多种 operand shape，静态 source 不证明矩阵上传/转置 | identity/translation/rotation/normal 输入在官方黑盒中的输出如何区分 |
| 后端分支 | authored source 分别出现 `HLSL`、`GLSL` 与 platform 条件 | 哪些分支改变固定输入结果；其他 backend 是否具有相同表面。本观察不回答项目编译链 |
| 坐标与法线 Y | source 显示多个坐标/法线变换候选 | 非对称法线/反射输入是否产生上下镜像，以及镜像发生在哪个可观察阶段 |
| 纹理格式 combo | §4.1 观察到 13 个枚举值 | 实际加载格式如何影响 combo 与输出；R8 的上传/采样结果是什么 |
| 法线解压 | §4.2 记录三条 source 分支和一个 source 常量 | 同一法线内容以不同编码输入时，官方结果是否一致；本页不把 source 表达转为项目算法 |
| 灰度 | §5 观察到两套不同 source 权重 | 纯色/非对称颜色输入在两个 helper 下的官方输出是否不同 |
| PBR | source 中存在多个 helper identity 与参数 | 哪些参数对 bounded profile 的像素结果可观察；未运行 golden 前不定义支持子集 |
| combo 注解 | 固定 frontend 读取精确 `[COMBO]`、material 显式值和 active declaration default；变体拼写只在 source 中出现 | 三种变体拼写是否被消费；显式值与同值 default 是否得到相同结果；缺失/冲突/畸形时的官方结果是什么 |
| uniform 标注 | inline uniform metadata 与 combo 是不同表面，`type` 值域也不同 | `color`、`imageblending` 等类型分别影响哪些 author-visible 行为 |
| `[PASS]` 注解 | 固定 frontend 读取 `[PASS]`；已观察样本均与 3D shadow 路径相关 | fur/foliage/chroma 的 shadow pass 何时被调度；2D 或未知 token 的结果仍未闭合 |
| sampler parser | 固定 frontend 可识别多位数字索引；公开 authored contract 为 0...7 | `g_Texture7`、`g_Texture8/9` 与超范围输入分别产生什么作者可观察结果 |
| slot metadata | fixed client 内部存在 physical/mapped/texel/mip/rotation/translation binder 家族 | 公开 0...7 槽在 resource generation 改变时，metadata 与 texture 的可观察更新是否原子 |
| texture purpose | source 中对 color/data/normal 采用不同处理候选 | 同一编码以不同 purpose 输入时，哪些颜色/alpha 变化能由官方黑盒确认 |

## 10. 未覆盖与边界

- 候选 prelude/frontend token 的**确切展开文本与完整 provider**不在随包 source corpus 中。运行时 frontend 与 built-in binder 的存在已有静态执行路径支持；token 展开文本、完整 backend translation 和数值语义仍未知。
- `SHADERVERSION` 与 `VERSION` 的取值范围无本地证据。
- `HLSL/` 子目录下 7 个 `dx11*` shader 是 D3D11 专用回退路径（`dx11fallback`、`dx11playlistgaussian`、`dx11playlisttransition`），与跨平台抽象无关，未展开。

## 11. 关联文档

- [Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md) —— Shader IR 与 executor 实现进度
- [SceneScript 2.8.42 固定客户端静态取证](scenescript-runtime-implementation-contract.md) —— JS 侧 WEColor 与 shader 侧色彩函数的研究差异
- [资料来源与证据索引](source-index.md) —— 官方 Shader 文档页面入口
- [Windows 官方客户端取证记录](../../history/scene/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) —— 证据等级
