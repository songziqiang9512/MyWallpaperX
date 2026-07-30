# Shader source 前置合同与跨后端假设审查

审查日期：2026-07-25
取证快照：Wallpaper Engine 2.8.42 `assets/shaders`
审查方式：只读静态检查，共 14 个头文件 + 108 个顶层 shader + 7 个 HLSL 专用 shader

> [Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md) 记录了 EffectDefinition、Material、FBO 与 Shader 的 IR 与 executor 实现进度。本文补充一个前置观察：扫描到的官方 shader 源码使用一组在同一 source corpus 中没有定义的 token；它们可能由编译前端、未随包的 include 或其他宿主阶段提供。
>
> 这只建立“自研 frontend 必须解析或拒绝这些 token”的输入合同，不证明 token 的官方展开文本、注入模块或 Metal 映射。

## 1. 结论先行

1. 扫描得到 **25 个候选 frontend token**，在 `assets/` source corpus 中被使用但没有找到本地定义。缺席是 A 级事实；由哪个 executable/module 注入是 C 级假设。
2. `mul`、`saturate`、`frac`、`clip`、`ddx`/`ddy` 等命名明显受 HLSL 影响，但矩阵上传、转置与各目标语言展开仍需独立 fixture 和 Windows golden。
3. 源码存在 `HLSL`、`GLSL`、`HLSL_SM30`、`PLATFORM_ANDROID` 条件分支。MyWallpaperX 应保留这些 authored branches，并设计自有 MSL frontend/translator；不得直接复制官方分支或把 `HLSL` 路径等同于 Metal。
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

源码把 `HLSL` 与 `GLSL` 当作独立条件，并在部分位置使用 `HLSL_SM30` 特化；本地静态文件没有证明所有编译任务中两者必有且仅有一个为真。MyWallpaperX 的 MSL 变体应使用自有 backend identity，并对每个保留分支做显式准入，不能复用 `HLSL` 标志伪装成 Metal。

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

源码通过 `TEX0FORMAT`、`TEX1FORMAT`、`TEX4FORMAT`、`TEX8FORMAT`、`THICKFORMAT` 等 combo 选择分支。sidecar/binary format 与这些枚举存在可对照关系，但 combo 的最终来源、覆盖优先级和缺省值尚未由运行时确认；自研 loader 应先保留 authored、sidecar 与 decoded format 三者，再由 fixture 锁定 variant key。

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

`d432d4d5` 将上述两类扩展为八类穷举 identity：premultiplied color、straight albedo、generic preserved、mask、noise、flow、phase、normal。32 个 Effect helper 调用按实际 slot 角色拆分；七类非预乘 identity 当前仍共享严格 source-channel policy，但 cache 不再混用。strict Particle REFRACT 的自建 GPU 门让同一 format-4 packed-normal 内容分别走 single-image CPU BC3 decode 与 multi-image native BC3 直传，并与 decoded-byte-equivalent format-0 RGBA 经真实 loader/shader 比较；两条 BC 路径分别与 RGBA 在 2 个字节内一致，G/A swapped 与 neutral normal 均为有效负对照。该门闭合的是项目内部 storage equivalence，不定义官方 DXT5n 恢复公式；format 5 / BC5、generic Effect/material normal 与 Windows golden 继续在已证合同外。

## 5. 灰度权重冲突

两个函数计算灰度，权重向量的 R/B 分量相反：

| 函数 | 文件 | 权重 | 展开 |
|---|---|---|---|
| `greyscale(color)` | `common.h` | `vec3(0.11, 0.59, 0.3)` | `0.11·R + 0.59·G + 0.30·B` |
| `Desaturate(color, amount)` | `common_blending.h` | `vec3(0.3, 0.59, 0.11)` | `0.30·R + 0.59·G + 0.11·B` |

`Desaturate` 的权重接近标准 Rec.601（`0.299, 0.587, 0.114`）；`greyscale` 的 R 与 B 权重互换，**不符合任何标准亮度公式**。

无论这是否为历史兼容或笔误，都不能在 parser 阶段把两个 helper 合并成同一身份。自研实现应以纯色输入建立独立 golden，并在得到 Windows 像素证据前保留“行为待确认”，而不是直接移植官方表达式。

同类情况还有 HSV：`common.h` 的 `rgb2hsv`/`hsv2rgb` 是 GLSL 无分支实现（用 `1e-10` 防除零），与 `common_blending.h` 的 `RGBToHSL`/`HSLToRGB` 是**不同色彩空间的不同实现**（HSV vs HSL），不可互换。JS 侧 `WEColor` 模块又是第三套实现，见 [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md) §7.4。

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

它们属于 §10 说明的 D3D11 专用回退路径，**不参与跨平台抽象**，与上表合并统计会得到 161 这个无实现意义的数字。MyWallpaperX 不需要实现这一组。

官方公开的 built-in 变量应以在线 Variables 页面为准（见 [资料来源与证据索引](source-index.md) §1.4）；本清单包含未公开的内部 uniform，可用于判断某个 workshop shader 引用的是否为合法 built-in。

### 7.4 运行时 slot metadata binder 的静态确认

Ghidra 选择性静态路径确认，2.8.42 运行时为每个内部纹理槽建立同构的 resolution、mapped size、texel/mipmap、rotation 与 translation 元数据族；内部 registry 覆盖 0...9。

官方公开 authored shader 合同仍只有 sampler 0...7，因此：

- MyWallpaperX 的公开 schema、兼容声明和作者输入继续限制 0...7；
- 内部 8/9 只能作为保留槽或显式 unsupported，不能据此扩宽公开兼容范围；
- per-slot binder 必须从最终 texture candidate/generation 更新同一组元数据，不能由各 strict effect 分别猜测。

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

只匹配 `[COMBO]` 的 parser 会把它们当普通注释丢弃；按「包含 COMBO」宽松匹配又会把它们误当启用的 combo。两种都错。MyWallpaperX 应只承认精确 `[COMBO]`，其余拼写记为「已识别、不启用」的显式诊断。官方未公开这三种拼写的合同，见 [资料来源与证据索引](source-index.md) §6。

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

`type` 缺 63 条、`default` 缺 15 条、`material` 缺 13 条——三者都不能当必填。只有 `combo` + `default` 的形态是「有 variant，不暴露给作者 UI」。

`options` 字典的键既可以是本地化 key（`ui_editor_properties_gradient` 9 次为最高频），也可以是英文字面量（`{"Center":0,"Post":1,"Pre":2}`）。不能假设一律需要查本地化表。

### 8.3 `require` 是 combo 之间的依赖条件

25 条 `[COMBO]` 带 `require`，形态为 `{"<其他 COMBO 名>": <取值>}`：

| `require` | 次数 |
|---|---:|
| `{"LIGHTING":1}` | 12 |
| `{"DIRECTDRAW":0}` | 8 |
| `{"WRITEALPHA":0}` | 2 |
| `{"TRANSFORMUV":1}` | 2 |
| `{"RAYMODE":2}` | 1 |

即 combo 空间不是自由笛卡尔积：`RIMLIGHTING` 只在 `LIGHTING == 1` 时有意义。variant 矩阵生成器必须读 `require` 并剪掉非法组合，否则会编译出官方不会产生的 variant，也会把 variant 数量放大到无意义的规模。

字段名支持「依赖门」解释，但官方在依赖不满足时是隐藏该属性、强制默认值还是跳过编译，无静态证据（等级 C）。

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

对 render graph 的影响：依赖收集与 pass 枚举不能只扫 JSON，还要解析 shader 头部注解。三个宿主 shader 都是 3D 模型类（fur/foliage/chroma），与阴影投射用途一致。只有 3 个样本，`[PASS]` 的完整参数形态与官方调度时机无证据（等级 C）。

### 8.6 Shader frontend 注解是运行输入

Ghidra 静态执行路径确认，客户端 frontend 会识别多位数字的 `g_TextureN`、`uniform` inline metadata，以及 `[COMBO]`、`[PASS]`。inline metadata 至少包含 `material`、`default`、`components` 和 `formatcombo` 族。

这把上述注解从“随包 source 中存在”推进为“运行时 frontend 会读取”；它仍不能推出完整预处理展开、default/override 精确优先级、backend translation 或未公开 slot 的作者可用性。

## 9. 对 MyWallpaperX 的规格与验收门

| 项 | 规格 | 验收门 |
|---|---|---|
| frontend token | §2 的 25 个 token 建 typed IR 或明确诊断 | 每个 token 有 operand/stage fixture；未知形态 fail closed |
| `mul` 约定 | 按 operand shape 保存，不预先假定转置 | identity/translation/rotation/normal fixture + Windows 对照 |
| 后端分支 | 保留 authored `HLSL`/`GLSL`/platform 条件；MSL 使用自有 backend identity | variant key 包含 backend/stage/combo；不伪装成 HLSL |
| 坐标与法线 Y | 作为待验证 transform contract | 非对称法线/反射 fixture 不发生未解释的上下镜像 |
| 纹理格式 combo | §4.1 的 13 个枚举值 | 加载器实际格式 → combo 值映射正确；R8 上传为 `r8Unorm` |
| 法线解压 | §4.2 三分支，`0.965` 偏移 | 同一法线贴图分别以 BC7 与 RGBA8888 编码，解压结果一致 |
| 灰度 | §5 两套权重分别实现 | 纯红输入下 `greyscale` 得 0.11、`Desaturate` 得 0.30 |
| PBR | 保留 helper 身份与参数 | 参数 sweep 与 Windows 像素 golden 定义已支持子集 |
| combo 注解 | 只承认精确 `[COMBO]`；除 `combo` 外全部键可缺席；`require` 参与 variant 剪枝 | §8.1 三种变体拼写产出诊断而非静默忽略；`require` 不满足的组合不进 variant 矩阵 |
| uniform 标注 | 与 combo 分成两条通道，`type` 值域不共用 | `type == "color"` 不生成 variant；`type == "imageblending"` 不生成颜色控件 |
| `[PASS]` 注解 | shader 头部声明的附加 pass 进入依赖收集与 pass 枚举 | fur/foliage/chroma 的 shadow pass 被枚举到，而非只扫 JSON |
| sampler parser | 支持多位数字索引，同时对 authored contract 执行 0...7 边界 | `g_Texture7` 正门、`g_Texture8/9` 保留/失败关闭门、超范围负门 |
| slot metadata | 每个公开槽使用同构 physical/mapped/texel/mip/rotation/translation binder | 0...7 表驱动 fixture；资源 generation 改变时元数据与纹理原子更新 |
| texture purpose | storage format 与 color/data/normal identity 分离 | 同一 BC3 fixture 走 color 与 normal/data，只有 color 发生项目要求的 premultiply |

## 10. 未覆盖与边界

- 候选 prelude/frontend token 的**确切展开文本与完整 provider**不在随包 source corpus 中。运行时 frontend 与 built-in binder 的存在已有静态执行路径支持；token 展开文本、完整 backend translation 和数值语义仍未知。
- `SHADERVERSION` 与 `VERSION` 的取值范围无本地证据。
- `HLSL/` 子目录下 7 个 `dx11*` shader 是 D3D11 专用回退路径（`dx11fallback`、`dx11playlistgaussian`、`dx11playlisttransition`），与跨平台抽象无关，未展开。

## 11. 关联文档

- [Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md) —— Shader IR 与 executor 实现进度
- [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md) —— JS 侧 WEColor 与 shader 侧色彩函数的差异
- [资料来源与证据索引](source-index.md) —— 官方 Shader 文档页面入口
- [Windows 官方客户端取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) —— 证据等级
