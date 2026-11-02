# Scene Runtime 事实架构地图

<!-- document-role: current-state -->

> 复核：2026-11-02，依据当前工作树源码静态核对入口、构造、调用与释放；不代表本轮重新通过运行或性能验收。
>
> 本图只回答实际代码怎样接线。长期职责归[运行时架构](runtime-architecture.md)，语言与进程边界归[技术栈合同](../../architecture/technology-stack-boundaries.md)，能力与实际运行分别查[能力台账](../capabilities/coverage-ledger.md)和[运行证据](../capabilities/runtime-evidence-current.md)。目标与现状不同的部分，按明确的重构事项处理，不把现状提升为规范。

## 1. 一页总览

### 1.1 加载链

```text
App 产品意图与当前记录
  → SceneDaemonClient：可重放请求、属性 revision、控制与显示配置
  → DaemonProcessTransport：同二进制 --mwx-scene-daemon，newline JSON
  → SceneDaemonRuntime：解码命令，私有 SceneDesktopWallpaperHost
  → Host.requestLaunch：请求代次、取消、后台 preparation
  → SceneRuntimeModelBuilder：项目/Document/ResourceView/descriptor/属性输入
  → prepareLaunch：材质/graph/资源/Timeline/粒子/QuickJS 准备
  → SceneDesktopWallpaperLaunchContext
  → 候选 SceneDesktopWallpaperSession：接管 VM 线程、建立 Surface
  → SceneMetalView / SceneMetalRenderer：首帧编码与 GPU 完成
  → 父端 commit → 实际 presented → 父端 finalize → 旧 Session 退役
```

源码起点：应用的 [daemon 分支](../../../MyWallpaperX/App/MyWallpaperXApplication.swift)、[Scene client](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift)、[daemon endpoint](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift)、[加载准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift)、[RuntimeModelBuilder](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeModel.swift)与[候选激活](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift)。

准备阶段已有后台设备资源任务和首 Surface runtime 预热。Surface 建立仍会消费准备产物、建立实例并执行其必要加载；不能把全部首帧工作描述成已经离开 daemon 主线程。

### 1.2 所有权权威

| 当前职责 | 实际 owner 与消费边界 |
| --- | --- |
| 产品选择与持久化设置 | App 的产品服务与跨引擎切换事务；SceneDaemonClient 保存已接纳的 authored intent 和重放身份，不持有图形资源 |
| 进程端点 | SceneDaemonRuntime 私有持有唯一产品 Host；普通 App 经 client 控制，不构造产品 Host；显式 DEBUG direct runner 另持隔离 Host |
| 当前输出与候选决策 | SceneDesktopWallpaperHost 持有 active、candidate 和 retiring Session，负责请求身份、候选提交与回滚 |
| 场景时间与模拟 | Session持sceneClock、VM programs、活动状态、输入与媒体；Surface持本屏粒子/Puppet CPU实例与唯一冻结帧，每cadence推进一次，View消费结果 |
| 作者 identity 与顺序 | Model、RenderDescriptor、material catalog 和已准备计划；运行修改通过原 typed topology/属性路径进入 |
| SceneScript | 同一场景的 QuickJS domain、各属性绑定 program 和 typed host bridge；模块 heap 与 Swift typed mutation 具有不同撤回边界 |
| 属性 | 不可变BindingProgram在构造/解码时持有验证及索引；launchContext.liveState独占实例有效输入、current与revision，再发布typed快照；普通值更新不自行取得资源或topology修改权 |
| 资源来源 | SceneResourceView、所选 Root/entry 与各实际资源 producer；共享 CPU/GPU 产物按其用途保留 |
| 进程资源额度 | SceneResourceBudget.shared 统一计费应用持有的 Scene GPU 与 decoded 驻留；原 pool/cache 上限是子约束，不另建资源身份或淘汰 owner |
| 每屏资源发布 | SceneMetalRenderer.textureRegistry；provider 在帧边界发布资源，提交或丢弃由该 Surface 的实际结果决定 |
| 每屏图执行与完成 | SceneResolvedMaterialRuntimeBridge 暴露接口，其 submissions 持有 SceneResolvedMaterialSubmissionCoordinator；目标、history、claim 与完成沿原执行链管理 |
| 最终视觉输出 | 每个 SceneMetalView 的 CAMetalLayer，SceneMetalRenderer 按作者顺序经唯一主合成出口编码和提交 |
| 系统频谱 | App 的 SystemAudioSpectrumService 持有采集/分析；daemon 的 SceneAudioSpectrumInbox 消费 demand scope 对应快照 |

[Host](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift)、[Session](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession.swift)、[LaunchContext](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperLaunchContext.swift)、[Renderer](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift)、[RuntimeBridge](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift)与[资源父额度](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift)是核对这些所有权的起点。

### 1.3 线程地图

| 工作 | 当前执行位置 | 修改时要保留的关系 |
| --- | --- | --- |
| App UI、选择与控制 | App 主线程及既有服务任务 | 不逐帧驱动 Scene；对异步端点保持请求身份 |
| 场景 preparation | Host.launchPreparationQueue 与既有资源/预热 worker | 产物发布到当前请求；取消后不接管新请求身份 |
| 帧驱动、QuickJS、模拟与编码 | daemon 主 RunLoop；Session 使用一次性 Timer 排帧 | 激活时 VM adoptCurrentThread；搬线程必须一起迁移 VM、输入、Surface 和提交生命周期 |
| 作者 Shader 编译 | 固定编译工具的独立子进程 | 输出 artifact/reflection；不持有桌面或 compositor |
| MTLLibrary/PSO | 既有graph/source准备入口写PassEncoder唯一正/负缓存 | 普通帧只查询；未准备key局部typed失败，合法遗漏回原warmup修正 |
| 视频、文字、资源与存储 | 各已有 worker/inbox；Scene 在边界接纳结果 | pending 保留旧有效产物，迟到结果不能覆盖新来源 |
| GPU 终结 | Metal completion 与既有 owner 回投 | 回调只提交原身份的完成事实；不能读取 mutable current 后重贴身份 |

源码：[帧驱动](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift)、[编译子进程](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderCompilerProcess.swift)、[Pipeline warmup](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Warmup.swift)与[编码器缓存](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift)。本图不使用“零 actor”或“全部后台化”等无法代表实际调用关系的概括。

<a id="component-source-map"></a>
### 1.4 组件源码入口

| 职责 | 当前源码入口 | 专项权威 |
|---|---|---|
| 作者与节点描述 | `Format/SceneDocument*`、`Runtime/Frame/SceneRenderDescriptor*` | [格式与图](../capabilities/scene-format-and-render-graph.md) |
| 属性与帧值 | `Systems/Properties/ScenePropertyBindingProgram`、`ScenePropertyLiveUpdateState`、`SceneDynamicSnapshot` | [输入与属性](../capabilities/runtime-input-property-coverage.md) |
| Timeline | `Systems/Timeline/SceneTimelinePlaybackRuntime`及 evaluator/compiler | [输入与属性](../capabilities/runtime-input-property-coverage.md) |
| VM 与 typed owner | `Systems/Script/SceneScriptValueRuntime`、`SceneQuickJS*`及对应 bridge | [SceneScript API](../capabilities/scenescript-api-coverage.md) |
| 动态图层准备与当前值 | `Systems/Script/SceneScriptDynamicLayerRuntime*`、`SceneScriptLayerTopologyProjection`；`Rendering/Composition/SceneDynamicLayerRenderTopologyCache` | [组件合同](../capabilities/runtime-systems-reference.md#02-数据与依赖方向) |
| 粒子定义、实例与 GPU | `Systems/Particles/` 保模拟、child、RNG与history，Session.Surface唯一持CPU实例与冻结帧；View消费该帧，每屏粒子pipeline独占buffer复用、上传、draw及取消，原slot管理GPU使用期 | [粒子组件](../capabilities/particle-component-coverage.md) |
| 媒体封面 | `Systems/Media/SceneMediaThumbnailInbox`、`Resources/Providers/SceneMediaThumbnailTextureStore` | [组件合同](../capabilities/runtime-systems-reference.md#73-media) |
| 文本 | `Systems/Text/SceneTextTextureLoader`、`SceneDynamicTextTextureStore` | [输入与属性](../capabilities/runtime-input-property-coverage.md) |
| 相机与光照 | `Systems/Input/SceneCameraProjection`；`Rendering/Lighting/SceneLightSnapshot`、`SceneSpotLightPlan`、`SceneSpotLightRuntime`和 pipeline | [组件合同](../capabilities/runtime-systems-reference.md#8-puppet3d-和-lighting) |
| 声音实例 | `Systems/Media/SceneSoundPlaybackProgram`、`SceneSoundPlaybackRegistry` | [声音与频谱分工](../capabilities/runtime-systems-reference.md#72-audio) |
| Puppet/模型与动画 | `Systems/Puppet/`、`Systems/Animation/`；[Surface装配](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfacePuppets.swift)、[骨骼帧](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfacePuppetBones.swift)、[GPU几何](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/ScenePuppetMeshGeometry.swift)及同目录`ScenePuppetClipping` | [高级对象](../capabilities/advanced-object-coverage.md) |
| 资源与 provider | `Resources/Assets/`、`Resources/Textures/`、`Resources/Providers/`、`Systems/Media/` | [资源准入](../architecture/scene-resource-admission.md) |
| 材质与 graph | `Compilation/Material/`、`Compilation/Graph/`、`Rendering/Graph/` | [Graph/Shader](../capabilities/render-graph-shader-coverage.md) |
| 图层合成与输出 | `Rendering/Composition/`、`Rendering/Frame/SceneMetalRenderer`和 surface | [运行时架构](../architecture/runtime-architecture.md) |

路径以 `MyWallpaperX/Core/SteamWorkshopScene/` 为根；这些是当前定位信息，不冻结未来目录或类型名称。

<a id="diagnostic-source-map"></a>
### 1.5 诊断截图源码入口

| 职责 | 当前源码入口 |
|---|---|
| 请求、额度、readback、PNG 与 outstanding | `Diagnostics/SceneDebugFrameCapture.swift` |
| submit 与取消 | `Rendering/Frame/SceneMetalRenderer+Submission.swift`、`SceneMetalRenderer+FrameOutcome.swift` |
| active/retiring surface 与 GPU/export 排空 | `Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift` |
| Runner 与 AppKit 退出 | App 的 `Debug/DebugScenePlaybackRunner+HostOwnership.swift`、`AppDelegate.swift` |

前三行相对 Scene 源码根，最后一行相对 App 目录。生命周期语义由[诊断截图合同](gpu-stage-timestamp-diagnostics.md#debug-capture-lifecycle)维护。

## 2. 加载与分配地图

| 产物 | 准备、持有与失效 |
| --- | --- |
| 场景、资源与作者描述 | RuntimeModelBuilder 从唯一 source facts 构造；launchContext 保留执行所需数据，相关内容改变后重新准备 |
| 材质与 Shader artifact | Compilation 产生 catalog、variant、prepared uniform 来源和执行能力；后端产物进入同一 Program/Graph，不引入另一 renderer |
| 纹理、模型与粒子定义 | 后台设备资源任务与资源 loader 准备；实例和 Surface 消费结果；资源来源、用途、device 与 revision 决定复用 |
| MTLLibrary、PSO、sampler | 原 repository/PassEncoder 缓存；同一来源合并编译，launch warmup 提前准备当前需求 |
| Puppet准备与实例 | PreparedPuppetResources保CPU资产及作者/default pose，`ScenePreparedDeviceResources+Puppets`在BaseImageResources一次准备paint，PipelineRepository按需准备clipping PSO；Surface经同步资源hook装配几何，有播放实例时注册会话动画runtime后安装CPU/GPU。Surface负责成员、骨骼ABI与冻结RenderFrame，View.puppetGeometries保GPU存储/发布；已提交删除同步退休实例，表面退出清CPU后沿原GPU drain释放 |
| GPU 纹理和 buffer | 通过 makeSceneTexture/makeSceneBuffer 等分配入口绑定实际资源 lease；额度随实际对象释放，候选和退役资源仍计费 |
| decoded 中间缓存 | SceneTextureDecodeCacheBudget 与进程父额度共同约束；不命中或不保留中间缓存仍可沿原解码/上传路径播放 |
| 用户选择纹理 | PreparedLaunch短期携初始结果，候选激活显式移交Session；Session保存唯一活动结果，View仅保存绘制快照。LaunchContext无纹理镜像，新表面读Session当前结果，旧绑定沿原completion/drain释放 |
| 视频与 Sound | Session 的实际播放 registry 持有可变播放状态；私有媒体文件使用原 OwnedFile/AV borrower 生命周期，stop 不冒充全部 AV 借用已结束 |
| 动态文字 | Session唯一Store准备初始raster并后台更新；每attempt共享ready snapshot，View独立保存prepared/submitted几何。任一屏提交后消费单份pending输入；重建复用producer，完整stop挂既有retirement fence后清引用 |
| 动态图层 | Mutation Runtime/Plan保存出生Layer与原typed current；资源、创建尺寸和seed只在出生准备。结构revision缓存Layer数组及Renderer projection，同revision不回填live字段；当前值沿Session snapshot进入原消费者 |
| 媒体封面 | Session唯一Store生产current/previous及各purpose；每cadence一次snapshot供VM/各View，View只保冻结snapshot与输入generation。共享pending在任一屏提交后请求一次，重建复用，完整stop撤权后沿retirement group排空 |
| 目标与 history | 原 Surface pool、graph target 与 completion owner 管理；受 SceneResourceBudget 父额度约束，history 与 submission pin 决定可释放时机 |
| 运行属性与脚本状态 | Session 的 LaunchContext、frame schema 和 program；JS heap 不随 typed admission 失败复制或回滚 |
| 帧资源发布 | 每个 Renderer 的 SceneFrameTextureRegistry；beginFrame、commit/discard 和完成信息共同确定可见版本 |

资源父额度计费应用通过入口分配和持有的部分，不等于 Metal/AV/WindowServer 全部内存。精确覆盖、限制与未计入项查[资源准入设计](scene-resource-admission.md)。已存在进程父额度，不能继续把“没有跨 Surface 聚合 cap”当作当前缺口。

## 3. 一帧执行与隐性约束

Session 冻结本次时间、属性、输入、音频和媒体（含完整 wall date），形成脚本可读的前置快照；执行回调与 typed mutation 后，准备最终模拟状态。每个 Surface 消费同一模拟 cadence 的状态，再作自身投影、资源发布、图编码与提交。

1. **模拟与呈现分开。** 稳态 Surface 的 drawable 缺失或 GPU 忙，不重新执行已消费的 VM、timer 或输入；恢复屏采用最新模拟状态。
2. **候选首帧单独协调。** 初始候选使用 SceneInitialPresentationCohort 跟踪当前 Surface 成员及 GPU 成功；这不要求稳态每帧等待全部屏幕。
3. **提交前可以取消。** PreparedFrame 持有 submit/cancel，Surface 决定是否提交；提交后通过 GPU completion 终结，不能假装 CPU 撤回已经提交的命令。
4. **图资源跟随同一提交。** claim、target、输出消费、seal、publication 与 completion 必须匹配原 command buffer 和执行身份；不能提前 enqueue 或私建第二个提交出口。
5. **JS heap 与 typed 状态分开。** 当前 typed mutation、事件确认与 localStorage candidate 有自己的接纳或撤回规则；shared、闭包和模块对象不是可复制回滚的事务存储。
6. **坐标与资源用途保持来源。** 动态根变换由SceneLayerDynamicWorldFrameResolver局部更新，作者层级/attachment共用SceneLayerWorldFrameResolver的localFrame。SceneScriptLayerRuntimeDescriptorBridge仅向既有作者catalog发布其prepared byID内的Mat4；动态clone仍沿C record与Renderer typed变换。资源extent、UV、sampler和颜色保原来源。
7. **诊断只观察。** DEBUG readback、trace 和 HUD 消费真实执行；统计、截图或证据窗口不构成产品提交权威。

源码：[Session Surface 提交](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceSubmission.swift)、[View 帧消费](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift)、[Renderer 提交](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Submission.swift)与[纹理 registry](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift)。顺序和失败目标由[运行时架构](runtime-architecture.md#83-一帧的有序工作与可见时间)维护，脚本具体语义查[API 合同](../capabilities/scenescript-api-coverage.md)。

## 4. 修改边界与释放

| 修改 | 当前应核对的 owner |
| --- | --- |
| 切换、取消、崩溃重放与外部设置 | SceneDaemonClient、SceneDaemonRuntime、Host 及跨引擎切换事务 |
| 场景准备与首次资源 | RuntimeModelBuilder、prepareLaunch、LaunchContext 及原 prepared task |
| 普通值、脚本与动态节点 | Session FrameDriver、frame schema、typed bridge 和实际消费者 |
| 图、目标和最终合成 | RuntimeBridge/submissions、Renderer、MainPassEncoder 与 ImageLayerCompositor |
| 资源更新与采样 | 原 producer、ResourceView、registry、相关 store 和 Program binding |
| 停止与资源回收 | Host retiringSessions、Session SurfaceTeardown/Shutdown 及每类资源 owner |

停止会先撤新工作、输入与订阅，关闭 store，停止媒体与脚本 owner。Session 保留已经退休 Surface 及其 CPU drain；已接纳文字、媒体封面及deferred worker结束后，再用原 command queue 的 GPU barrier 确认终态。Host 沿原 preparation queue 尾 fence 等待已接纳准备；没有当前 Session 也不能漏掉这部分工作。主线程不阻塞等待。

[SurfaceTeardown](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift)、[Shutdown](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift)与[Host 退役](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift)分别给出关闭、排空及保留关系。GPU 成功不代表 AV borrower、文件借用或 DEBUG 导出已结束，释放结论按实际 owner 划定。

### 4.1 已落地缓存的边界

Shader artifact、variant 分析、decoded 资源、prepared geometry 与 Pipeline 都有各自缓存。复用条件在对应 owner，缓存命中不能重贴请求身份，也不授予已停止 owner 继续发布的权利。

当前已有设备资源后台准备、上传queue共享、进程父额度及实际存活期lease。材质Graph/source准备的warmup是唯一PSO编译点；PassEncoder帧内只消费正/负缓存，缺准备结果局部拒绝，reset仅撤旧command代次而保不可变PSO。后续优化先测准备、分配与编码成本，不重建已有能力。启动与缓存合同查[启动合同](scene-launch-responsiveness-contract.md)，Pipeline源码查[PassEncoder](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift)。

## 5. 保留的底座与需要继续收敛的职责

保留同二进制 daemon、Swift/Metal 产品所有权、真实 QuickJS VM、唯一资源来源、prepared catalog/Program、每屏图与统一最终合成，以及模拟和呈现分离。外部通用设计中的同进程起步、JSC 优先或整套新目录，不覆盖这些已经存在的合理边界。

当前 prepareLaunch 与 FrameDriver 仍负责装配多类 program、状态和资源，LaunchContext 同时携带不可变准备事实及可变实例。后续按实际数据寿命和消费者收敛准备/实例/Surface 职责，退役重复投影与准入；不在现有对象之外再包一层 SceneSession 或万能组件容器。具体改造与顺序进入现役顶层设计和路线，不由本图再开第二个队列。

## 6. 维护规则

变更 owner、构造、消费或释放点时更新对应行，并核当前源码。保留符号和文件入口，避免把易漂移行号、旧批次统计和一次样本结果当永久事实。能力和运行结果分别回各自权威，本图不记录支持率、PASS 数、临时产物或未来任务顺序。
