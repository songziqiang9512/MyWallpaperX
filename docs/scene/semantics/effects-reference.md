# Wallpaper Engine 内置 Effects 语义全集

> 核验日期：2026-07-22
>
> 覆盖：官方 sitemap 中 45 个用户可见 Scene effect 页面，以及 1 个 asset 内部 `_empty` 占位。
>
> 实现基线、当前两层运行门、签名 App 身份及聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)；本表不复制基线 commit，文内 commit 号是各能力的历史落地提交。
>
> 用法：先按 effect ID 查作者启用、输入、pass/RT，再决定 parser、renderer 和测试，不按名称直接套一个视觉近似。

## 1. 阅读约定

- 所有效果首先要求对象 `effects[].file` 显式引用，且实例最终可见；播放器拥有该能力不构成启用条件。
- 表中 `T0`、`T1` 等表示 shader texture slot。官方公开 sampler 0...7，但每槽的具体含义来自对应 material/shader；不得把表中某个 effect 的槽位推广成全局规则。
- `previous`、mask/normal/flow/noise 等精确槽位来自 WE-compatible asset 定义观察，证据级别为 C；官方专页确认的作者行为是 A。
- `1P/4P` 表示 material pass 数；`RT` 是中间 render target；`Hist` 表示跨帧状态；`Compose` 表示需要场景背景。
- Combo 是 shader compile-time variant。optional texture 只有真实绑定后才能启用对应 combo。
- 固定 revision `b016d7d1fdcf4e5fd2f9c9fa420a8aaa07fee02d` 的 `Almamu/linux-wallpaperengine` 源码树不附带 stock effect/material/shader assets；它只能作为 Effect/Material/pass/FBO/texture precedence 的 D 级交叉证据，不能复核本表 45 项的逐效果参数、默认值、pass/RT 数或 shader 算法。

官方入口：[Effects Overview](https://docs.wallpaperengine.io/en/scene/effects/overview.html)、[Effects Introduction](https://docs.wallpaperengine.io/en/scene/effects/introduction.html)、[Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html)。

## 2. 动画类

| 官方名称 / asset ID | 作者语义和关键输入 | 图结构 | MyWallpaperX 实现合同 | 证据 |
|---|---|---|---|---|
| [Foliage Sway](https://docs.wallpaperengine.io/en/scene/effects/effect/sway.html) / `foliagesway` | UV 或 Vertex 模式；可选 opacity mask、noise；corner/direction weight 和 bounds 控制局部风摆 | 1P | 两模式分开；不能把 mask 内摆动替换成整层平移 | A+C |
| [Iris Movement](https://docs.wallpaperengine.io/en/scene/effects/effect/iris.html) / `iris` | 用 mask 限定瞳孔区域；scale/speed/smoothness/noise/phase 与 background variant | 1P | 只修改作者 mask 区域，不当作全局视差 | A+C |
| [Pulse](https://docs.wallpaperengine.io/en/scene/effects/effect/pulse.html) / `pulse` | noise、可选 opacity mask；可使用时间或音频频段驱动 color/alpha/blend | 1P | 时间和 audio 两条输入路径都进入统一 frame context | A+C |
| [Cloud Motion](https://docs.wallpaperengine.io/en/scene/effects/effect/cloudmotion.html) / `cloudmotion` | opacity mask + Perlin 驱动局部 UV 流动 | 1P | 保留 noise repeat、mapped resolution 和画布比例 | A+C |
| [Scroll](https://docs.wallpaperengine.io/en/scene/effects/effect/scroll.html) / `scroll` | X/Y 独立速度和 texture repeat/wrap | 1P | 滚动 UV，不移动 layer bounds；不得因此露出 clear color | A+C |
| [Shake](https://docs.wallpaperengine.io/en/scene/effects/effect/shake.html) / `shake` | T1 flow、T2 time-offset、T3 opacity mask；可选 audio；direction/bounds/friction/strength 控制局部变形 | 1P | flow RG 中性点约 0.5，位移受 `strength^2` 和 mask 限定；不是整块晃动 | A+C |
| [Spin](https://docs.wallpaperengine.io/en/scene/effects/effect/spin.html) / `spin` | effect-local center、可选 mask、ellipse/noise/repeat、axis/phase/feather | 1P | 围绕 effect 区域旋转，不能写回 object angles | A+C |
| [Swing](https://docs.wallpaperengine.io/en/scene/effects/effect/swing.html) / `swing` | p0/p1、center、size、feather 定义局部铰链；可选 mask/noise；支持 double-sided | 1P | 只扭曲选区，不能把整个头发/衣物对象旋转 | A+C |
| [Twirl](https://docs.wallpaperengine.io/en/scene/effects/effect/twirl.html) / `twirl` | effect-local center/size/feather、ellipse、inner/repeat/noise、可选 mask | 1P | 严格使用 effect-local UV 和作者作用域 | A+C |
| [Water Flow](https://docs.wallpaperengine.io/en/scene/effects/effect/waterflow.html) / `waterflow` | flow mask + time-offset，按方向做周期性局部重采样 | 1P | 保留 phase/scale/feather/repeat；不能替换成全图水波 | A+C |
| [Water Ripple](https://docs.wallpaperengine.io/en/scene/effects/effect/waterripple.html) / `waterripple` | 可选 opacity mask + water normal；两组滚动 normal；Perspective 是 combo | 1P | 解码 normal 格式、aspect、scroll 和 `strength^2`；Perspective 不默认启用 | A+C |
| [Water Waves](https://docs.wallpaperengine.io/en/scene/effects/effect/waterwaves.html) / `waterwaves` | 可选 opacity/time-offset mask；一组或双组定向正弦波；可选 Perspective | 1P | `PERSPECTIVE`、`DUALWAVES` 默认关闭；仅在作者 mask 内变形 | A+C |

### 2.1 对当前错误最重要的区别

```text
object transform        -> 整个 layer 的位置/旋转/缩放
Camera Parallax         -> scene 开启后按 layer depth 移动相机/对象
Shake/Swing/Foliage     -> effect-local、mask/flow/region 限定的局部变形
Water Flow/Waves/Ripple -> effect-local UV 重采样
Depth Parallax          -> depth map 驱动的 UV/POM 重采样
```

五类路径不能共用一个“正弦位移”实现。

## 3. 模糊类

| 官方名称 / asset ID | 作者语义和关键输入 | 图结构 | MyWallpaperX 实现合同 | 证据 |
|---|---|---|---|---|
| [Blur](https://docs.wallpaperengine.io/en/scene/effects/effect/blur.html) / `blur` | 下采样后横/纵模糊，最终与 previous 合成；最终阶段可有 opacity mask | 4P；2 个 quarter RT ping-pong | 保留 quarter 尺寸、bind index、kernel、composite 和 blur-alpha combo | A+C |
| [Blur Precise](https://docs.wallpaperengine.io/en/scene/effects/effect/blurprecise.html) / `blurprecise` | 全分辨率横/纵 Gaussian；mask 槽只在对应 combo 启用 | 2P；1 个 full RT | 不复用 coarse blur 的 slot/layout；texel size 来自实际 RT | A+C |
| [Motion Blur](https://docs.wallpaperengine.io/en/scene/effects/effect/motionblur.html) / `motionblur` | current + history accumulation，可选 mask，显式 copy 更新历史，再 combine | 3 步；2 full RT；1 Hist | resize/switch/seek/stop 时初始化或清空 history；copy 不能省略 | A+C |
| [Radial Blur](https://docs.wallpaperengine.io/en/scene/effects/effect/radialblur.html) / `blurradial` | 当前帧围绕指定中心多次采样，可选 mask | 1P | 不使用 Motion Blur history；处理中心、方向、aspect 和 mask | A+C |

## 4. 交互类

| 官方名称 / asset ID | 作者语义和关键输入 | 图结构 | MyWallpaperX 实现合同 | 证据 |
|---|---|---|---|---|
| [Cursor Ripple](https://docs.wallpaperengine.io/en/scene/effects/effect/cursorripple.html) / `cursorripple` | pointer 投影到 effect-local UV；可选 collision mask；维护波场 | 3P；2 个 fit 512 RT ping-pong；Hist | 保留上一帧 simulation、边界、resize/reset；不能变成鼠标相机位移 | A+C |
| [Advanced Fluid Simulation](https://docs.wallpaperengine.io/en/scene/effects/effect/advancedfluidsimulation.html) / `fluidsimulation` | point/line/image emitter、collision/gradient/dye mask；velocity/pressure/divergence/curl/dye simulation | 约 20P；9 RT；8 Hist；R/RG float formats | 作为完整 simulation graph 单独建设；迭代、format、clear、ping-pong 和 emitter 顺序都是语义 | A+C |
| [Depth Parallax](https://docs.wallpaperengine.io/en/scene/effects/effect/depthparallax.html) / `depthparallax` | 必需 depth map、可选 opacity mask、`g_ParallaxPosition`；基础/24 层/64 层质量 | 1P | 与 Camera Parallax 分离；先把全局 pointer 投到 effect-local space；缺 depth map 不执行 | A+C |
| [X-Ray](https://docs.wallpaperengine.io/en/scene/effects/effect/xray.html) / `xray` | pointer 局部区域在 source/blend texture 间混合，并可叠加 halo/sprite 与 mask | 1P | 处理 local cursor、radius/feather、mapped size 和 aspect，不做全屏 radial overlay | A+C |

## 5. 色彩与叠加类

| 官方名称 / asset ID | 作者语义和关键输入 | 图结构 | MyWallpaperX 实现合同 | 证据 |
|---|---|---|---|---|
| [Blend](https://docs.wallpaperengine.io/en/scene/effects/effect/blend.html) / `blend` | T1-T6 最多六个 blend image，T7 optional opacity mask；每槽独立 amount/UV | 1P | 支持 blend count/mode、WRITEALPHA、transform/repeat/clip/clamp；不压缩空槽 | A+C |
| [Blend Gradient](https://docs.wallpaperengine.io/en/scene/effects/effect/blendgradient.html) / `blendgradient` | blend image、gradient mask、opacity mask 是三个不同输入；支持 edge glow | 1P | 分离 gradient 与 opacity 坐标/槽位，保留 transform、repeat、write-alpha | A+C |
| [Chromatic Aberration](https://docs.wallpaperengine.io/en/scene/effects/effect/chromaticaberration.html) / `chromaticaberration` | RGB 分离；directional/radial/barrel/expansion；可选 mask | 1P | 按 screen/effect aspect 与局部中心采样，mask 外保持 source | A+C |
| [Clouds](https://docs.wallpaperengine.io/en/scene/effects/effect/clouds.html) / `clouds` | cloud albedo + optional mask；shading/blend/write-alpha/Perspective | 1P | 这是 image effect，不是粒子；纹理 repeat 与颜色插值需保真 | A+C |
| [Color Key](https://docs.wallpaperengine.io/en/scene/effects/effect/colorkey.html) / `colorkey` | key color、tolerance/feather、invert/flatten 生成或调整 alpha | 1P | 明确 straight/premultiplied alpha，避免透明边灰黑 | A+C |
| [Film Grain](https://docs.wallpaperengine.io/en/scene/effects/effect/filmgrain.html) / `filmgrain` | time-driven noise + optional mask；greyscale/blend variants | 1P | noise 随时间更新，mask 外不污染；使用实际 texture resolution | A+C |
| [Glitter](https://docs.wallpaperengine.io/en/scene/effects/effect/glitter.html) / `glitter` | 先生成闪烁 tile，再与 previous 合成；可选 mask | 2P；固定 256x256 R8 repeat RT | 固定 format、尺寸和 repeat 是语义，不能替换成 full RGBA surface | A+C |
| [Shimmer](https://docs.wallpaperengine.io/en/scene/effects/effect/shimmer.html) / `shimmer` | opacity mask、time-offset、gradient map；linear/mirror style | 1P | gradient、mask、time offset 分离；保留移动方向、带宽与 blend | A+C |
| [Fire](https://docs.wallpaperengine.io/en/scene/effects/effect/fire.html) / `fire` | flow map 决定火焰方向，cloud/albedo 决定形态；refract/blend variants | 1P | flow 和 albedo 是不同资源；没有对象声明不得创建 | A+C |
| [Light Shafts](https://docs.wallpaperengine.io/en/scene/effects/effect/lightshafts.html) / `lightshafts` | noise、gradient、opacity mask 的槽位依 rendering/direct-draw combo 变化 | 1P | resolver 必须按 combo 构建 slot layout，不能固定绑定表 | A+C |
| [Nitro](https://docs.wallpaperengine.io/en/scene/effects/effect/nitro.html) / `nitro` | cloud/albedo + optional mask，时间驱动静电/fizzle | 1P | 保留 repeat、颜色、blend 和强度，不降成普通 noise overlay | A+C |
| [Opacity](https://docs.wallpaperengine.io/en/scene/effects/effect/opacity.html) / `opacity` | 只调整目标区域 alpha；可选 opacity mask | 1P | exact stock `MASK=0` 已按精确 fingerprint 执行，静态/direct-binding alpha 经 per-surface snapshot live；MASK1、SceneScript 与 variants 继续 fail closed；保持预乘 RGB/alpha 关系和 effect 顺序 | A+C |
| [Reflection](https://docs.wallpaperengine.io/en/scene/effects/effect/reflection.html) / `reflection` | 动态 reflection UV、mask、方向/速度/比例；可选 Perspective | 1P | 计算局部/透视坐标，不复制整层做倒影 | A+C |
| [Tint](https://docs.wallpaperengine.io/en/scene/effects/effect/tint.html) / `tint` | 按指定 blend mode 着色，可选 mask | 1P | 不用简单 RGB multiply 代替全部模式；保留 source alpha | A+C |
| [VHS](https://docs.wallpaperengine.io/en/scene/effects/effect/vhs.html) / `vhs` | time/noise 驱动扫描、artifact、通道错位和旧磁带着色；可选 mask | 1P | 依赖 texel size 和 variant；不能输出静态噪声贴图 | A+C |
| [Water Caustics](https://docs.wallpaperengine.io/en/scene/effects/effect/watercaustics.html) / `watercaustics` | mask、Voronoi、uniform/noise、offset noise、glow 共五类额外输入 | 1P | 五槽分别解析；支持 realistic/illustrative、blend 与 Perspective | A+C |

## 6. 畸变类

| 官方名称 / asset ID | 作者语义和关键输入 | 图结构 | MyWallpaperX 实现合同 | 证据 |
|---|---|---|---|---|
| [Fisheye](https://docs.wallpaperengine.io/en/scene/effects/effect/fisheye.html) / `fisheye` | 以局部中心和 aspect 做径向畸变；background variant 控制越界 | 1P | 正确 clamp/background，不能让越界采样露灰或重复 | A+C |
| [Perspective](https://docs.wallpaperengine.io/en/scene/effects/effect/perspective.html) / `perspective` | 四点 projective square-to-quad 变换 | 1P | 使用透视插值与裁切，不能用 affine transform 近似 | A+C |
| [Refraction](https://docs.wallpaperengine.io/en/scene/effects/effect/refraction.html) / `refraction` | 先 compose layer 后方场景，再按 normal map 折射；可选 mask | Scene Compose + material pass | background、layer source 和 final scene 必须分离；错误顺序会重复背景 | A+C |
| [Skew](https://docs.wallpaperengine.io/en/scene/effects/effect/skew.html) / `skew` | Vertex/UV 两模式、四边偏移和 repeat variant | 1P | 两模式分开，越界策略服从 combo | A+C |
| [Transform](https://docs.wallpaperengine.io/en/scene/effects/effect/transform.html) / `transform` | effect-local center/offset/rotation/scale；Vertex/UV；clamp/repeat | 1P | 不写回 object transform，不改变后续 layer hierarchy | A+C |

## 7. 增强类

| 官方名称 / asset ID | 作者语义和关键输入 | 图结构 | MyWallpaperX 实现合同 | 证据 |
|---|---|---|---|---|
| [Edge Detection](https://docs.wallpaperengine.io/en/scene/effects/effect/edgedetection.html) / `edgedetection` | Sobel 邻域、threshold/color/blend | 1P | texel size 来自 source texture，不是固定 drawable | A+C |
| [God Rays](https://docs.wallpaperengine.io/en/scene/effects/effect/godrays.html) / `godrays` | threshold/downsample -> ray cast -> X/Y blur -> combine；可选 mask/noise/full-frame input | 5P；2 half RT ping-pong | 区分 local previous 与 full-frame alias；COPYBG 与方向/径向 variants 分开 | A+C |
| [Local Contrast](https://docs.wallpaperengine.io/en/scene/effects/effect/localcontrast.html) / `localcontrast` | downsample -> X/Y blur -> source 与低频图 combine；mask 在 final | 4P；2 quarter RT | RT scale/format、source/blur 槽和 final mask 都要准确 | A+C |
| [Shine](https://docs.wallpaperengine.io/en/scene/effects/effect/shine.html) / `shine` | threshold/noise -> cast -> X/Y blur -> combine；可依赖 full-frame | 5P；2 half RT ping-pong | 保留 sample/kernel/edge/blend/COPYBG variants，不降成单 pass glow | A+C |

## 8. 内部占位与命名别名

WE-compatible asset payload 还包含 `_empty` / `empty`：它是内部 passthrough 占位，没有用户官方页面。未知 effect 不能统一映射到 `_empty` 后宣称成功；必须记录 degraded/unsupported。

已确认的官方 URL 与 asset ID 别名：

| 官方 URL slug | asset ID |
|---|---|
| `sway` | `foliagesway` |
| `radialblur` | `blurradial` |
| `advancedfluidsimulation` | `fluidsimulation` |

分派身份应优先规范化 file path 和 effect instance ID，不能只依赖显示名或 `replacementkey`。观察到 `depthparallax` definition 的 `replacementkey` 异常指向 `iris`，再次说明 editor metadata 不能替代执行身份。

## 9. Parser 注意项

- `effect.json` 的 pass order、`target`、`bind{name,index}`、raw `compose`、copy/swap command、FBO `scale/fit/width/height/format/clear/unique/uvs/conditions` 都是执行字段；command 不消耗 material-pass ordinal。
- Advanced Fluid definition 的一个观察副本含 trailing comma。若合法官方 assets 也确认这一点，应在 effect-definition 专用入口做可诊断的 relaxed JSON；不能对所有 JSON 粗暴字符串替换。
- shader/material texture array 必须保留 `null` hole。
- optional mask/texture 未绑定时关闭对应 combo；不能绑定空白 texture 后仍把 combo 当 enabled。
- effect 可挂到 image、text、fullscreen、composition 等 layer，IR 不应绑定到某一种 base content；RT identity 必须包含 effect instance。raw `unique` 只声明实例唯一性，history 仍需数据流和生命周期分析。

## 10. 支持度记录格式

每个 effect 建议在诊断/测试矩阵记录：

```text
effectId
officialName
explicitReference
resolvedVisible
passCount
rtCount / formats / sizes
historyRT
sceneCompose
textureSlots and resolved providers
combos
builtins(time/pointer/audio/matrices)
supportLevel
runtimeEvidence
knownDeviation
```

`supportLevel` 至少区分：`recognized`、`graph-built`、`executed-degraded`、`semantics-verified`，不能把“识别名称”统计成效果已支持。

当前 MyWallpaperX v22 继承 EffectDefinition、authored graph/canonical SHA、provider metadata、property binding program 和 loss-preserving ShaderContract；严格匹配的 precise Blur、stock standard Blur、stock Local Contrast、exact Workshop Shadow、stock Opacity、Shake、Water Waves、Water Flow、Foliage Sway、Water Ripple 与 X-Ray 共十一类 backend 已进入 GPU。所有 strict profile 均核对 exact graph/material/shader/resource 合同；部分合法 live 值从 per-surface snapshot 消费，动态形变只消费各自受控参数与 scene time 或 pointer。fingerprint 只用于准入，实际仍执行项目内手写 MSL。当前 45 样本门为 91 stage、15 条 chain、Water Flow 10、Water Waves 11、Shake 24、0 failed；固定 13 样本门保护 24 stage、2 条 chain、Water Flow 1、Water Waves 6、Shake 1、Opacity 4、Workshop Shadow 1、failed 0。这些子集仍只能记为 `executed-degraded`。X-Ray 后接 unsupported Effect 时只允许显式受限前缀；MASK1、dynamic variants、Workshop variants、generic shader 与 Windows pixel parity 均未完成。
