# Scene 壁纸支持 — 进度与下一阶段计划

> 历史交接快照：正文保留 2026-05 至 2026-06 的实现过程和当时样本结论，不作为当前本地样本、自动门或下一步的现役答案。当前执行计划见 [`scene-capability-development-plan-2026-07-22.md`](./scene-capability-development-plan-2026-07-22.md)，当前能力结论见 [`../reviews/web-scene-current-state-roadmap-2026-07-19.md`](../reviews/web-scene-current-state-roadmap-2026-07-19.md)。
>
> 配套技术设计：[`scene-runtime-design-2026-05-15.md`](./scene-runtime-design-2026-05-15.md)。
> 工程目标：在 MyWallpaperX 内做出一套可维护、可诊断、可扩展的**独立 Scene 播放系统**，与现有 Video / Web 链路完全区分。
> 不承诺 100% 复刻 Wallpaper Engine。

---

## 1. 当前状态（交接时点）

### 1.1 已落地

**Core (`MyWallpaperX/Core/SteamWorkshopScene/`)**

| 文件 | 职责 |
|---|---|
| `SceneProject.swift` | `project.json` → Scene 项目识别（`type` 大小写不敏感），定位 `scene.pkg` |
| `ScenePkgReader.swift` | 原生 PKGV reader（已验证 PKGV0023），按 entry 读数据 |
| `ScenePkgCacheExtractor.swift` | 受控缓存解包到 `~/Library/Caches/MyWallpaperX/SteamWorkshopScene/<hash>/`；白名单含 `materials/` `models/` `shaders/` `effects/` `particles/` `fonts/` `img/` `images/` `textures/` + `.png/.jpg/.jpeg` 扩展名 |
| `ScenePkgExtractionReport.swift` | 解包状态描述 |
| `SceneDocument.swift` | 解析 scene.json：camera (eye/center/up) + general (ortho width/height、clearcolor、nearz/farz、clearenabled) + objects (含 typed transform、effect、constantshadervalues) |
| `SceneResourceIndex.swift` | 目录资源索引（shader、material、model、texture、particle、font、script 分类） |
| `SceneResourceReferenceIndex.swift` | scene.json 引用 → 索引/缓存的路径解析；`models/util/*` 归为内置引用 |
| `SceneAssetCatalog.swift` | `models/*.json` + `materials/*.json` 摘要，含 material path、autosize、`cropoffset` 与每个 material pass 的 typed constantShaderValues |
| `SceneCapabilityProfile.swift` | 第一阶段能力缺口诊断 |
| `SceneRenderDescriptor.swift` | renderer 输入描述。`formatVersion 3` 起含 `CameraDescriptor` + per-layer 数值 transform + `modelCropOffsetXY` |
| `SceneInterpretationFile.swift` | 派生解释文件读/写/版本校验，文件名 `.mywallpaperx-scene-interpretation.json`（隐藏，落样本目录） |
| `SceneDiagnostics.swift` | 汇总诊断报告，**每次 build 都覆盖写解释文件**（丢失自动重生） |
| `SceneRuntimeModel.swift` | runtime / playback / input / timeline / shader 骨架；从解释文件优先加载 render descriptor |
| `SceneMatrix.swift` | simd 矩阵工具（translation / scale / rotation / lookAt / ortho），右手系 Metal NDC |
| `SceneTextureLoader.swift` | `.png/.jpg/.jpeg` + `.tex` 内嵌 JPEG/PNG + BC1/BC3 + `format 0` 三分流（PNG/JPEG payload / static raw RGBA8〔上传前做 alpha 预乘〕 / MP4 payload，预留 BC5）加载；`TEXB0003/0004` mip 表解析、`COMPRESSION_LZ4_RAW` 解压、4096 像素长边降采样；**不**做 CGContext Y 翻转 |
| `SceneTexturePathResolver.swift` | layer→model→material→texture-name→实际 URL 解析链路 |
| `SceneMetalPipeline.swift` | textured-quad pipeline state + 内嵌 MSL（MVP + 4 个内嵌 effect 路径）|
| `SceneOffscreenTexturePool.swift` | 复用型 offscreen ping-pong 纹理池（按源纹理等比 clamp 到最长边 2048） |
| `SceneMetalRenderer.swift` | per-layer model matrix + 相机投影 + parent 链路 + effect flag 派发 + 多 encoder 离屏骨架 |
| `SceneMetalView.swift` | layer-hosting CAMetalLayer NSView + 60fps Timer 循环 + 本地 mouse tracking / 外部 screen-space mouse 注入 + 加载诊断 log（含 offscreen route 标注） |
| `SceneDesktopWallpaperHost.swift` | 每屏一个 desktop-level `NSWindow` 的真实 Scene 壁纸宿主；负责多显示器重建、space 切换重挂、30fps 鼠标轮询转发，以及在 runtime 切走时自 teardown |

**Steam 模块 (`MyWallpaperX/Modules/SteamWorkshop/Scene/`)**

| 文件 | 职责 |
|---|---|
| `SteamWorkshopSceneDownloadRecord+Scene.swift` | 下载记录 Scene 字段扩展 |
| `SteamWorkshopSceneService+SceneDetection.swift` | Scene contentType 识别（按 type/file/scene.pkg/workshopType 兜底） |
| `SteamWorkshopSceneService+SceneDiagnostics.swift` | 详情页诊断摘要 |
| `SteamWorkshopSceneService+ScenePlayback.swift` | "设为壁纸" 动作：调诊断 → 发 `.steamWorkshopSceneReadyToRender` 通知 |
| `SteamWorkshopSceneDetailModels.swift` / `SteamWorkshopSceneDetailSection.swift` | 详情页 Scene 区块 |

**Shared (`MyWallpaperX/Shared/UI/WallpaperRuntimeSwitch.swift`)**

- `WallpaperRuntimeKind`：当前定义 `video / web / scene / systemStill`
- `.wallpaperRuntimeWillSwitch`：不同 runtime 切换前的广播中转，避免 Scene / Video / Web 直接互相引用

**App 集成 (`MyWallpaperX/App/MainWindowCoordinator.swift`)**

- `observeSteamWorkshopSceneReadyToRender()`：读解释文件 → 启动 `SceneDesktopWallpaperHost` → 广播 `.wallpaperRuntimeWillSwitch(kind: scene)` → 清空 `WallpaperManager` 的视频引用并停掉旧 `WallpaperEngine`
- `observeSteamWorkshopWebWallpaperReadyToPlay()` / `WallpaperManager.setAsWallpaper(...)` 分别在 Web / Video 真正接管前发 runtime switch，保证 Scene 宿主能自行退出

### 1.2 已实现的视觉效果

- 静态 image layer 渲染（按 origin/size/scale/angles + parent 链路 + camera ortho 投影）
- 子图层相对父图层定位（parent frame 沿链组合）
- renderer 内部维持 Y-down 世界，但 `scene.json` 对象 transform 现已在进入 world frame 前做 root `sceneH - y` / child `-y` / `angles.z` 取反的坐标对齐
- `models/*.json` 的 `cropoffset` 已进入解释文件，当前先保留为诊断字段，不在 renderer 里额外补偿，避免把已编码进对象 `origin` 的裁切位移再推一次
- 内嵌 JPEG/PNG `.tex` 解码
- 4 个 inline effect（命名匹配 `layer.effectFiles` 路径）：
  - `foliagesway`：UV 水平摆动（底部锚定）
  - `waterwaves` / `waterripple`：UV 双轴正弦
  - `cursorripple`：cursor 周围环形波
  - `chromaticaberration`：径向 3-tap RGB
- `iris`：第二张 `R8` mask 纹理按同 UV 采样，并读取 `scale/speed/phase/rough/noiseamount` 做最小扰动后裁切可见域
- `opacity`：单 pass `opacity` effect 读取 mask 纹理与 `alpha` 常量，按 premultiplied 路径衰减图层颜色/alpha
- 离屏渲染骨架：命中多 pass / post-process effect 的 layer 会先渲染到 offscreenA，若 effect 声明多于 1 pass 再 bounce 一次到 offscreenB，最后 composite 回主 framebuffer；无此类 effect 的 layer 仍走原直绘路径
- mouse parallax（4% ortho box 相机偏移，无条件应用）
- 真实桌面级播放：不再用 NSPanel 预览窗口；当前直接起 desktop-level Scene 宿主窗口，每个显示器各一份 `SceneMetalView`

### 1.3 当前样本覆盖情况

以下 8 个真实 Steam Workshop Scene 样本是历史交接时点记录；2026-07-22 真实 Workshop 的 `Scene/` 目录为空，现役自动门使用 `.codex` 隔离下载的 `3723344874` 与 `3724095562`：

| 样本 ID | image layers | 可加载 | 主要阻塞 |
|---|---|---|---|
| 3722249669 | 23 | 22 | BC1/BC3 已打通；只剩 builtin 音圈 |
| 3722933264 | 7 | 7 | 已能正确显示（修了 PNG 误判） |
| 3723230275 | 6 | 3 | 剩余是 builtin / unresolvable layer，不再卡在 BC |
| 3723257973 | 33 | 2 | 主背景/placeholder 是 `format 0` raw `.tex` + 大量 SceneScript 控件 layer |
| 3723344874 | 24 | 19 | BC1 装饰已可加载；剩余 1 个 `format 0` raw `.tex` + 几个 builtin |
| 3724095562 | 1 | 1 | 已能显示 |
| 3724289844 | 29 | 3 | 26 个 cherry-branch 是 `format 0` raw `.tex`（不是 BC）；粒子/branch 仍全失 |
| 3724553795 | 2 | 1 | 主图 + iris mask 路径已通；layer 153 是 audio visualizer 无法渲染 |

**BC1/BC3 `.tex` 加载链路已落地并通过样本回放验证。** `format 0` 现在也改成按 payload 分流：静态 PNG/JPEG payload、静态 raw RGBA8、MP4/动画 payload 分别处理；当前剩余阻塞更集中在 builtin 资源、SceneScript / audio visualizer，以及真正的 transform/effect 还原，而不是“容器读不出来”。

**离屏骨架命中情况（按现有隐藏解释文件推导，尚未逐个重新点预览回放）**：
- `3723230275`：layer `21`（`bloom` + `bokeh_blur`，23 passes）、`297/501`（`opacity`）
- `3723344874`：layer `365`（`fluidsimulation`，18 passes）、`47`（`glitter` + `godrays`，7 passes）、`348`（`blur`，4 passes）
- `3724553795`：当前 `iris` 最小路径继续走 inline mask，不进入 offscreen skeleton

### 1.4 验证手段

每次"预览 Scene"（当前会直接启动真实桌面级 Scene 宿主）会写两份诊断文件到样本目录：
- `.mywallpaperx-scene-interpretation.json` — 派生 render descriptor，方便对照
- `.mywallpaperx-scene-preview-log.txt` — 逐 layer 纹理加载结果（OK / unsupportedFormat / unsupportedTexFormat / texNoEmbeddedImage / texContainsVideoPayload / decodeFailed / textureAllocationFailed），以及 `offscreen skeleton N pass(es)` 标注；每层会额外记录 cache 相对路径、mask 加载结果（iris / opacity）和 placement 摘要，用于诊断"为什么这张图没显示"、"mask 是否命中"和"层位置是否异常"

构建：
```bash
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```
（在主项目目录里跑；沙箱 worktree 里跑会因 DerivedData 沙箱写权限失败，正常）

---

## 2. 已知不可逾越的边界

- **不承诺 100% 兼容 Wallpaper Engine Scene**——内嵌 effect 是手写视觉等价，不是 HLSL→MSL 转译。
- 完整 SceneScript VM、完整 shader 转译、完整 particle 模拟器**都不是目标**。
- 工程目标是"可用的 Scene runtime 子集"持续扩大覆盖面，按样本驱动新增视觉路径。

---

## 3. 下一阶段优先级（按收益）

### 3.1 BC1/BC3/BC5 解码器（BC1/BC3 已落地，BC5 预留）

**为什么是最高优先级**：5/8 样本的关键内容原先卡在这里。当前 BC1/BC3 版已让 `3722249669` 从 `1/23` 提升到 `22/23`，也把 `3723344874` 的 BC1 装饰补出来；`format 0` raw `.tex` 则作为下一层阻塞被显式暴露。

**格式参考**：
- [linux-wallpaperengine TEXTURE_FORMAT.md](https://github.com/Almamu/linux-wallpaperengine/blob/main/docs/textures/TEXTURE_FORMAT.md)
- [notscuffed/repkg](https://github.com/notscuffed/repkg)

**`.tex` 容器结构（TEXV0005）**：

```
offset  size  field
0       8     "TEXV0005"
8       1     null
9       8     "TEXI0001"
17      1     null
18      4     uint32 LE — texture format
                 0 = ARGB8888 (uncompressed)
                 4 = DXT5 / BC3
                 6 = DXT3 / BC2
                 7 = DXT1 / BC1
                 8 = RG88
                 9 = R8
22      4     uint32 LE — flags
                 1 = Interpolation
                 2 = ClampUVs
                 4 = IsGif (animation)
26      4     uint32 LE — texture width
30      4     uint32 LE — texture height
34      4     uint32 LE — image width
38      4     uint32 LE — image height
42      4     uint32 — unknown (likely dominant color)
46      8     "TEXB0001/0002/0003/0004"
54      1     null
55+     ...   mip count + per-mip { width, height, byteLength, data }
```

**本轮已落地**：

1. 新文件 `SceneTexContainer.swift`（Core）：按 `linux-wallpaperengine` / `repkg` 的 reader 解析 `TEXV0005` + `TEXB0001/0002/0003/0004`，非 MP4 `TEXB0004` 按 `TEXB0003` mip 布局读取。
2. `compression = 1` 的 mip 走 `COMPRESSION_LZ4_RAW` 解压，吐给 loader 的是实际像素/压缩块字节，而不是容器内的 LZ4 block。
3. `SceneTextureLoader` 已新增 BC 分支，用 `MTLPixelFormat.bc1_rgba` / `.bc3_rgba` / `.bc5_rgSnorm` 直接创建 compressed `MTLTexture`，并在 diagnostics log 里区分 `.unsupportedTexFormat(code:)`。
4. 第一版仍只取**第一 image / 第一 mip**；`format 0` 已不再一律按 raw 处理，而是先区分 PNG/JPEG payload、真 raw RGBA8、以及 MP4 payload。MP4 路径现可接入 Scene 动态纹理源；更复杂的多帧/多 image `.tex` 仍留给下一阶段。

### 3.2 iris / opacity mask（参数化最小路径已落地）

`iris` 在 3724553795 出现。它是**用 mask 纹理控制 visibility** 的 effect。

**本轮已落地**：

1. 直接复用现有 `effects[].passes[].texturePaths` 拿到 `materials/masks/iris_mask_xxx.tex`，**不需要改解释文件格式，也不需要 bump formatVersion**。
2. `SceneTextureLoader` 额外支持 `format 9` 的 raw `R8` `.tex`，够用来把 iris mask 读成 `MTLTexture.r8Unorm`。
3. `SceneMetalPipeline` 新增 `effectParams0/1` uniform 并读取 `scale/speed/phase/rough/noiseamount`，`SceneMetalRenderer` 通过解释文件里的 `constantShaderValues` 给 `iris` 注入参数（仍是近似，不是原版 shader 转译）。
4. `opacity` 的单 pass 路径会读取 mask 与 `alpha` 常量，直接在 fragment 中按 premultiplied 流程做可见域衰减。
5. `SceneMetalView.loadImageLayers` 的 preview log 会把 iris / opacity mask 的加载结果写在主 layer 行尾，方便从样本目录直接确认“主图 OK 但 mask 没上”这类问题。

**仍未做**：

- 多张不同 effect mask 同层联立（当前仍是单辅助 mask 槽，冲突时优先 `iris`）
- 依赖离屏渲染的多 pass iris 变体

### 3.3 离屏渲染骨架（最小路由已落地）

`blurprecise`、`bloom`、复杂 `iris`、多 pass effect 都需要 layer 先渲染到 offscreen texture 再后处理。

**本轮已落地**：

1. 新文件 `SceneOffscreenTexturePool.swift`：为命中的 image layer 复用一对 ping-pong `MTLTexture`，按源纹理尺寸等比 clamp 到最长边 `2048`。
2. `SceneMetalRenderer.renderFrame` 改成单个 command buffer 下多 encoder 串行：主 framebuffer encoder 会在命中 offscreen layer 时暂时结束，跑完离屏 pass 后再以 `loadAction = .load` 回到主 framebuffer，保持原图层混合顺序不变。
3. 第一版路由是：`source texture -> offscreenA -> (如果 effect 声明多于 1 pass，则 identity bounce 到 offscreenB) -> composite 回 framebuffer`。这是**骨架**，不是 blur / bloom / godrays 的真实 shader 数学。
4. `SceneMetalView.loadImageLayers` 的 preview log 现在会把 `offscreen skeleton N pass(es)` 写到对应 layer 行尾，便于用样本目录隐藏文件直接确认这层是否已进入离屏链路。

**仍未做**：

- `blur` / `bloom` / `godrays` / `glitter` / `fluidsimulation` 的真实 per-pass shader
- 复杂 `iris` 变体的离屏后处理
- 基于 effect pass 内容的 shader/常量驱动，而不是当前的 route-only skeleton

### 3.4 实际"播放"（第一版已落地）

**本轮已落地**：

1. 新文件 `SceneDesktopWallpaperHost.swift`：每个 `NSScreen` 建一个透明 borderless `NSWindow`，level 设为 `desktopWindow + 1`，contentView 直接挂 `SceneMetalView`，成为真实壁纸层而不是 `NSPanel` 预览。
2. `SceneDesktopWallpaperHost` 监听 `NSApplication.didChangeScreenParametersNotification` 和 `NSWorkspace.activeSpaceDidChangeNotification`，在显示器变化时整体重建 surface，在切换 space 后重新 `orderFrontRegardless()` 保持可见。
3. 因为壁纸窗口必须 `ignoresMouseEvents = true`，所以宿主额外开 30fps `Timer` 轮询 `NSEvent.mouseLocation`，把 screen-space 鼠标位置转发给每个 `SceneMetalView`，继续驱动 mouse parallax / cursorripple。
4. 新增共享通知 `WallpaperRuntimeWillSwitch`，Video 在 `WallpaperManager.setAsWallpaper(...)` 入口发 `.video`，Web 在 `WallpaperEngine.setWebWallpaper(...)` 入口发 `.web`，Scene 宿主收到"不是 `.scene`"的切换广播时会自行 teardown。
5. `MainWindowCoordinator.observeSteamWorkshopSceneReadyToRender()` 已改成：先 launch `SceneDesktopWallpaperHost`，成功后再广播 `.scene` 并停掉旧 `WallpaperEngine`；顺序不能反，否则新 Scene 宿主会吃到自己的切换通知后立刻停止。
6. `WallpaperManager` 现已持久化 `activeWallpaperRuntime`；启动恢复、播放失败、播放结束等视频回调都只在 `.video` runtime 下生效，静态图片 / Web / Scene 接管后不会再把旧视频链路反弹拉起。
7. Steam 已下载 Scene 的下载卡片、右键主动作与详情面板统一走“设为壁纸”入口，再由 `setAsWallpaper(_:)` 内部分流到 `requestSceneRender(_:)`，不再保留“预览 Scene”的旧语义。

**仍未做**：

- Scene runtime 还没接入 `WallpaperEngine` 的 pause / resume / battery / fullscreen 状态评估器，当前是独立常驻 60fps 渲染
- 图片库目前只接了右键“设为壁纸”入口，统一通过 `staticImageWallpaperReadyToApply` 通知让 `MainWindowCoordinator` 写系统桌面图并停掉动态 runtime；如果后续新增双击/按钮设壁纸，也应复用同一通知

### 3.5 粒子系统

样本里 particle layer 完全不渲染。完整粒子系统是大工程（emitter 配置 / lifetime / velocity / gravity / atlas / color over lifetime），但 3724095562 / 3724289844 的视觉重点之一是粒子。优先级低于 BC 解码但高于 SceneScript。

### 3.6 不做或慢做

- 完整 SceneScript VM
- 完整 HLSL→MSL 转译
- 音频反应材质（audioline 等）的真实音频接入
- 100% 兼容所有 Workshop 自定义 effect

---

## 4. 排雷区

接手 AI 在改这套链路时容易踩的坑：

- **解释文件 `formatVersion`**：扩 `SceneRenderDescriptor` 必须 bump。`SceneDiagnosticsBuilder` 每次都覆盖写，不用担心残留旧文件。
- **Y 轴**：四处对齐（详见设计文档 §3）。改任一处都要四处同步审视。
- **JPEG/PNG 在 `.tex` 容器里**：scan magic 必须限制在前 256 字节，否则 PNG 压缩数据里随机 `FF D8 FF` 会被当 JPEG 起始；不要扫 EOI/IEND 截断，让 CGImageSource 自己停。
- **CGContext 上传**：macOS CGBitmapContext 默认 y-up + memory top-down，draw 自然正向，**不要**加 translateBy+scaleBy。
- **CAMetalLayer**：必须用 layer-hosting 模式（init 中 `self.layer = ...` 先于 `wantsLayer = true`），并在 `init` 就 prime `drawableSize`，否则首帧 `nextDrawable()` 会因 0×0 返回 nil 显示黑屏。
- **Timer mode**：`Timer(timeInterval:...).RunLoop.main.add(forMode: .common)`，否则菜单弹出/拖窗时画面会卡。
- **壁纸窗口吃不到鼠标事件**：desktop-level host 必须 `ignoresMouseEvents = true`，所以 parallax / cursorripple 只能靠宿主轮询 `NSEvent.mouseLocation` 后转发进 `SceneMetalView`。
- **跨模块通信**：必须通知中转。Steam 模块不要直接 `import` Core Metal 类。
- **runtime switch 顺序**：Scene 切入时必须先 launch 新宿主，再广播 `.scene`；如果先发通知，新宿主注册的 observer 会把自己停掉。
- **沙箱 worktree 构建**：在 `.claude/worktrees/` 里跑 `xcodebuild` 会因 DerivedData 沙箱写权限失败；必须在主项目目录构建。文件修改可以在 worktree 里做，构建/验证回主目录。
- **样本目录污染**：解释文件和 preview log 是隐藏文件（`.` 开头），可以放样本目录；解包的几十 MB 资源**只能**放缓存目录，不要往样本目录写。

---

## 5. 验收 checklist（交接后任何一轮提交都应该过）

- [ ] 重新打开 8 个样本，对照 `.mywallpaperx-scene-preview-log.txt` 看加载结果
- [ ] 命中离屏骨架的 layer 在 `.mywallpaperx-scene-preview-log.txt` 里应出现 `offscreen skeleton N pass(es)`
- [ ] 主图方向正确（不上下颠倒）、子图层位置正确（在父图层内合理偏移）
- [ ] 预览窗口尺寸接近 scene aspect（没有大面积灰色 letterbox）
- [ ] 鼠标移动有 parallax 反馈
- [ ] Scene 启动后切到 Video / Web 时，桌面级 Scene 宿主应自行退出，不残留在桌面层
- [ ] 在主项目目录 `xcodebuild ... build` 通过，只有既有的 AppIntents 警告
- [ ] 改 `SceneRenderDescriptor` 字段必同步 `SceneInterpretationFileWriter.currentFormatVersion`
- [ ] 每次有效改动单独 commit，文档同步更新
