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

<a id="dynamic-layers"></a>
动态层沿 `SceneScriptDynamicLayerRuntime`、原 C handle/journal、typed mutation 和原 compositor 接入。Layer 保存出生资源、尺寸、根关系和 seed；完整 upsert 更新当前值。资源在出生准备，值变化不伪造 topology revision。C authored/dynamic 共享总 layer slots，Swift owner 工作界限是另一种输入预算；具体常量以 [C 头](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJS.h)与[Runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime.swift)为准。槽位只在原事务/快照寿命结束后回收，旧 handle 不能提前复用；journal 按需增长，不给所有 owner 预分配最大 payload。

<a id="frame-order"></a>
## 一帧与可见时间

1. Session 固定单调时间、wall date、音频、媒体和输入，读取已提交 topology，并求得属性/Timeline 的前置值。
2. 在 VM 前同步 Puppet 成员并采样会话动画 clock；各 Surface 推进骨骼 physics，准备 pre-script pose、attachment/world 观察，沿原单屏/多屏资格发布给脚本。这里不能推迟到 VM 后。
3. SceneScript 按原阶段执行回调，收集 owner effects、typed 值和骨骼等命令。模块 heap、副作用与 typed mutation 不是同一种事务。
4. 形成准入后的最终 typed snapshot；各 Surface 先应用骨骼写入，再完成 skinning/attachment、当前 world/camera 和粒子模拟，冻结 SimulationFrame。没有 drawable 仍推进一次模拟。
5. 每个 Surface 独立准备资源、编码和提交。未提交候选取消自身资源，不撤销另一屏已提交工作。
6. 任一屏提交后，Session 消费唯一 pending provider 输入，文字与封面各请求一次；一个 attempt 的所有屏仍消费循环前固定的 publication。全未提交保留到重试或下一 cadence 覆盖。
7. 原 commit/finalize 接纳 typed mutation、动画/媒体命令、storage 与 topology；下一 cadence 不重放已消费的 VM 或事件。

前置与最终 snapshot 有不同消费者，不能合成一个阶段来省调用。camera、visibility、particle、texture command 的当帧/next-frame 边界由各自实际语义决定，不能统一改为立即或下一帧。

暂停重绘只消费冻结帧。媒体只在 generation、terminal publication 和完整同帧 cohort 匹配时刷新；不采新 Inbox 或重跑 VM。候选首呈现有独立 cohort，稳态不等待所有屏幕。原暂停重试窗口、异步失败恢复与 stale completion 都归 [FrameDriver](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift)、[pre-script骨骼](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfacePuppetBones.swift)、[SurfaceSimulation](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceSimulation.swift)、[SurfaceSubmission](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceSubmission.swift)。

<a id="rendering"></a>
## 材质、图与输出

`GraphAdmission → Template / Variant → PreparedAssembly → ExecutionCapabilityCatalog → bindFrame → PassEncoder / GraphExecutor` 是材质主链。Compilation 构造能力；`Runtime/Frame/SceneResolvedMaterialExecutionCapabilityCatalog`持运行声明、私有 identity/map 和 claim。Bridge 只取得实际资源 demands，不持整份 compiler catalog。

PreparedAssembly 唯一持静态 uniform 计划、layout 与 shader/render-state identity；帧只附当前资源、值和设备/附件事实。HostUniformSchema 做准备分类，UniformEncoder 编码已分类输入。图 TextureIdentity 自带 layer-source 与 input-role 值语义，准备和实际 target/transition 共用。

MTLLibrary/PSO 在 graph/source 准备入口 warmup；PassEncoder 是其正/负缓存 owner。帧只查询，缺准备结果作 effect-local typed failure；reset 撤旧 command 代次而保不可变 PSO。可选 archive 发布不阻挡 ready。执行期仍检查当前 extent、publication、generation、target/hazard 与 GPU 使用期，不重新做静态资格证明。

Coordinator 在原锁内提交 state/history/pin，GPU terminal 才提升完成版本。Surface 实际采用 destroyed 成员时清其 committed 与 pending final tails；在途 pin 沿原 terminal 释放，晚 completion 不能复活 dead tail。跨层 named 是独立 reservation/copy/publication，不连带清健康 consumer 自有 history。隐藏活 provider 仍可因真实 demand 执行。

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
## 线程与销毁

- AppKit、Session cadence、QuickJS、输入及 Metal encode 在 daemon 主 RunLoop。VM 在激活时 adoptCurrentThread；搬线程必须连同 VM、输入与提交寿命迁移。
- Host 的 preparation queue、资源/文字/媒体/storage worker 和编译工具子进程处理准备。首 Surface 建立仍有必要的实例加载，不是所有首帧工作都离开主线程。
- Surface rebuild 保会话共享 Store/VM；只退休该屏实例、GPU 与 capture。destroy commit 退休粒子/Timeline 等活动状态；文字沿已采用 topology 和成功提交退休。Surface 采用时退休本屏 GPU/history，冻结帧继续持原值。
- 完整 stop 先撤新工作与订阅，清 pending 输入，关闭 producer 并登记原 retiringSurfaceDrain；等文字、媒体和 deferred CPU 尾任务后，再用原 command queue barrier 等 GPU terminal。Host 还等待已接纳 preparation 队列尾 fence。
- GPU、AV borrower、文件租约及 PNG 导出有不同终态。不能用窗口关闭、cache.remove、GPU completed 或进程 RSS 代替所有资源释放。

[SurfaceTeardown](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift)、[Shutdown](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift)与[Host 退役](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift)是退出入口。资源计费归[资源合同](scene-resource-admission.md)，观察与截图归[诊断合同](gpu-stage-timestamp-diagnostics.md)。

<a id="changes"></a>
## 修改边界

外部输入在实际入口校验一次；内部传确定类型。必要的异步请求、来源 revision、publication 和 GPU 使用期只在真实消费边界确认，失败不扩大到无关层或会话。新增状态、抽象或检查须指出具体消费者和会发生的错误，替换后同批撤旧字段/API/重复计算。

只以当前源码和可复现行为说明现况。缺少测试不等于已发现缺陷；构建、路由命中、非黑或少量样本不证明全能力。后续工作从[开放队列](../roadmap/scene-open-breakpoint-queue.md)进入，性能归因使用[测量方法](../roadmap/performance-convergence-card.md)。
