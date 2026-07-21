# Scene 播放能力开发计划

> 建立日期：2026-07-22
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

## 2. 2026-07-22 代码事实

### 已实现

- `project.json` Scene 识别、PKGV 文件表读取和受控资源解包；
- `scene.json` camera、general、object、effect、pass、常量和资源引用解析；
- model/material 摘要、解释文件、资源索引和缺口诊断；
- PNG/JPEG、raw RGBA8、R8、BC1/BC3/BC5 与 MP4 payload 纹理路径；
- Metal image layer 合成、父子 transform、source-order、alpha、正交相机和桌面多屏宿主；
- 包内字体的静态 text layer 纹理化、父容器可见性传播、cover 投影和按 `general.cameraparallax` 参数启停的鼠标视差；
- foliage/water/cursor/chromatic/iris/opacity 等手写效果子集及 mask 路径；
- 多 pass 的 offscreen ping-pong 路由、coarse gaussian blur，以及 Bloom 的亮部提取、横纵模糊与 tint composite 真实 GPU pass；
- Video/Web/Scene runtime 切换时的 Scene 宿主释放。

### 尚未闭环

- Scene 自动矩阵已扩至 7 个样本并覆盖 MP4 payload、particle layer、脚本密集场景和音频声明，但这些标签不代表对应高级能力已经渲染；
- godrays/glitter/fluid/bokeh blur 等仍是 route-only；blur precise 也尚未实现真实数学；
- 动态 text/SceneScript、particle、timeline、用户属性、puppet/mesh、音频响应和 built-in 资源未形成完整运行能力；
- 自定义 material/shader 只解析引用，不执行或转译；
- Scene 未接入 pause/resume、fullscreen/battery、目标 FPS 和系统状态评估；
- 已有签名身份、非黑双帧、动态像素和退出释放门；CPU/GPU/显存、性能退化和 soak 门仍未建立。

## 3. 官方能力面

Wallpaper Engine 官方设计文档把 Scene 主要能力分为：

- image/effect stack；
- user properties；
- timeline animations；
- particle systems；
- audio visualization；
- parallax 与交互；
- SceneScript；
- custom shaders、3D models、puppet warp；
- 性能和纹理预算。

参考入口：

- [Scene Editor Overview](https://docs.wallpaperengine.io/en/scene/overview.html)
- [Effects Overview](https://docs.wallpaperengine.io/en/scene/effects/overview.html)
- [User Properties](https://docs.wallpaperengine.io/en/scene/userproperties/overview.html)
- [Timeline Animations](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html)
- [Particle Systems](https://docs.wallpaperengine.io/en/scene/particles/introduction.html)
- [Audio Visualization](https://docs.wallpaperengine.io/en/scene/audiovisualizer/overview.html)
- [Shader Programming](https://docs.wallpaperengine.io/en/scene/shader/overview.html)

## 4. 分阶段路线

### S0：可重复基线与证据门

交付：

- Debug 参数可从隔离根目录直接启动指定 Scene；
- benchmark 固化样本来源、SHA-256、App 身份、解释结果、纹理加载、窗口可见性、首帧与动态证据；
- teardown 后窗口、timer、video source 和临时资源归零；
- 首批矩阵至少覆盖静态多层、mask effect、offscreen effect、MP4 texture、particle、脚本和音频声明。

验收：同一签名 Debug App、临时 HOME、隔离样本根下重复运行结果稳定；任一关键短板使矩阵非零退出。

### S1：高频 2D effect runtime

按真实样本频率依次推进：

1. coarse gaussian blur / blur precise；
2. bloom 与 glow composite；
3. godrays / light shafts；
4. glitter、reflection、color/tint、blend；
5. water/foliage/shake 等已有近似路径的参数和 mask 对齐。

每个 effect 必须有独立 pass 类型、参数解析、GPU 实现和基准截图/像素差证据。没有真实数学的 effect 继续标记 unsupported，不得只因进入 offscreen 路由就算支持。

### S2：属性、时间轴与生命周期

- 解析 `general.properties` 和默认值；
- 建立 property key 到 visibility、transform、texture、effect uniform 的绑定索引；
- 保存每个 wallpaper / display 的用户覆盖；
- 实现 timeline keyframe、duration、loop/mirror/single、插值与 pause；
- 接入应用暂停、全屏、睡眠、电池和目标 FPS；
- 建立 Scene/Video/Web 快速互切和跨重启恢复门。

### S3：粒子系统子集

先实现高覆盖 sprite 粒子：

- emitter rate/burst；
- lifetime、position、velocity、gravity；
- size/color/alpha over lifetime；
- sprite sheet 与基础 blend；
- 确定性随机种子、粒子上限和 GPU buffer 预算。

再按样本增加 child emitter、collision、mouse/audio operator。未知 component 必须诊断并跳过，不能拖垮整个场景。

### S4：高级动态内容

- 复用系统音频 64+64 stereo 频谱，把音频 uniform 接到 effect/particle；
- 基于至少 20 个脚本语料定义 SceneScript 白名单子集；
- text/font、puppet warp、mesh/3D model；
- 常见 built-in 资源和材质语义；
- 评估开源 shader IR/跨编译方案的来源、许可证与 Metal 可维护性。

完整未知脚本执行和不受控二进制 shader 加载仍不接受。

### S5：发布级门禁

- 固定、扩展和新下载三层样本矩阵；
- 单/双屏 CPU、GPU、内存、显存、功耗和缓存预算；
- 30 分钟交互运行、2 小时 soak、睡眠/唤醒和显示器/音频设备变化；
- Scene runtime 矩阵接入 CI/发布 checklist；
- 所有“支持”结论必须能追溯到样本、构建身份、报告和提交。

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
