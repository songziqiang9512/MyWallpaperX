# Scene 引擎：从这里开始

MyWallpaperX 是原生 macOS 动态壁纸程序：AppKit 管理窗口、壁纸选择和用户意图；Video 使用 AVFoundation，Web 使用 WebKit，Scene 把 Wallpaper Engine 作者数据准备成可执行资源，再通过 Metal 合成为桌面画面。兼容程度按能力与实际运行证据判断，不能由“加载成功”推出。

## 引擎如何工作

```text
主 App：选择壁纸 / 属性 / 暂停 / 屏幕变化
    ↓ typed command → SceneDaemonClient
同一 App 二进制的 --mwx-scene-daemon 进程
    ↓ Host 加载作者数据，准备 Program / graph / resources
    ↓ FrameDriver 更新 clock / property / script / simulation / provider
    ↓ 每个 surface 的 renderer → Metal encode → 唯一 compositor
    ↓ GPU completion / publication → 后续帧消费；切换时撤销旧 generation
```

静态纹理、字体、shader 和 graph 在加载或明确失效时准备；视频、动态文字、粒子等只更新必要的帧数据。所有对象接入同一资源、帧状态和输出合同。普通帧不重新解析、编译或建图；耗时诊断不参与正常播放。

这是职责概览。逐对象加载时机、合成入口、失败及释放规则见[播放器设计 §8](design/runtime-architecture.md#8-scene-播放生命周期与落代码合同)；实际代码所有权与现有偏差见[代码地图](design/runtime-as-built-map.md)。

## 现在做什么

| 任务 | 只打开这个入口 |
|---|---|
| 架构重构、性能、代码与文档消融 | [重构执行计划](engine-refactor-program.md)：E0 基线到 E8 集成，每项含依赖、验收和回退 |
| Apple Silicon 平台与性能优化 | [专项执行与验收](engine-refactor-program.md#apple-silicon)：现有工程计划的顺序细化 |
| 兼容能力、可见正确性与发布完成门 | [兼容路线](scene-compatibility-roadmap.md)：P0–P5 |
| 处理眼前尚未关闭的播放问题 | [当前断点队列](scene-open-breakpoint-queue-2026-09-09.md)：兼容路线的派生短表 |
| 开始落代码、选择验证门 | [开发工作流](development/development-workflow.md) |

## 去哪里改代码

Scene 源码在 [Core/SteamWorkshopScene](../../MyWallpaperX/Core/SteamWorkshopScene/)，按执行阶段与能力领域组织：

```text
Format/        作者文件、格式与解码定义
Compilation/   Graph、Material、ShaderContract、ShaderFrontend、ShaderPreparation
Runtime/       IPC、Session、Frame（进程、会话与帧编排）
Systems/       Properties、Timeline、Script、Particles、Puppet、Text、Media、Input、Animation
Resources/     Assets、Textures、Providers（共享定位、上传、驻留与发布）
Rendering/     Frame、Bindings、Graph、Targets、Dependencies、Geometry、Metal、Composition 等
Diagnostics/   独立的统计、诊断和捕获 owner
```

Format 表达作者输入；Compilation 生成 prepared 产品；Systems 更新能力状态；Resources 管理共享资源；Rendering 编码并合成唯一输出；Runtime 编排加载、帧与退出。能力不能拥有第二套 clock、registry 或 compositor。类型的扩展跟随主体，Host/Renderer 的能力接入扩展仍由编排对象持有。这些目录仍在同一 App target 中，不构成 Swift 模块依赖隔离；拆 target/package 必须先证明边界和构建收益，不能因目录分开就默认完成架构解耦。

例如：修改骨骼姿态去 `Systems/Puppet`，修改骨骼最终绘制沿 `Rendering/Frame` 到 `Rendering/Geometry`；修改文字排版去 `Systems/Text`，纹理发布查 `Resources/Textures`；修改 shader 编译去 `Compilation`，修改 FBO/history 提交查 `Rendering/Graph` 与 `Rendering/Targets`。

[布局清单](../../script/scene_source_layout.json)登记目录职责与文件归属，[测试源集合](../../script/scene_swift_source_sets.json)登记 standalone 编译输入；移动类型时同步两者、验证选择器及工程桥接路径。QuickJS 第三方源码保留 `Systems/Script/QuickJSNG` 原有内部布局。新增字段、effect、provider 或脚本 API 按播放器设计 §8.4 选择已有职责。

## 目录怎么读、怎么维护

- **本层 `.md`**：本入口与当前路线。计划只留未完成动作、依赖、完成门和退役条件；不追加完成日志。
- **`design/`**：长期设计、当前代码地图、[进程合同](design/scene-runtime-daemon-contract.md)、[启动合同](design/scene-launch-responsiveness-contract.md)、按需重构审计。已实现功能仍需要设计合同，不能因实现完成而删除合同。
- **`development/`**：落代码和验证方法。
- **[semantics/](semantics/README.md)**：按问题查能力、证据与作者语义；不整目录阅读。大型台账只按主题或精确 anchor 查询。
- **`reference/`**：版本化参考 fixture，不是下一步任务。
- **[历史库](../history/README.md)**：退役计划与已完成过程；不参与默认阅读。

[Fast Scene Suite 机器合同](../../script/scene_fast_suite.json)是 readiness 的唯一事实入口；`selection-required` 不能执行或算作通过。代码/可复现证据是当前事实，设计是目标，路线决定顺序；本页不复制动态验收计数。第一次进入仓库读完本页，再按任务选择一条路线即可。
