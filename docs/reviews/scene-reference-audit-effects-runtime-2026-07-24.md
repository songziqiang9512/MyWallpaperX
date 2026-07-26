# MyWallpaperX Scene 参考项目与官方语义证据审查

审查日期：2026-07-24  
审查方式：只读  
审查目录：`/Users/songziqiang/Documents/Development/MyWallpaperX/Reference Project`

> 使用边界：本文是研究记录，不是现役能力状态入口；与 [全量参考项目审查](scene-reference-project-audit-2026-07-24.md) 为同日互补记录（本文聚焦 effect/runtime 专题）。已转化为可执行合同的条目以现役文档为准：puppet MDLV mesh block 与 BC/TEX 二进制合同见 [场景格式与 Render Graph 第 11 节](../scene/semantics/scene-format-and-render-graph.md)，X-Ray/Water 系 strict profile 边界见 [Effect 执行覆盖表](../scene/semantics/effect-execution-coverage.md)。本文其余线索在进入实现前仍须按语义手册的证据等级交叉验证。

## 1. 文档定位

本文整理本次参考项目审查中，对 MyWallpaperX Scene 自研渲染器最有价值的资料，重点覆盖：

- 有序 Effect / Material / Pass 执行链；
- X-Ray 交互效果；
- `halo_6` 默认遮罩纹理；
- Water Ripple、Water Flow 与 Water Waves；
- 时间输入、动态文字与文字纹理；
- 视频纹理和图层混合模式；
- Scene 相机、指针与 Effect 投影；
- WaifuX、`wallpaper-wgpu`、RePKG、RenderDoc 的可用边界；

本文是参考资料与实施依据，不代表 MyWallpaperX 当前已经实现了这些能力。当前能力状态仍应以项目内 Scene capability ledger、运行证据和测试结果为准。

## 2. 核心结论

1. `linux-wallpaperengine-reference` 是参考目录中唯一可审计的 Scene 渲染器源码，但它主要负责解释 Wallpaper Engine 的 Project、Material、Shader 和 Pass，不是独立实现所有官方 Effect 算法。
2. X-Ray、Water Ripple、Water Flow、通用混合模式等精确算法，实际来自 WaifuX `zip_data.o` 中的 stock shader/material 资源。
3. WaifuX 的 `wallpaper-wgpu` 只有预编译 arm64 二进制，没有 Rust/Cargo 源码，不能用于源码移植，也不能把二进制字符串直接提升为官方语义。
4. 最值得借鉴的是“数据结构、执行顺序、纹理槽位、矩阵和像素行为”。
5. MyWallpaperX 应以样本配置、封面/预览和可观察输出固定行为合同，再以代码和测试实现。

## 3. 证据等级

| 等级 | 含义 | 用途 |
| --- | --- | --- |
| A | 官方/真实样本配置、资源或可重复运行结果直接证明 | 可进入行为合同 |
| B | 多处第三方开源实现与样本数据相互印证 | 可作为高价值实现线索 |
| C | 单一第三方实现或不透明二进制线索 | 只能生成待验证假设 |
| D | 未经样本或源码证实的推测 | 不应进入兼容声明 |

`zip_data.o` 内资源与真实样本缓存文件 hash 完全一致时，可以证明它们是同一份 stock payload。

## 4. 参考项目概况

### 4.1 linux-wallpaperengine-reference

- 路径：`/Users/songziqiang/Documents/Development/MyWallpaperX/Reference Project/linux-wallpaperengine-reference`
- 审查提交：`b016d7d1fdcf4e5fd2f9c9fa420a8aaa07fee02d`
- 价值：Project/Material/Effect 解析、有序 pass、FBO、纹理覆盖链、固定渲染状态、时间/鼠标输入。
- 限制：部分语义存在 TODO、退化或明确错误，不能把该项目等同于 Wallpaper Engine 官方标准。

### 4.2 WaifuX-main

- 路径：`/Users/songziqiang/Documents/Development/MyWallpaperX/Reference Project/WaifuX-main`
- 价值：renderer 启动协议、属性/画布/裁切输入、内嵌 stock assets、烘焙 sidecar 和宿主生命周期。
- 限制：核心 Scene renderer 是预编译二进制。

`wallpaper-wgpu` 两份副本：

- `WaifuX-main/wallpaper-wgpu`
- `WaifuX-main/Resources/wallpaper-wgpu`
- SHA-256：`0c170c6830227dc6b29e0dc3054e3cc858a493cc4f6756192a1da488b19dec6d`
- 格式：Mach-O arm64
- 签名：ad-hoc
- 源码：参考目录内不存在 `Cargo.toml` 或 `.rs` 源码

`scripts/build-wallpaper-wgpu.sh:61-83` 明确只是从外部路径复制预编译 renderer，不是构建 renderer 源码。

### 4.3 RePKG

- 路径：`/Users/songziqiang/Documents/Development/MyWallpaperX/Reference Project/repkg-master`
- 价值：PKG 目录表、TEX header、mipmap、LZ4、DXT1/3/5 解码。
- 限制：没有 Effect、Shader、SceneScript、混合或相机语义。

## 5. 有序 Effect / Material / Pass 执行链

### 5.1 精确源码证据

`ObjectParser::parseEffects`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/ObjectParser.cpp`
- 行：`192-203`
- 行为：按 Scene JSON `effects` 数组原顺序追加，不排序、不合并。

`EffectParser::parseEffectPasses`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/EffectParser.cpp`
- 行：`48-79`
- 行为：按 effect 文件中的 `passes` 数组原顺序解析 material、bind、command、source 和 target。

`MaterialParser::parsePasses`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/MaterialParser.cpp`
- 行：`25-56`
- 行为：保留 material pass 顺序，并解析每个 pass 的 shader、texture、usertexture、combo、constant 和渲染状态。

`CImage::setup`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CImage.cpp`
- 行：`627-720`
- 行为：依次展平 base material passes、每个 effect、每个 effect pass 和 material 内部 passes。

`CImage::setupPasses`

- 文件：同上
- 行：`784-851`
- 行为：为每个 pass 连接 input、previous、target FBO、最终 Scene FBO 和 ping-pong。

`TextureParser::parseTextureMap`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/TextureParser.cpp`
- 行：`125-153`
- 行为：数组中的 `null` 不创建纹理记录，但仍递增纹理 slot，不能压缩稀疏槽位。

`CPass::setupTextureUniforms`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp`
- 行：`697-846`
- 行为：建立 shader default、material、usertexture、override、bind 的纹理候选链。
- `bind` 最后写入，优先级最高。
- 不可用资源会继续尝试较低优先级候选。

### 5.2 可移植语义

MyWallpaperX 可独立实现：

1. 有序 effect graph；
2. effect 内有序 pass；
3. material 内有序 pass；
4. 稀疏 texture slot；
5. explicit target、previous、copy、swap；
6. 无 target pass 的 ping-pong；
7. 每 pass 独立的 blend/depth/cull 状态；
8. 最终 pass 输出到 Scene framebuffer。

### 5.3 不应直接复制

- GPL C++ 类型和控制流；
- `CPass`、`CImage`、`FBOProvider` 的类结构；
- 原项目的错误字符串、宏和 shader 预处理代码；
- 参考项目里的 TODO 或退化行为。

## 6. X-Ray

### 6.1 stock 资源路径

容器：

`/Users/songziqiang/Documents/Development/MyWallpaperX/Reference Project/WaifuX-main/Resources/zip_data.o`

内部文件：

- `assets/effects/xray/effect.json`
- `assets/effects/xray/materials/effects/xray.json`
- `assets/effects/xray/shaders/effects/xray.vert`
- `assets/effects/xray/shaders/effects/xray.frag`

对应 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| `effect.json` | `745a3ed8cdeb268f9eb6cf3a127f9928f19b720656c31711ff81ac21c51fb8e4` |
| `xray.json` | `79b16f1ff55144ad29c216ef7c80b825fb277d521e687cf46c15773a107b254f` |
| `xray.vert` | `5d4e6a303e1d10b417b352dd2f06040ae8f2328dbd1ba3d3a666e5d572d90039` |
| `xray.frag` | `d884d586e20bca2ecf2bef48280da1d4e226d1116010f642fe36de944c2e7525` |

这些文件与隔离样本 `3757555836` 的解析缓存文件 hash 完全一致。

### 6.2 纹理槽位

`xray.frag:16-19`：

| Uniform | 语义 |
| --- | --- |
| `g_Texture0` | 当前 effect chain 输入 |
| `g_Texture1` | 鼠标区域内显示的下层/替代画面 |
| `g_Texture2` | 指针 sprite，默认 `particle/halo_6` |
| `g_Texture3` | 可选 opacity mask |

`xray.frag:44-45` 对 `g_Texture2` 读取 `.ra`，实际权重是：

`sprite.r * sprite.a`

因此不能只读取 alpha，也不能把 `null` slot 压缩后错误地把 opacity mask 绑定到 slot 2。

### 6.3 指针与投影

`xray.vert:35-40`：

1. 将指针 Y 翻转到 texture space；
2. 将 `[0,1]` 指针坐标转为 clip space；
3. 通过 `g_EffectTextureProjectionMatrixInverse` 反投影；
4. 除以齐次坐标；
5. 使用 `g_Texture0Resolution` 校正源纹理纵横比；
6. 依据 `g_PointerScale` 缩放指针 sprite。

`xray.frag:31-45`：

1. 完成逐像素反投影；
2. 计算当前源像素与指针中心的相对坐标；
3. 映射到指针 sprite UV；
4. 用 sprite 和 opacity mask 调制 blend；
5. 以 `BLENDMODE` 将替代画面混入原画。

### 6.4 Linux 参考实现的关键错误

`CPass::setupUniforms`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp`
- 行：`881-882`

该实现将：

- `g_EffectTextureProjectionMatrix`
- `g_EffectTextureProjectionMatrixInverse`

都固定为单位矩阵。

这意味着它不能正确处理带旋转、缩放、裁切、非全屏位置或中间 render target 的 X-Ray。该处只能证明 uniform 名称存在，不能作为正确投影实现。

### 6.5 真实样本顺序

`3757555836`：

- 图层 `兰汤春酽_原画` 的 effects 顺序为：
  1. X-Ray
  2. Water Flow
  3. Water Ripple
  4. Water Flow
  5. Shake
- X-Ray texture override：`[null, "兰汤春酽_原画h", null]`
- slot 2 为 `null`，必须回退到 stock default `particle/halo_6`。

`2998757800`：

- X-Ray 位于四个 Shake 和一个 Foliage Sway 之后；
- texture override：
  `[null, "人物-表情r18-1", null, "masks/xray_mask_0b95b6e9"]`
- X-Ray 必须读取前面 deformation effects 的输出，而不是原始纹理。

### 6.6 MyWallpaperX 实现建议

可以独立实现：

- 当前 pass 的 model/view/projection；
- effect texture projection 及 inverse；
- viewport/crop 到 Scene UV 的指针映射；
- `R*A` 指针遮罩；
- slot 1 blend texture；
- slot 3 opacity mask；
- X-Ray 在 authored effect chain 中的真实顺序。

不应直接打包：

- 原始 `xray.vert` / `xray.frag`；
- 官方 `halo_6.tex`；
- WaifuX 内嵌 asset payload。

## 7. `halo_6`

内部路径：

- `assets/materials/particle/halo_6.tex`
- `assets/materials/particle/halo_6.tex-json`

SHA-256：

`2959d59e983754e09a14ef25115ca4259857eef21bb70cf001ae0013a01376f6`

metadata：

```json
{
  "format": "rgba8888",
  "clampuvs": true,
  "nomip": true
}
```

语义结论：

- `halo_6` 是 X-Ray 默认鼠标遮罩 sprite；
- 采样应 clamp；
- 不使用 mipmap；
- 其 R 和 A 通道共同决定权重；
- 它不是 Scene 中普通粒子系统的 `halo_6` 特例。

发布时更稳妥的方案：

1. 从用户合法拥有的 Wallpaper Engine 安装资源中运行时解析；
2. 或生成 MyWallpaperX 自有、视觉等价的软遮罩；
3. 不直接复制和重新分发原始 TEX。

## 8. Water Ripple

stock 路径：

- `assets/effects/waterripple/effect.json`
- `assets/effects/waterripple/materials/effects/waterripple.json`
- `assets/effects/waterripple/shaders/effects/waterripple.vert`
- `assets/effects/waterripple/shaders/effects/waterripple.frag`
- `assets/effects/waterripple/materials/effects/waterripplenormal.*`

### 8.1 核心算法

`waterripple.vert:42-54`：

- 生成两组 UV；
- 两组 UV 沿相反时间方向滚动；
- animation speed 和 scroll speed 都使用平方；
- 依据源纹理 aspect ratio 与用户 `ratio` 修正。

`waterripple.frag:61-65`：

1. 对 normal texture 采样两次；
2. 从 `[0,1]` 转为 `[-1,1]`；
3. 将两组 XY normal 相加；
4. 归一化；
5. 以 `normal.xy * strength² * mask` 扭曲源 UV。

可选 specular 在 `waterripple.frag:69-75` 根据 normal、方向、power、strength 和 color 增亮。

### 8.2 Perspective 模式

`waterripple.vert:56-57` 调用：

`inverse(squareToQuad(point0, point1, point2, point3))`

这属于 effect-local 四边形单应变换，不是 Scene perspective camera。

### 8.3 样本证据

`1937925563` 的 `effects/waterripple/effect.json` 与 stock 文件相比，仅删除：

- `replacementkey`
- 编辑器 `gizmos`

运行 pass、dependencies、material 和 shader 不变，因此 stock Ripple 数学可用于该样本的行为合同。

## 9. Water Flow

stock 路径：

- `assets/effects/waterflow/effect.json`
- `assets/effects/waterflow/materials/effects/waterflow.json`
- `assets/effects/waterflow/shaders/effects/waterflow.vert`
- `assets/effects/waterflow/shaders/effects/waterflow.frag`
- `assets/effects/waterflow/materials/effects/waterflowphase.*`

### 9.1 核心算法

`waterflow.vert:22-35`：

- 生成四个周期：
  - `time * speed`
  - `time * speed + 0.5`
  - `time * speed + 0.25`
  - `time * speed + 0.75`
- 周期减去 `0.5` 后用于双向 UV 偏移；
- 使用 `smoothstep` 和 `g_PhaseFeather` 平滑切换。

`waterflow.frag:18-36`：

1. 从 `g_Texture2` 读取 phase；
2. 从 `g_Texture1.rg` 读取 flow vector；
3. 以 `0.498` 为中性值；
4. flow vector 乘 `strength * 0.1`；
5. 对源纹理进行两组双周期采样；
6. 先按周期 blend，再按 phase texture blend；
7. 最后按 flow vector 长度混回原图。

### 9.2 纹理槽位

`waterflow.json` 默认 texture 数组：

`[null, null, "effects/waterflowphase"]`

- slot 0：effect 输入；
- slot 1：作者 flow map；
- slot 2：默认 phase texture。

必须保留 `null` 对应的稀疏索引。

## 10. Water Waves 不是 Ripple

独立 stock 路径：

- `assets/effects/waterwaves/effect.json`
- `assets/effects/waterwaves/materials/effects/waterwaves.json`
- `assets/effects/waterwaves/shaders/effects/waterwaves.vert`
- `assets/effects/waterwaves/shaders/effects/waterwaves.frag`

Water Waves、Water Ripple、Water Flow 应保留为三个独立 semantic backend。不能因为最终都表现为水面扭曲，就合并成同一套近似参数。

## 11. 时间、动态文字与文字纹理

### 11.1 全局时间输入

`WallpaperApplication.cpp:879-887`：

```text
g_Daytime = (hour * 60 + minute) / (24 * 60)
g_Time = renderTime
```

`CPass.cpp:869-870` 将二者绑定到 shader。

结论：

- `g_Time` 是渲染时间；
- `g_Daytime` 是本地一天中的归一化时间；
- 两者不能替代 SceneScript 的 `Date` 语义；
- clock text 的实际内容仍需要脚本执行。

### 11.2 stock font material

`zip_data.o` 内：

- `assets/materials/fonts/basefont.json`
- `assets/materials/fonts/basefontrgba.json`
- `assets/shaders/font.vert`
- `assets/shaders/font.frag`

`font.frag`：

- 普通字体从 R8 texture 读取 coverage；
- `COLORFONT` 模式读取 RGBA texture；
- 最终颜色由 `g_Color4` 和 coverage 合成；
- material 使用 `translucent` blending。

### 11.3 Linux CText 可借鉴部分

`CText::rebuildTextureFrom`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CText.cpp`
- 行：`231-301`
- 行为：FreeType 两阶段测量和栅格化，生成单张 R8 glyph texture。

`CText::render`

- 文件：同上
- 行：`373-403`
- 行为：每帧 tick SceneScript；仅当文本或 pixel size 改变时重建纹理。

可借鉴：

- 脚本每帧运行；
- 纹理只在内容变化时更新；
- glyph coverage 使用单通道纹理；
- 动态文字与普通渲染帧生命周期分离。

不可作为最终实现：

- 按 `unsigned char` 遍历 UTF-8；
- 仅支持单行；
- 无 shaping、kerning、换行、ellipsis；
- 使用独立直绘 shader；
- 不经过 text object 自己的 effects。

### 11.4 `3750813609` 的直接证据

隔离缓存 Scene：

`/Users/songziqiang/Documents/Development/MyWallpaperX/.codex/scene-legacy-compose-20260724/full26-results-pass3/runtime-homes/3750813609/Library/Caches/MyWallpaperX/SteamWorkshopScene/fe5e02873c21e0b8/scene.json`

Clock text object 包含：

- alpha：`0.7`
- 自定义字体：`fonts/SairaExtraCondensed-Light.ttf`
- 设计时文本：`12:34`
- SceneScript：调用 `new Date()`、`getHours()`、`getMinutes()`、可选秒；
- Effect 1：Blur；
- Effect 2：Clouds。

这说明：

1. `12:34` 只是编辑器占位值，不能直接固定播放；
2. 动态时间必须由 SceneScript 更新；
3. 文字首先生成 texture；
4. Blur 和 Clouds 必须作用于文字 texture；
5. “文字内部动态云层”不能通过 DOM overlay 或普通白色文本模拟。

### 11.5 WaifuX 动态文字只可作为宿主参考

`Services/WallpaperDynamicTextParser.swift:5-10` 明确说明：

- 只读取 SceneBakes 同名 sidecar JSON；
- 不从原始 Scene/PKG 推导；
- 播放 MP4 时额外叠加 dynamic text overlay。

`Resources/scene-bake-web-template/index.html`：

- 用 DOM/CSS 显示动态文字；
- 以名称、脚本字符串和格式做行为检测；
- 每秒或每分钟更新时钟/日期。

它可用于理解宿主如何保持烘焙视频上的时钟更新，但不能作为官方 text renderer：

- 无真实 glyph texture；
- 无 text effect chain；
- 无云层填充、blur target 和 authored pass；
- CSS 排版与 WE Scene 坐标/字体行为不完全一致。

### 11.6 MyWallpaperX 实现方向

1. 用 CoreText/CTLine/CTFramesetter 做 Unicode shaping；
2. 栅格化为 R8 或 RGBA Metal texture；
3. 保留字体、字号、alignment、spacing、padding、width/row limit；
4. SceneScript 更新文本后按需重建 texture；
5. 把 text texture 接入与 image layer 相同的 authored effect chain；
6. 最终按 stock font 的 translucent 语义合成。

## 12. 视频纹理和混合模式

### 12.1 视频首先是普通纹理

`CTexture`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/CTexture.cpp`
- 行：`19-42`
- 行为：当 TEX 标记为 video 时，将视频数据交给播放器并更新普通 GL texture。

因此视频层不应另建一套简化合成器。正确模型是：

`视频解码帧 -> 普通 Scene texture -> material/effect/pass -> layer composition`

### 12.2 固定管线 blending

`CPass::setupRenderFramebuffer`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp`
- 行：`121-178`

映射：

| Material blending | 行为 |
| --- | --- |
| `normal` | source 覆盖 destination |
| `translucent` | source alpha / one-minus-source-alpha |
| `additive` | source alpha / one |

这是 pass render state，不等同于 `colorBlendMode`。

### 12.3 `colorBlendMode`

`ObjectParser.cpp:161` 读取 image object 的 `colorBlendMode`。

`CImage.cpp:750-766`：

1. 加载 `materials/util/effectpassthrough.json`；
2. 设置 `BLENDMODE` combo；
3. 追加一个额外 pass。

stock 文件：

- `assets/materials/util/effectpassthrough.json`
- `assets/shaders/genericimage3.vert`
- `assets/shaders/genericimage3.frag`
- `assets/shaders/common_blending.h`

`genericimage3.frag:60-61`：

- `g_Texture4` 默认绑定 `_rt_FullFrameBuffer`。

`genericimage3.frag:285-289`：

1. 读取已经合成的 Scene 背景；
2. 调用 `ApplyBlending`；
3. 保留背景 alpha。

### 12.4 混合模式映射

`common_blending.h:172-270` 定义 0-32：

| ID | 关键模式 |
| --- | --- |
| 0 | Normal fallback |
| 1 | Darken |
| 2 | Multiply |
| 3 | Color Burn |
| 6 | Lighten |
| 7 | Screen |
| 8 | Color Dodge |
| 9 | Add |
| 10 | Max/Lighten |
| 11 | Overlay |
| 12 | Soft Light |
| 13 | Hard Light |
| 18 | Difference |
| 19 | Exclusion |
| 26 | Hue |
| 27 | Saturation |
| 28 | Color |
| 29 | Luminosity |
| 30 | Tint |
| 31 | `A + B * opacity` |
| 32 | `mix(A, A + A * B, opacity)` |

### 12.5 Metal 实现要求

Screen、Color Dodge、Overlay 等不能只设置 Metal fixed-function blend state，因为 shader 必须读取已有背景像素。

推荐：

1. 保持完整 Scene color texture；
2. 当前 layer/effect 输出为 foreground texture；
3. 将 Scene color 和 foreground 作为两个 shader 输入；
4. 写入另一个 render target；
5. 完成后交换 Scene color target。

不要在同一 texture 上同时读写，也不要把这些模式降级为统一 alpha blend。

### 12.6 `3747492842` 的谨慎结论

该样本左侧 `leftpic` material：

`materials/3月22日(1).json`

声明：

- shader：`genericimage4`
- blending：`translucent`
- usertexture：`leftpic`

目前没有 Scene JSON 证据证明它使用 `colorBlendMode=7` 或 `10`。因此不能仅凭肉眼“像滤色/亮色”就硬编码 Screen。应先确认：

- `leftpic` 实际像素 alpha；
- user texture 是否为视频；
- `genericimage4` combo；
- 上下层顺序；
- 是否有其他 effect 修改。

## 13. Scene 相机、指针和 Effect 投影

### 13.1 Scene camera

`WallpaperParser::parseScene`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/WallpaperParser.cpp`
- 行：`24-80`
- 行为：要求 `orthogonalprojection`，同时解析 eye、center、up、near、far、fov。

`CScene`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Wallpapers/CScene.cpp`
- 行：`37-74`
- 行为：auto projection 根据 image layer extent 推导宽高，随后仍调用正交投影。

`Camera::setOrthogonalProjection`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Camera.cpp`
- 行：`42-51`
- 行为：唯一 Scene projection 实现是 `glm::ortho`。

结论：

- 该参考实现没有通用 perspective camera；
- 读取 `fov` 不等于已经执行 perspective；
- 不能据此声明官方 perspective camera 已覆盖。

### 13.2 指针到 Scene UV

`CScene::updateMouse`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Wallpapers/CScene.cpp`
- 行：`364-391`

行为：

1. viewport 像素位置归一化；
2. 应用当前 fill/fit crop UV；
3. 保留 current 和 last pointer；
4. 处理 shader 所需的 Y 方向。

这部分是 X-Ray、鼠标遮罩、交互粒子和 cursor SceneScript 的公共依赖。

### 13.3 每层 MVP 与 inverse

`CImage::updateScreenSpacePosition`

- 文件：`linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CImage.cpp`
- 行：`1094-1127`

组合：

- layer rotation；
- camera projection；
- camera look-at；
- parallax；
- MVP inverse。

MyWallpaperX 应在每帧、每层、每个实际 pass 输出空间中维护明确矩阵，不能将所有 effect 统一为 Scene identity projection。

### 13.4 Effect-local perspective

`assets/shaders/common_perspective.h` 中的 `squareToQuad` 是标准四点 homography，用于 Ripple 等 effect 的 perspective UV。

它与 Scene perspective camera 是两件事：

- Scene camera 决定世界到屏幕；
- Effect homography 决定纹理局部四边形映射。

## 14. RePKG 可复用范围

### 14.1 可直接参考的 MIT 源码

`PackageReader`

- 文件：`repkg-master/RePKG.Application/Package/PackageReader.cs`
- 行：`13-61`
- 语义：读取 entry count、path、offset、length，并按 data section 起点定位 payload。

`TexReader`

- 文件：`repkg-master/RePKG.Application/Texture/TexReader.cs`
- 行：`38-59`
- 语义：验证 `TEXV0005` / `TEXI0001`，读取 header、images 和 GIF frame info。

`TexMipmapDecompressor`

- 文件：`repkg-master/RePKG.Application/Texture/TexMipmapDecompressor.cs`
- 行：`10-49`
- 语义：
  - LZ4 解压；
  - DXT1/3/5 解码；
  - 转为 RGBA8888。

### 14.2 与本次渲染目标无关的部分

RePKG 不提供：

- Effect chain；
- shader preprocessing；
- blend mode；
- text effect；
- SceneScript；
- camera；
- particle simulation。

因此它只能帮助格式层，不能解决显示效果差异。

## 15. RenderDoc 可用范围

RenderDoc 的价值主要是：

- 在受支持 API 上查看 render pass；
- 检查纹理、shader uniform、draw call；
- 查看 pixel history。

但当前参考版本：

- 支持表不包含 macOS；
- Metal 标记为 N/A；
- 不能直接抓取 MyWallpaperX Metal 帧作为主要工具；
- 更不能提供 Wallpaper Engine 官方语义。

在 macOS 上应优先使用：

- Xcode Metal Frame Capture；
- GPU Counters；
- 自有 pass trace；
- 离屏纹理导出；
- 固定像素 probe 和截图差异。

## 16. 推荐开发顺序

### P0：公共有序执行链

先完成：

- object effect 顺序；
- effect pass 顺序；
- material pass 顺序；
- sparse texture slots；
- texture override/default/bind 优先级；
- target/previous/copy/swap；
- ping-pong；
- 每 pass render state。

验收：

- 自有三 pass fixture 的 trace 和最终像素严格一致；
- `null` slot 不发生位移；
- 多 effect 顺序改变时输出必须可观察地改变。

### P1：X-Ray

实现：

- live pointer；
- viewport/crop 映射；
- effect projection/inverse；
- slot 1/2/3；
- `R*A` sprite；
- authored blend mode；
- ordered chain 输入。

关键样本：

- `3757555836`
- `2998757800`

验收：

- 鼠标移动时遮罩跟随；
- 替代画面只在遮罩内出现；
- opacity mask 生效；
- 旋转/缩放/非全屏图层坐标正确；
- 不出现整层切换或 identity projection 偏移。

### P2：Water Ripple / Flow / Waves

分别实现三个 backend，不合并。

验收：

- Ripple 双 normal 滚动和 `strength²`；
- Flow `0.498` 中性值、四周期、phase blend；
- perspective quad；
- mask 和 aspect correction；
- 真实样本动态像素差。

关键样本：

- `1937925563`
- `3738202317`
- `3767343314`
- `3757555836`

### P3：Scene framebuffer-aware blend

实现：

- normal/translucent/additive fixed state；
- `colorBlendMode` shader composition；
- Scene color target ping-pong；
- Screen、Color Dodge、Add、Lighten 的像素合同。

验收：

- 1x1 和 2x2 自有色块测试；
- foreground alpha 为 0、0.5、1；
- 背景 framebuffer 不被错误覆盖；
- 视频帧与图片使用同一合成路径。

### P4：动态文字纹理与文字 effect chain

实现：

- CoreText Unicode shaping；
- SceneScript Date/time；
- 内容变化时更新 texture；
- text object authored effects；
- blur/clouds 等作用于 glyph texture。

关键样本：

- `3750813609`

验收：

- 不再固定显示 `12:34`；
- 时间按脚本属性更新；
- 半透明白色文字正确；
- Clouds 在文字内部动态变化；
- Blur 与 Clouds 顺序正确；
- 中文和自定义字体不乱码。

### P5：统一相机与 Effect 坐标

实现：

- scene orthographic projection；
- auto projection；
- fill/fit crop；
- layer model matrix；
- pointer scene UV；
- pass output-space projection；
- effect-local homography。

验收：

- 16:9 和非 16:9 viewport；
- fill/fit；
- 旋转层；
- parallax；
- offscreen target；
- X-Ray 和 perspective Ripple 坐标一致。

## 18. 建议的自有测试

1. 三个常量色 shader 的严格 pass 顺序测试。
2. `[null, red, null, green]` 的 sparse texture slot 测试。
3. shader default、material、usertexture、override、bind 五级优先级测试。
4. target + previous + ping-pong 的离屏像素测试。
5. X-Ray 中心、边缘、超出范围和 opacity mask 测试。
6. X-Ray 旋转层和 crop viewport 测试。
7. Ripple 双 normal 相位和 `strength²` 测试。
8. Flow `0.498` 中性 flow map 测试。
9. Screen/Color Dodge/Add/Lighten 的固定 RGBA 测试。
10. UTF-8、中文、kerning、换行和 ellipsis 文字测试。
11. 动态 clock script 的时间注入测试。
12. text texture 经过 Blur -> Clouds 的 ordered chain 测试。
13. 16:9 与 MacBook Pro viewport 的 projection/crop 坐标测试。
14. 每个 effect pass 的输入、输出、uniform 和 render target trace。

## 19. 最终判断

参考项目对 MyWallpaperX 最有价值的不是“把另一个 renderer 搬进来”，而是帮助确定以下事实：

- Scene Effect 必须严格有序；
- stock default texture 和 sparse slot 是兼容核心；
- X-Ray 依赖正确的 effect-space inverse projection；
- Ripple、Flow、Waves 是不同算法；
- 高级图层混合依赖 Scene framebuffer；
- 视频只是动态纹理，不能绕过通用 material/effect chain；
- 动态文字必须先形成 texture，再执行 text effects；
- Scene camera、crop、pointer 和 effect projection 必须统一在同一坐标合同下。

这些事实足以指导自研 Metal 引擎的下一阶段，但不足以授权复制 GPL 实现或官方资源。后续开发应继续以真实隔离样本、封面/GIF、可重复像素证据和自有 fixture 为准。
