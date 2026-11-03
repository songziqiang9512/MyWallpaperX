# Scene 组件职责

<!-- document-role: stable-contract -->

共同执行顺序与线程边界见[运行时架构](../architecture/runtime-architecture.md)。这里限定组件交接的数据和寿命，不要求为每个阶段创建包装类型。

<a id="owners"></a>
## 数据与 owner

| 组件 | 准备事实 | 可变状态 | 编码或发布 | 退出 |
|---|---|---|---|---|
| 属性 | BindingProgram、目标类型与索引 | LaunchContext.liveState、typed snapshot | 原 uniform/图层消费者 | 真实目标退休或 Session 退出 |
| Timeline | Program、轨道、target 与 playback owner | SceneTimelinePlaybackRuntime | 同一 cadence 的数值和事件 | 活动轨道退休；幸存共享 anchor 保留 |
| SceneScript | 模块、property-bound owner、typed host 接口 | 同一 QuickJS domain 的 heap 与各 owner 状态 | typed mutation 与事件 consumer | owner quiescence、定时器/job/句柄撤权，最终 domain 退出 |
| Sprite | TEX 帧与采样元数据 | Session 的 TextureAnimationPlaybackRuntime | View 的 MultiImageSpritePlayback | commit 退休时间状态，Surface 采用新拓扑才撤 GPU 实例 |
| 文字 | 字体、排版输入、模板与初始 raster | Session 的 DynamicTextTextureStore | 各屏采用 ready snapshot 与几何 | 无活消费者时撤 producer/发布权；模板和冻结引用按各自寿命保留 |
| 粒子 | emitter/initializer/operator/child/renderer 计划 | 每屏 PlaybackState、模拟器、RNG、局部历史 | 原 ParticleMetalPipeline 的上传与 draw | commit 退 CPU root/独占 child；采用新拓扑退 GPU key，command 终态释放在途资源 |
| Puppet/模型 | mesh、rig、clip、paint 与材质 | 会话动画 clock；Surface pose/physics/骨骼与成员 | GeometryProduct、原模型/Puppet encoder | 当前成员同步退休；buffer、mask 与 publication 沿 GPU 使用期释放 |
| 相机/灯光 | 作者定义及所需 typed 输入 | 当前 topology、world frame 与动态值 | 同阶段 CameraFrame/LightSnapshot | 删除影响当前选择；隐藏不等于销毁 |
| 视频 | 资产、解码入口与实例声明 | Session 的原 video registry/source 与 AV 生命周期 | 当前/last-ready texture publication | 原 source generation、定位 token、AV borrower 与 drain |
| Sound | 声音声明、可用媒体与播放计划 | SoundPlaybackRegistry 的 voice/随机与局部时间 | 原音频播放 consumer | 实例退休、停止与真实借用结束 |
| 系统输入 | 实际 provider/脚本/粒子需求 | 原系统服务、inbox 与订阅 | 一次冻结的输入/纹理快照 | 最后活动 consumer 退出时撤需求 |
| Graph | 条件准入结果、依赖、target/transition、材质能力 | 原 SubmissionCoordinator 的 frame/ledger/history | GraphExecutor、唯一主合成 | submitted/cancelled/failed 终态及 Surface 退出 |

作者定义和 prepared 引用不可被普通 setter 回填成当前值。当前属性、播放位置、world/camera、资源 generation 和最终输出各只有一个写入权威；GPU 参数与冻结帧是消费结果。

<a id="frame"></a>
## 一次 cadence

Session 先冻结时间、完整 wall date、属性、音频和媒体，按已提交成员采样 Puppet 动画、推进原 pose/physics 并准备 VM 可读的骨骼与 cursor 投影。执行真实 VM 和 typed mutation 后，应用骨骼写入并完成 skinning/attachment，准备各 Surface 的当前投影、粒子与冻结帧。Sprite 时间在现有 Surface 循环前由同一会话 clock 求值一次。Surface 只推进属于自己的屏幕相关模拟。

View 消费冻结结果及 Rendering 资源。无 drawable、GPU busy、未提交取消与 DEBUG 重绘不能重新执行已消费的 VM、timer、出生或事件。暂停重绘可采用已就绪媒体，但不推进模拟。

- delta 来自单调时钟；wall date 与日历独立。恢复先重锚，暂停时长不注入恢复首个 simulation delta。
- VM heap 写入与 typed transaction 不同；typed 拒绝不等于撤回 shared、闭包或外部 OS 副作用。
- 初始候选用原 presentation cohort 验首帧；稳态某屏失败不回滚另一屏已提交资源。
- submit 前可 cancel；Metal 已编码/提交工作只能沿原 completion 终结。资源当前值不能在迟到 completion 中被重新贴成新请求身份。

<a id="retirement"></a>
## 活动成员与保留资源

准备模板不等于活动实例。销毁只在已提交 topology 边界退休 CPU 状态；各屏采用该 topology 后才撤对应后续 GPU 工作。commit 仅处理新增死亡集合，不重放累计死集。

隐藏、暂停、离屏、尚未出生或临时 bad return 不能充当销毁。活 clone、named 或 particle consumer 仍需对应准备资源；重建先排除已提交死实例，保留可复用 definition。

History 退休在 Surface 采用点清该层 committed 和 pending final tails，阻止晚 completion 重新提升死 tail；已编码输入与 pins 保留到原 FIFO 终态。named 输出是独立 reservation copy，不能因 producer 的私有 tail 退休误清活 consumer 或 scene color。

输入需求在 committed 成员变化或实际 owner 永久禁用/恢复处重算；普通稳定帧只检查变化标记。订阅退出只停止未来采集，不能提前释放冻结或 GPU 持有的资源。

完整 stop 先撤新工作和输入，等待已接纳 worker、媒体借用、GPU 与诊断导出各自终态。GPU drain 不能代替 AV borrower 或 PNG 导出完成。

<a id="source-map"></a>
## 当前代码入口

路径根为 `MyWallpaperX/Core/SteamWorkshopScene/`。

| 交接 | 入口 |
|---|---|
| 模型/准备 | `Runtime/Frame/SceneRuntimeModel.swift`、`Runtime/Session/SceneDesktopWallpaperHost+Launch.swift` |
| 帧/提交 | `SceneDesktopWallpaperSession+FrameDriver`、`+SurfaceSimulation`、`+SurfaceSubmission` |
| 退休/输入 | `+FrameDriverLifecycle`、`+AudioDemand`、`+PointerEvents`、`+SurfaceTeardown`、`+Shutdown` |
| 运行材质 | `Runtime/Frame/SceneResolvedMaterialExecutionCapabilityCatalog`、`Rendering/Graph/SceneResolvedMaterialRuntimeBridge` |
| GPU 终结 | `SceneResolvedMaterialSubmissionCoordinator`、`Rendering/Frame/SceneMetalRenderer+Submission` |

各领域的数值语义和支持限制由[能力索引](README.md#overview)进入，不以类型存在或文件位置推定已经执行。
