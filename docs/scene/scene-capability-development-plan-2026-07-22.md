# Scene 播放能力开发计划

> 建立日期：2026-07-22
>
> 最近更新：2026-07-22（按官方资料、当前代码与 21 个隔离样本重新排序）
>
> 作用：定义 MyWallpaperX Scene runtime 从当前可审计子集向 Wallpaper Engine 常用能力逼近的实施顺序、样本门和验收标准。当前能力结论仍以 [`../reviews/web-scene-current-state-roadmap-2026-07-19.md`](../reviews/web-scene-current-state-roadmap-2026-07-19.md) 与最新运行证据为准；历史 memo 不反向覆盖本计划。

## 1. 目标与边界

目标不是宣称私有格式 100% 兼容，而是让常见 Windows Wallpaper Engine Scene 壁纸在 macOS 上达到可播放、可交互、可配置、可诊断和可持续回归的工程状态。

实现优先级由四项共同决定：

1. 真实 Workshop 样本命中频率；
2. 对首帧和主要视觉构成的影响；
3. 能否建立确定性自动验收；
4. 实现的来源、维护成本和安全边界。

不采用以下捷径：

- 不把 Scene 转成 Web 播放；
- 不按单个样本 ID 硬编码；
- 不把 route-only、占位 shader 或静态截图写成“效果已支持”；
- 不执行未知 SceneScript，也不直接加载来源不明的预编译 DirectX shader；
- 不直接修改真实 Workshop 样本。

## 2. 2026-07-22 当前代码事实

### 已真实进入运行链

- `project.json` / entry 同名 `gifscene.json` 识别、PKGV 索引、受控缓存解包、路径校验和 interpretation v12；
- PNG/JPEG、raw RGBA/RG/R8、BC1/BC2/BC3/BC5、LZ4、MP4 payload 和 TEX sprite sequence；
- Metal image/solid/text/particle 合成、父子 transform、有效可见性、source order、alpha、正交/透视粒子相机和桌面多屏宿主；
- cover 投影；Camera Parallax 服从 Scene options、逐层 depth、传播和属性 override，未声明时不启用；
- coarse/precise gaussian blur、标准 Bloom 子集、normal-map waterripple 子集、perspective+opacity、mode 9 additive，以及 foliage/water/cursor/chromatic/iris 等明确标注为近似的内联 effect；
- 静态 text 的 authored `pointsize * 4`、vector padding、包内字体、系统字体别名和缺失字体诊断；
- 作者包内 2D sprite 粒子的 definition/resource graph、sphere/box、rate/burst/prewarm、常见 initializer/operator、sequence/random frame、additive/translucent、朝向、静态 override、CPU simulation 与 Metal instancing；
- 用户属性定义、group/display condition/options、默认值/override、visibility/text/camera 与部分 effect target、按壁纸持久化、活动 Scene 受控重建和独立属性窗口；
- typed `composition/project/fullscreen` 与 generic dependency layer ID；对可见、无 child/dependency consumer、效果栈完整受支持且无需缺失 mask 的 utility layer，执行当前 framebuffer 前缀捕获并按作者 transform/alpha 合回；
- 签名 Debug App、隔离 sample root/HOME、Metal ready/after 双帧、语义合同和 stop 后 surface=0；当前正式矩阵 **12/12 通过**，image `136/137`、solid `43/43`、text `71/84`、particle `3/26`。

### 仅解析/诊断或部分实现

- utility current-frame capture 只是首个受限子集；named render target、dependency texture 注入、隐藏 provider、child/nested target、utility mask 与任意 material/shader pass 尚未实现；
- material pass 的 texture slots、combos、constant values 已保留，但 renderer 不执行 Wallpaper Engine material/shader；多数 blend mode、mask/composite 和 effect pass 仍缺失；
- Timeline 只有数据模型空壳，没有关键帧、Loop/Mirror/Single、Bézier、wrap-loop、pause 或 target 写回；
- SceneScript 只检测 inline script / `.js`，没有 ECMAScript runtime、`init/update`、事件、globals 或属性写回；
- 用户属性未闭环 sceneTexture/texture variants、transform、alpha、particle/audio/puppet target 和 `applyUserProperties`；
- child particle graph 可遍历但不实例化；built-in particle texture、trail/rope、world-space、control point、collision、音频和动态 override 未实现；
- Scene 音频/媒体未接现有系统服务；动态时间/日期/媒体 text、puppet/mesh/3D/lighting、自定义 shader 均未实现；
- pause/resume、fullscreen/battery、目标 FPS、CPU/GPU/显存预算和 soak 尚未闭环。

12 样本 PASS 不能解释成视觉兼容率：正式矩阵仅证明已声明的解析、GPU 完成、非黑画面和释放门通过。Utility 定向 4 样本共有 42 个候选，只有 2 个进入 capture，仍有 26 条 dependency edge 与 18 个 named-target 缺口；`2902406982` 最新截图仍有白色三角形，主构图 P0 尚未关闭。21 样本首轮分级是历史截图基线；新增能力需要重跑后才能重新分级。

## 3. 官方资料核验后的契约边界

[Wallpaper Engine Scene 能力参考](wallpaper_engine_scene_compatibility.md) 的能力地图总体成立，但官方资料描述编辑器/官方运行时行为，没有公开稳定的 Workshop 序列化格式。实现仍以真实隔离样本和可复现 parser/runtime 证据为准。

当前直接影响架构与验收的官方契约：

1. [Camera Parallax](https://docs.wallpaperengine.io/en/scene/parallax/introduction.html) 必须由 Scene options 开启，并逐层尊重 parallax depth；0 表示该层关闭。[Depth Parallax](https://docs.wallpaperengine.io/en/scene/effects/effect/depthparallax.html) 是独立 effect，还要求 Camera Parallax 开启且当前层普通 depth 为 0。
2. [Timeline](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html) 包含 Loop/Mirror/Single、start paused、默认 Bézier、左右切线和 wrap-loop。动画事件通过同层 SceneScript `animationEvent` 触发，不直接操作声音或图层。
3. [SceneScript](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html) 是属性绑定型 ECMAScript 运行时；动画先求值，脚本再更新并可覆盖结果。不能先造一个与 layer/effect/text/particle target 脱节的通用 JS 执行器。
4. [User Properties](https://docs.wallpaperengine.io/en/scene/userproperties/overview.html) 的控件、默认值、直接绑定、条件显示与持久化应先于脚本回调；`applyUserProperties` 首次加载后只携带变化键。
5. [SceneScript AudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) 为 16/32/64 可选频段，提供 left/right/average 并每个渲染帧更新；不能直接套用 Web 固定 64+64、约 30Hz 回调合同。
6. [Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) 区分标准 Bloom 和 Ultra HDR，并有逐层 HDR brightness；自定义 shader/3D/Puppet 的能力虽强，但没有当前 2D 主构图资源链优先。
7. [RGB Composition](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html) 明确像相机一样记录其下方图层；[Effects](https://docs.wallpaperengine.io/en/scene/effects/introduction.html) 和 [Blend](https://docs.wallpaperengine.io/en/scene/effects/effect/blend.html) 允许链接动态 layer。官方没有公开 Workshop named-target 名称、dependency DAG 或 `projectlayer` 稳定格式，这些只能由隔离样本建立内部合同。

## 4. 重新排序后的实施路线

### S0：可重复基线与作者语义门（已完成）

- 隔离 runner、签名身份、Metal 双帧、12 样本语义矩阵和 surface 释放门已落地；
- cover、Camera Parallax、effect/particle visibility 均按作者声明执行；
- 未声明或默认关闭的效果必须继续作为负向门，不能用“能力存在”替代启用条件。

### S1：首帧主构图闭合（当前 P0）

按依赖顺序实施：

1. **已完成** `models/util/solidlayer.json` 与 model JSON `solidlayer:true` 程序化色块：保留作者 color，复用 1×1 白纹理，只对 solid 在通用 fragment 中乘 layer tint；提交 `c8c463b`。
2. **已完成 S1.2a**：typed utility、受支持 effect 的 current-frame prefix capture、受限离屏池、mask fail-closed 与 GPU completion telemetry；提交 `1517f4a`、`1f8f148`。
3. **当前 S1.2b**：只实现样本已证明的 `dependency -> layer-ID target -> consumer texture slot`，包含隐藏 provider、缺失/forward/cycle/budget fail-closed；不扩成任意 pass DAG 或 shader graph。
4. sceneTexture / Texture Variants：项目默认资源、用户授权替换、属性条件、持久化和 renderer 热更新共用同一 resource provider。
5. 重新运行 21 样本视觉矩阵，优先关闭 `2902406982`、`2938612768`、`3122339805`、`3768229922` 的主构图 P0；`3766415113` 的 gifscene UV/sampler 已修复，不再列为待办。

### S2：统一 live-value runtime（P1）

1. 先建立 layer/effect/text/particle 的 typed target setter 和每帧值快照；属性、Timeline、SceneScript、音频只能经此层写值。
2. Timeline 先实现 keyframe、duration/FPS、Loop/Mirror/Single、start paused、Bézier、wrap-loop 和多属性同步；动画事件在脚本核心可用后接入。
3. SceneScript 以官方属性绑定契约为边界，先实现 `init/update`、Vec/Mat、Date/Math、`engine` 基础字段、`thisScene/thisLayer/thisObject/shared` 和确定执行顺序，再加入 user/cursor/audio/media 事件。
4. 动态时钟/日期/媒体 text、transform/alpha/effect/particle property target 与无重建热更新复用同一 live-value 层。

### S3：高级粒子与音频（P1 后段）

- built-in particle resource provider、world-space、常用 emitter/operator/control point；
- child、sprite trail、rope/rope trail、collision 分批实现，不一次性做大而全；
- Scene 音频桥按脚本选择提供 16/32/64 left/right/average，并按渲染帧更新；
- 媒体桥提供可缺省的播放状态、标题/作者/专辑、封面和颜色，必须有可注入测试源。

### S4：视觉与角色能力（P2）

- 标准 Bloom 完整参数、颜色空间/预乘 alpha、常见 blend 与高频内置 effect/material；
- waterflow/ripple、godrays/glitter/shadow 等按真实样本和官方录屏逐类提高一致性；
- Puppet 基础 mesh/weights/timeline 后，再做 physics、IK、复杂 mixing；
- 实时 2D lighting 与 HDR 必须带 GPU/显存和降级门。

### S5：高级兼容与发布门（P3）

- 3D model、lighting/shadow/volumetric、自定义 shader translation 和 RGB 均后置；
- 每个阶段持续记录加载时间、纹理内存、粒子上限、帧时和降级原因；
- 最终建立固定/扩展/新下载三层矩阵、30 分钟交互、2 小时 soak、系统生命周期和发布 checklist。

### 已完成：S1.1 solid layer

- 固定 built-in 路径和 model JSON `solidlayer:true` 实例统一进入 typed `solid`；缺失作者 color 在 descriptor 中保留 `nil`，渲染时才回退白色。
- 共享 1×1 白纹理随 `SceneMetalView` 创建一次；color/alpha/effect/mask/blend 继续走现有 compositor，没有伪纹理、样本 ID 或普通 image/text 全局乘色分支。
- 定向 `3122339805 / 3750813609 / 3765760121` 为 **3/3**；正式 11 样本为 **11/11**，solid `34/34`，image/solid `106/113`。`3122339805` 为 `90/90`，中性灰底像素由 45.96% 降至 0.33%。
- 报告：`.codex/scene-solid-targeted-pass2-20260722/`、`.codex/scene-solid-matrix11-pass2-20260722/`；提交：`c8c463b`。

### 已完成：S1.2a utility current-frame capture

- `composelayer/projectlayer/fullscreenlayer` 已进入 typed descriptor；generic dependency ID、局部 composition geometry 与 project/fullscreen 全画布 geometry 均有确定性合同。
- 当前只对作者可见、无 child/dependency consumer、所有可见 effect 均受支持且不缺 mask 的 utility layer 执行捕获。未支持、部分支持、隐藏、无 effect 和带缺失 mask 的层均明确跳过，不把能力默认套给样本。
- source copy 与 effect encoder 失败均 fail closed；离屏纹理限制为最大 2048 维、96 MiB 预算，capture 成功只在 Metal command buffer 完成后上报。
- 定向 4 样本 **4/4**：42 个 utility candidate 中 2 个 capture，layer `410/530` 均 GPU succeeded，0 failed；正式矩阵 **12/12**，17 candidates / 2 capture / 8 dependency edges / 6 named-target gaps。
- 报告：`.codex/scene-utility-render-targeted-pass-20260722/`、`.codex/scene-utility-formal12-20260722/`；提交：`1517f4a`、`1f8f148`。

### 当前执行项：S1.2b named layer target / dependency texture

- **预期**：作者 dependency 引用的 layer 在其 authored source-order 位置发布稳定的 layer-ID target；consumer 只在声明匹配的 effect/pass/slot 读取，不重排主图层顺序。
- **实际**：v12 已保留 26 条定向 dependency edge，但 renderer 尚不发布 named target，也不向 consumer slot 注入；`2902406982` 的 6 个 target gap 使白色三角仍遮挡主构图。
- **根因假设**：现有三纹理池是瞬时工作集，同尺寸 target 会互相覆盖；同时缺少 typed slot binding、按帧 target 生命周期、cycle/forward/missing 校验和明确的首个 consumer executor。
- **修改范围**：先支持严格 `_rt_imageLayerComposite_<id>_a` 引用、独立有预算的 layer-ID target pool、隐藏 provider 与 cycle/missing/budget fail-closed；首个 consumer 只覆盖真实样本证明的 clipping-mask 合成，不实现任意 shader/pass DAG。
- **目标样本**：`2902406982` 为视觉正向，`3768229922` 验证隐藏 provider 计划，`2938612768` 验证 forward/ordinary provider 诊断；无 dependency 的正式样本为负向回归。
- **验收**：290 的 6 个 provider 与 8 个 consumer binding 精确匹配，白三角不再由缺失 named target 产生；循环、缺失、forward unsupported 和预算失败均不递归、不错误采样；代码健康、签名构建、定向视觉门与正式矩阵通过后单独提交。

## 5. 样本规范

- Steam App ID 固定为 Wallpaper Engine `431960`；记录 Workshop ID、下载日期、标题、文件 SHA-256 和下载方式；
- SteamCMD 必须运行在 `.codex` 可写副本，不能让自更新改动签名 App bundle；
- Steam 下载缓存只作为来源，测试前移动或复制到 `.codex/scene-representative-samples-<date>/Scene/<id>`；
- 真实 `~/Movies/MyWallpaperX/创意工坊` 始终只读；benchmark 使用隔离 sample root 和临时 HOME；
- 样本二进制不提交 Git，仓库只提交矩阵、来源、哈希和能力标签。

## 6. 开发规范

- 修复前记录预期、实际、根因假设、影响文件、样本范围和验收标准；
- 公共 parser/renderer 修复优先于样本绕过；
- 一个独立能力一个提交，完成目标样本和相关样本验证后才提交；
- `SceneRenderDescriptor` 合同变化必须 bump interpretation format 并同步 reader；
- 坐标改动同时复核 texture、model、projection、cursor 与 child transform；
- GPU 资源必须有所有权、上限和释放路径；不在每帧创建 pipeline、texture cache 或无限增长的 buffer；
- 新 Swift 文件不超过 400 行，历史超限文件只减不增；修改 Swift 后按项目规则运行代码健康门；
- 诊断必须区分 unsupported、resource missing、decode failure、pipeline failure、no drawable 和 lifecycle failure。

## 7. 测试金字塔

### 单元层

- PKGV/TEX/scene JSON fixture；
- effect 名称与参数到 typed pass 的映射；
- property/timeline/particle 数据模型；
- transform、插值、资源路径和评分规则。

### GPU/集成层

- 小尺寸离屏纹理输入，验证输出像素、alpha 和 mask；
- Debug runner 启动真实 Scene，确认解释文件和纹理加载；
- 截取 ready 与 after-interaction 两帧，验证非黑、运动和窗口归属；
- stop 后确认 surface/timer/video source 清零。

### 样本矩阵层

- 目标样本：验证本次能力；
- 相关样本：覆盖相同 parser/effect/texture 路径；
- 固定矩阵：公共 runtime、resource、effect 或 lifecycle 改动后运行；
- 长批次失败不能用单样本重试替代，只能作为独立诊断证据。

## 8. 首轮实施

> 第 8-14 节是已完成阶段的证据记录，不再决定当前优先级；当前执行顺序以第 2-4 节为准。

### 问题（实施前）

实施前没有可自动启动和评估 Scene 的正式回归门；`3723344874` 的 blur/fluidsimulation/glitter/godrays layer 虽进入 offscreen skeleton，但 identity bounce 不产生对应视觉效果。

### 根因假设

1. Scene 播放只从 Steam UI 通知进入，测试无法指定隔离根；
2. offscreen pipeline 没有 typed post-process pass，renderer 只做一次无效果的复制；
3. 旧预览日志把“进入骨架”记录出来，但没有区分 route-only 与真实效果支持。

### 修改范围

- `App/DebugScenePlaybackRunner.swift` 与最小 AppDelegate 接线；
- `script/scene_wallpaper_benchmark.py`、矩阵 JSON 和脚本测试；
- typed blur pass、Metal shader 与 renderer 路由；
- Scene 状态文档和样本来源记录。

### 验收

- SteamCMD 样本 `3723344874` 在隔离根和临时 HOME 下启动；
- runner 日志确认 descriptor、image layer、loaded texture、surface 与 teardown；
- benchmark 对 ready/after 帧执行非黑和动态检查；
- blur pass 有确定性 GPU/像素或截图证据，不再标记 route-only；
- 相关非 blur image/mask 路径无回归；
- 脚本测试、代码健康和 Debug build 通过；每个独立问题单独提交。

## 9. 2026-07-22 首轮结果

- `DebugScenePlaybackRunner` 可从隔离 root 直启 Scene，并拒绝真实 Workshop 路径；Debug evidence 模式使用当前 Space 的可捕获窗口，不改变生产 desktop-level 窗口语义。
- `scene_wallpaper_benchmark.py` 会隔离复制签名 App、样本和 HOME，校验样本 SHA-256、App 身份、ready、纹理加载率、非黑双帧、像素变化和 stop 后 surface=0。
- SteamCMD App ID `431960` 下载并固化两个初始代表样本：`3723344874`（复杂多层/effect）与 `3724095562`（单图层直绘），二进制只保存在 `.codex`。
- 初始两样本矩阵 **2/2 通过**。`3723344874` 为 35 layers / 24 image layers / 29 effects，20/24 主纹理加载，1 层真实 gaussian blur、2 层 route-only，两帧 changed ratio 10.60%；`3724095562` 为 1/1 主纹理、静态两帧一致。
- 报告：`.codex/scene-benchmark-gaussian-blur-matrix2-20260722/report.json`。App 身份为 Team `H9QWU9XN8R`、CDHash `17d3751df90e55868ae1d2e0500682746026b665`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `650da4e5ece48cd464c30ce6896aed908844aa0eef44474f546e5527a2bdc858`，运行前后验证一致。
- 下一步见下一节的扩充结果和当前优先级。

## 10. 2026-07-22 第二轮样本扩充与 Bloom 结果

- 新增 SteamCMD 隔离样本 `3722933264`、`3723230275`、`3723257973`、`3724289844`、`3724553795`；加上初始两项，正式矩阵现为 7 个真实样本。候选 `3722249669` 和两个当前热门候选在匿名 SteamCMD 下不可下载，没有混入运行失败统计。
- 新矩阵覆盖 1 到 126 层、0 到 66 个 effect、MP4 payload、particle layer、103 个 inline-script layer、音频响应声明、单图直绘和复杂 mask/offscreen 路径。样本二进制与运行副本均在 `.codex`，真实 Workshop 根保持只读。
- `3723230275` 的主图包含真实纹理和 16-pass Workshop Bloom；旧实现只做 identity ping-pong。现在 `SceneBloomPipeline` 执行 threshold、separable gaussian blur、tint/intensity composite，并保留此前 foliage 等内联效果结果。
- 正式矩阵 **7/7 通过**。纹理加载率依次为 `100% / 50% / 12.12% / 83.33% / 100% / 100% / 50%`；六个动态样本 changed ratio 为 `7.38% / 38.88% / 44.29% / 10.72% / 12.66% / 18.52%`，静态样本为 `0%`。Bloom runtime 命中 1 层，Gaussian runtime 命中 1 层，所有样本 stop 后 surface 为 0。
- 最终报告：`.codex/scene-bloom-full-matrix-final-20260722/report.json`。App 身份为 Team `H9QWU9XN8R`、CDHash `7e77a8aad22a6a94353394971a95d5973001556f`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `5605fb190f8f66d68051800fa5d2295ea27c224bcf3cc1fb2f57cb9fa8ca7e5b`。
- 低加载率样本是有意保留的兼容缺口证据，不是全能力通过。后续优先通用 effect/pass 合成、built-in 资源与 container 语义；样本只作为能力验收，不增加 ID/名称适配分支。

## 11. 2026-07-22 文本与相机语义结果

- 新增 typed text style 与 CoreText 纹理链，使用包内 TTF/OTF、point size、颜色/亮度、背景、padding 和对齐默认值；有效父链下 `3723230275` 为 3/3、`3723257973` 为 10/10、`3723344874` 为 4/4、`3724289844` 为 3/3。interpretation contract 升至 v5。
- 文字目前渲染 descriptor 的静态 `value`，不执行未知 SceneScript；时钟、日期、属性绑定和音频驱动仍不会动态更新，不能据此声明脚本兼容。
- 正交相机由 letterbox 改为 cover；对非零 camera center 保留作者构图，同时限制可见矩形在 Scene 边界内。静态样本 `3724095562` 的灰色边带消失，ready/after 变化率为 0，边缘单色占比从修复前 82.70% 降至 25.48%。
- parallax 不再默认套用。正式矩阵逐项验证 `3723230275`、`3723257973` 为启用，其余五项为关闭，并记录 amount 与 mouse influence；静态样本增加最大动态像素门。
- 最终 7 样本矩阵 **7/7 通过**，报告为 `.codex/scene-camera-semantics-final-20260722/report.json`。App 身份为 Team `H9QWU9XN8R`、CDHash `a43628baf354f21e6c8bfdbc629ef779d0d95816`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `f7f0c5973a0d69412ecbfd63603671f35f6279da078a9cf1f4f0d1f5043f4a71`。
- 下一阶段先推进通用 shader/effect pass 顺序、blend/composite 与 mask 语义，再处理动态属性和脚本子集；不得把所有效果默认打开，也不得按样本 ID 修图。

## 12. 2026-07-22 precise blur 与复合水波层结果

- `blurprecise` 已接入与 coarse blur 共用的两遍 Gaussian GPU 路径；作者 `scale` 按像素半径解释，再按实际离屏纹理宽高归一化。`3724289844` 三个可见文字层分别读取 `0.43 / 1.33 / 1.28`，运行日志命中 3 层，不再记为 route-only。
- `3723230275` 原有逻辑会按层名 `ripple` 和包含不可见 pulse 的效果列表跳过整层。直接取消跳过会暴露两张黑底纹理，因为该链还依赖未完整实现的 waterflow、waterripple、perspective 和 opacity 合成。
- 中间版本先改成只检查可见 pass 的 capability gate；随后补齐 layer `colorBlendMode`、真实 projective UV+opacity replacement pass 和 mode 9 additive final composite。两层现在均进入 runtime，`unsupported composite skipped` 从 2 降为 0，黑矩形消失。
- 最新正式矩阵 **7/7 通过**；coarse blur 1 层、precise blur 3 层、Bloom 1 层、perspective-opacity 2 层、color blend mode 9 两层，fallback 为 0。报告保存在 `.codex/scene-perspective-blend-matrix-20260722/`。
- 最新签名 App 身份为 Team `H9QWU9XN8R`、CDHash `7d2a5032b6cf1aa31ae9cb1b26cce8d976dcff04`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `7a2689fd9cabc9f8610d1846538afb83e5a5ea97fd55e42c7ccfb3856f6d4bc5`；81 个脚本测试、签名 Debug build 和代码健康门通过。

### 当时产品判断（历史）

这一阶段曾按 7 样本与 v6/v7 renderer 估算完成度，并把 water/effect 精修排在前面。属性、基础粒子、文字和 11 样本语义门落地后，该估值与顺序已经失效；当前判断和 S1-S5 顺序以第 2-4 节为准，不再维护无统一量尺的百分比。

## 13. 2026-07-22 pass 元数据合同结果

- effect 实例 pass 与 material pass 现在同时保留有序 `textureSlots: [String?]` 和 `combos: [String: Int]`；原有去空的 `texturePaths` 继续存在，当前纹理加载和渲染路径没有行为变化。
- interpretation 升至 v7。固定 SHA 的 `3723230275` 精确验收为 effect 37 槽/20 空洞/17 combo 条目、material 24 槽/8 空洞/12 combo 条目；`waterripple` 的 `[null, null, normal]` 与 `ripple.json` 的 `VERSION=2` 均已进入 renderer descriptor。
- 最新正式矩阵 **7/7 通过**，报告为 `.codex/scene-v7-contract-matrix-20260722/report.json`。签名 App 为 Team `H9QWU9XN8R`、CDHash `64879014f3bf56763b127d0b5075cfeb0c468a30`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `d9543c624e35e010a931acfe2ab12ee5664b2a799deeb2d62d22944678120b5a`；83 个脚本测试、签名 Debug build 和代码健康门通过。

## 14. 2026-07-22 normal-map waterripple 结果

- 新 runtime 按同一可见 waterripple pass 的 `textureSlots[2]` 绑定 normal map，使用作者 shader 的两组 UV、相反动画相位、方向滚动、source aspect、ratio 与 `ripplestrength²` 数学；normal 采样 repeat，source 采样 clamp。
- 新 pass 激活时移除旧 `.waterwaves` 正弦 flag，执行顺序为 source → normal ripple → perspective+opacity → final blend，避免双重扰动或 perspective 重新读取旧 source。T1 mask 或 `MASK/SPECULAR=1` 尚未实现时不冒充支持，保留 legacy 路径。
- 最终矩阵 **7/7 通过**。`3723230275` 两层均加载 `256×256` normal，normal runtime 2、legacy 0、perspective-opacity 2、mode 9 两层、fallback 0；`3724289844` 的 T1 mask 变体保持 normal runtime 0、legacy 1，precise blur 仍为 3。报告为 `.codex/scene-normal-ripple-final-matrix-20260722/report.json`。
- 最终签名 App 为 Team `H9QWU9XN8R`、CDHash `1dcb8d87465cc9fd241bd10e6581694861267aa1`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `5c47f37d35a370a0232a5a796e4e1d2403acd6cf2e92bb51132ef3f5026caac8`；83 个脚本测试、签名 Debug build 和代码健康门通过。`SceneMetalView` 已从历史 419 行降至 300 行并退出 legacy baseline，`SceneMetalRenderer` 基线从 454 收紧到 418。
