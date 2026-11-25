# 仓库职责与修改入口

这是一张当前源码导航图，不授予目录新的产品权威。以实际调用、构造、提交与销毁关系核对 owner；目标技术边界见[架构合同](technology-stack-boundaries.md)，协作和验证见[仓库开发工作流](../development/repository-workflow.md)。

## 从用户任务到负责代码

| 任务 / 边界 | 当前源码起点 | 合同、事实与最近验证 |
|---|---|---|
| App 装配、Shell、菜单、选择 | [应用入口](../../MyWallpaperX/App/MyWallpaperXApplication.swift)、[主窗口装配](../../MyWallpaperX/App/WallpaperLibraryWindowComposition.swift)、[播放切换](../../MyWallpaperX/App/MainWindowCoordinator+PlaybackRouting.swift) | [AppKit 路线](appkit-migration.md)；UI 变更须实际操作对应路径 |
| 原生筛选弹层 | [共享排版](../../MyWallpaperX/Shared/UI/WallpaperFilterPanelController.swift)、[图片源绑定](../../MyWallpaperX/App/OnlineImageFilterPanel.swift)、[Pixabay绑定](../../MyWallpaperX/Modules/Pixabay/Toolbar/PixabayFilterPanel.swift) | 只共享checkbox几何/菜单呈现，查询与清空规则仍归各源；[UI20](../development/main-window-playlists-redesign.md#ui-online-panels-twenty) |
| 用户关系、设置导入与混合轮换 | [关系 Store](../../MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift)、[命令与回执队列](../../MyWallpaperX/Core/LibraryCollections/UserCollectionsController.swift)、[个人设置](../../MyWallpaperX/Core/LibraryCollections/LibraryPersonalSettings.swift)、[导入装配](../../MyWallpaperX/App/PersonalSettingsImportCoordinator.swift)、[播放序列](../../MyWallpaperX/Core/PlaybackControl/WallpaperPlaybackSequence.swift) | [播放列表专项](../development/main-window-playlists-redesign.md)；关系持久化、来源查询与原播放事务各有唯一 owner |
| Video 播放意图与持久化 | [WallpaperManager](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift)、[应用请求](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+WallpaperApplication.swift)、[持久化](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift)、[事件回流](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackEvents.swift) | 产品意图、pending、ready 不能混为同一状态；库索引与用户设置是不同存储 |
| Video 请求、每屏 session、播放进程 | [WallpaperEngine](../../MyWallpaperX/Core/Playback/WallpaperEngine.swift)、[session 生命周期](../../MyWallpaperX/Core/Playback/WallpaperEngine+DaemonSessionLifecycle.swift)、[daemon 播放](../../WallpaperDaemonSources/Daemon/Playback/WallpaperDaemon+Video.swift) | [播放控制测试](../../script/tests/ui/test_playback_command_multiplexer.py)只覆盖相应合同；真实首帧、断连、重启另验 |
| Web 请求、宿主、导航与属性 | [Web 接线](../../MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift)、[进程控制端](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift)、[Web 文档入口](../web/README.md) | [当前状态](../web/current-state.md)、[project 模型](../web/web-project-json-runtime-model.md)；导航/会话失效须用 Web 反例 |
| Scene 准备、执行、输出 | [Scene 入口](../scene/README.md)、[源码职责图](../scene/architecture/runtime-architecture.md) | [目标架构](../scene/architecture/runtime-architecture.md)、[当前能力](../scene/capabilities/README.md)、[运行证据](../scene/capabilities/runtime-evidence-current.md) |
| 共同暂停、系统策略、播放命令 | [命令分发](../../MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift)、[策略](../../MyWallpaperX/Core/PlaybackControl/PlaybackPolicyController.swift) | [分发测试](../../script/tests/ui/test_playback_command_multiplexer.py)、[策略投递测试](../../script/tests/ui/test_playback_policy_delivery.py)；涉及跨引擎时验证切换和迟到事件 |
| 视频屏保与锁定显示（验证中） | [App装配](../../MyWallpaperX/App/ScreenSaverCoordinator.swift)、[配置窗口](../../MyWallpaperX/App/ScreenSaverWindowController.swift)、[原生媒体发布](../../MyWallpaperX/Core/System/ScreenSaverIntegration.swift)、[原生系统宿主](../../ScreenSaverSources/Native/SystemWallpaperHostProtocol.swift) | [专项与证据](../development/lock-screen-screensaver-design.md)；[发布/活动门](../../script/tests/ui/test_screen_saver_integration.py)与[系统边界门](../../script/tests/ui/test_system_wallpaper_wire.py)不替代真实宿主验证 |
| 静态图片库与桌面应用 | [SILService](../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift)、[应用消费者](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+RuntimeSwitching.swift)、[系统桌面写入与退出恢复](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+WallpaperApplication.swift) | 库服务不拥有最终桌面输出；Manager调用NSWorkspace并处理动态runtime退出，静态图片退出规则见[专项T06](../development/main-window-playlists-redesign.md#inspector-playback-appearance-round) |
| 在线来源浏览、解码与分页 | [Pixabay服务](../../MyWallpaperX/Modules/Pixabay/Core/PixabayService.swift)、[Pixabay值模型](../../MyWallpaperX/Modules/Pixabay/Core/PixabayModels.swift)、[Wallhaven](../../MyWallpaperX/Modules/Wallhaven/Core/WallhavenClient.swift)、[Pixiv](../../MyWallpaperX/Modules/Pixiv/Core/PixivClient.swift)、[共享图片浏览会话](../../MyWallpaperX/Core/OnlineImages/OnlineImageBrowserSession.swift) | 来源入口解码与过滤、分页/账号代次、Shell展示各保原职责；[Pixabay HTTP门](../../script/tests/ui/test_pixabay_pagination.py)、[Pixiv HTTP门](../../script/tests/ui/test_pixiv_client.py)使用受控响应，不证明真实账号/服务可用性 |
| 多来源下载任务与本机历史 | [App来源接线](../../MyWallpaperX/App/DownloadTasksController.swift)、[通用面板](../../MyWallpaperX/Modules/Downloads/UI/DownloadTasksPopover.swift)、[非Steam终态历史](../../MyWallpaperX/Modules/Downloads/Core/DownloadHistoryStore.swift) | 各来源保原执行/发布；查看本机历史无登录门槛；[主界面专项](../development/main-window-playlists-redesign.md#ui-simplification-sixteen) |
| Steam 获取、下载、入库与会话 | [三类型播放分发](../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPlayback.swift)、[获取合同](steam-workshop-acquisition-contract.md)、[协议测试](../../script/tests/steam/test_steam_protocol_golden.py) | Swift 产品状态与 .NET SteamService 会话/下载隔离；离线 fixture 不证明真实账号和下载验收 |
| 导入后自动播放 | [意图门](../../MyWallpaperX/Core/PlaybackControl/ImportedVideoAutoplayGate.swift)、[观察者](../../MyWallpaperX/App/ImportedVideoPlaybackObserver.swift) | [行为测试](../../script/tests/ui/test_imported_video_autoplay_gate.py)；旧导入完成不得覆盖新用户意图 |
| 依赖、构建、签名、发布 | [技术栈边界](technology-stack-boundaries.md)、[CI](../../.github/workflows/ci.yml)、[发布合同](../release/release-signing.md) | 版本、来源、锁文件、协议与失败隔离分别验证；发布只走显式授权流程 |

## 修改边界与存量偏差

<a id="wallpaper-quality"></a>
壁纸质量从 [AppKit 设置](../../MyWallpaperX/Shared/Settings/AppKitSettingsView.swift)、[播放偏好](../../MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift)与[导入恢复](../../MyWallpaperX/App/PersonalSettingsImportCoordinator.swift)进入。Scene 跟 [daemon 控制面](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift)、[帧驱动](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift)及[有效策略](../scene/architecture/runtime-architecture.md#effective-quality-policy)。Web 跟 [宿主投影](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift)，Video 跟 [原片执行](../../WallpaperDaemonSources/Daemon/Playback/WallpaperDaemon+Video.swift)。Scene 预设与手改共用同一偏好和 [命令 mux](../../MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift)，按已保存请求派生。新启动或重建路径沿各端种子检查，执行工作见[现役工作卡](../development/wallpaper-quality-work-card.md#execution)。

发给用户的设置说明写在五语 [内置帮助](../../MyWallpaperXHelp/zh-Hans.lproj/index.html)，按正文的 Video、Web、Scene 章节随适用范围变动更新。 [帮助书检查](../../script/governance/check_help_bundle.py)

三引擎交接和冷恢复用 [签名产品验收](../../script/web/playback_quality_coexistence.py) 从正常库选择入口核实会话、实际窗口和已保存的 Scene 质量。 [验收范围](../development/wallpaper-quality-work-card.md#quality-engine-coexistence)

Scene 的 [显示模式与目标屏](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneScreenTopology.swift) 进入原 daemon 拓扑入口。请求、生效上限及解码配额见 [帧率合同](../scene/architecture/runtime-architecture.md#scene-frame-rate-policy)。Scene 稳态节律用 [原产品启动基准](../../script/web/wallpaper_startup_benchmark.py) 对实际接管的 daemon 采集逐屏呈现与 GPU 完成。参数、观测边界和当前 A/A 见[工作卡](../development/wallpaper-quality-work-card.md#连续帧率的产品测量与接管)。

Scene 的 [基础图像准备](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift) 和 [TEX 候选加载](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift) 负责真实纹理规格。Auto 的目标像素从 [原屏幕安装与 drawable 变化](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfacePreparation.swift) 接入。精确用途、GPU 表示与作者布局见 [纹理档位合同](../scene/architecture/runtime-architecture.md#scene-texture-quality-policy)。

Scene 后处理接入 [终端合成](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ClearColor.swift)、[Bloom 纹理链](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneBloomPostProcess.swift) 与 [显示映射](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneDisplayMappingPostProcess.swift)。 [Apple 附件重建与回退](../scene/architecture/runtime-architecture.md#scene-hdr-bloom-reconstruction)

Scene 反射从 [帧相序](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+SceneDrawing.swift) 进入 [快照与 mip](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ClearColor.swift) 及 [真实分配](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTexturePool+SceneColor.swift)。 [有效档与画面合同](../scene/architecture/runtime-architecture.md#scene-reflection-quality-policy)

Scene MSAA 请求经 [主域准入](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+SceneDrawing.swift) 交给 [唯一主合成编码器](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneMainPassEncoder.swift)。普通图像、纯色与文字用 [同采样 Quad PSO](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneMetalPipeline.swift)。 [实际采样与回退](../scene/architecture/runtime-architecture.md#raster-sample-domain)

Scene 阴影档经冷准备进入 [光空间贴图与受光绘制](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+StaticModels.swift)。 [尺寸与回退合同](../scene/capabilities/advanced-object-coverage.md#model-directional-shadow-density)

Scene 体积开关从同一准备请求进入 [根域点光与有序聚光绘制](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+OrderedLayerEncoding.swift)。 [点光管线](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/ScenePointVolumePipeline.swift) 负责实际光球覆盖与同一积分编码。积分阶数沿 [PSO 槽](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneImageEffectPipelineRepository.swift) 冷选。 [生效合同](../scene/architecture/runtime-architecture.md#scene-volume-lighting-policy)

本地 Video 和已就绪 Steam Video 详情共用[原片轨道读取](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift)。标称帧率来自实际播放文件；[Steam 获取合同](steam-workshop-acquisition-contract.md#source-video-facts)约定适用范围。

Pixabay 新下载由 [规格选择](../../MyWallpaperX/Modules/Pixabay/UI/PixabayDownloadQualityPrompt.swift)交给[下载服务](../../MyWallpaperX/Modules/Pixabay/Core/PixabayService.swift)发布实际文件。[下载历史](../../MyWallpaperX/App/DownloadTasksController.swift)用原档位重试。播放仍由原 Video daemon 读取发布文件。

- `App/` 装配产品入口，`Shell/` 承载主界面，`Modules/` 按产品能力组织，`Core/` 提供当前共享执行能力；名字本身不证明依赖方向。`SteamWorkshop/Web/Core` 中仍有三类型分发，定位时必须追调用者。
- 三引擎采用相同的控制/播放隔离边界；Video/Web 与 Scene 的会话生命周期分属现役执行链；不能把 `WallpaperEngine` 描述成全引擎唯一生命周期 owner。静态输出也有独立系统 API 消费者。跨引擎工作先核对[工程路线](../scene/architecture/runtime-architecture.md)的迁移合同。
- Scene Rendering 合法消费 Compilation 产出的 prepared Program。不能用“目录之间不得引用”替代公共合同与内部实现的区分；依赖门须先确定哪种具体反向依赖破坏 owner。
- 当前 path groups 并未给每个产品文件映射 focused test；build-only 不是行为覆盖。每次从验证预览检查实际选中模块；缺映射时补现有最近行为门，缺行为门时先建立输入/输出反例。
- 文件体量与结构预算是风险信号，不是架构完成度。按生命周期、数据流和消费者拆分，保留 defer/事务/释放边界；仅移动代码不能证明减少耦合、成本或缺陷。

共享系统音频的分析与可视响应见[频谱设计](system-audio-spectrum-design.md)；三类型保留各自绘制owner。歌曲信息由 [共享媒体服务](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaService.swift) 在主 App 唯一采集，Web/Scene 分发与退出见 [D6](../web/mediaremote-nowplaying-design.md)。

## 工程材料放置

产品代码在现役产品目录；正式工具在 `script/`，行为测试在 `script/tests/`，稳定知识在 `docs/` 的角色索引中。临时实验放 `/private/tmp`，本机证据遵守已有 ignored evidence 目录规则。历史仍按[历史索引](../history/README.md)保存；新增导航只链接 owner，不复制批次结果。
