# 仓库职责与修改入口

这是一张当前源码导航图，不授予目录新的产品权威。以实际调用、构造、提交与销毁关系核对 owner；目标技术边界见[架构合同](technology-stack-boundaries.md)，协作和验证见[仓库开发工作流](../development/repository-workflow.md)。

## 从用户任务到负责代码

| 任务 / 边界 | 当前源码起点 | 合同、事实与最近验证 |
|---|---|---|
| App 装配、Shell、菜单、选择 | [应用入口](../../MyWallpaperX/App/MyWallpaperXApplication.swift)、[Shell 路由](../../MyWallpaperX/Shell/AppKitMainSplitView+ModuleRouting.swift)、[播放切换](../../MyWallpaperX/App/MainWindowCoordinator+PlaybackRouting.swift) | [AppKit 路线](appkit-migration.md)；UI 变更须实际操作对应路径 |
| Video 播放意图与持久化 | [WallpaperManager](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift)、[应用请求](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+WallpaperApplication.swift)、[持久化](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift)、[事件回流](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackEvents.swift) | 产品意图、pending、ready 不能混为同一状态；库索引与用户设置是不同存储 |
| Video 请求、每屏 session、播放进程 | [WallpaperEngine](../../MyWallpaperX/Core/Playback/WallpaperEngine.swift)、[session 生命周期](../../MyWallpaperX/Core/Playback/WallpaperEngine+DaemonSessionLifecycle.swift)、[daemon 播放](../../WallpaperDaemonSources/Daemon/Playback/WallpaperDaemon+Video.swift) | [播放控制测试](../../script/tests/test_playback_command_multiplexer.py)只覆盖相应合同；真实首帧、断连、重启另验 |
| Web 请求、宿主、导航与属性 | [Web 接线](../../MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift)、[Web 文档入口](../web/README.md) | [当前状态](../web/current-state.md)、[project 模型](../web/web-project-json-runtime-model.md)；导航/会话失效须用 Web 反例 |
| Scene 准备、执行、输出 | [Scene 入口](../scene/README.md)、[源码职责图](../scene/architecture/runtime-as-built-map.md) | [目标架构](../scene/architecture/runtime-architecture.md)、[当前能力](../scene/capabilities/coverage-ledger.md)、[运行证据](../scene/capabilities/runtime-evidence-current.md) |
| 共同暂停、系统策略、播放命令 | [命令分发](../../MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift)、[策略](../../MyWallpaperX/Core/PlaybackControl/PlaybackPolicyController.swift) | [分发测试](../../script/tests/test_playback_command_multiplexer.py)、[策略投递测试](../../script/tests/test_playback_policy_delivery.py)；涉及跨引擎时验证切换和迟到事件 |
| 静态图片库与桌面应用 | [SILService](../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift)、[应用消费者](../../MyWallpaperX/App/MainWindowCoordinator+PlaybackRouting.swift) | 库服务不拥有最终桌面输出；消费者调用 NSWorkspace 并处理动态 runtime 退出 |
| Steam 获取、下载、入库与会话 | [三类型播放分发](../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPlayback.swift)、[迁移与验收](../scene/roadmap/scene-steamkit-migration-plan.md)、[协议测试](../../script/tests/test_steam_protocol_golden.py) | Swift 产品状态与 .NET SteamService 会话/下载隔离；离线 fixture 不证明真实账号和下载验收 |
| 导入后自动播放 | [意图门](../../MyWallpaperX/Core/PlaybackControl/ImportedVideoAutoplayGate.swift)、[观察者](../../MyWallpaperX/App/ImportedVideoPlaybackObserver.swift) | [行为测试](../../script/tests/test_imported_video_autoplay_gate.py)；旧导入完成不得覆盖新用户意图 |
| 依赖、构建、签名、发布 | [技术栈边界](technology-stack-boundaries.md)、[CI](../../.github/workflows/ci.yml)、[发布合同](../release/release-signing.md) | 版本、来源、锁文件、协议与失败隔离分别验证；发布只走显式授权流程 |

## 修改边界与存量偏差

- `App/` 装配产品入口，`Shell/` 承载主界面，`Modules/` 按产品能力组织，`Core/` 提供当前共享执行能力；名字本身不证明依赖方向。`SteamWorkshop/Web/Core` 中仍有三类型分发，定位时必须追调用者。
- Video/Web 与 Scene 的生命周期分属现役执行链；不能把 `WallpaperEngine` 描述成全引擎唯一生命周期 owner。静态输出也有独立系统 API 消费者。跨引擎工作先核对[工程路线](../scene/roadmap/engine-refactor-program.md)的迁移合同。
- Scene Rendering 合法消费 Compilation 产出的 prepared Program。不能用“目录之间不得引用”替代公共合同与内部实现的区分；依赖门须先确定哪种具体反向依赖破坏 owner。
- 当前 path groups 并未给每个产品文件映射 focused test；build-only 不是行为覆盖。每次从验证预览检查实际选中模块；缺映射时补现有最近行为门，缺行为门时先建立输入/输出反例。
- 文件体量与结构预算是风险信号，不是架构完成度。按生命周期、数据流和消费者拆分，保留 defer/事务/释放边界；仅移动代码不能证明减少耦合、成本或缺陷。

## 工程材料放置

产品代码在现役产品目录；正式工具在 `script/`，行为测试在 `script/tests/`，稳定知识在 `docs/` 的角色索引中。临时实验放 `/private/tmp`，本机证据遵守已有 ignored evidence 目录规则。历史仍按[历史索引](../history/README.md)保存；新增导航只链接 owner，不复制批次结果。
