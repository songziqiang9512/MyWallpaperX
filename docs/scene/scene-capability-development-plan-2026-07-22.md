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
- foliage/water/cursor/chromatic/iris/opacity 等手写效果子集及 mask 路径；
- 多 pass 的 offscreen ping-pong 路由骨架；
- Video/Web/Scene runtime 切换时的 Scene 宿主释放。

### 尚未闭环

- 没有 Scene 自动化样本矩阵；旧 8 样本结果是历史手工证据，当前本地 Scene 目录为空；
- offscreen blur/bloom/godrays/glitter 等仍是 identity bounce，没有真实 pass 数学；
- text、particle、timeline、用户属性、SceneScript、puppet/mesh、音频响应和 built-in 资源未形成运行能力；
- 自定义 material/shader 只解析引用，不执行或转译；
- Scene 未接入 pause/resume、fullscreen/battery、目标 FPS 和系统状态评估；
- 没有首帧、动态像素、窗口身份、退出释放、CPU/GPU/显存或 soak 门。

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

### 问题

当前没有可自动启动和评估 Scene 的正式回归门；`3723344874` 的 blur/fluidsimulation/glitter/godrays layer 虽进入 offscreen skeleton，但 identity bounce 不产生对应视觉效果。

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
