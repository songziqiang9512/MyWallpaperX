# Scene 当前架构与源码地图

<!-- document-role: current-state -->

本文描述当前 Scene 的执行结构、数据所有权和修改边界。领域语义与支持范围归[能力入口](../capabilities/README.md)，当前缺口归[开放队列](../roadmap/scene-open-breakpoint-queue.md)。源码路径以 `MyWallpaperX/Core/SteamWorkshopScene/` 为根；路径是定位信息，不是必须维持的类名或目录模板。

当前产品与状态由 Swift/AppKit 管理，GPU 使用 Metal；SceneScript 通过 C ABI 执行 QuickJS-NG。作者 Shader 沿现有 normalization、随 App 的 glslang / SPIRV-Cross 工具、MSL 与设备准备链进入 Metal，不在 Swift 中另写语言解释器。

<a id="execution-chain"></a>
## 播放主链

```text
App 用户意图 / 属性 / 显示与系统输入
  → SceneDaemonClient → DaemonProcessTransport
  → 同二进制 --mwx-scene-daemon → SceneDaemonRuntime
  → SceneDesktopWallpaperHost.requestLaunch
  → RuntimeModelBuilder / ResourceView / prepareLaunch
  → prepared graph、Program、资源、Timeline、QuickJS
  → 候选 Session → Surface / View / Renderer → 首帧 GPU 完成
  → 父端 commit → 实际 presented → 父端 finalize → 旧 Session 退役

Session cadence
  → 时间与输入快照 → Timeline / VM / typed mutation
  → 各 Surface 的投影、模拟和冻结帧
  → 资源发布 → graph encode → 作者顺序合成 → 场景后处理
  → 每个 View 的唯一 CAMetalLayer 输出
```

产品意图、跨引擎选择和持久设置在 App；Scene daemon 持有播放窗口、VM、资源和 Metal。普通帧不经 IPC 传节点或 draw call。启动、属性准备与可选缓存细节归[启动合同](scene-launch-responsiveness-contract.md)，进程交接归[daemon 合同](scene-runtime-daemon-contract.md)。

源码入口：[应用分支](../../../MyWallpaperX/App/MyWallpaperXApplication.swift)、[client](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift)、[endpoint](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift)、[Host 准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift)、[模型构造](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeModel.swift)、[候选激活](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift)。

<a id="owners"></a>
## 唯一所有权

| 职责 | 当前 owner | 消费与退出 |
|---|---|---|
| 活动、候选和退役会话 | `SceneDesktopWallpaperHost` | 请求 newer-wins；失败保旧输出；finalize 后退旧 Session |
| 时间、VM、输入与共享模拟 | `SceneDesktopWallpaperSession` | 一次 cadence 消费一次；暂停不追补模拟债务 |
| 实例属性 | `LaunchContext.liveState`、原 BindingProgram | Program 持验证和索引，LiveState 持当前值/revision；发布 typed snapshot |
| 脚本 heap 与模块 | 同场景 QuickJS domain、各 property owner | Swift typed mutation 可拒绝；JS heap 不复制回滚；owner 退出撤事件/timer/job |
| 本屏模拟与冻结帧 | `Session.Surface` | 粒子/Puppet 实例保本屏输入；View 只消费已形成的 SimulationFrame |
| 动态文字、媒体封面 | Session 的唯一 Text Store / Media Store | 各屏共享同一次就绪快照；重建不关 producer；会话结束排空 |
| 视频与声音 | Session 的 Video/Sound registry 及原 source | source/voice 状态独立；stop 与 AV borrower 最终释放分别判断 |
| 来源与资源 identity | `SceneResourceView`、typed lookup identity、各 producer | 路径解析、来源租约、purpose、publication 分开；不另造资源注册中心 |
| 资源总额 | `SceneResourceBudget.shared` | 只管字节租约；cache/pool 子额度和真实对象使用期仍归原 owner |
| 每屏资源发布 | Renderer 的 `SceneFrameTextureRegistry` | prepared/current/previous、提交/丢弃按本 Surface 结果处理 |
| 每屏图、history 与 GPU 完成 | Bridge 的 `SceneResolvedMaterialSubmissionCoordinator` | ledger、target、pin 和 terminal 回执使用原身份 |
| 最终输出 | `SceneMetalRenderer` / `SceneMetalView` | 作者顺序合成与唯一 drawable 输出 |

[Session](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession.swift)与[LaunchContext](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperLaunchContext.swift)持有实际运行引用。PreparedLaunch 是后台准备到 Session 的短期交接；同一 Context 被接管，不是第二执行器。用户选择纹理的活动结果只在 Session，View 保存绘制快照。

<a id="data-phases"></a>
## 数据分期与依赖

| 层 | 当前内容 | 代码落点 |
|---|---|---|
| 作者事实 | 原始顺序、缺席、资源引用、脚本、材质声明 | `Format/`、`SceneRuntimeModelBuilder`、资源解析 |
| 准备结果 | typed definitions、Program、graph、binding、需求、静态 uniform / sampler / compile identity | `Compilation/`、`Runtime/Frame/` 的值与能力声明 |
| 活动状态 | 属性 current、Timeline、VM、动态层、实例 RNG/pose、provider generation | `Systems/`、Session / Surface |
| 帧产物 | typed snapshot、相机/世界矩阵、冻结模拟结果、当前纹理与 GPU 参数 | `Runtime/Frame/`、`Rendering/` |
| GPU 使用期 | allocation、reservation、prepared pass、submitted ledger、history pin | `Resources/Textures/`、`Rendering/Targets/`、`Rendering/Graph/` |

普通帧不重读作者 JSON、编译、整图序列化/哈希或构造完整诊断。准备计算和运行载体分开；不能为清目录依赖把混合 namespace 全部公开，也不必把真实 Template/Variant 准备消费者伪装成纯值。

BindingProgram 在构造/解码入口验证并建立索引；普通属性求值只处理当前输入。自然尺寸回填只改 descriptor 几何，不重算既有准备计划。动态 topology 与 frame schema 分别按实际 revision 更新，同 revision 不回填完整活动树。parent、update 顺序和 render 依赖是三种关系，不能互相替代。

Direct model 的冷 MaterialPlan 从 descriptor 已准备材料链接固定首个 pass0，一次投影材质并合并原 Catalog 资产需求；原 DeviceResourcesTask 在 geometry 发布后的唯一 resource-planning 交接接收计划、最小 readiness 和 Script 动态 image 需求。两个 Task 的实现归 `Runtime/Session/ScenePreparedDeviceResourcesTask.swift`，无第二等待。模型Entry持可选asset/named缺省与typed用户slot0身份；用户ready优先、only absent回缺省，未选named/video不阻反射或呈现，从当前FrameTextureRegistry取当帧texture/UV/sampler/content，颜色和阴影复用冻结draw，退出 slot0 冷加载与纹理驻留。视频只索引实际 preparedVideo 消费者，复用原 decoder、初供资格和暂停重试。详细边界归[模型资产合同](../capabilities/advanced-object-coverage.md#model-albedo-frames)。

<a id="default-2d-general-zoom"></a>
### Default2D 的 general.zoom 输入合同

本节约定普通二维画布的 `general.zoom` 输入合同；产品支持和固定官方控制的观察范围由[运行证据](../capabilities/runtime-evidence-current.md#general-zoom)维护。官方普通2D控制在 General=3 的有效大尺度画面同时读到 `getCameraTransforms().zoom=1`，因此 General 基准与 CameraTransforms 相对倍率必须保留独立身份；不能因二者均影响 cover 而合并 target。保存的 editor eye/center 不因此成为普通画布的运行变换。不扩大到 native perspective、source/UV 算法或未获资格的混合相机语义。

`authored general.zoom → 原 GeneralDescriptor / Timeline IR → CameraDescriptor.generalZoom / 原 prepared definition、BindingProgram、ScalarProgram → .camera(.generalZoom) → typed snapshot → 原 CameraFrame factory`。`.camera(.zoom)` 保留 CameraTransforms / 原 path 的相对倍率、fallback1和原命令事务；General 不进入 `staticTransformFields`、C getter/setter 或持久 setter map。解析和来源选择只在冷准备做一次，不新增 zoom store、clock、缓存、来源仲裁表、C ABI 或样本派发。

| 输入 | 原 owner 与准备结果 |
|---|---|
| 静态数值与 wrapper fallback | GeneralDescriptor 保原作者数值；原 CameraInputProfile / launch definition merger 形成 generalZoom 的唯一 fallback，缺省保1 |
| Animation | 原 general Timeline 解析与 TargetCompiler 保作者 lanes/options/身份，交唯一 PlaybackRuntime / SceneClock；linked 与 Script 组合仍须原 owner 的真实消费，不能剥关系后静默改成静态或独立轨 |
| 直接 user property | 外部 general.zoom 归原 `.scene(field: "zoom")` 路径分类，再映射 typed General target；原 BindingProgram、liveState 和 prepared live consumer 负责热更，不暴露内部 generalZoom 为顶层 camera 字段 |
| return-only Scalar Script | 原 ScalarProgram / ValueOwner 读取真实 exports并发布 General target；不新增 side-effect 权限 |
| CameraTransforms setter | 只写原 eye/center/up/zoom；完整 getter record 改 eye/center 后回写不再夺取 General target。原 command/admission/回滚、当帧覆盖及 play 归还原 Timeline 的事务保持 |

已选择的 default2D camera path 保原 zoom 来源、缺省、显隐、命名和播放时钟；General 不作为新增 writer 加入该分支，也不能反过来使健康 path 被拒。有作者camera声明的输入（含原拒绝路径）继续原route；仅无该声明的普通default2D分支接General。原 CameraFrame factory 在普通2D将 General 基准乘既有相对倍率一次，再按原数学将 cover 世界范围除以该倍率；source/main 不另乘相机。此组合来自相对倍率/default1语义与既有数学，官方显式相对倍率2的组合公式及晚段尚未获资格，不能记为官方精确公式已证。General/path混合、native场景仍未支持。HDR条件只约束bloom消费者。

输入沿原 typed 数值与 target 局部失败合同处理；坏属性热更、Script 异常及拒绝的组合保合法 fallback/current 和健康 peer。General只映射独立generalZoom，不暴露内部字段为顶层camera输入；原ortho live consumer接纳General热更，CameraTransforms fallback1与path边界保持。来源已拒绝时不得拿1伪装作者 zoom 已消费，也不在普通帧补解析、补 VM 或重复验证。

当前 SourceFacts 每次 launch 重新解析，property inspection 只保进程内准备快照，没有独立解析磁盘 schema 可升级；launch definitions/index 继续按原 authoredDefinitionRevision 失效。持久编译缓存由构建生成的 SceneShaderCacheIdentity 语义指纹区分，Format 已属于其输入；本次解析变更必须随构建生成新指纹，不手改生成资源、不为未改的 shader wire 格式加版本。若实际改到持久 envelope，才在其原 owner 升级对应 schema；暖帧不扫描源码或重算指纹。

验收先沿真实 parser → 原 producers → typed generalZoom/zoom 各自 source → CameraFrame 验静态、缺省、原 single 曲线、合法属性/Script 与失败/回滚；必须覆盖同帧 General3与getter1，以及普通作者完整record只改eye/center的往返回写不锁住General轨。保旧 path 的显隐、命名、暂停与 setter/play/rollback 反例，以及 HDR 开启仍消费 General。真实 LaunchFrameSchema/FrameDriver 消费不能仅由手工 Fixture merge替代。再核宽窄viewport、非零origin、parallax与同帧cursor/particle，普通image/effect、local composition和fullscreen仍只消费原camera结果。Swift变更须Debug build与隔离首段/终段画面；接线或粗尺度控制不关闭黑纹问题。需要新camera owner、未定混合规则或第二输出时停止扩张。

<a id="dynamic-layers"></a>
动态层沿 `SceneScriptDynamicLayerRuntime`、原 C handle/journal、typed mutation 和原 compositor 接入。Layer 保存出生资源、尺寸、根关系和 seed；完整 upsert 更新当前值。资源在出生准备，值变化不伪造 topology revision。C authored/dynamic 共享总 layer slots，Swift owner 工作界限是另一种输入预算；具体常量以 [C 头](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJS.h)与[Runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime.swift)为准。槽位只在原事务/快照寿命结束后回收，旧 handle 不能提前复用；journal 按需增长，不给所有 owner 预分配最大 payload。

<a id="frame-order"></a>
## 一帧与可见时间

1. Session 固定单调时间、wall date、音频、媒体和输入，读取已提交 topology，并求得属性/Timeline 的前置值。
2. 在 VM 前同步 Puppet 成员并采样会话动画 clock。各 Surface 推进骨骼 physics 并准备 pose、attachment/world；本帧 [光标路由](../capabilities/runtime-input-property-coverage.md#cursor-puppet-surface)确定共享骨查询和 `input` 的来源。随后一次发布共享脚本快照。
3. SceneScript 按原阶段执行回调，收集 owner effects、typed 值和骨骼等命令。模块 heap、副作用与 typed mutation 不是同一种事务。
4. 形成准入后的最终 typed snapshot；各 Surface 先应用骨骼写入，再完成 skinning/attachment、当前 world/camera 和粒子模拟，冻结 SimulationFrame。没有 drawable 仍推进一次模拟。
5. 每个 Surface 独立准备资源、编码和提交。未提交候选取消自身资源，不撤销另一屏已提交工作。
6. 任一屏提交后，Session 消费唯一 pending provider 输入，文字与封面各请求一次；一个 attempt 的所有屏仍消费循环前固定的 publication。全未提交保留到重试或下一 cadence 覆盖。
7. 原 commit/finalize 接纳 typed mutation、动画/媒体命令、storage 与 topology；下一 cadence 不重放已消费的 VM 或事件。

前置与最终 snapshot 有不同消费者，不能合成一个阶段来省调用。camera、visibility、particle、texture command 的当帧/next-frame 边界由各自实际语义决定，不能统一改为立即或下一帧。

General基准与CameraTransforms相对倍率共用此值求解顺序但保独立target；最终准入后的generalZoom与zoom只由原CameraFrame factory组合一次并转成本Surface的camera/cover，world、cursor、particle及source/回绘消费同阶段结果。普通帧不读取general，setCameraTransforms的当帧命令和失败回滚仍归原事务，不能通过重跑Timeline或另乘source/main矩阵补相位。

暂停重绘只消费冻结帧。媒体只在 generation、terminal publication 和完整同帧 cohort 匹配时刷新；不采新 Inbox 或重跑 VM。候选首呈现有独立 cohort，稳态不等待所有屏幕。原暂停重试窗口、异步失败恢复与 stale completion 都归 [FrameDriver](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift)、[pre-script骨骼](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfacePuppetBones.swift)、[SurfaceSimulation](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceSimulation.swift)、[SurfaceSubmission](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceSubmission.swift)。

稳态 tick 到期且当前各屏均等待原材质 GPU 提交时，FrameDriver 可在消费本次模拟输入之前等至下一名义 tick。原 Coordinator 结算并释放历史后，首个恢复准入的当前屏唤醒同一个一次性计时器。截止时照常推进一次模拟，延后的 tick 从实际执行时刻排下一帧，避免追赶时额外触发 VM。健康屏存在时照常前进，媒体、drawable 和编码失败仍走原路径。暂停、换屏、退役沿原计时器与 Surface 身份取消。保原历史提交和失败回滚，不重画旧模拟或放宽串行约束。以原包实际呈现间隔、CPU 每秒成本及独立媒体邻例核验。

<a id="rendering"></a>
## 材质、图与输出

`GraphAdmission → Template / Variant → PreparedAssembly → ExecutionCapabilityCatalog → bindFrame → PassEncoder / GraphExecutor` 是材质主链。Compilation 构造能力；`Runtime/Frame/SceneResolvedMaterialExecutionCapabilityCatalog`持运行声明、私有 identity/map 和 claim。Bridge 只取得实际资源 demands，不持整份 compiler catalog。

PreparedAssembly 唯一持静态 uniform 计划、layout 与 shader/render-state identity；帧只附当前资源、值和设备/附件事实。HostUniformSchema 做准备分类，UniformEncoder 编码已分类输入。图 TextureIdentity 自带 layer-source 与 input-role 值语义，准备和实际 target/transition 共用。

终端 Compositor 从原 DrawRequest 取得尚未被 Program 消费的依赖，不另传同一依赖的单数投影。正常绘制与延后复用共用最终合成；延后复用沿原 ticket 记账已消费的输入，即使当前 request 的依赖向量为空。

原 `SceneMainPassEncoder` 保首次附件操作（clear 或 load）。首个 encoder 成功创建后，读取前景前先关闭实际写入的 encoder，封口也只关闭当前 encoder。两处都复用已存储的同一附件，不创建空 load/store pass。首次附件操作失败仍交原失败链；保深度 store、组背景、已填历史颜色与后续真实 draw。验证主合成 pass 数和实际颜色等价，再用同条件呈现与 GPU 帧时判断收益。

MTLLibrary/PSO 在 graph/source 准备入口 warmup；PassEncoder 是其正/负缓存 owner。帧只查询，缺准备结果作 effect-local typed failure；reset 撤旧 command 代次而保不可变 PSO。可选 archive 发布不阻挡 ready。执行期仍检查当前 extent、publication、generation、target/hazard 与 GPU 使用期，不重新做静态资格证明。

Coordinator 在原锁内提交 state/history/pin，GPU terminal 才提升完成版本。Surface 实际采用 destroyed 成员时清其 committed 与 pending final tails；在途 pin 沿原 terminal 释放，晚 completion 不能复活 dead tail。跨层 named 是独立 reservation/copy/publication，不连带清健康 consumer 自有 history。隐藏活 provider 仍可因真实 demand 执行。

<a id="effective-quality-policy"></a>
### 默认能力与质量策略

默认播放以完整作者能力为基准；水滴所需的官方后处理超高发光属于当前兼容目标，不等待档位UI。作者General HDR/Bloom开关、各自strength与材质声明继续控制实际贡献，默认不能覆盖关闭或零贡献。材质语义及验收归[HDR发光合同](../capabilities/advanced-object-coverage.md#model-hdr-emissive-gain)，未验证效果仍由开放队列维护，不把目标写成已获官方画面资格。

后处理的「超高」和「超高（显示 HDR）」共用作者工作域、资源、颜色传递函数与终端映射。App 保存选择，Scene daemon 将同一意愿交给活动、候选及以后安装的 Surface；Metal View 只消费显示意愿和当前屏有效 headroom。普通超高始终使用 SDR 范围，显示 HDR 按屏申请 EDR。切换这两档不重建 Program、附件、作者时钟或 raw history。已暂停的活动 Surface 用原冻结帧刷新，候选继续按原接管状态。这条类型化路径接管后退出独立 HDR 偏好通知及跨进程强制同步。 [现役工作卡](../../development/wallpaper-quality-work-card.md#execution)

兼容降低 HDR 工作域时，带 `clear=false` 的作者场景继续通过原 `sceneColor` 保存跨帧 raw。用当前 SDR 附件描述建立资源，终端把完成 raw 复制到当前 drawable，普通 Bloom 在显示副本上执行。暂停重导出及 GPU 完成保持原身份规则。普通作者 SDR 的 `clear=false` 仍沿其原合成路径。

质量请求在 [Scene 冷准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift)将阴影档投影给原静态模型和光空间深度图。全部作者灯仍由现有状态供直接灯、体积及几何消费者读取，「禁用」只撤可选阴影绘制和实际贴图采样。「中」沿原 PCF 和投影 fit，将定向图封顶 1024。「超高」保现有自适应预算。点／聚光沿原尺寸和采样，每次新准备在候选中固定阴影档，旧会话持续用已准备资源。重新应用、属性重载和 daemon 恢复会采用新意图。

点光体积档在同一 Scene 准备请求生效。禁用时跳过点光体积及其专用实体遮挡深度管线，清屏透视和作者无阴影灯的准入仍归原点光路径。主相机深度、表面光、聚光锥和阴影消费者保持各自职责。已显示会话保本代体积结果，效果随原壁纸重载换代。 [点光体积合同](../capabilities/advanced-object-coverage.md#point-light-volume)

场景反射档在冷准备选择可选模型反射管线和普通图像的默认屏幕反射。关闭时保模型材质声明与原 HDR 发光、颜色和深度。普通图像的原 [光照 profile](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneBaseMaterialLightingProfile.swift) 供直绘与基础图像捕获，共用作者 alpha、直接光及剩余有效纹理需求。作者 Program 的显式环境输入沿原资格供货。Shader 声明默认环境槽的基础材质随实际消费者准备，复用原前后帧颜色。具名模型源晚到时，独立环境消费者可用原根深度预约，无需可选反射模型作为许可。无其它环境需求时，模型关档退出原可选快照和 mip 工作，持久 raw、终端完成及具名输出继续由原提交 owner 管理。 [反射合同](../capabilities/advanced-object-coverage.md#static-model-screen-reflection)

<a id="scene-frame-rate-policy"></a>
App 以 10–120 整数保存动画帧率，Scene 启动和热更新沿原数值 IPC。现有目标屏拓扑同时记录当前显示模式的小数刷新率。单屏和同频屏按当前模式限制，不同频或未知模式采用共同保守上限，最多 60。仅刷新率变化时重排原 timer，保候选身份和原 Surface。设置显示已确认会话的生效值，尚未接管时显示当前配置能预测的上限。 [活动及候选会话](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession.swift) 各接收同一请求，活动会话重排原 timer，不更换作者时钟。过载找下一未来槽，暂停首帧保原有界准入。粒子沿原 1／60 秒固定步进，在正常低帧率期间按该会话有效间隔调节过载上限。

解码租约预算在 Scene host 初始化时定一次，并与帧率分开。升级前使用旧小预算的设备保留本机兼容值，便携导入不传递它；改帧率不会扫描或缩减已有缓存。 [移除旧预算的验证条件](../../development/wallpaper-quality-work-card.md#scene-rate-rollout)

增加新的性能档位前，先以可比CPU/GPU、内存、启动或能耗证据确定取舍，再在原prepare入口形成被真实Program/资源/后处理消费者使用的有效策略，质量只控制对应能力和采样/分辨率等实际成本。当前不先建空enum、仅透传对象、第二配置owner/cache或无消费者的uniform位；普通帧不重读UI、不重编或重复判档位。策略改变沿原受影响资源/Program准备与提交寿命更新，不分叉作者时钟、材质算法或最终输出。每项降档须说明具体画面代价，保作者控制、遮挡和健康peer，并退出被替代的旧决策；不能把缺功能、采集过载或未归因暗图称为性能优化。

<a id="raster-sample-domain"></a>
### 光栅采样域与单一可读输出

当前产品保持1×。默认2×候选因实际播放/驻留成本撤回；收益与停止线归[模型证据](../capabilities/model-runtime-evidence.md#model-raster-coverage)，不保无消费者PSO、采样参数、准备状态或测试API。后续重启须先有更低成本的可见收益，不能仅重跑原矩阵。

若重新引入多采样，最小正确单元是同一`SceneMainPassEncoder`的颜色及共享cameraDepth域，包含所有实际模型与image/text终端；PSO和附件的实际采样数一致。连续几何保同一份逐sample颜色/depth，中断读取只resolve到原单采样2D可读target，续画保原sample内容。不能逐模型resolve后叠透明小图、广播resolved深度或重开clear；clear=false只从原raw sceneColor种入一次。原MainPass/Program/pool及completion/pin承接职责，发布、历史、Bloom、display mapping仍只有原可读输出，无第二合成器、AA历史或独立分配器。屏幕后滤波不能冒真几何覆盖。

光空间shadow、VolumeOccluder独立深度重放、真正离屏图保持原域。非线性attachment-read仍限1×；多采样沿既有resolved前缀→完整graph→普通终端，不把`f(mean(c))`冒作`mean(f(c))`。选择依据真实prepared消费者/设备能力，不按样本或材质名许可；PSO只为实际消费者冷准备，普通帧不编译或解析。

原必需资源顺序和最小失败半径必须保留。可选采样不能先占账号使graph/source/snapshot或原1×深度失败；也不能仅记需求就当成真实容量、常规先造1×再重造2×、清暖缓存后每帧重建，或改账面lease却仍持物理纹理。已有在途/发布资源不回收，未编码可选资源沿原owner真实退账；不得为此无限扩张回收/重试协调层。域确定后不换采样数，无法取得原必需资源仍沿原局部失败/延期。

验收须能区分相关覆盖丢失：同半像素边缘近红/远蓝任意绘序均等于近红solo，远蓝加近红alpha.5等于purple；先读取远蓝再续近红仍须等于红solo，不能把resolved蓝广播回未覆盖sample。再核普通深度终端、offscreen/named/readback、attachment-read原graph、clear=false、取消及真实冷/暖/resize小预算反例。原景连续画面、主影/健康peer、独立作者与实际CPU/GPU/在途驻留共同决定取舍；小相位/非黑/编译成功不能替代这些结果。

<a id="submission-cancellation"></a>
### 提交与生命周期取消

`seal` 在原锁内把已经确认的 ledger、资源 pin 和 command buffer 交给 pending submission；完成回调只接纳该注册的 observation identity。正常提交在 GPU terminal 后校验当前 epoch、可发布的 sceneColor 与 tails，再提升 current/history。Surface stop 或 Scene switch 会先使旧 epoch 和池版本失效；其已提交候选完成后只退出使用期，不再要求旧内容仍可发布到新 epoch。

因此这两种生命周期取消在真实 GPU completed 后直接沿原 cancelled 终态退休，不能复用 commit 校验，也不对已封口内部载荷再建一套去重/消费许可。原 `terminalizeLedgerLocked` 按唯一 ledger ID 原子取走记录，command-buffer 注册挡旧回调；重复完成不能重复发布或释放。未到 GPU terminal 的资源继续由 pending 持有，sceneColor 的失败完成只释放、不提升版本。GPU failed、reprepare、device/executor 或未知原因仍沿原失败分类，不能通过过滤日志或修改测量器冒充修复。

验收使用原 reserve/encode/mark/seal 后调用真实 invalidate 的路径，覆盖 surfaceStop/sceneSwitch、池失效和非空 sceneColor/history、尾帧保留、重复回调与 GPU 失败；对原 bad seal、ticket 复用和正常 commit 保留独立反例。不用手工构造未消费的 sealed ledger 作为取消重认证的依据，不新增取消 owner、shadow state 或 ordinary-frame 工作。

局部视觉失败保安全 current/previous 与健康内容；非法来源、越界、错误 identity 或 GPU hazard 只拒最小不安全单元。不伪造 binding/history/资源，不把诊断或可选 cache 成功当播放许可。领域细节归[graph/shader](../capabilities/render-graph-shader-coverage.md)、[effect/composition](../capabilities/effect-execution-coverage.md)。

源码：[运行能力](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneResolvedMaterialExecutionCapabilityCatalog.swift)、[Bridge](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift)、[Executor](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift)、[PassEncoder](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift)、[提交与完成](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift)。

<a id="components"></a>
## 组件入口

| 组件 | 主要源码 | 状态与资源边界 |
|---|---|---|
| 属性 / Timeline | `Systems/Properties/`、`Systems/Timeline/` | prepared definitions/曲线与实例 current/anchor 分开 |
| SceneScript | `Systems/Script/` | 同场景 VM domain；typed mutation、owner、job 与 handle 各有实际寿命 |
| 动态文字 | `Systems/Text/SceneDynamicTextTextureStore*` | Session producer、每屏 prepared/submitted 几何；clone 模板与活动 raster 分开 |
| 粒子 | `Systems/Particles/`、`Rendering/Particles/` | Surface CPU 实例/RNG/child 与 GPU buffer/slot 分开；批次是值 |
| Puppet / 模型 | `Systems/Puppet/`、`Rendering/Geometry/` | CPU 准备共享；Surface pose/physics/RenderFrame；View GPU 几何 |
| 图片 / Sprite | `Resources/Textures/`、`Systems/Animation/` | 原 loader 准备和共享上传；动画 clock 与 GPU 更新事务分开 |
| 视频 / Sound | `Systems/Media/`、`Resources/Providers/` | source/voice 与播放意图、当前帧、借用文件寿命 |
| camera / lighting | `Rendering/Frame/SceneMetalRenderer+Camera`、`Rendering/Lighting/` | 当前成员、顺序、world/camera frame；真实 light/shadow pass |
| 系统输入 | `Runtime/Session/*AudioDemand*`、`SceneDesktopWallpaperSession.reconcileSystemMediaDemand`、`*Pointer*` | 只为真实活消费者维持采集/订阅；hidden、paused、bad return 不等于退休 |

具体类型/算法和当前未支持形态查[组件合同](../capabilities/runtime-systems-reference.md)。新组件接入现有 identity、typed 值、资源、clock、graph 与 compositor；不预建通用 ECS、第二属性树或管理器。

<a id="threads"></a>
<a id="particle-control-point-components"></a>
## 粒子控制点组件

控制点初始化、单点半径约束与双点端点搬移统一沿原 DefinitionParser → execution plan → Simulator → Runtime batch 执行。纯计划不依赖可变模拟器；各字段由实际消费者处理，不用 raw flags 组合、效果名或样本身份授播放许可。未知附加字段和未消费选项只保相关诊断，不伪称完整能力，也不阻断健康 writer、emitter 或整个系统。数值合同、实际支持范围与未资格项由[组件能力](../capabilities/particle-component-coverage.md#control-point-position)唯一维护。

控制点位置选择与空间转换分开。原 typed 帧供当前值，原点 frame 负责 world→local；实际 prepared consumer 决定需求，不借 Force 的 parentless/无 child 许可。构造预热、普通帧与显式发射各用对应输入，显式命令不能偷用后来普通帧的变换。Child 在同一个 frame 复合原 origin/scale，不能把 root frame 原样当作 child frame；普通热路径按实际需求构造点转换，child 无需求时不派生 frame。

单控制点半径约束只在解析入口准备所消费的控制点、距离和强度，普通步按作者 operator 顺序消费当前点与粒子位置；不在 renderer 补正，不复用 Force 的环境许可。固定官方对照已见移动控制点对旧粒子的搬移，仅按当前圆心投影不足以表达该行为。必要的上一控制点由原 Simulator 的控制点约束历史承接并进入原快照，不另建历史 owner 或每粒子缓存；具体搬移、半径混合、速度及缺省数值合同仍归组件能力。缺输入只跳当前操作，复供按当前点建立基线，不累积缺供期间的虚构位移；后续运动与健康组件照常执行，沿原最终运动结果边界接纳数值。

双点搬移的上一对端点只由原 Simulator 持有并进入原快照。General world 的存量粒子按原固定参考空间绘制；约束也在该空间比较控制点与当前位置，不能把 follow 当前 origin 的变化当成额外位移。ChildRuntime 仅传本次 origin/scale 和原 birth-origin 表的只读值，沿 advance→step→operator 消费；预热存量进入原表，没有第二份每粒子历史、坐标树或时钟。该额外字典读取仅发生在实际需要的 world-child 约束中，普通路径保持直接计算。

验收分真实 Parser/Simulator、Runtime→生产 Metal 和作者 batch→最终捕获；官方局部点位和定性尺寸顺序不能升级成全域公式、完整动画或逐像素一致。未消费选项及未资格组合留在[开放问题](../roadmap/scene-open-breakpoint-queue.md)，不能变成隐藏的整链许可。

<a id="particle-world-translation"></a>
## 粒子祖先平移与参考空间

世界空间粒子的层级平移沿原 `SceneLayerWorldFrameResolver → SceneLayerDynamicWorldFrameResolver → SceneParticleRootWorldTranslationPlan → Simulator / ChildRuntime → DrawBatch → particleModelMatrix` 供货。reference 是作者静态世界矩阵，current 是同一 typed 帧解析的实际矩阵；平移只改变新生位置，存量世界粒子和 Trail 历史留在 reference。相机/parallax 仍由原 renderer 消费。不另建坐标树、时钟、出生历史或状态 owner。

准备沿完整祖先链识别 origin writer，不能再以 parentless、childless 或 renderer 名称判断该平移能否执行。当前切片只接已有固定线性基下的画布平移：附件、perspective、角度/缩放 writer 及改变 basis/z 的当前值不借平移适配器授新行为；实际当前矩阵仍由原 plan 在消费处判断。renderer/材质/组件各自的真实准备与空间消费者保原职责，不借此放开尚未实现的空间操作或作者 child flags。

Root 新生沿原 birthPositionOffset 进入 reference。Child 复用原系统 origin 和 birth-origin 表：world child 的 origin 以 reference 表达，静态系统的 current origin 随本帧层平移，存量保原出生 origin；local child 的系统 origin 仍以当前层本地空间表达，事件/follow 入厂先将 parent 的 reference 位置转换为本地值，组装实例时再投到 reference，不能重复加层平移。depth-two 读取 world parent 的存量或死亡事件时复用其原 birth-origin，不能一律借当前 system origin。child batch 使用与 root 一致的 reference；点转换用匹配的参考或当前 frame 和该 child origin/scale。构造预热、事件/follow 新建模拟器和普通 advance 都接对应调用时的 typed frame，不能偷用模板初始帧。原 child 预热 population 已初始化 birth-origin 表，复用即可。

鼠标投影统一输出 current-local 坐标，需求只保 layer ID 集合；出生在原末端加一次偏移。Force 目标、Vortex 中心和 Plane 的距离比较在各自原消费者转换到粒子的参考空间，方向不平移；world child 复用原 birth-origin 差，不重复保存历史。noise 继续消费原 canonical 粒子字段，没有证据的域变换不猜。

缺失或不相容 current 只冻结受影响层的原 root/child 模拟，不补出生或推进历史；向 child 仍提供真实存活 parent population，不能用空数组触发假死亡。恢复、pause/stop、rollback 和已提交历史继续由现有 owner 处理。

验收须区分旧存量/新出生、world/local、root/static/event/follow/depth-two、初始预热和晚建预热；配旋转/非均匀静态基、改名、无效 frame 冻结/恢复及健康 peer。先用真实 Runtime/Simulator 与生产 model matrix 核世界坐标，再核实际 Metal/PNG。实际child声明与绑定需求归[Child合同](../capabilities/particle-component-coverage.md#child-declaration-options)；本段空间验收不授未消费绑定、flags位义或整条作者效果。未取得的组合继续留开放队列，不为通过控制改作者输入。

<a id="particle-scalar-remap"></a>
## 标量 Remap 合同

Remap 的 input、range、transform、operation、output 和原 lifecycle blend 分别准备、消费；不得再以一组字段形状授执行许可，或另加“某input+某output+某flags”的样本式 profile。新增消费者沿原 Parser → OperatorExecutionPlan → Simulator → batch/GPU，不增加时钟、组件注册表或每帧解析。外层 blend 已由 Operator 解析，Remap 不重复将其判为未知字段。

首个待接通的 input 是作者 `particlesystemtime`，首个输出是 opacity。其供值必须与 range/缺省 transform 分开资格，不能按字段名称直接别名为含预热和 rate 缩放的 `Simulator.simulationTime`。现有 SceneClock/SceneFrameTiming 是 typed 时间载体，不因此替未资格的 input 定义语义；沿原 frame→runtime→step 只传消费者需要的值，不增加第二时钟。与源/目标无关的标量范围、变换及运算使用同一准备与求值路径；系统级时间变换每个操作每步只求一次，粒子只处理自身当前值、作者顺序和 blend。原 vector simplex 与 scalar speed FBM 的既有行为保留在同一执行计划中，替换平行可选计划，不增加第三份专用许可；超出已有真实消费者的源或值维度保持局部不可用。

缺省 operation、input/output range、sine 的相位/单位/幅度及实际 clock 必须先有可区分证据，再写入数值合同，不能猜公式或沿用 noise 近似。先做一组有界官方控制：缺省与显式参数、常量输出运算、可见时钟与冻结相位、预热；无法区分时保留问题，重新评估下一项，不反复扩大矩阵。数值验收含有限值、0 scale、逆序范围、真正无效输入、改名与既有噪声/RNG邻例，不增加编辑器数值上限或整壁纸拒绝。

完成条件是新值经实际 Simulator alpha、Rope/Sprite batch 与生产 Metal 消费，并在相同作者输入下核活动 Remap 与最终捕获；未取得同步像素或完整子束资格时保持对应边界。证据和当前能力仍由原组件与运行证据卡维护。

<a id="display-reconciliation"></a>
## 显示配置和屏实例

目标是显示配置变化时保留仍在目标集的 Surface/View/PlaybackState、VM/cadence、粒子/RNG/拖尾和媒体播放；新增屏才准备独占实例，移除屏才退休对应资源。Session 原 reconciliation/debounce、Host preparation queue 和 retiringSurfaceDrain 继续各自所有权，不增加 controller、Clock、常驻缓存或迁移快照。旧的“任意 topology 变化即全量 teardown/rebuild”应退出已接通的场景，不用窗口更换或构建次数代表收益。

- **几何与成员权威**：主 App 的 `screenTopology` 裁决目标 ID，实际 frame/backing/输出取当前 live NSScreen/window。原 debounce 一次解析 tuples，按唯一 actual `surfaces` 与 resolved 求 retained/removed/added；同集合只刷新变化的几何，缩减只退休差集并发布一次成员。未解析的新增 ID 不拆健康屏；空解析沿原 revoke/stop。异步完成处重新解析当时目标几何，仅采用仍 desired/resolved 且尚无 actual 的结果，不用 IPC frame 或另一份 topology/cache 代替。
- **原实例与冻结帧**：保留 Surface/View/Renderer/graph、root/active child simulator、sprite/puppet实例和输入队列。playing 沿原 cadence 继续；paused resize 只按新画布重绘原 SimulationFrame，已 commit但未被 simulation 采用的 destroy 不因 geometry 提前执行。extent 变化仅沿现有 allocationReprepare 和 GPU terminal 失效 target/history，不能复用旧尺寸资源，也不更换 graph owner、清播放状态或另加 drain/fence。原 initial cohort 对实际尺寸失效的撤证仍保留，不给过时首呈现 token 续证。
- **回调事实**：client prepared callback rows 归原 transport/request/record/source/script generation，是启动期 UI 投影，不是每屏播放许可。退役 displayConfiguration.didSet 对它的无消费者清零；几何和成员变化都不产生新的 launched，不能靠等待新 launch恢复同一事实。原 switch/stop/transport 的撤销及 Host 每次 update 对当前 context、实际 prepared/unavailable/retired consumer 的检查仍是 authority，不新增 display 认证、版本或许可表。无屏解析失败的 Session 终态回流另需其原请求链取证，不借任意显示事件猜终态。
- **新增屏准备输入**：主线程在 job 准入时冻结 `evaluationTransaction.committedSnapshot`、当前 particle intent/revision 与 destroyed IDs、原 audio inbox 的只读 frame 候选。worker 只接 typed 值及实际构造所需 descriptor/assets/base-image loader/material catalogs/device，不能持整个含 VM/Storage/liveState 的 LaunchContext。初始 launch 由原准备 owner 提供初始 typed seed。原 base-image 最终 outcome 在 worker 每 job 编译一次 LayerImage，供全部新增独占实例；不复制 retained 的 SimulationFrame/Simulator、位图或 RNG，不为每帧 property generation 重做预热。
- **仅移除的退休与消费者**：先从实际map取走removed对象，再共用原单屏CPU/窗口退休步骤：只使该View的graph失效、退休粒子/Puppet、关窗，并由原retireSurface保GPU与capture至终态。全量teardown同批改用同一单屏步骤，退出复制的释放顺序；其全局输入/clock/VM/provider停止仍只归完整teardown。preparedSurfaceIDs同步为survivors，原storage identity在2→1时切唯一屏（失败仍global-only），音频需求按实际survivors一次更新；这三项在原Session共用成员发布步骤。不停健康cadence、不改committed/adopted frame、pendingProviderUpdate或共享媒体/声音。原stop继续join retiringSurfaceDrain，晚GPU/geometry回调沿既有对象身份检查失效，不新增退出队列或epoch。
- **输入来源与移除**：既有CursorPendingEvent只补optional surfaceID，由record入口写真实sample.surfaceID；跨屏leave消费该sample前原previousSurfaceID，不新增另一份leaving identity。原cursor owner仅撤removed的capture、previous hit/pointer/surface上下文及pending重试，保健康pending与单一物理previousPrimaryButtonIsDown；不合成leave/up/click，不全局empty/revoke shortcut watermark。dispatch到owner commit/finalize在原主线程无await，GPU completion不restore cursor；协调在此段外，不为假想跨段rollback添candidate过滤、tombstone或代次。真实按住移除后不能在survivor伪造down/click。
- **共享供货与候选**：同 Session 固定 prepared device，video registry 的 layer/device binding 不是 per-screen 引用计数。增减屏均不 withdraw 作者源、begin/completeSurfaceRebuild、重置 binding 或重新 prime initial videos；新增 View 从当前 source owner/key/device 与采用时最后实际接纳的 user publication 幂等取得原源，不另加缓存/计数。初始视频、动态 Store 与启动 cohort 仍只归初始启动；正式 display 入口由 Host 先 cancel pending/unconfirmed，再交 active Session。source incarnation/时钟及后续 decoded 消费若授连续性须实测。
- **新实例时间与意图**：全部 root 在原 worker 按 job-start typed size/rate/alpha/CP/层变换与 audio 完整执行作者 starttime；audio 在 root/static-child warmup 前进入原 Simulator。pointer 仍按无历史指针预热，安装时才按新屏几何零步投影，不借他屏局部坐标。新屏不补当前 sceneTime 或排队墙钟；SceneClock/VM/Timeline 仍属 Session。采用前仅对新实例按当前 destroyed 整层退休并直接对齐 root 当前 intent/revision：stop 清 root 人口，pause 保人口，play 沿原 rearm 语义；emit 只增 revision 不得伪造 play/rearm，加入消费者前的 emit 不补放。普通 static/frame-created child 原240步及独立 aging 不借本批扩张；全部 root 离主线程后退役3,600步/加权四百万的旧关卡与参数。
- **零步首帧与装配**：同一单屏装配职责消费必需的独占 PlaybackState/material runtime，供 initial 与 added 共用；删除主线程 cold-root fallback。窗口/View/pipeline/Puppet GPU 仍主线程，Session 共享 Store/VM/源不重建。新增实例在进入 actual map 前，仅对自己按当前 committed dynamic/topology、共享动画/媒体/audio 与 SceneClock 时间生成零 delta SimulationFrame；不跑 VM、发动画事件或更新 retained simulation/pose。paused 原 driver 因全部屏已有帧只重绘，playing 原 timer 不重启；实际空过或 paused 才唤醒 driver。首 GPU/capture 继续归原输出 owner，不增加 handoff 屏障或复用 startup cohort 续证。
- **混合、无保留屏与失败**：retained 是 actual∩resolved，始终沿原 cadence；obsolete actual−resolved 立即按单屏退休，不让已不 desired 或已迁移的窗口等新增屏。disjoint 准备期间 actual 可空，保同一 Session/VM/clock/共享源，允许输出空窗，首个新屏装好再唤醒 driver。可选图像/pipeline 失败局部降级；新增单屏失败不拆健康屏，不自动无限重做长预热。无健康屏且工作结束、没有更新目标待准备时沿原 revoke/stop；空 resolver 与正在准备的空 actual 分别处理。终态回流原请求/UI 的未资格边界仍独立取证。
- **新增屏异步工作与退出**：复用 Host 唯一 preparation queue；Session 仅持一个短寿命 pending 工作（覆盖 IDs、原 cancellation），入队前登记原 retiringSurfaceDrain。部分 ID 过时只丢弃其结果，全部不需、stop 或 Host 接受新壁纸请求时取消；切换先让新 candidate 入原队列，旧工作实际收尾后若还需补屏，其下一项排在 candidate 后，在原逐步取消检查点让路；不承诺抢占单步或最大切换延迟。worker 完成后主线程采用/teardown 全部产品并对同 primary loader eviction，最后才清 pending/leave，随后按最新 desired 补尚未准备的新 ID。不用 serial queue 返回冒充 loader 已完成交接，不增锁、任务列表、dirty flag 或取消代次。stop 等这项 CPU 尾、原上传队列、Surface GPU/capture；before-start 取消也必须到实际处置尾才结束工作。

<a id="display-user-texture-updates"></a>
disjoint 准备空窗不退休 Session 的用户贴图请求。原 Session 在图片准备完成、视频 prime 前后按 context/record、program、device、registry、key revision 与取消状态确认当前性，退出 actual 必须非空的旧条件；再由原 typed live consumer/adoption 接纳，原 publication/liveState 保存结果。新增 View 采用时读取这笔当前资源，不新增 pending 资源表、最后 publication 许可或假屏；完整 stop/新请求与同 key 覆盖仍使原异步尾失效。混绑的粒子显隐、模型动画等真实缺 consumer 仍按原事务拒绝，不借空窗普遍放开热更。paused 供货继承原时钟状态，无 actual 时 driver 在 VM 前退出，新屏沿原零步首帧采用。

验收先在真实 Session 方法核同请求图片/视频 prime 的空窗提交、reset/坏资源保旧、新 revision 与 stop/context/registry/device/program/取消反例；控制边界不冒充解码或 GPU。App 复用原 A→B/准备队列和 DEBUG runner，以原协议解码一笔纹理输入交 Host，核更新提交及完成时 actual=0、同 Session/request、新 B 实际纹理采样→main/seal/GPU与固定像素；未命中空窗即停止资格，不调整结果阈值。自然预热与受控 queued gate 分别记录，不把 queued 称运行中 worker。direct Host 只授其实际纵向链，不代 Service/IPC 同次交付；终态回流、全部暂停属性/视频连续及真实多屏仍独立取证。

验收复用按需DEBUG快照、原App及输入/退休门：按displayID核实例/真实几何、playing进展和paused VM/frame/sprite/root/active-child观测值，像素、allocation/GPU和capture终态继续归原门。DEBUG同集合事件先真缩窗再恢复live几何；移除事件只从原resolver结果取非空子集，交与normal debounce共用的实际协调步骤，不改env屏数冒充物理拓扑、不存override/cache。2→1/3→1须保survivors、精确退休差集、保健康输入重试、撤removed重试及物理按住反例；真实removed导出尾期间健康屏可提交，stop-before-drain仍等原尾。暂停/恢复诊断只比同次resume前后成员，不因dwell期间合法缩减误报恢复失败。新增 A→AB、混合 AB→BC、disjoint A→B 与空解析分别验真实 worker、当前输入/意图对齐、取消/失败及退出尾；长准备期间 retained 必须有真实输出，paused 不得增加 VM cadence。DEBUG accepted暂停截图仅标目标Surface需提交并唤醒原frozen driver，不借内容失效撤cohort、不重跑VM/清graph，也不因拒绝/playing请求重启cadence。初始新增屏的长starttime、准备期间size/rate/CP edit、stop/emit/destroy、晚取消仍独立验收；单物理屏的多个DEBUG View不授真实多屏、物理缩放/EDR、严格RNG轨迹同态、媒体连续或性能。

## 线程与销毁

- AppKit、Session cadence、QuickJS、输入及 Metal encode 在 daemon 主 RunLoop。VM 在激活时 adoptCurrentThread；搬线程必须连同 VM、输入与提交寿命迁移。
- Host 的 preparation queue、资源/文字/媒体/storage worker 和编译工具子进程处理准备。初始粒子实例按[预热准备合同](../capabilities/particle-component-coverage.md#prewarm-work)在原队列完整准备、每 Surface 独占移交；AppKit Surface 与 GPU pipeline 仍在主线程安装。增量新增屏沿同队列准备；具体设计见[显示配置和屏实例](#display-reconciliation)，实现与验证状态只由开放队列/运行证据维护。
- 显示增减保会话共享 Store/VM；只退休移除屏实例、GPU 与 capture。destroy commit 退休粒子/Timeline 等活动状态；文字沿已采用 topology 和成功提交退休。Surface 采用时退休本屏 GPU/history，冻结帧继续持原值。
- 完整 stop 先撤新工作与订阅，清 pending 输入，关闭 producer 并登记原 retiringSurfaceDrain；等文字、媒体和 deferred CPU 尾任务后，再用原 command queue barrier 等 GPU terminal。Host 还等待已接纳 preparation 队列尾 fence。
- GPU、AV borrower、文件租约及 PNG 导出有不同终态。不能用窗口关闭、cache.remove、GPU completed 或进程 RSS 代替所有资源释放。

[SurfaceTeardown](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift)、[Shutdown](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift)与[Host 退役](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift)是退出入口。资源计费归[资源合同](scene-resource-admission.md)，观察与截图归[诊断合同](gpu-stage-timestamp-diagnostics.md)。

<a id="changes"></a>
## 修改边界

外部输入在实际入口校验一次；内部传确定类型。必要的异步请求、来源 revision、publication 和 GPU 使用期只在真实消费边界确认，失败不扩大到无关层或会话。新增状态、抽象或检查须指出具体消费者和会发生的错误，替换后同批撤旧字段/API/重复计算。

只以当前源码和可复现行为说明现况。缺少测试不等于已发现缺陷；构建、路由命中、非黑或少量样本不证明全能力。后续工作从[开放队列](../roadmap/scene-open-breakpoint-queue.md)进入，性能归因使用[测量方法](../roadmap/performance-convergence-card.md)。
