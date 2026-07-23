# Scene 官方 Effect 执行覆盖表

> 状态：现役专项能力表
>
> 最近核对：2026-07-24
>
> 实现基线：`1766c76`；当前两层运行门、签名 App 身份及聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)。

本文把 45 个官方用户 Effect 逐项映射到 MyWallpaperX 当前执行级别和公共依赖。作者语义、输入槽和 pass/RT 结构见 [Effects 语义全集](effects-reference.md)，Graph/Shader 原子能力见 [Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md)，依赖 ID 见 [公共能力依赖图](capability-dependency-map.md)。

所有 Effect 的第一启用条件相同：对象 `effects[]` 显式引用、effect 自身有效可见、owner layer 最终可见。表中的运行时拥有某个 profile 不会让未声明 Effect 自动启用。

## 1. 等级与执行通道

| 等级 | 本表唯一含义 |
|---|---|
| `L0` | effect reference/definition 不能可靠识别或保留 |
| `L1` | reference/definition/value 可识别或保留；没有有效执行路由 |
| `L2` | 进入 typed graph/route/fail-closed blocker；没有该 Effect 的可靠视觉执行 |
| `L3` | 表中明确限定的 profile 有真实 GPU 执行、正反测试和运行证据；仍非 WE parity |
| `L4` | 作者启用、输入、顺序、生命周期和视觉均经合法 Windows WE golden 验证 |

执行通道：`IR-only` 只保留数据；`graph-only` 只建图或 route；`inline-profile` 是项目自写的有界 Metal 近似；`strict-graph-profile` 先匹配完整 graph/material 形状再执行固定 backend，且可在整链所有 stage 均严格准入时参与 ordered strict effect-chain；`provider-profile` 是受限跨层纹理 consumer。任一 stage 不受支持时整链失败关闭。当前没有 generic authored shader executor，也没有任何 `L4` Effect。

## 2. Animation

| Effect / asset ID | 等级 | 当前执行通道与边界 | 公共依赖 | 当前证据 | 下一验收门 |
|---|---|---|---|---|---|
| Foliage Sway / `foliagesway` | `L3` | `inline-profile`：单一 built-in UV 模式，服从 mask 与作者参数 | [D2](capability-dependency-map.md#d2) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline) | Vertex、noise/weights/bounds、multi-stack、Windows golden |
| Iris Movement / `iris` | `L3` | `inline-profile`：有 mask 时局部缩放/扰动近似 | [D2](capability-dependency-map.md#d2) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline) | background variant、完整 scale/noise/smoothness 与像素门 |
| Pulse / `pulse` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D4](capability-dependency-map.md#d4) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | time/audio 两驱动、mask/color/alpha/blend profile |
| Cloud Motion / `cloudmotion` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | Perlin、mapped resolution、mask、repeat profile |
| Scroll / `scroll` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | UV-only movement、X/Y speed、repeat/wrap 和 author-off |
| Shake / `shake` | `L3` | `strict-graph-profile`：exact stock 单 pass `MASK=0/AUDIOPROCESSING=0/NOISETEXTURE=0`，RG8 flow + authored white phase fallback；可与 exact Blur Precise 按作者顺序组成全支持 chain | [D2](capability-dependency-map.md#d2) [D4](capability-dependency-map.md#d4) [D5](capability-dependency-map.md#d5) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-SHAKE](runtime-evidence-index.md#e-effect-shake) [E-EFFECT-CHAIN](runtime-evidence-index.md#e-effect-chain) | dynamic speed/audio/noise/direction、MASK1、非 exact fingerprint、局部坐标/采样和 Windows golden |
| Spin / `spin` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | local center/mask/ellipse/noise/repeat profile |
| Swing / `swing` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | p0/p1 hinge、feather、mask/noise、局部形变门 |
| Twirl / `twirl` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | center/size/feather/ellipse/inner/repeat/mask profile |
| Water Flow / `waterflow` | `L1` | 只参与已知错误 composite 的 fail-closed 判断 | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | flow/time-offset、phase/scale/direction/mask profile |
| Water Ripple / `waterripple` | `L3` | `inline-profile`：无 mask normal-map 子集；另有 legacy 单 pass 近似 | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline) | optional mask、双 normal、specular、Perspective、Windows golden |
| Water Waves / `waterwaves` | `L3` | `inline-profile`：仅当 Water Waves 是 owner layer 唯一可见 Effect 时执行单组定向波近似；mixed/repeated declarations 因无法保持作者顺序与独立参数而 fail closed | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline) | authored-chain backend、双波、time-offset、Perspective、mask 边缘与 Windows golden |

## 3. Blur

| Effect / asset ID | 等级 | 当前执行通道与边界 | 公共依赖 | 当前证据 | 下一验收门 |
|---|---|---|---|---|---|
| Blur / `blur` | `L3` | `strict-graph-profile`：stock default 4 pass / 2 quarter RT | [D5](capability-dependency-map.md#d5) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-BLUR](runtime-evidence-index.md#e-effect-blur) | kernel/composite/blend/alpha/mask variants、rounding/color-space parity |
| Blur Precise / `blurprecise` | `L3` | `strict-graph-profile`：显式 2 pass / 1 full RT，或 exact `KERNEL=0` legacy `compose:true` 两遍语法归一化；均使用固定近似 kernel | [D5](capability-dependency-map.md#d5) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-BLUR](runtime-evidence-index.md#e-effect-blur) [E-GRAPH-LEGACY-COMPOSE](runtime-evidence-index.md#e-graph-legacy-compose) | authored shader、mask/variant、generic compose/scene background、sampler 和像素等价 |
| Motion Blur / `motionblur` | `L2` | `graph-only`：material-copy-material 可建图；无跨帧 history | [D2](capability-dependency-map.md#d2) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | history copy/ping-pong、first frame、resize/switch/seek/stop |
| Radial Blur / `blurradial` | `L1` | `IR-only` | [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | local center、direction、aspect、mask profile |

## 4. Interactive

| Effect / asset ID | 等级 | 当前执行通道与边界 | 公共依赖 | 当前证据 | 下一验收门 |
|---|---|---|---|---|---|
| Cursor Ripple / `cursorripple` | `L3` | `inline-profile`：pointer + optional mask 的无 history 环形近似 | [D2](capability-dependency-map.md#d2) [D4](capability-dependency-map.md#d4) [D6](capability-dependency-map.md#d6) [D8](capability-dependency-map.md#d8) | [E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline) | 3 pass / 2 fit RT 波场、collision、reset lifecycle |
| Advanced Fluid / `fluidsimulation` | `L2` | `graph-only`：约 20 nodes / swap 可保留；condition/function blocker | [D2](capability-dependency-map.md#d2) [D4](capability-dependency-map.md#d4) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | 9 RT / 8 history、float formats、condition/function、emitters |
| Depth Parallax / `depthparallax` | `L1` | `IR-only`；与 Camera Parallax 保持分离 | [D4](capability-dependency-map.md#d4) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | required depth、local pointer、basic/24/64 quality、mask |
| X-Ray / `xray` | `L1` | `IR-only` | [D4](capability-dependency-map.md#d4) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | local cursor、source/blend、halo/sprite、mask/aspect |

## 5. Colorization and overlays

| Effect / asset ID | 等级 | 当前执行通道与边界 | 公共依赖 | 当前证据 | 下一验收门 |
|---|---|---|---|---|---|
| Blend / `blend` | `L3` | `provider-profile`：单 image dependency、有限 blend mode、静态 consumer | [D1](capability-dependency-map.md#d1) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-PROVIDER](runtime-evidence-index.md#e-provider) | six slots、holes、per-slot UV/amount、mask/write-alpha |
| Blend Gradient / `blendgradient` | `L1` | `IR-only`；Workshop `gradient_color` profile 不是此 Effect | [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | blend/gradient/opacity 三输入、edge glow、write-alpha |
| Chromatic Aberration / `chromaticaberration` | `L3` | `inline-profile`：手写径向通道偏移子集 | [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline) | directional/radial/barrel/expansion、mask/aspect variants |
| Clouds / `clouds` | `L1` | `IR-only`；不冒充粒子 | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | albedo/mask、shading/blend/write-alpha/Perspective |
| Color Key / `colorkey` | `L1` | `IR-only` | [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | tolerance/feather/invert/flatten、straight/premultiplied alpha |
| Film Grain / `filmgrain` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | time noise、mask、greyscale/blend variants、resolution |
| Glitter / `glitter` | `L2` | `graph-only`：明确 offscreen route，没有 glitter executor | [D2](capability-dependency-map.md#d2) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | fixed 256x256 R8 repeat RT、tile generation、combine |
| Shimmer / `shimmer` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | gradient/mask/time-offset、linear/mirror、blend |
| Fire / `fire` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | flow/albedo 分离、refract/blend/time variants |
| Light Shafts / `lightshafts` | `L1` | `IR-only`；particle `light_shafts_6` 不是此 Effect | [D5](capability-dependency-map.md#d5) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | combo-dependent slot layout、direct draw、mask/noise |
| Nitro / `nitro` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | cloud/mask/time/repeat/color/blend |
| Opacity / `opacity` | `L3` | `strict-graph-profile`：exact stock 单 pass `MASK=0`，静态或 direct-binding alpha 经 per-surface snapshot live；另保留既有 inline mask/Perspective 子集 | [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-OPACITY](runtime-evidence-index.md#e-effect-opacity) [E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline) | MASK1、SceneScript/Workshop variants、其他顺序与 Windows premultiplied/color golden |
| Reflection / `reflection` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | dynamic reflection UV、mask、direction/speed/ratio/Perspective |
| Tint / `tint` | `L1` | `IR-only`；base layer tint 不是此 Effect | [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | blend modes、mask、source alpha 和 color-space |
| VHS / `vhs` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | scan/artifact/channel/noise/color variants、texel size |
| Water Caustics / `watercaustics` | `L1` | `IR-only` | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | mask/Voronoi/uniform/offset/glow 五输入、style/blend |

## 6. Distortion

| Effect / asset ID | 等级 | 当前执行通道与边界 | 公共依赖 | 当前证据 | 下一验收门 |
|---|---|---|---|---|---|
| Fisheye / `fisheye` | `L1` | `IR-only` | [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | local center/aspect、background/clamp 和 edge sampling |
| Perspective / `perspective` | `L3` | `inline-profile`：仅严格 Perspective -> Opacity 四边映射 | [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline) | standalone effect、clip、invalid quad、all combos/pixel gate |
| Refraction / `refraction` | `L1` | raw `compose` 可保留并 fail-closed；无 scene background executor | [D1](capability-dependency-map.md#d1) [D5](capability-dependency-map.md#d5) [D6](capability-dependency-map.md#d6) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | background/source/final identity、normal/mask、ordering |
| Skew / `skew` | `L1` | `IR-only` | [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | Vertex/UV、four edges、repeat/clamp variants |
| Transform / `transform` | `L1` | `IR-only`；object transform 不是此 Effect | [D7](capability-dependency-map.md#d7) [D8](capability-dependency-map.md#d8) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | effect-local center/offset/rotation/scale、clamp/repeat |

## 7. Enhancement

| Effect / asset ID | 等级 | 当前执行通道与边界 | 公共依赖 | 当前证据 | 下一验收门 |
|---|---|---|---|---|---|
| Edge Detection / `edgedetection` | `L1` | `IR-only` | [D5](capability-dependency-map.md#d5) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | Sobel texel size、threshold/color/blend、mask if authored |
| God Rays / `godrays` | `L2` | `graph-only`：多 pass route，无 visual executor | [D5](capability-dependency-map.md#d5) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | 5 pass、half RT、full-frame alias、COPYBG/mask/noise |
| Local Contrast / `localcontrast` | `L3` | `strict-graph-profile`：每个 stage 只接受 stock KERNEL0/GREYSCALE0/MASK0、Gaussian `scale=(1,1)` 的 4-pass/2-quarter-RGBA 图；exact graph/material/shader fingerprint 失败即关闭，可参与整链全部支持的 ordered strict chain | [D5](capability-dependency-map.md#d5) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-LOCAL-CONTRAST](runtime-evidence-index.md#e-effect-local-contrast) [E-EFFECT-CHAIN](runtime-evidence-index.md#e-effect-chain) | mask/greyscale、非默认 kernel/Gaussian scale、包含 unsupported stage 的 mixed chain、generic shader 与 Windows golden |
| Shine / `shine` | `L2` | `graph-only`：多 pass identity，无 visual executor | [D2](capability-dependency-map.md#d2) [D5](capability-dependency-map.md#d5) [D6](capability-dependency-map.md#d6) [D7](capability-dependency-map.md#d7) | [E-EFFECT-IR](runtime-evidence-index.md#e-effect-ir) | 5 pass、half RT、threshold/noise/kernel/edge/COPYBG |

## 8. 非 45 项边界与汇总

| 项目 | 等级 | 边界 |
|---|---|---|
| internal `_empty` / `empty` | `L1` | passthrough 占位；未知 Effect 不得映射到它后宣称成功 |
| Workshop `gradient_color` | `L3` | 项目样本中的严格单 pass profile；不是官方 Blend Gradient |
| Workshop layer Bloom approximation | `L3` | 受限 threshold/blur/composite；不是官方 Scene-level Bloom/HDR，也不是 45 个 Effect 专页之一 |
| Workshop `3488490208/shadow_____________` | `L3` | exact single-pass strict profile；只接受完整 definition/material/ShaderContract fingerprint、`MASK=0`、`BLENDMODE=0`、normal/nocull/depth disabled 与静态常量。不是官方 45 项 Effect、generic Shadow 或 authored shader；mode 0 尚无官方 Windows 像素 oracle |

45 项汇总：`L1=27`、`L2=5`、`L3=13`、`L4=0`。这个统计只反映当前表中最小可声明级别，不是样本命中率、视觉相似度或已知语义比例。

`b541867` 只增加 strict profile 之间的有序、全有或全无调度，没有改变 45 项数量或等级；其阶段报告 `.codex/scene-effect-chain-gated-final13-20260723/report.json` 的 8 stage、0 real chain 是 Shadow 前的历史负门。`809b75e` 的 exact Workshop Shadow、`b8842d8` 的 stock Opacity `MASK=0` 与 `4f13daf` 的 exact legacy Blur Precise compose 都只扩充既有 `L3` 行的受限 profile。`e505a9e` 首次把官方 Shake 从 `L1` 提升为 `L3` 受限 profile，并让未修改 `2802243144` 的三层 `Blur Precise <-> Shake` 链真实执行。当前完整门为 30 stage、3 条 chain、16 个 legacy blocked layer；固定门仍保护 14 stage、1 条真实 chain、Opacity 4、Workshop Shadow 1。最新路径与边界统一见 [运行证据索引](runtime-evidence-index.md)。

## 9. 开发顺序

1. D6 ordered strict effect-chain 骨架与 `3724289844:20` exact Workshop Shadow 正门已完成；后续仍只补可由完整 graph/material/ShaderContract fingerprint 约束的 backend，不扩大 path substring 分支。
2. stock Opacity `MASK=0` 与 exact stock Shake strict profile 已完成；290 的四层 Opacity、`2802243144` 的三层 Shake chain 是正门，293 的 SceneScript Opacity 与 `2134765860` 的动态 audio/speed Shake 是负门。下一 Effect 只在结构化 authored-graph census 与公共 primitive 收益明确后选择；route-only 不能替代该 census。MASK1、Workshop variants、未知 combo/hash 和 unsupported 后续 stage 继续 fail closed。
3. 每个 Effect 新增执行前必须锁定显式引用、author-off、missing input、slot/combo、local space、alpha/color、resize/switch/stop。
4. 只有对应行取得 Windows golden，才能从 `L3` 升到 `L4`；样本封面只用于固定画布上的主构图、主体位置、色调、亮度和明显效果范围参考，不能验证动态时序、粒子轨迹、音频响应或像素等价。
