# Scene Runtime 技术设计

> 历史架构快照：正文保留早期 interpretation v7 与 bounded effect 设计，不能作为当前格式或能力状态。现役 interpretation 为 v20，当前实现基线为 `b541867`，最新正式门为 `.codex/scene-effect-chain-gated-final13-20260723/report.json`；下一步 `3724289844:20` exact Workshop single-pass shadow profile 与完整实施顺序以 [`scene-capability-development-plan-2026-07-22.md`](./scene-capability-development-plan-2026-07-22.md) 和 [`../reviews/web-scene-current-state-roadmap-2026-07-19.md`](../reviews/web-scene-current-state-roadmap-2026-07-19.md) 为准。

## 0. 总线结论

Scene 是独立播放链路，不进入 Web / Video / Shell 复用层。

不要让宿主或 renderer 直接吃 Wallpaper Engine 原始 `scene.json`，链路是：

```text
scene.pkg / scene.json
  -> MyWallpaperX Scene parser
  -> .mywallpaperx-scene-interpretation.json（派生解释文件，落样本目录）
  -> Scene runtime / Metal renderer
```

兼容压力集中在解释层，宿主和 renderer 只消费稳定中间格式。

## 1. 分层职责

### `MyWallpaperX/Core/SteamWorkshopScene/`

独立 Scene runtime。负责：

- `scene.pkg` PKGV reader / 受控缓存解包
- `scene.json` / `models` / `materials` / `effects` 解析
- 资源索引、引用命中诊断
- 派生解释文件读写
- runtime model / render descriptor 构造
- Metal 渲染器（pipeline、纹理加载、effect shader、view）
- Scene 桌面宿主（desktop-level 多屏窗口 + 鼠标转发）

绝对禁止依赖 Steam 模块业务、WallpaperManager、Web 宿主。

### `MyWallpaperX/Modules/SteamWorkshop/Scene/`

Steam 模块对接：

- Scene contentType 识别
- 下载记录展示、诊断区块
- "设为壁纸" 动作通过 `NotificationCenter` 发出 `.steamWorkshopSceneReadyToRender`

绝对禁止把 Scene runtime 内核逻辑放在这里。

### `MainWindowCoordinator`

监听 `.steamWorkshopSceneReadyToRender`，从样本目录读解释文件，启动 `SceneDesktopWallpaperHost`。Video / Web / Scene 之间的切换只通过通知广播中转，不直接互相引用。

## 2. 派生解释文件契约

文件：`<样本目录>/.mywallpaperx-scene-interpretation.json`（隐藏文件，与 `project.json` / `scene.pkg` 同级，对齐 Web 链路 `.mywallpaperx-web-analysis.json` 边界）。

- `formatVersion = 7`（本文形成时的版本；包含 typed text/camera parallax、layer color blend mode，以及 effect/material nullable texture slots 与 shader combos）
- 写入：`SceneDiagnosticsBuilder.build(rootURL:)` 每次都覆盖，**删除文件后下次诊断/预览自动重建**。
- 读取：`SceneInterpretationFileReader` 严格校验版本，不兼容旧版本时由 builder 当场重生。
- 大体积资源（材质、shader、`.tex` 等解包出来的几十 MB）仍在 `~/Library/Caches/MyWallpaperX/SteamWorkshopScene/<hash>/`，**不污染下载目录**。

### `SceneRenderDescriptor` 字段约定（当时的 formatVersion 7）

- `entryPath`、`camera` (eye/center/up + orthoWidth/orthoHeight + nearZ/farZ + clearColor + clearEnabled)
- `layers[]`：id / layerIndex / name / contentKind (`image` / `particle` / `text` / `container`) / imagePath / particlePath / parentID / childLayerIDs / visible / alpha / colorBlendMode / **原始字符串 transform** (origin/size/scale/angles) / **数值 transform**（originXYZ/sizeWH/scaleXYZ/anglesXYZ）/ **modelCropOffsetXY**（来自 `models/*.json cropoffset`）/ text / hasInlineScript / effects（effect pass + typed constantShaderValues + texturePaths + 有序 nullable textureSlots + 整数 combos）/ effectFiles / texturePaths
- `rootLayerIDs` / `renderOrderLayerIDs` / `renderOrderPolicy = "source-order"`
- `modelMaterialLinks` / `materialPasses`（含 typed constantShaderValues、兼容用 texturePaths、有序 nullable textureSlots 与整数 combos）
- `shaderReferences` / `textureReferences` / `missingResources` / `builtInReferenceCount` / `firstStageRendererGaps`

renderer 只消费这个结构。如果要扩字段，**bump `formatVersion`** 并在 reader 里更新版本校验。

## 3. 坐标系约定

**Renderer 内部世界仍按 Y-down 处理，但 `scene.json` 对象 transform 不能直接裸吃**：

- root layer 的 `origin.y` 要先做 `sceneH - y`，再进入 renderer 世界。
- child layer 的局部 `origin.y` 要先取反；`angles.z` 也要取反，才能和 root 一起落到同一视觉方向。
- `scene.json` 的 `camera.eye/center` 仍相对**scene 中心** `(orthoW/2, orthoH/2)`；默认 eye=(0,0,0) 把相机放在 scene 中心、看 -Z。
- Renderer 加了一个 `cameraDepth = max(1, nearZ*10)` 沿 +Z 方向偏移，避免 layer (z=0) 落到 near clip 之前。

为了在 Metal Y-up NDC 上正确显示，渲染器做两处对称翻转：
1. `modelMatrix` 的 `sizeScale` Y 取负 — quad +Y vertex 映射到 layer 的较小 world Y（视觉顶边）。
2. `makeViewProjection` 的 ortho `top`/`bottom` 交换 — world (0,0) → NDC (-1, +1)（屏幕左上）。

Cursor 输入：`mouseNormalized` 是 NSView +Y-up 的 `[-1, +1]`，转 world 时 Y 减号，得到 Y-down world cursor。`cursorUV` 不需要 V 翻转（world Y 和 texture V 都向下）。

## 4. 纹理加载

`.tex` 容器是 Wallpaper Engine 私有格式。

- 内嵌 JPEG / PNG 的 `.tex`（多 mipmap，第一个 SOI / PNG header 在 offset ~91）：通过 `SceneTextureLoader` 扫描前 256 字节找 magic，从那里到文件末尾交给 `CGImageSource`。**搜索窗口必须限制**，否则 PNG zlib 压缩数据里随机出现的 `FF D8 FF` 会被误判为 JPEG SOI，把 PNG 文件截断后再喂 CGImageSource，必失败。
- `SceneTexContainerReader` 现在会解析 `TEXB0001/0002/0003/0004`；非 MP4 的 `TEXB0004` 按 `TEXB0003` mip 布局读取，`compression = 1` 的 mip 用 `COMPRESSION_LZ4_RAW` 解压。
- BC 压缩的 `.tex`：`format 4/7`（以及预留的 `format 5`）走 `MTLPixelFormat.bc3_rgba` / `.bc1_rgba` / `.bc5_rgSnorm` 原生上传，当前只取**第一 image / 第一 mip**。
- `format 0` `.tex` 现在按 payload 再分流：
  - mip 首字节是 PNG / JPEG magic：直接把 mip 当静态图片 payload 解码
  - mip 字节数刚好等于 `width * height * 4`：按静态 `RGBA8` raw 上传；上传前先做 CPU 侧 alpha 预乘，匹配 renderer 的 premultiplied source-over 混合
  - mip 首帧是 `ftyp...`：视为 MP4 payload，走 `AVPlayerItemVideoOutput -> CVMetalTexture` 动态纹理
  - 只有三者都不命中时才报 decode failure，避免把一批原本可读的静态 PNG payload `.tex` 误杀成 raw mismatch

CGContext 上传时**不要加** translateBy + scaleBy 翻转——`CGBitmapContext` 默认 y-up，memory row 0 = 视觉顶，draw 自然就正向了。多余的翻转会让所有内嵌图像上下颠倒。

纹理大小上限：长边 4096（`CGContext` 自动降采样上传）。8192×6144 等超大原图会被压到 4096×3072。

## 5. Metal 渲染管线

- `SceneMatrix`：simd 矩阵工具（translation/scale/rotation/lookAt/ortho），右手系 + Metal [0,1] 深度 NDC。
- `SceneMetalPipeline`：textured-quad pipeline state（内嵌 MSL），含 effect flag fragment 分支。
  - vertex buffer 0：unit quad 顶点（含 UV）
  - vertex buffer 1：MVP 4×4
  - fragment buffer 0：`SceneLayerFragmentUniforms`（time / alpha / effectFlags / cursorUV + effectParams0/1，64 字节）
  - fragment texture 1：可选的单张辅助 mask sampler（当前给 `iris` / `opacity` 复用；冲突时 `iris` 优先）
  - 混合：premultiplied source-over
- `SceneOffscreenTexturePool`：按源纹理尺寸复用一对 ping-pong `MTLTexture`，最长边等比 clamp 到 `2048`，专供多 pass / post-process layer 的中间结果。
- `SceneGaussianBlurPipeline`：coarse/precise gaussian blur 的 9-tap separable Metal pipeline，先横向再纵向采样；coarse scale 使用归一化 UV，precise scale 使用作者像素半径并按离屏纹理尺寸归一化。
- `SceneWaterRipplePipeline`：无 mask/specular waterripple 的独立 replacement pass；按 T2 normal map 做双 UV repeat 采样和作者参数位移，不与旧正弦 flag 叠加。
- `SceneEffectRuntimePlanner`：统一决定 inline flags、真实 gaussian blur/Bloom、perspective+opacity replacement 和仍为 route-only 的 offscreen effect，不再让 renderer 同时承担 effect 解析与 GPU 调度。
- `SceneMetalRenderer`：
  - 预计算所有 layer 的 worldFrame（沿 parentID 链路组合 translate+rotate+userScale；size 单独应用，避免父 scale 重缩子 quad geometry）。
  - 每帧：按 cover 规则算 view+projection，并只在 `general.cameraparallax` 声明启用时施加作者幅度的 mouse parallax → 按 `renderOrderLayerIDs` 顺序遍历 image/text layer → 算 model/effect plan → 直绘、真实 blur/Bloom 或 route-only offscreen 路径 → framebuffer。
  - 主 framebuffer 不再假设“一帧只有一个 render encoder”；命中 offscreen layer 时会先结束主 encoder，跑完离屏 pass，再用 `loadAction = .load` 继续往同一 drawable 里画，保住原图层顺序。
  - clear color 用 scene `general.clearcolor`。
- `SceneMetalView`：
  - **Layer-hosting** NSView：init 中直接 `self.layer = CAMetalLayer()` 然后 `wantsLayer = true`，避免 `makeBackingLayer()` 的 lazy 创建导致 `drawableSize` 长时间为 0。
  - 在 `init` / `setFrameSize` / `viewDidMoveToWindow` / `viewDidChangeBackingProperties` 都更新 `drawableSize`。
  - `Timer` 60fps 渲染循环，运行在 `.common` mode（菜单/拖拽时不停）。
  - `NSTrackingArea` 监听本地 mouse，归一化为 `[-1, +1]` 视图坐标；也支持宿主从 screen-space 主动注入鼠标位置。
  - `loadImageLayers(from:logURL:)`：用 `SceneTexturePathResolver` 走 layer → model → material → texture name → 实际文件路径的链路；effect 辅助纹理由 `SceneLayerEffectTextureLoader` 按声明槽位加载；可选写逐 layer 报告，并明确区分 normal/legacy waterripple、coarse/precise blur、Bloom、perspective-opacity、color blend mode 与 route-only。
- `SceneDesktopWallpaperHost`：
  - 每个 `NSScreen` 建一个透明 borderless `NSWindow`，level = `desktopWindow + 1`，contentView 挂 `SceneMetalView`，成为真实壁纸层。
  - 监听显示器变化重建 surfaces，监听 active space 变化后重新 `orderFrontRegardless()` 保持可见。
  - 因壁纸窗口必须 `ignoresMouseEvents = true`，额外用 30fps `Timer` 轮询 `NSEvent.mouseLocation` 并转发给每个 `SceneMetalView`，继续驱动 parallax / cursorripple。

## 6. 当前已实现的 effect（hand-written MSL）

不是 HLSL→MSL 转译，是给每个 effect 写一个最小视觉等价的 MSL 路径。`SceneMetalRenderer.effectFlags(for:)` 扫 `layer.effectFiles` 路径名匹配关键词，命中就 OR 进 flag。`SceneLayerFragmentUniforms.effectFlags` 是 `OptionSet`，已占用：

- `foliagesway` (bit 0)：UV 水平摆动，振幅按 (1-uv.y)² 衰减（底部锚定）
- `waterwaves` (bit 1)：UV 双轴正弦扰动；`waterripple` 路由到同一 flag
- `cursorripple` (bit 2)：以 layer-local cursor UV 为中心的环形波，距离指数衰减
- `chromaticaberration` (bit 3)：径向 3-tap RGB 偏移
- `iris` (bit 4)：第二张 mask 纹理按同 UV 采样，并用 `scale/speed/phase/rough/noiseamount` 做最小扰动后裁切可见域
- `opacity` (bit 5)：单 pass `opacity` effect 读取 mask 纹理与 `alpha` 常量，按 premultiplied 路径衰减图层颜色/alpha

Mouse parallax 不是 effect，是 view-matrix 级别的相机偏移；只在 Scene general 声明启用时应用，并读取 amount 与 mouse influence。

可见 coarse `blur` 与 `blurprecise` 已有横纵两次 9-tap gaussian GPU pass；Bloom 已有 threshold、blur 和 tint composite。无 mask/specular 的 waterripple 已按 v7 T2 槽位采样作者 normal map；默认 UV/repeat 的 perspective 与后续 opacity mask 已有 projective replacement pass，layer `colorBlendMode=9` 在最后使用 additive composite。nullable texture slots 与 combos 已保留到 v7 descriptor，但 renderer 尚未按它们执行通用材质 pass；`godrays` / `glitter` / `fluidsimulation` / `waterflow` 等仍没有真实 per-pass shader 数学，带 T1 mask 或 SPECULAR combo 的 waterripple 仍走 legacy 正弦近似。

仍未实现但样本里出现的 effect：`audioline`（需音频输入）、复杂 `opacity` / `shadow` 语义、各种 workshop 自定义 shader 数学。

## 7. 通知协议

- 名字：`.steamWorkshopSceneReadyToRender`
- userInfo:
  - `rootURL: URL` — 样本目录（含项目文件、`.mywallpaperx-scene-interpretation.json`、log）
  - `cacheDirectory: URL` — 解包后资源目录（含 `.tex` 等纹理）
- 触发：`SteamWorkshopService.requestSceneRender(_:)`（先 `SceneDiagnosticsBuilder.build()` 写解释文件，再 post）
- 接收：`MainWindowCoordinator.observeSteamWorkshopSceneReadyToRender()`

跨模块通信必须走通知。Steam 模块不要 import Core 的 Metal 渲染类。

另有一个 runtime 切换广播：

- 名字：`.wallpaperRuntimeWillSwitch`
- userInfo:
  - `kind: "video" | "web" | "scene" | "systemStill"`
- 用途：各 runtime 在真正接管桌面前先广播自己的目标类型。`SceneDesktopWallpaperHost` 收到"不是 `scene`"的切换时自行 teardown，避免 Video / Web 直接依赖 Scene 宿主。

## 8. 不变量与禁区

- 派生解释文件落样本目录（隐藏文件），解包资源落 cache 目录，不要混。
- 解释文件 `formatVersion` 改动必须配 reader 同步更新。
- Quad 模型 vertex 永远是 unit quad (-0.5..+0.5)，所有变换通过 MVP；不要在 quad 顶点里编码 layer 尺寸。
- 任何 Y 轴翻转改动必须同时考虑：texture loader / model sizeScale / ortho top-bottom / cursor world Y / cursorUV V，四者一致才不会出诡异方向问题。
- 不要让 renderer 直接读 scene.json，必须经过 `SceneInterpretationFileReader`。
- 禁止把 Scene 接入 WebView 或视频播放器作为兜底。
- Scene 切入顺序必须是：先 launch `SceneDesktopWallpaperHost`，再广播 `.wallpaperRuntimeWillSwitch(kind: scene)`；反过来会让新宿主吃到自己的 observer 后立刻 stop。

## 9. 当前 progress

当前能力、样本证据和下一阶段以 `scene-capability-development-plan-2026-07-22.md` 与 Web/Scene 现状路线图为准；`scene-support-memo-plan-2026-05-15.md` 仅保留历史交接过程。
