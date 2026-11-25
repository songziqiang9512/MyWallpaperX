<!-- document-role: active-plan -->
<!-- retirementCondition: 各质量项完成验收或明确退役，稳定语义归对应引擎合同，专项顺序与设计登记一并退役。 -->

# 三引擎壁纸质量设置执行评估

评估以 2026-11-25 主仓库 `codex/engine-refactor-program` 的源码为依据，三引擎初版基线为 `5946c3683`，Scene 六项算法选型复核至 `b2b80f892`。产品目标是 macOS 26+、Apple Silicon（M1 及更新硬件）。本文引用仓库已有运行结果，候选参数和发布条件在实施时按冻结输入验收。

[官方选项](#reference-and-current) · [偏好与预设](#product-and-state) · [Scene 算法](#scene-aa) · [Web](#web) · [Video](#video) · [实施顺序](#delivery) · [实测条件](#validation)

[现役工作卡](wallpaper-quality-work-card.md#execution)维护批次顺序及接手状态。Q2 首片由后处理的「超高（显示 HDR）」接管原独立 HDR 的物理输出。普通「超高」保作者发光，使用 SDR 输出范围。 [Wallpaper Engine 2.0.97 公告](https://steamcommunity.com/games/431960/announcements/detail/3133943554973045545)

<a id="decision"></a>
## 实施裁决

1. 在 AppKit 设置的「节能与暂停」附近新增「壁纸质量」区域。首批整合现有 Scene 30／60 FPS 与 HDR 显示入口，让 Web 可选采用该帧率建议，Video 明示按当前素材播放。用户原有偏好升级后保持同等行为。
2. Scene 以官方完整档位作为评估范围，沿现有帧节奏、Program、资源和 Metal 渲染入口分批交付。先验证全景 Bloom、实时反射、模型阴影和体积光的开关，再验证各质量档。动画帧率扩展到 10–120 FPS 的计划分两段，MSAA 保持默认 1×，2×／4×／8× 逐档验证。
3. Web 通过官方兼容桥交付 FPS 建议，作品自行控制绘制和媒体。Video 的节能入口选用真实较低规格文件，先评估来源已有档，再用离线 A/B 决定是否上线可选派生。预设只能组合已经有效、已验收的控件。
4. 首批完成条件为升级、导入恢复和复位正确，Scene 实际控制提交节奏，Web 在真实宿主中正确收发建议值，Video 的适用范围一目了然，三引擎候选、暂停、恢复和输出交接通过代表验证。后续每项都以独立可见结果和成本取证决定发布。

<a id="reference-and-current"></a>
## 官方对照与当前底座

档位名称和范围按用户提供的官方客户端画面及补充记录。10–120 FPS 是帧率范围，渲染输出像素和纹理尺寸各自有独立的调整路径。

| 项目 | Wallpaper Engine 可见选项 | 本分支可复用能力与差距 |
|---|---|---|
| 预设 | 低／中／高／超高 | 现有 30／60 同时绑定帧率与缓存，尚缺可编辑的质量组合 |
| 帧率 | 下限 10，客户端由运行端提供上限。用户观察到 120 档，图中当前值 25 FPS | Scene 首批 30／60，缺省 60，分别关联 512 MiB／1 GiB 解码缓存。Web 取目标屏建议并封顶 60，Video 按素材播放 |
| 抗锯齿 | 无／MSAA ×2／×4／×8 | 兼容默认 1×。连续合格主域可请求 2×／4×，8× 等支持设备的正向验收。 |
| 后处理 | 禁用／启用／超高。符合显示资格时另有「超高（显示 HDR）」 | Scene 有普通／HDR Bloom、作者动态参数和单独的 EDR 显示。缺用户后处理档 |
| 纹理分辨率 | 自动／高质量／高性能 | Loader 保用途、来源版本和设备缓存。帧率绑定的缓存额度只影响驻留，缺可以改变解码／上传规格的用户档 |
| 阴影 | 禁用／低／中／高／超高 | Scene 按定向、点、聚光的实际 caster／receiver 编码，有定向分配降级。缺用户开关与预算档 |
| 体积照明 | 禁用／低／中／高／超高 | Scene 有透视根域的无阴影点光深度积分，以及可在根层、普通父层和局部 source 绘制的聚光锥。遮挡、投影混合和 3D 聚光覆盖各自有限 |
| 反射 | 开／关 | Scene 的模型及普通图像已有实时反射消费者，部分通用 Program 消费 `.sceneEnvironment`。反射历史和普通画布／具名历史有不同寿命 |

官方资料明确了普通／HDR Bloom、三种投影灯、点／聚光体积、Web FPS 建议和视频素材质量。四套预设的实际属性值见下方客户端核验，渲染差别与生效时机仍由固定版本的单项 A/B 验收。 [性能 FAQ](https://help.wallpaperengine.io/en/performance/gpu.html) · [Web FPS Limiter](https://docs.wallpaperengine.io/en/web/performance/fps.html) · [Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) · [高级光照](https://docs.wallpaperengine.io/en/scene/models/lighting.html) · [反射](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) · [纹理分辨率开发者答复](https://steamcommunity.com/app/431960/discussions/2/3035978213219373047/) · [mip 开发者答复及后续修复](https://steamcommunity.com/app/431960/discussions/1/4418677198500806035/)

重用本仓库的 Apple Silicon／macOS 26 路线，分别由 AppKit、Metal、WKWebView、AVFoundation 承担现役职责。主 App 管用户意图，运行端保各自时钟、资源与唯一输出。运行中的质量改变沿既有执行代次投递，画面接管沿原产品事务。 [技术栈合同](../architecture/technology-stack-boundaries.md) · [三引擎切换事务](../architecture/playback-lifecycle-transaction-design.md) · [Scene 默认质量与采样域](../scene/architecture/runtime-architecture.md#effective-quality-policy) · [Web 现役状态](../web/current-state.md)

<a id="product-and-state"></a>
## 控件、偏好与生效

### 入口与作用范围

- 复用 `SettingsWindowController`、`AppKitSettingsView` 和 `AppSettingsPanelDependency`。质量区域由动画帧率、Scene 质量、Web 建议和 Video 素材组成。Scene 后处理统一管理显示 HDR。作品的作者属性仍可从原属性面板操作。 [布局现址](../../MyWallpaperX/Shared/Settings/AppKitSettingsView+Layout.swift) · [设置动作注入](../../MyWallpaperX/Shared/Settings/AppSettingsPanelDependency.swift)
- 全局「动画帧率」首批保留 30／60 两值，随后在已验收范围内采用可键盘步进和直接输入的 1 FPS 滑杆，目标范围为 10–120。副标题说明 Scene 使用此调度上限，受当前屏幕组合限制时并列显示意愿与生效值。Web 可选「随显示器（最高 60）」或「跟随动画帧率」，缺省随显示器；跟随后，帧率、预设或 Web 模式变更将重算作品建议。Video 显示已知的片源分辨率与素材帧率，派生达到交付门后再显示素材选择。静态图、封面、系统屏保与锁屏遵循各自既有路径。
- 使用 AppKit 原生 segmented control、popup、switch，连续 FPS 经验证再用有数值反馈和键盘步进的 slider。Tab、VoiceOver 读出控件名和当前值，说明和失败状态用文字表达；窄窗、浅／深色及已支持语言的长文案实查。拖动时可预览数字，触发资源准备或 IPC 只在一次完成编辑时合并提交。 [本地化与布局标准](localization-contract.md#layout)
- 「恢复默认画质」沿一次差分更新复位帧率、Web 模式和已交付的画质字段。显示 HDR 随后处理档恢复为普通超高。保留用户请求值；当前作品不适用、设备不支持、重新应用才生效或回用原画的理由，从已有引擎就绪／准备结果一次反馈。未完善的档位留在开发验证面。状态基于既有事件，Web 无作者回执时显示「作品支持时应用」。

### 数据与生命周期

| 层 | 拟落地职责 |
|---|---|
| 持久化与入口 | 延伸现有播放偏好。Q1 的 typed UserDefaults 值只含动画 FPS 和 Web 模式，后续仅随实际消费者加入字段。按请求向量匹配预设，手改向量时重新判断「自定」。设备、内容、预算导致的有效值变化另用现有状态呈现。Q2 加入后处理请求，Scene 只在有效输出意图变化时更新。 |
| 首开与升级 | 新记录未建立时取 `mwx.playback.performanceProfile` 的合法 30／60 与原缓存映射，缺失或无效时用 60。已有新记录中新增字段按兼容默认初始化。旧键供一次迁移或旧版读取，日常只写新值。自定义 FPS 须先测独立 decoded cache 上限，再一起退役原帧率绑定与重复额度写入。 [画质偏好与旧键投影](../../MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift) |
| 便携 v8 导入／导出 | 按明确声明的字段更新。新 FPS 合法时优先，只有缺省新 FPS 才读取合法 legacy 30／60。新字段存在但枚举未知或数值越界时保本机相应字段，类型或结构错误沿原写入前错误。旧档只含 30 时只改 FPS，保本机 Web 模式和其它档。导出向旧字段仅投影能表示的 30／60，直接退回旧二进制仍读取升级前旧键。 [v8 载荷](../../MyWallpaperX/Models/PersonalSettingsPayload.swift) |
| 中断恢复与复位 | 旧 v3 恢复票据在 preferences 阶段前将实际声明的字段投影到相同 typed 比较，沿原 before／target 处理间隔编辑。已结算的 preferences 继续承认其收据，存储按启动迁移。画质复位和完整重置显式写默认向量，保原 reset epoch。旧恢复票据里相同的隐含 HDR 布尔值作为未编辑处理。验写前／写后中断、用户后续更改及旧键 30 同时存在的反例。 [导入恢复](../../MyWallpaperX/App/PersonalSettingsImportCoordinator.swift) · [完整重置](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift) |
| App 到执行端 | 通过现有动作和命令层下发各端实际消费的 typed 字段。Scene 沿单一父端和 daemon wire。Web 定向到现有 Web 入口，处理 Video／Web handler 别名和广播去重，更新 Web 会话与以后 launch 的 seed；Video 没有需要消费的 FPS 消息。wire 以现有版本和请求信封承载，启动状态含完整有效子集，变更发一次差分或小快照。 [App 装配](../../MyWallpaperX/App/MyWallpaperXApplication.swift) · [命令层](../../MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift) · [Scene IPC](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol.swift) |
| 执行端有效值 | 由当前内容、设备／显示能力、实际 consumer 与原帧／资源合同决定。字段只进入其消费点；静态资格于准备期确定，动态作者值仍由 typed snapshot 提供。执行有效值和回退原因可按已有状态／诊断观察，请求值可以在换作品或换屏时重新求有效。 |
| 失败与回退 | 热更新只在当前会话和合法边界采用；已准备的下次应用项按最新偏好重新解析。需要更新资源／pipeline 的候选沿现有 request、generation、surface、提交和 pin，候选失败保旧画面，取消或更晚的意图淘汰旧结果。关闭/恢复档位沿原单一事务，无新 watchdog、每帧 IPC 或偏好认证。 |

Scene FPS 在下一排帧边界采纳，Web 在当前文档回调，能原位采用的可选 Metal 功能在提交前的帧边采纳。预算或资源规格引起的重新准备优先标明「下次应用壁纸生效」；需要「现在应用」时用原同源执行事务，它可能重建作者 VM 和动画历史，状态不能安全迁移的作品应明确表述。Scene 暂停时只用原路径必要的冻结帧更新；已提交的 Web 页面暂停时保存最新设置，沿原恢复回调交付。暂停、切换、轮换、系统休眠与恢复原先各有权威。

### 四档候选

兼容默认向量为 60 FPS（升级保原 30／60）、1×、作者适用的普通／HDR 泛光、现役纹理与自适应阴影、点光原全尺寸四点和原聚光锥、作者可用的实时反射。Web 按屏幕给建议，Video 默认原片。恢复默认采用这个向量，后处理选普通超高。

预设沿已核对的官版请求向量。帧率、抗锯齿、后处理、纹理、阴影和反射直接投影。现有体积「启用」保作者点光和聚光的实际贡献，各档先共用。原 60 FPS 兼容默认向量不随发布改变，恢复默认也沿同一向量。

| Scene 预设 | FPS | 抗锯齿 | 场景泛光 | 纹理分辨率 | 阴影 | 体积照明 | 实时反射 |
|---|---:|---|---|---|---|---|---|
| 低 | 10 | 无 | 禁用 | 高质量 | 低 | 启用 | 关 |
| 中 | 15 | 无 | 启用 | 高质量 | 中 | 启用 | 开 |
| 高 | 25 | MSAA ×2 | 启用 | 高质量 | 高 | 启用 | 开 |
| 超高 | 30 | MSAA ×2 | 超高 | 高质量 | 超高 | 启用 | 开 |

用已保存的 Scene 请求和动画帧率精确派生当前预设。任一字段不同就显示「自定」。设备上限、EDR 和作者的实际生效范围独立确定。待验的体积分级随其验收映射。HDR 显示、高刷和高性能纹理保独立选择。Video 文件继续各自选择。Web 已选择跟随时接收同一动画帧率建议。 [官版向量](#official-quality-evidence)

<a id="scene"></a>
## Scene 逐项技术裁决

### 帧率上限

- **首批方案**保留 30／60 的可见语义，共享同一 daemon host 配置，包含候选、重建和恢复。复用 `SceneDesktopWallpaperSession+FrameDriver` 的单次 Timer、GPU admission／忙帧重试与 `SceneClock` host time；切档更新调度上限和既有对应 decoded cache 额度，仍用真实经过的场景时间。单独核对 Timeline、VM callback、粒子、媒体、作者日期、暂停首帧和恢复时间。多 Surface 仍由同一 session clock 供时。 [现有帧驱动](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift) · [Scene 时钟](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneFrameContext.swift)
- **10–60 FPS**先解耦帧率与解码缓存，再从设置入口规范化整数值。按单调目标期限跳过错过的周期，忙帧沿原 admission，热切重定下一期限。验 10／11／24／25／30／59／60 和越界值。10 FPS 核粒子、动画事件、媒体、触控响应和基于帧计数的脚本，保作者时间与原回调语义。25 FPS 在固定 60 Hz 屏上按稳态上限和呈现间隔分布验证，忙后保持无连续补帧，明确区分提交与物理呈现。
- **61–120 FPS**在高刷屏和真实输入的 GPU、作用线程及耗电结果通过后开放，验 61／90／119／120、退出高刷与热插。现有 Session 由单一时钟驱动多 Surface，先以单高刷屏或同刷新率组合取证。混合刷新率先沿已验证共同上限运行；只有省掉低刷屏额外提交的价值成立，才在既有驱动中按 Surface 准备有效调度，继续共用 SceneClock。用户选择可随屏幕限制临时降效，屏幕更换重新取有效值。
- **技术比较**优先现有 Timer。若实测发现跨刷新率抖动、额外唤醒或提交错位，再在同一驱动职责内比较 `CADisplayLink`／`CAMetalDisplayLink`。系统帧率范围是调度提示，验收以尝试／提交／GPU 完成／presented 及长窗节奏为准。 [Apple 帧节奏建议](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings) · [CAMetalDisplayLink 帧率提示](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframeraterange)

<a id="scene-aa"></a>
### 抗锯齿

**选型为默认 1×，合格的 3D 主几何域优先试 Metal 原生 MSAA ×2。** 做过迟 resolve 的样本 358 在 3024×1964 下，GPU 帧时 P50 由 15.180 增至 18.463 ms，池峰约 743 至 855 MiB。环边阶梯减轻，碎石暗点仍在。独立样本 347 的 GPU P50 由 12.178 增至 13.316 ms，画面收益不足以抵消成本。两组短窗导致通用默认 2× 撤回，已有 4× 局部覆盖参考。重启 2× 必须利用能降低旧成本的实际几何域，再证整景动态收益。 [已有 GPU／像素对照与停止线](../scene/capabilities/model-runtime-evidence.md#model-raster-coverage)

| 算法 | 对本项目的取舍 |
|---|---|
| **Metal MSAA** | 在光栅化时处理几何覆盖、遮挡与混合，保原生输出尺寸。Apple GPU 在合格连续段可用片上 `memoryless` 附件并 resolve 到单采样原输出。跨 pass 须保留样本时，额外色深存储和读写是主要成本。 [Apple MSAA 示例](https://developer.apple.com/documentation/metal/improving-edge-rendering-quality-with-multisample-antialiasing-msaa) · [附件 load／store 合同](https://developer.apple.com/documentation/metal/setting-load-and-store-actions/) |
| FXAA／SMAA 1× | FXAA 在单采样终图单遍滤波，SMAA 1× 用边缘检测、权重搜索和混合改善斜线。适合作只能取得终图时的独立候选，须同时比较文字／线稿锐度、HDR 和全屏读写。已合成的颜色不足以重建原逐样本遮挡。 [FXAA 白皮书](https://developer.download.nvidia.com/assets/gamedev/files/sdk/11/FXAA_WhitePaper.pdf) · [SMAA 论文](https://www.iryoku.com/smaa/downloads/SMAA-Enhanced-Subpixel-Morphological-Antialiasing.pdf) |
| TAA／MetalFX Temporal | 可针对运动亚像素闪烁。接线需可信的运动向量、深度、抖动、历史重置和透明效果的有效输入。当前 Scene 缺可覆盖作者材质、骨骼、粒子和具名图的共同运动输入。仅在真实输入能闭合的 3D 场景重开。 [Apple MetalFX 时域接线](https://developer.apple.com/videos/play/wwdc2022/10103/) · [透明效果与拖影](https://developer.apple.com/videos/play/wwdc2025/211/?time=406) |
| 超采样／纹理过滤 | 两轴 2× 超采样会产生 4 倍渲染像素，适合离线边缘参考。缩小纹理产生的摩尔纹由其 mip 与过滤处理，保作者的 nearest／图集合同。 [Apple mip 采样](https://developer.apple.com/documentation/metal/improving-texture-sampling-quality-and-performance-with-mipmaps) |

**设备级别**。Apple 当前能力表中，M1／M2／M3–M4 对应 Apple7／8／9，原生 render pass 的 MSAA 上限为 4×。8× 列在 Apple10（含 M5）和 Apple11。Apple7 已列出 `rgba16Float` 过滤、混合及 MSAA／resolve，`depth32Float` 的过滤资格单独看设备。档位仍由实际 device sample count、格式／PSO 和预算决定。当前请求为无、2× 和 4×。8× 要在实际支持的设备和格式取得正向画面及预算证据。跨设备导入保有已交付的意图。 [Apple GPU 映射、采样上限与像素格式表](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)

**实现和生效**由原 `SceneMainPassEncoder` 准备实际颜色和相机深度的共同采样域。设备、附件格式、PSO 和当前资源预算在准备期接纳 2×／4×／8×。共用附件的模型、文字、图像与粒子使用匹配的 pipeline（含 alpha-to-coverage 和深度状态）。连续段用 `.multisampleResolve`，中间读色后续画须保逐样本色深和原顺序。非线性 attachment-read、无法匹配 PSO 或紧预算时该域采用原 1×，界面保请求并显示有效值。独立阴影、VolumeOccluder、compute、真实具名离屏仍按自身附件合同。高采样数独立验证每档收益，低档不可用时按 1× 回退。 [采样域合同](../scene/architecture/runtime-architecture.md#raster-sample-domain) · [粒子 PSO](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift) · [设备采样数查询](https://developer.apple.com/documentation/metal/mtldevice/supportstexturesamplecount%28_%3A%29)

**实测验收**固定原生像素、相机、场景相位和 LOD，用独立高采样参考量斜边 alpha 覆盖误差和连续帧边缘跳变。近远半像素遮挡换序、前缀读取后续画、透明模型和粒子、`clear=false`、具名历史、SDR／HDR 与小预算回退必须能区分错解。纯 2D、文字和未命中的工作量作为负控。分别量 resolve 次数、帧时 P95、submit／present、私有附件及在途峰值。候选须在合格作者正例和独立动态作品有可重复的改善，并在承诺设备／帧率守住[质效门](#quality-release-gates)，否则保 1×。

<a id="scene-post-processing"></a>
### 后处理与 HDR

**选型为现有低尺寸可分离 Bloom 和保留当前 HDR 工作域的浮点金字塔。** 场景后处理首先负责全景泛光及显示 HDR。作者启用 HDR Bloom 后，官方最终播放中的用户档需用「超高」，并可让作者另配普通 Bloom 供「启用」档使用。属性面板只控制作品公开的相应作者参数。自定义局部 effect 沿其图执行。Windows 编辑器预览与 macOS 每屏 HDR 显示各有自身状态。 [官方 Bloom 合同](https://docs.wallpaperengine.io/en/scene/effects/bloom.html)

| 算法 | 对本项目的取舍 |
|---|---|
| **现有 MSL 分离模糊与 HDR 金字塔** | 普通路线在宽高 1/4 提取，1/8 做纵向、返回 1/4 做横向，按源物理像素计步距，最后用 RGB 加法写回。HDR 用 `rgba16Float` 保超白值，首级按面积聚合先逐像素取软阈值的贡献，再做 tent 降采样与加权重建。HDR raw／history 及作者混合沿当前 display-referred 工作域，EDR 终端才解码到线性输出。combine 无需新全尺寸结果。 [Bloom 实现](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneBloomPostProcess.swift) · [终端颜色转换](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneDisplayMappingPostProcess.metal) · [阈值与奇数边合同](../scene/capabilities/render-graph-shader-coverage.md#hdr-bloom-extraction) |
| 全尺寸 Gaussian／MPS | 可在离线或同尺寸探针中做参考。sigma、边界权重、色彩、alpha 和源步距决定实际光晕，高分辨率中间读写仍有成本。保持现有分离路径，只有相同光晕和作者结果的候选在 Apple GPU 实测有明确收益时才替换局部滤波。 [MPS Gaussian API](https://developer.apple.com/documentation/metalperformanceshaders/mpsimagegaussianblur/init%28device%3Asigma%3A%29) |
| Dual Kawase／减少金字塔级数 | 更少采样或在小纹理处理宽晕是候选。核形、跨级权重和亚像素能量会改变光晕。优先保作者级数，缩档须守阈值、强度和局部对照。已有有界官方宽块结果支持沿当前核，薄线的官方精确能量和通用性能仍待取证。 [Dual Filtering 方法](https://community.arm.com/cfs-file/__key/communityserver-blogs-components-weblogfiles/00-00-00-20-66/siggraph2015_2D00_mmg_2D00_marius_2D00_notes.pdf) · [项目 HDR 证据](../scene/capabilities/runtime-evidence-current.md#hdr-bloom-extraction) |

**档位和生效**「禁用」沿原终端让预约和编码使用同一有效配置，跳过全景泛光，保原颜色、alpha、局部效果与 raw history。作者 General 开关仍供作者逻辑。普通与禁用档须在原准备入口确定有效 HDR 工作域和亮度，终端再分别走普通泛光或跳过。当前 HDR 初始化选择 HDR PSO，普通档使用原普通准备入口。「超高」采用作者 HDR 金字塔，普通作品仍可用基础路径。作者禁用、零贡献或可选分配失败沿原局部结果。两个超高档共用作者工作域，只有「超高（显示 HDR）」向可用屏申请 EDR。 [作者场景和粒子](../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift) · [合成与终端](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ClearColor.swift) · [Apple EDR 映射](https://developer.apple.com/documentation/metal/performing-your-own-tone-mapping)

普通参数缺省在 General 已补为 1／0.65／白色。先用固定官版对照仅配置 HDR、显式普通参数等于默认、以及有动态普通绑定的场景。「启用」如适用普通缺省就直接用现有值。如果仅显式配置时才生效，在现有 General 解码保留消费所需的最少声明或绑定信息，沿当前 descriptor 投影。该语义通过黑盒与原 App 夹具后再开放「启用／禁用」。 [General 解码](../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument+General.swift) · [摄像机配置](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor.swift)

当前禁用／零贡献早退会留下原 `SceneBloomPostProcess` 对暖纹理的引用。用户改档停用一条链时由该 owner 在帧边释去该链的缓存引用，保在途 command buffer 的资源直到完成。作者动画短暂经过零只跳过当前帧工作，沿原容量规则复用。退出暖占用须以同进程里的实际配额可再次取得验证，必要附件优先。

**实测验收**用单亮像素、多相位细线、偶／奇数边界、宽亮斑、彩色过亮和零强度输入。在原工作域比较 `开 − 关`。需报告线性输出时对开、关各施同一终端变换再取差，记录两组实际 headroom。量近／中／远光晕剖面、RGB 贡献积分、alpha 和基础颜色，验仅普通／仅 HDR／两者皆有及动态开关。再跑含体积加光、反射和 `clear=false` 的作品，确认 Bloom 读取完成主色、累积历史保持 raw，验证预算失败后恢复和完成后可再取得配额。记录各级 pass、实际尺寸和读写、首次切档时间、暖／在途峰值、P95、呈现与 SDR／EDR 换屏。

<a id="scene-texture-quality"></a>
### 纹理分辨率

**选型为保作者 mip 与可用的原生 BC，合格静态色图选择真实较小 mip／解码尺寸。** 沿原 Loader、source revision、`TextureKey`、raw／BC uploader 和 frame publication 结算。Apple Silicon 用统一内存，RGBA8 的 4096² 基级单张逻辑 64 MiB，从作者 2048² mip 开始可跳过这部分基级数据。BC、对齐、cache 及同时在途改变物理读写和峰值，须另量。现有采样器按作者 filter 决定 mip 插值，线性且符合各向异性条件时已有最高 16 的设置。 [Loader](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift) · [采样器](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift) · [设备 BC 能力](https://developer.apple.com/documentation/metal/mtldevice/supportsBCTextureCompression)

| 算法 | 对本项目的取舍 |
|---|---|
| **作者 mip 尾和原生 BC** | 合格 TEX 上移物理 base，上传保留的原 mip，源文件原样。先以一档试验，保颜色角色、滤波／地址语义、逻辑尺寸和有效取样密度。Apple7／8 也须按 macOS 上的实际 `supportsBCTextureCompression` 和用途选择，失败沿已支持解码路径。若当前容器仍物化全部 LZ4／mip payload，初版只计已证的 GPU 上传／驻留收益。解码成本确为瓶颈时，在原 parser 的 payload 材料化点跳过已完成边界检查的未选级。 [TEX 读取](../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift) · [压缩上传](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift) · [Metal 格式表](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf) |
| **ImageIO 目标尺寸解码** | 静态普通 RGB(A) 图片沿原入口试长边 2048，保 ICC、颜色空间、预乘 alpha 和逻辑像素。非默认方向 JPEG 沿原 EXIF thumbnail transform，与缩小在一次输出完成，其他格式保原方向规则。每种纳入格式实测 CPU 峰值，含特殊 alpha／色彩解码而语义未证相同的图片继续走原路径。 [现有 ImageIO 与上传](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift) · [Apple ImageIO 指南](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/imageio_source/ikpg_source.html) |
| LOD bias、GPU 重采样、重压缩／streaming | 现有 mip 过滤处理取样闪烁。只改 bias 仍保完整分配。GPU 上传后再缩小须计双方同时驻留和带宽，适合已有原尺寸消费者的情形。ASTC 重新编码和 sparse 需额外硬件门、映射及缓存维护，由独立瓶颈决定。 [Metal 纹理优化](https://developer.apple.com/documentation/metal/optimizing-texture-data) |

**档位和生效**「高质量」等同现役选择、尺寸上限和设备预算。「高性能」对用途已知且可缩放的静态色图减少实际规格。「自动」由准备期的最大投影 footprint 取满足目标屏与所有消费者的最小已验证表示。缺稳定投影上界或依赖精确像素时沿原规格。已证明的静态普通图随实际 drawable 扩大越界后异步升级到原基级，准备阶段沿现役尾链。精确像素寻址、固定 LOD、`g_TextureResolution`／mip 信息参与精确作者计算、未知通道、数据／法线、atlas／动画、mask/cutout、LUT、体积、动态／Video 保原语义。实际表示不同且共享缓存会相遇时才加 GPU key 的 base mip／extent，CPU 原字节可共享，旧代待现有租约和 GPU pin 回收。档位在下次应用时采用，已选择自动的会话可以在原 Surface 内升级资源。 [候选元数据](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift) · [资源准入](../scene/architecture/scene-resource-admission.md)

首批只接通无 padding、已知全域归一 UV 的静态色图。候选几何记录实际 GPU extent 和用于取样的 mapped extent，降档后两者都来自所选输出，保持 UV 比例为 1。作者原逻辑尺寸由现有布局元数据供应实际消费者。`candidateOutputGeometry` 当前只接受原物理尺寸或现有规范化尺寸，须在这个入口识别已授权的 base mip／缩尺寸输出。ImageIO 现把解码结果与原 `displaySize` 比较，在原 uploader 验证所选输出尺寸并复用其方向结果。精确和带 padding 的角色保既有尺寸校验。 [候选 UV 几何](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift) · [ImageIO 尺寸及方向](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift)

**实测验收**用真实 4K 静态 TEX、普通图片分别量源读取、解析／LZ4、ImageIO 解码、Metal 上传及 `allocatedSize`／池计费／进程峰，按冷、暖、切档与新旧 Surface 共存取样。用条纹斜移和实际 1×／2× 显示验证摩尔纹、锐度、UV 与颜色。检查候选物理 mip 尺寸、边界采样和作者布局尺寸，加入定向不对称 JPEG、ICC、透明边、奇数长宽、颜色和数据共享消费者、资源改名、等价表达及带 padding 的 atlas/cutout、动态媒体、绝对取样、无 mip 反例。验 Auto 的尺寸决策、换屏／放大、源 revision 与坏缓存重建。实际减少内存／解码成本且可见精度在预登记范围内时，才公开对应档。

<a id="scene-shadow-quality"></a>
### 阴影

**选型为现有灯空间深度图＋接收平面校正的 PCF，首批用是否生成阴影和真实深度图预算分档。** 定向图根据实际可见接收区做固定世界网格拟合，定向比较当前 16 tap（分组 gather），点／聚光保原 4 tap。点光为六面 3×2 atlas，聚光和定向各一图。深度图跨 pass 供接收者读取，用原 `depth32Float` 池。单图 1024² 的逻辑载荷约 4 MiB，4096² 约 64 MiB，单个点光 1024 六面约 24 MiB。历史固定 1024→4096 短对照 GPU P50 20.354→23.417 ms，池峰约多 120 MiB（两个在途图）。因此档位先控制真实图尺寸，采样成本单独量。 [现役编码](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+StaticModels.swift) · [接收面滤波](../scene/capabilities/advanced-object-coverage.md#model-directional-shadow-filter) · [图尺寸对照](../scene/capabilities/model-runtime-evidence.md#model-directional-shadow-density)

| 算法 | 对本项目的取舍 |
|---|---|
| **现有 shadow map 与 PCF** | 保合法屏外 caster、同帧 pose／UV、镂空材质、真实接收面、灯序和偏移。GPU 用原 gather 与逐 tap 深度参考。调 map 密度直接影响覆盖、内存和带宽，PCF 的世界尺度随 texel 变化，需要同时验证阴影边宽。 |
| 硬件单参考 PCF／PCSS | 固定比较参考的硬件 PCF 不能表达现有逐 tap 的接收面深度。PCSS 能按遮挡者距离改变半影，增加遮挡搜索与采样，需要真实作者光源尺度及遮挡材质合同。有独立软阴影需求时再比较。 [PCSS 原文](https://download.nvidia.com/developer/presentations/2005/SIGGRAPH/PCSS.pdf) |
| VSM／CSM／光追 | 方差图可预滤但需要统计纹理和压制漏光。级联可改善宽距离跨度，却增加图、边界和共享预算。实时光追引入加速结构与动态几何更新，也扩大硬件资格。当前需求由实际接收区的单图与预算解决，另有实证问题再立项。 [VSM 方法与漏光](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-8-summed-area-variance-shadow-maps) · [Metal 光追加速结构](https://developer.apple.com/documentation/metal/ray-tracing-with-acceleration-structures) |

| 档位 | 定向图候选上限 | 点光／聚光每面候选上限 |
|---|---:|---:|
| 禁用 | 跳过 map、caster encode 与 receiver 阴影采样 | 同左 |
| 低 | 512 | 512，验证点光六面与聚光边缘后采用 |
| 中 | 1024 | 1024 |
| 高 | 2048 | 1024 |
| 超高 | 4096，沿原接收区选择 | 1024，沿现行路径 |

**实现和生效**先验禁用、定向上限 1024 和现行自适应上限。高图集预约仍整体优先保护必需主附件，分配失败走原局部回退。当前原定向 fit 基于 1024 的保守边界，逐灯分配及高图回退也有 1024 固定值。试 512 时用同一有效 extent 接通投影边界／texel 稳定网格、逐灯与整组回退、实际 atlas viewport 和 receiver 采样，验证不会越过档上限或削掉有效投影。禁用改变实际阴影生产和读取，保直接表面光、相机深度、体积遮挡与作者 `castsShadow` 声明。作者设为投影的点光仍按现有定义排除在无阴影体积积分外。中／高／超高在只有点光／聚光时可等效。 [作者点光资格](../../MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePointLightDefinition.swift)

**实测验收**用固定 world 网格和亚 texel 四相位的原生 Metal 正控，量投影轮廓位移、静态邻点亮度随时间变差、接触间隙、遮挡孔洞和自阴影伪影。动态骨骼、组裁剪、合法屏外 caster、点光六面接缝、聚光锥边界、多灯紧预算、草木 cutout 和原独立实体遮挡为正反例。比较每灯 map 真实物理尺寸、caster draws 和深度 pass、接收者着色成本、纹理计费及连续帧 P95。低档的柔化或边缘跳变须守预定可见容差，关闭时三种可选阴影工作实际归零，且直接光与普通遮挡保持。 [实际投影与覆盖合同](../scene/capabilities/advanced-object-coverage.md#model-directional-shadow-density) · [完整回归与影边成本](../scene/capabilities/model-runtime-evidence.md#model-directional-shadow-filter)

<a id="scene-volume-quality"></a>
### 体积照明

**选型为点光保当前球内有限视线的分段 Gauss–Legendre 求积，聚光保自己的有序光锥绘制。** 点光需要清屏透视根域、作者无阴影的合格点光、至少一个合格的根域实体写入者。用独立遮挡深度截取视线，进出球界之后在最近点分段，每段现用四点求积，指数零直接用线段长度。聚光当前是按作者 TRS 及材质参数绘制的锥形覆盖，沿根层、父层和组 source 位置合成。两者已有真实链证据，通用照明、多重散射及更广聚光遮挡须各自验收。 [点光合同](../scene/capabilities/advanced-object-coverage.md#point-light-volume) · [点光 MSL](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/ScenePointVolume.metal) · [实际遮挡生产](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+StaticModels.swift) · [聚光锥合同](../scene/capabilities/advanced-object-coverage.md#spot-light-frame) · [代表实播证据](../scene/capabilities/runtime-evidence-current.md#point-light-volume)

| 算法 | 对本项目的取舍 |
|---|---|
| **原尺寸四点积分／原有光锥** | 点光在同一实际遮挡深度上积分，按真实光球投影的保守并集收紧片元覆盖，输出直加原主颜色。全屏仍走同一积分。同尺寸两点未复现收益，实验已退役。聚光开关沿真实 producer，保作者锥形覆盖和顺序。 [实测](wallpaper-quality-work-card.md#scene-volume-point-coverage) |
| 半宽高积分＋深度引导重建 | 色积分像素数约 1/4，增加中间颜色目标与重建。每个粗像素读取自身射线对应的深度 texel，按原反向深度和相机重建到可比较的视空间尺度，再用全尺寸深度邻域引导。沿用整数读取，避免跨边混合以及依赖部分 GPU 缺少的 `depth32Float` 过滤。计遮挡重放、分配、读写与合成总成本，若薄障碍或深度断层回归、总帧时无稳定收益，保现有原尺寸四点。 [联合上采样参考](https://johanneskopf.de/publications/jbu/) · [Metal 像素格式表](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf) |
| 逐像素 ray march／froxel／时域重投影 | 支撑更广的阴影体积和介质，增加采样、3D 网格或历史，且会碰到作者分组／顺序和动态透明深度。待有完整的光空间可见性和介质需求再独立评估。 [视锥体素照明实践](https://advances.realtimerendering.com/s2018/Siggraph%202018%20HDRP%20talk_with%20notes.pdf) |

| 档位 | 点光已交付基线与其余候选 |
|---|---|
| 禁用 | 停可选遮挡收集、独立深度重放及终端加光，保表面光与主相机深度 |
| 低 | 同尺寸两点已退役。整帧收益有证据时再试半宽高两点＋深度引导 |
| 中 | 半宽高四点＋深度引导的候选。只有与低档在画面及完整成本上存在一致分级时开放 |
| 高 | 对应已交付「启用」所用的原尺寸四点兼容基线，积分区域按实际场景收紧 |
| 超高 | 全尺寸试六点或经验证的较高阶数，薄峰与积分误差有独立收益才开放 |

**实现和生效**首片交付禁用及现行质量。关点光一并跳过遮挡收集与度量需要的 optional pass，实体深度仍由实际合法几何供给。关聚光要证明在根层、组和显式图输入的原位置取消贡献，保其它 producer、父程式输入、顺序、可见性和普通灯。首片只有点光具备这项证明时按「点光体积」呈现。比较新等级只改变目标中间尺寸／求积阶数，作者半径、密度、指数和亮度仍由原参数控制。 [顺序编码与遮挡重放](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+OrderedLayerEncoding.swift)

**实测验收**用离线高精度积分或指数零的解析长度验证能量与光锥轮廓，再用场内球内／外、擦边射线、近远裁剪、亮窄峰、透明轨、薄实体、名义有灯但零贡献及 group／named spot 夹具核原 App。配对作者启用／关闭 `castsShadow`，分别切用户阴影档，核前者不会生出无阴影光束。移除唯一合格根域实体作无体积负控。单列前景两侧的漏光与轮廓偏差，核异尺寸换屏、开关无错误残影、Fog 与直接灯邻例。量遮挡深度重放、积分、重建各自成本和总 P95、带宽、临时池与整机能耗。额外纹理读写吞掉节省时放弃半尺寸，较高积分阶数未超过参考噪声时让「高」保持上限。

<a id="scene-reflection-quality"></a>
### 反射

**选型为沿原实时屏幕颜色近似反射，按真实消费者启用最近合格完成帧的完整颜色与 mip。** 模型路径对屏幕颜色按法线偏移、视角权重、边缘淡出与粗糙度 LOD 取样。图像和合格 Program 的环境输入沿各自已准备着色。独立水滴和同作品官版开／关对照已证局部贡献，尖端与相位的精确一致和整景性能仍需对应实测。统一内存上的全图复制和 mip 阶段应分开测。以 UHD 的 `rgba16Float` 为例，单基级约 63.3 MiB 逻辑载荷，完整 mip 链约 84.4 MiB，原 raw／候选与在途租约另计。 [原模型采样](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneStaticModel.metal) · [模型反射证据](../scene/capabilities/model-runtime-evidence.md#model-screen-reflection)

| 算法 | 对本项目的取舍 |
|---|---|
| **原合格完成帧颜色＋mip** | 复用原 `ReflectionFrame`、pool、blit 和完成状态。经尺寸、像素格式及提交收据接纳的最近成功帧可跨过失败或无呈现帧。只有实际被采样才准备环境副本及 mips，采样与 publication 留同一执行代。Metal blit 要求实际格式可渲染、可过滤，mip 核随 GPU 家族可变。 [现有历史与 blit](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ClearColor.swift) · [Metal mip 生成](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/generatemipmaps%28for%3A%29) |
| 平面反射／环境 cubemap | 镜面重绘需第二视角、遮挡／剪裁和更多带宽，只适合确认的平面。探针或预过滤 cubemap 可给作者已声明的环境，动态更新和屏外内容需要别的输入，不能拿静态图替实时系统的一般颜色贡献。 |
| 深度 ray march SSR／Metal 光追 | SSR 要完整几何深度并处理屏外、遮挡与透明缺失。光追另需加速结构、动网格同步和硬件资格。当前由作者材质与完成的颜色供货满足首批开关，仅在真实可观测的反射缺口下独立研究。 [屏幕空间射线方法](https://jcgt.org/published/0003/04/04/) · [Metal 光追](https://developer.apple.com/documentation/metal/ray-tracing-with-acceleration-structures) |

**开关和生效**「关」抑制可选采样和贡献，适用于已准备模型、受光图像及证明能失去环境的 optional slot。若没有必需环境消费者，再停快照和环境复制／mip。混合必需 Program 的同一 Surface 沿当前共享生产者供货及推进收据，只关闭可选材质贡献，恢复时可采最近合格环境。主画布完成事实目前也经 `ReflectionFrame.mainSourceCompleted`，沿唯一终端继续供货。普通颜色／named history 和局部折射保持职责。需要改变 `CAMetalLayer.framebufferOnly` 或实际附件规格时走原 Surface 重准备。 [消费者准入](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight+Admission.swift) · [当前收束](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift) · [反射合同](../scene/capabilities/advanced-object-coverage.md#static-model-screen-reflection)

可选 `.snapshot` 因关档停产时，由原提交 owner 撤销旧快照的再用与完成采纳资格，原 GPU pin 保到 terminal。重开时先用基础材质，待本次启用后成功完成的快照才恢复。仅场景工作域启用 HDR 且 `clear=false` 时，必需 `.persistence` 沿原收据更新，开档可使用同请求最近合格 raw，包括关档期间完成的 raw，已累计的作者颜色继续保留。两者沿原 receipt 判定，整图 invalidate 会清掉持久／named history，热切应避免。现有提交边界若无法仅处理停产的可选快照，选择「下次应用」或原 Surface 重准备。 [raw 准入条件](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ClearColor.swift) · [快照资格与完成](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+SceneColor.swift) · [现有失效边界](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Lifecycle.swift)

**实测验收**以同一素材控制反射率、粗糙度、视角和屏幕边缘，核方向、粗糙度模糊、边界淡出、基础材质和 alpha。令 A 开档红、B 关档绿、C 重开蓝，令关档前的可选 A 晚完成，核停产 `.snapshot` 路径的 C 首帧使用基础材质且后续只采合格新代，加入非 HDR `clear=false` 防止误入持久路径。配对场景 HDR 且 `clear=false` 核 C 可采最近合格的 B 持久 raw，必需主色与既有 named publication 一直有效。混合 Program＋模型验证 B 时必需 Program 像素与源收据保持原节律，可选模型反射为零，C 可采关档期间合法推进的历史。补真实显隐、大小与多屏换代、暂停开关、首帧或快照失败、GPU 取消和无环境消费者。数快照、base copy、mip 编码、逻辑与驻留字节、P95／呈现和耗电。混合作品报告部分生效，纯可选作品关档去掉新增环境工作。

<a id="scene-quality-interactions"></a>
### 六项组合的执行边界

1. 采样域、显示范围和源用途分别在原准备入口确定。阴影图和体积实体遮挡保各自深度。作者 Project 的有界 FBO 缩放保原 source 及容量回退，加入跨采样域读取的反例。主颜色完成后，现行反射可选快照取含已编码体积贡献、尚未施加终端 Bloom／显示映射的源，后续 Bloom 再修改显示侧，最终只走原 SDR／EDR 映射。组内作者效果保原顺序。用 `clear=false`、HDR 和透明／具名源验证上述依赖。 [作者 Project 尺寸合同](../scene/capabilities/render-graph-shader-coverage.md#project-scaled-framebuffers) · [帧顺序](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+OrderedLayerEncoding.swift) · [终端调用](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift)
2. 每帧只采用一个匹配当前 Surface／请求的有效质量结果。首个合格新帧以前使用旧输出，源或缓存代际需重准备时走原候选、取消和交接。记录实际代际、显示 ID、逻辑与物理 extent、色深格式、有效档及退回理由。事件只在应用或状态变化时发。针对资源压力验证必需颜色、相机深度和 named/history 能先获容量，低档只撤对应可选工作。
3. 单项验收后做交互对照。最少包含 **MSAA×HDR／透明**、**纹理规格×阴影 cutout／显式 LOD**、**阴影禁用×作者有阴影的灯是否参与体积**、**体积加光×Bloom／反射**、**反射×`clear=false`／named 历史**。旧 30／60、现有预设、同时多项切换、失败回退和新旧 Surface 共存分别核预算和实际画面。

<a id="web"></a>
## Web 实施与兼容

**首批实行每屏 FPS 建议。** 现 `applyGeneralProperties` 用 scalar `fps`，按目标屏取 `max(1, min(60, screen.maximumFramesPerSecond))`。缺省保持该行为，用户选跟随后发送规范化的用户值；扩展到 10–120 后仍用同一个数值字段。屏幕与浏览器实际节律约束呈现，Scene 在对应屏幕组合下的有效上限与作者 Web 建议各自由自身消费者处理。沿正式 launch state、当前 adapter/session 与现有 callback 送到已登记主／子 frame，Web 作品的 canvas、WebGL 或作者 JS 可依 elapsed time 控制实际 draw，原官方 API 不提供作品接受证明。 [官方 Web FPS 合同](https://docs.wallpaperengine.io/en/web/performance/fps.html) · [属性监听合同](https://docs.wallpaperengine.io/en/web/api/propertylistener.html) · [当前桥](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift)

1. **投递顺序**从现有 `WallpaperEngine.WebWallpaperRuntimeState`、`WebDaemonLaunch.state` 和 typed command 到 daemon seed 与普通控制 FIFO。候选的启动静音拷贝保有 FPS 投影。更新当前／候选／standby、恢复会话、延迟 launch 及 topology rebuild 的最新值；空预热采用时取实际 launch 值。同 request 和 navigation generation 接纳，ready 沿原合格条件结算。 [Web 启动状态](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift) · [daemon 输入](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonRuntime.swift) · [会话与恢复](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift) · [延迟切换](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter+SwitchExecution.swift)
2. **初始、热更和重载**文档起始注入为 seed，已有 view 内新 frame、晚注册、reload 与跨源 hello 使用现有快照／回放。测首个和最终回调，若一次性初始化先读到构建期旧值，沿原 hello／快照调整首次回放。校验 reuse 同一 WKWebView 时旧评估在新文档收到最新值后迟到；若现有文档内 sequence 不足以区分跨文档投递，复用原 endpoint/document nonce。当前 view 内热更；暂停、原生媒体挂起、访问授权、输入、Web 音频／频谱、回调其余字段与浏览器存储继续原宿主合同。 [文档注入](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift) · [按 frame 投递](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift)
3. **其它画质**分辨率、MSAA、纹理、后处理、阴影、体积、反射可通过已声明的作者属性和应用内原属性面板操作。活动 WKWebView 公开接口无宿主统一的 FPS／独立 backing render scale；`pageZoom` 的 CSS 缩放、私有 WebKit 开关、全局 rAF／timer 包装或截图播放会改变布局、命中、JS 时序、iframe、CSS/WAAPI 或媒体行为。依旧用真实 WKWebView、原 pause policy 和作者值，热门作品不单列特例。只有官方或作者定义可复用质量合同且实测后才扩大通用字段。 [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) · [pageZoom](https://developer.apple.com/documentation/webkit/wkwebview/pagezoom) · [作者属性](https://docs.wallpaperengine.io/en/web/customization/properties.html)
4. **验收**自有听从设置的 canvas/WebGL 测实际 draw 和可见更新，用忽略建议的 CSS/WAAPI、HTML 视频、Worker 与静态页做反例。检验 60→30→随屏幕，扩展后加 25；更新 Main、同源和跨源晚注册 frame，候选无 hello、延迟 ready、进程崩溃、重载恢复及屏幕热插。暂停中连续改值后只恢复使用最新建议，观察同步绘制、解冻、音量与媒体状态。区分作者回调次数、实际绘制、物理呈现与 CPU/GPU/WindowServer 开销；忽略建议的内容作为工作量持平对照。 [Web benchmark 标准](../web/web-wallpaper-benchmark-standard.md)

<a id="video"></a>
## Video 实施与兼容

**默认原片。** 桌面 helper 使用本地 URL、`AVPlayerItem → AVQueuePlayer/AVPlayerLooper → AVPlayerLayer`，App 和 helper 在现有 DaemonKit 换行 JSON 协议中各司其职，系统屏保为独立执行端。原片尺寸和规格按需复用异步详情入口，素材帧率从 track 补读；VFR 仅显示已知的标称值并标明口径。现本地 item 设置的 `preferredMaximumResolution` 只适用 HLS，可在接触该 owner 时撤掉无效赋值。缩 layer、限呈现频率或改变 rate 无法替代压缩素材降规格。 [播放实现](../../WallpaperDaemonSources/Daemon/Playback/WallpaperDaemon+Video.swift) · [媒体详情](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift) · [Apple HLS 限制](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredmaximumresolution) · [官方 Video 性能](https://help.wallpaperengine.io/en/performance/gpu.html)

| 候选 | 选择与边界 |
|---|---|
| 在线源已有规格 | 优先评估 Pixabay 新下载，服务已有 large／medium／small／tiny 的实际 URL、尺寸和体积。下载弹层用实际可用规格，沿现有 attempt 将选中 URL、预期字节和元数据成套提交，取消/重复任务、重试、磁盘替换和原子发布沿原 owner。默认维持现有最高可用，缺候选明确重选或继续原流程。已有下载、Steam/本地单文件不自动换源或重下；继续只下载、不抢播。 [Pixabay 规格](../../MyWallpaperX/Modules/Pixabay/Core/PixabayModels.swift) · [下载 owner](../../MyWallpaperX/Modules/Pixabay/Core/PixabayService.swift) |
| 显式派生节能版 | 用同一个 SDR 输入先做原片、仅降像素、仅降 FPS、同时降两者的离线 A/B，全部走原播放器。通过后才提供单个可取消、可清理的可选节能版。尺寸预设优先 `AVAssetExportSession`（用实际输出证明），精确 PTS／尺寸／codec／色彩才用 `AVAssetReader/Writer`，编码沿平台支持。首候选为最多 1920×1080 横向或 1080×1920 竖向的等比例包围盒，按源 PTS 向至多 30 fps 选帧，低帧源保原频率，保持画面完整与比例。保 transform、色彩标记、音轨、时间原点、时长及首尾循环，验证偏差后再选择固定 FPS 或保时基。先覆盖普通 SDR 单视频、零或一条可保留的音轨；HDR10、HLG、Dolby Vision、alpha、复杂 VFR、多音轨留原片并各自取得资格再开放。 [Apple 导出预设](https://developer.apple.com/documentation/avfoundation/export-presets) · [原生 HDR 播放与逐帧处理](https://developer.apple.com/videos/play/wwdc2022/110565/) |
| 解码或呈现重写 | `AVVideoComposition` 可留在 AVPlayerLayer 呈现，`AVPlayerItemVideoOutput` 的自呈现路线另需管理窗口内逐帧交付。两者增加解后处理，较少输出帧无法证明较少压缩帧解码。VideoToolbox 的 reduced-resolution decode 是可选底层能力，需要自行承担解码时序、音频同步、HDR、原生轮换和输出。现阶段采用真实素材文件，保既有 AV 时钟和桌面输出。流媒体将来如有自适应档沿对应 HLS 能力独立处理。 [VideoToolbox 降分辨率解码](https://developer.apple.com/documentation/videotoolbox/kvtdecompressionpropertykey_reducedresolutiondecode) |

派生落地后，质量区提供「原片／优先使用已生成的节能版」，便携偏好只携带这一意愿；作品详情负责显式生成、查看与清理对应文件。现有 Video 执行层在下一次播放时解析实际 URL。产品选择、关系、收藏、恢复、历史、预览与结束事件仍以原始 `WallpaperReference` 为身份。当前 `ended` 结合 request 与 path，派生接线须将执行路径归回源身份后按原合同推进轮换。用来源轻量 revision、转换参数及版本给实际派生键，后台合并同键、单并发、有限字节，暂存后检查真实素材元数据再原子发布。缓存损坏、不可用／磁盘满和转换取消沿原片并显示实际档。删除、路径替换、clear cache 撤销在途发布；在用租约等真实旧 slot 清除或 helper 退出，复用取消回执，复用 helper 缺 slot 释放回执时只补该执行身份的回执。产品退役与发出 finalize 可早于 slot 清除。以后确有即时切档需求时，沿现有同源候选和每屏 cohort、同源 `CMTime`、静音准备及可见确认换档，保旧画面到接管和最新暂停／音量／速度／播放方式。 [执行交接](../../MyWallpaperX/Core/Playback/WallpaperEngine+SwitchExecution.swift) · [helper slot 释放](../../WallpaperDaemonSources/Daemon/Playback/WallpaperDaemon+VideoPreparation.swift) · [结束事件](../../MyWallpaperX/Core/Playback/WallpaperEngine+DaemonEvents.swift) · [系统锁屏独立入口](lock-screen-screensaver-design.md)

收益按实际选中的压缩文件和媒体时基验证。4K60→1080p30 理论源像素/秒约少八分之七，编码器、bitrate、媒体引擎及窗口合成决定实际能耗；测 App、每屏 helper、WindowServer 与整机，核 24／29.97／60、横竖和长 GOP、旋转/色彩、音画同步、loop/ended、跨屏和睡眠。1× 的素材帧率口径须明确，2× 播放速度属于时间控制。Scene 图中的视频、Web 媒体和系统屏保独立验证。

<a id="alternatives"></a>
## 超出截图的选项与决策

| 方向 | 采用条件与成本 |
|---|---|
| 固定渲染比例 | 仅评估 Scene。若性能瓶颈是可缩放颜色 pass，先试 0.75× 的原离屏 render extent → 单一原生 drawable，按实际选择 Metal 线性或经验证的缩放。保持 viewport/光标/作者逻辑分辨率、命名图、历史、精确 atlas、文字、EDR；禁止用全局 drawableSize 修改冒充完整方案。调档、屏幕尺寸和历史互斥需实证，MetalFX 或动态比例会加入新 pass／历史，只有固定档方向成立再评估。 |
| 自动省电与热状态 | 首轮优先使用现有前台／全屏／电池／空闲暂停。将来需要「电池降低 FPS」时采用原 policy 现有事件向 cadence 投影并显示有效值；固定、可逆、用户显式选择。自动降纹理、重载资源或多档瞬时跳变的切换成本大，先量到长稳真实收益，再限定迟滞、频率与条件。 |
| 每屏或每作品覆盖 | 现有多屏拓扑、设备能力与属性维持。全局值先验收；只有实测存在混合刷新率／EDR 或用户明确长期需要不同策略，才在原显示/作品 owner 加一个可解释覆盖层。设备测值只产生有效值，便携设置不写物理 display ID。 |
| 粒子、脚本、色彩、缩放 | 作者粒子数量、固定步进、script/timeline、阴影材质和各类后处理拥有各自语义，禁止随预设笼统删减。AV、WK、Scene 各自已有 fit 与色彩路径；显示比例与解码规格分开。库网格、预览帧、桌面静帧与系统锁屏控制另有既存入口。 |
| 平台与依赖 | 优先 AppKit/Swift、Metal、ImageIO、WKWebView、AVFoundation。引入 FFmpeg、另一个浏览器内核、私有 API、第二 renderer 或永驻转码 helper，都会增大发行、原生架构、签名、维护和退出成本。仅当确有竞争方案无解且独立设计验证后才重开。 |

<a id="delivery"></a>
## 评估工作包、工程成本与停止线

各批都可由现有实体任务分工，设置与导入/包协议等共享文件由一个整合者写入。Scene 多项可分开实验；真机性能、VM 和 GPU 取证顺序运行。以下为相对成本，包含行为门和代表运行，机型、素材和官方资格尚影响排期。

| 批次 | 交付与先决条件 | 成本与退出 |
|---|---|---|
| Q0 基线与夹具 | 固定当前 build 和至少一个默认 Scene、一个 HDR/阴影/体积/反射的正例及邻例，Web 作者建议页、Video A/B 源；保存现有 30/60、HDR、三引擎切换与功耗基线 | 中。依真实能力画面建立样本资格，核清观测成本。无法区分画面或机器噪声时先修测量；布局准备可并行 |
| Q1 设置与帧率 | 原面板、导入/复位、Scene 30/60 实际帧节奏、Web 可选跟随、Video 原片适用，回收重复设置入口 | 中。Debug 与正式 App 路由代表场景通过，原缺省及现有偏好无退化，运行中即时设置适用；切换、旧 v8 及暂停实证后可独立结束 |
| Q2 Scene 轻量项 | 依次验证 Bloom、反射、阴影、体积的禁用与现行质量，补普通 Bloom 路径和定向上限 1024。按实际光源、像素和成本扩阴影及体积档 | 中至高。一个控件牵涉的画面与开销分别取证。graph 或资源要求重准备时在下次应用生效，候选失败局部退回 |
| Q3 Scene 规格与预设 | 纹理验证高质量、高性能和自动。帧率先解耦缓存，并扩现有基准 CLI、Debug telemetry 与报告的 FPS 输入，再验证 10–60 及 61–120。MSAA 依 2×／4×／8× 逐档取证，用已验收字段组成预设 | 高。高刷、MSAA 和纹理各有独立收益与停止线。无实际独立差异的预设或档位继续在验证阶段 |
| QV Video | Q1 给现状，已有在线规格与 A/B 可并行；真实功耗、画质、回本时间通过才实现派生。需要即时换档则另做生命周期验证 | 中到高。缓存增长、HDR/loop 回归或实际总能耗不优时原片正式路径收口；下载规格独立判断 |
| Q4 整体验收 | 三引擎与静态图、显示与系统 policy、可访问性、导入、并发切换、恢复、长稳。对声称兼容的选项补官方有界对照 | 中到高。只有实测通过的选项进入发布说明；能力/证据回写原 owner，移除旧设置、废弃 wire/测试和专项顺序 |

<a id="validation"></a>
## 验证与度量

### 最近行为门与运行入口

| 边界 | 现有门或入口与应补断言 |
|---|---|
| 设置、兼容、跨引擎 | 扩 `test_settings_cache_actions` 所用原设置动作入口或等价真实验证、`test_personal_settings_import`、`test_playback_command_multiplexer`、`test_playback_switch_transaction`、`test_playback_switch_endpoints`。核一次变更一次 owner 写入与准确路由、旧数据和复位、候选取消、同时改作者参数、A→B→C、切出再恢复及迟到失败 |
| Scene 帧率与 IPC | `test_scene_daemon_protocol`、`test_scene_frame_context`、`test_scene_paused_frame_recovery`、`test_scene_surface_submission`、`test_scene_daemon_switch_cancellation`。经真实设置 → App client → daemon → timer/GPU/presented 检查 10／25／60／120 及两段边界、设备回退、时间轴和无连续补帧；高刷项在合格设备与混合刷新率反例中验收 |
| Scene 渲染项 | Bloom 扩 `test_scene_bloom_post_process`；纹理用 `test_scene_texture_candidate`、`test_scene_bc_texture_uploader`、`test_scene_raw_texture_uploader`、`test_scene_frame_texture_registry`；阴影用 `test_scene_directional_shadow_frame_owner`；体积用 `test_scene_point_volume`、`test_scene_spot_light_plan`、`test_scene_spot_light_rendering` 及聚光源真实 App 门；反射用 `test_scene_reflection_history_integration`、`test_scene_reflection_history_named_depth`；MSAA 复用 `test_scene_graph_resource_pass_encoder`、`test_scene_static_model_depth_pending`、`test_scene_particle_main_depth`。扩最近真实消费者与正反像素，不复写业务算法 |
| Web | `test_web_system_media`、`test_web_compat_parity`、`test_web_playback_pause`，另走正式进程与导航 `web_runtime_switch_benchmark.py` 和 `web_wallpaper_benchmark.py`；包含首个/最终回调、WebContent 重建、忽略建议和作者实际降绘制 |
| Video | `test_video_inspector_metadata`、`test_video_preparation_cancellation`、`test_playback_visibility`、`test_wallpaper_library_playback`、`test_pixabay_download_transfer`、`test_pixabay_downloaded_content`；沿现有进程隔离基准或正式库入口验证真实格式／PTS、端点收据、尾首音画时间、下一次切换、坏缓存回原片和真实释放。窗口 ready 与实际播放截图／时间采样分别记录。 [进程隔离基准](../../script/web/playback_process_isolation_benchmark.py) |

用 `python3.12 -B script/run_scene_tests.py --module <module>` 选最近门，产品 Swift 变更再跑现有 Debug 构建。先用 `verify_scene_change.py` 预览按 owned path 的门，GPU/生命周期用独立 staged App、HOME、只读素材的隔离副本和新输出目录验证。通过 direct-host 可快速定位，产品声明经正常 App 入口。末次运行后关精确归属的进程，清本批衍生产物，证据只保必要日志与画面。 [仓库验证工作流](repository-workflow.md#并行与验证) · [Scene benchmark](../../script/scene/scene_wallpaper_benchmark.py) · [Scene 性能](../../script/scene/scene_wallpaper_performance.py) · [Web benchmark](../../script/web/web_wallpaper_benchmark.py) · [产物保留规则](../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)

现有 Scene 基准 `--performance-fps` 和转发参数、direct-host／daemon-client 启动、Swift `reset(targetFPS:)` 与报告解析都只接收 30／60，呈现的尾部分位数为多流合计。Q3 先扩展这条同一入口读写合法 FPS，保 30／60 证据兼容。用已有呈现流标识关联实际 Surface／显示 ID，调度与实呈各按实际承诺节奏度量，逐屏输出计数、间隔、漏期和尾部。设备或屏幕代变后开启新测量窗。复用 Debug 观测，发布路径无需每帧收集画质报表。 [基准 CLI](../../script/scene/scene_wallpaper_benchmark.py) · [转发参数](../../script/scene/scene_wallpaper_property_updates.py) · [direct-host](../../MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Performance.swift) · [daemon-client](../../MyWallpaperX/App/Debug/DebugSceneDaemonClientRunner+Startup.swift) · [Telemetry](../../MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneFramePerformanceTelemetry.swift) · [结果解析与稳态资格](../../script/scene/scene_wallpaper_performance.py)

<a id="quality-release-gates"></a>
### 性能与画面门槛

| 发布判定 | 实测条件 |
|---|---|
| **输入与样本** | 每项至少一个能区分错误的自有夹具、一个实际受影响作品、一个未参与调参的独立作品和同域无该能力的负控。先写可观察预期、固定相位／seed、ROI、颜色空间、误差范围和失败判定，保改名、等价表达与相邻反例。源版本、显示拓扑和背板像素、合成比例、属性／音源、系统及热状态固定。优先同优化构建只改一项设置。算法变更需要不同构建时冻结各自构建身份，保相同优化、签名类型与测试参数。 |
| **原样与局部隔离** | 默认保冻结旧版的几何、覆盖、色彩、作者时钟与历史。对可要求精确的 identity、裁剪、alpha／深度、发布与回退用明确断言。光晕、粗糙度、降纹理及积分误差按各项预定的像素／时序容差。逐项验收列明效果损失和允许范围，组合验收验证同帧选择、必需容量、可见接管和相邻效果。 |
| **质效双门** | 降档需让目标阶段 GPU／CPU 时间、可见掉帧、真实驻留或整机能耗至少一项超过同机 A/A 波动，且守画面容差。提升档（如 MSAA、HDR 或更密阴影）可使用更多预算，但须比低档有可重复的独立画面收益且守承诺的帧节奏和资源容量。建议 Q0 初筛线为等质改造目标指标中位改善 ≥10%，原默认和邻例的 P95 帧时／可见首帧恶化 >5% 时复核。阈值在读取候选前按输入、机型和实际噪声确认。 |
| **帧节奏与负载** | 记录调度请求、提交、GPU completed 和实际 presented。以有效目标帧率 (F) 计算每帧 (1000/F) ms，30／60／120 FPS 约为 33.3／16.7／8.3 ms。逐屏登记固定刷新量化或可变刷新的实测机会。固定 60 Hz 上的 25 FPS 理想情况下每五段跨 12 个刷新周期，约有三段 33.3 ms、两段 50 ms，排列随相位变。正常量化列入参考。Q0 建议漏期率比同节奏基线至多多 1 个百分点，呈现间隔 P99 至多多一个该屏实测刷新周期，检测噪声较大时在试候选前据 A/A 定线。另对照 CPU／GPU 各自 P95、等待及提交到呈现延迟。预算内仍须逐屏实呈通过。 |
| **冷暖与长稳** | 同机 AB／BA 交替，冷起、暖稳、快速切换和长稳分别取样。45–90 秒可作短探针。Scene 发布级稳态沿已有 AS1 门槛，ready 后预热至少 30 秒，再取至少 60 秒有效窗，建议至少 5 对有效配对。整机功耗声明另用平衡热态的 20–30 分钟，保持同刷新率、实际呈现量和屏数。调档有意减载的节能结果标明对应画质／FPS，等质提速按同画质对照。报告中位、P95／P99、离群和所有失败。 |
| **设备与回退** | 至少验证最低代际 Apple Silicon 与较新代际，记录 OS build、GPU family、实际 sample count／格式、内存和 EDR headroom。覆盖单屏 Retina／普通外屏、混合刷新率及 SDR／EDR、热插、睡醒、供电切换、快速档位往返、暂停中改档、故障回退与退出。同一 PID 分别量 active／candidate／retiring 的高水位与归还，区分临时 display、warm cache 和真正漏掉的租约。缺相应硬件的项保留验收缺口。 |

每个候选在 Q0 登记可执行的通过判据及取样位置。作者语义与生命周期先用确定断言，错相位、错源、漏画、非法覆盖、必需分配失败或应关 pass 仍执行时直接退回。画质变化用相同色域的配对值，改进档须比低档超过重复取样噪声，节能档须低于预登记的最大误差。首轮在固定高对比夹具上可用 1 原生像素作额外边缘漂移的初筛上限，透明细线、灯影有效宽度及柔光范围须按各自参考调整。在看候选截图前冻结容差，并记录失效的作品和设备范围。SDR 和 EDR 先核同一 raw，显示侧用各自正确的输出映射，HDR 验收要保原浮点／高动态范围证据。

定位时用已有 benchmark、Metal System Trace、Metal Resource Events、必要的 GPU pass／内存带宽采样和 Time Profiler。采集帧与 profiler 使负载变化时独立取证，连同空闲桌面／正常播放对照。正式时间与能耗窗口关可选采集。纹理描述逻辑字节、Metal 已分配、资源池计费和进程 footprint 各自记账，统一内存下避免把其中几项相加。Web 加作者实际 draw 与 WebContent／WindowServer，Video 加真实 codec／PTS、音画与一次性转码时间和能耗。派生节能版的回本时间基于有效播放每小时节省。 [仓库性能工作卡](../scene/roadmap/performance-convergence-card.md#measure) · [Apple 性能观测](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) · [GPU 带宽](https://developer.apple.com/documentation/xcode/measuring-the-gpus-use-of-memory-bandwidth)

<a id="official-quality-evidence"></a>
### 官方对照证据与待验

2026-11-25 读取运行中的 Windows 客户端 2.8.0.42 设置资源，核对四档写入向量、刷新率上限输入和第四档条件。无显示 HDR 支持时界面省略第四档，并把该 UI 状态回落到普通超高。VM 是单路径 120 Hz、8 位 RGB，高级颜色不可用。当前核验覆盖已发客户端设置投影及显示资格，物理 HDR 仍需实际 HDR 设备与保留高动态的取证。 [官方显示 HDR 公告](https://steamcommunity.com/games/431960/announcements/detail/3133943554973045545) · [同版 Main renderer 响应证据](../scene/capabilities/model-runtime-evidence.md#model-hdr-emissive-gain)

| 官方 2.8.0.42 预设 | FPS | MSAA | 后处理 | 纹理 | 阴影 | 体积 | 反射 |
|---|---:|---|---|---|---|---|---|
| 低 | 10 | 无 | 禁用 | 高质量 | 低 | 低 | 关 |
| 中 | 15 | 无 | 启用 | 高质量 | 中 | 中 | 开 |
| 高 | 25 | ×2 | 启用 | 高质量 | 高 | 高 | 开 |
| 超高 | 30 | ×2 | 超高 | 高质量 | 超高 | 超高 | 开 |

锁定合法安装的 Windows 版 Wallpaper Engine build、位数／版本、系统／GPU／显示、全量设置和自有输入，先记录四预设逐字段向量，再测单项改变、选择另一作品、重启、按屏及运行中的生效时机。帧率记录 10／25／60／120 及输入步进、上限与显示节律，MSAA 在设备允许时用几何斜边、遮挡和纯 2D 反例逐档对照。后处理用作者普通／HDR 开关组合和实测三档相互验证，纹理以含 mip／无 mip／图集、阴影以三类灯、体积以点光／聚光、反射以实时接收与静态对照验证各档。另让相同 Web／Video 输入读取或播放，核影响面。每次只改一项，固定可见 ROI、捕获身份、色域、DPI、动画相位与 pause；预览如未采用桌面质量配置，验证其会话或改用有界桌面窗口。VM 采行为，Mac 功耗真机另测。

如固定版本的公开/可见实验无法区分「候选设置确实被该 consumer 读到」等问题，先用现有 locale/changelog 结构提取，再按官方研究工作流选择 REA 对单一设置写入→读取关系作有界静态研究。保留版本、证据位置和可观测预测，随后用单变量运行反证；解析结果只作线索，最终行为仍取实际画面与事件。现阶段采用公开资料和已有仓库证据，未新增 Windows 动态对照、REA 输出或 macOS 功耗数据。 [官方研究与保留规则](../scene/development/official-client-behavior-research-workflow.md) · [结构提取工具](../../script/evidence/extract_wallpaper_engine_client_evidence.py)

<a id="retirement"></a>
## 退役与完成判定

Q1 落地时统一设置入口、迁移和导入路径，后续用初始默认、相邻无影响例与独立作者移除被替换的 prototype、空档、旧入口和临时双写。Scene 的长期策略、Web 的作者桥语义、Video 的素材执行规则分别交原合同；Scene 能力缺口和运行报告依旧交开放队列和证据索引。官方未知、被停止的昂贵候选和缺覆盖的硬件保留明确收据。专项的退出条件是每个拟交付选项都能从原设置到真实消费与用户可理解结果，余项有证据或清楚退出；发布、提交和推送依当时授权。
