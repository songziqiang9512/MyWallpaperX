<!-- document-role: active-plan -->

# Apple silicon 与全 App 性能优化执行方案

状态：2026-10-19 研究完成；24 项候选／取证任务尚未实施，收益尚待分项验证。源码基准为 `32be3ec1d6bf3d8bf10eab343bcd57a0c1c3db76`。本轮只读研究产品、核查官方资料、编写文档，没有运行 App、构建或性能测试。

本计划拥有本轮跨模块研究的候选、建议依赖顺序与取证任务；不新增运行时 owner，不取代[技术栈合同](../architecture/technology-stack-boundaries.md)、[播放切换事务](../architecture/playback-lifecycle-transaction-design.md)、[Scene 性能卡](../scene/roadmap/performance-convergence-card.md)或[Web 当前状态](../web/current-state.md)。Scene 项进入实施时，先在原性能卡／所属设计接入选中任务，本计划对应项只留指针，不在两处维护“下一步／进行中”状态。本文不是全模块实现设计或全项改代码的授权。

## 目标、取舍与职责

用户目标是更快设置壁纸、属性准备更短、主窗口响应自然，以及长期播放资源消耗更低。保留独立播放进程、作者原效果、正常错误反馈、资源／路径／预算／生命周期安全校验；不做后台预编译、不增加 Release 常驻诊断、不默认提高 FPS、不降低图像质量、不引入第二缓存／资源总账／时钟／暂停真值。

保留判断按用户最新取舍：低复杂度、因果清楚、必要行为门与实际操作无回归、总体有正向收益的小修改可以保留，不机械要求每项都达到旧专项的某个百分比。安全和数据正确性是硬门；不可把稳定的非目标退步用其他指标平均抵消。正式稳定比例、尾部分布、功耗或全专项完成的声明仍需相应测量。噪声大时记录不确定性，修复测量条件，不抹掉已经证明的机制收益，也不把未测收益写成事实。

代码改动沿现 owner 完成：主 App 持有用户意图、持久化与共享媒体需求；播放进程持有桌面窗口／输入／执行；Scene 保持 authored → prepared Program/graph/resources → typed frame → Metal encode → 唯一 compositor。异步任务提交必须绑定原 request、generation、revision 与资源租约；晚到结果不得复活旧状态。项目默认 MainActor 隔离，`Task {}`、`nonisolated static` 或“后台队列存在”本身都不能证明耗时工作已离开主线程。

涉及持久化提交、跨进程协议、Activity 生命周期、显示时钟等变化时，实施前补齐所属现役设计的职责／数据流／失败／退出及 design gate；不能用本文的候选概述替代这些设计。局部数组复用、一次调用内值复用、等价算法顺序调整可按现合同直接做小修。

## 证据与这次采集到的数据

区分四类证据：**F** 为当前源码可证的触发／工作量；**H** 为历史冻结实验，注明输入与配置；**R** 为未来单一行为／真实操作验证；**P** 为未来可比较的优化产品性能结果。本轮新增 F 和官方依据，没有新增 R/P。下表的计算次数不是 profiler 测量值。

| 对象 | 本轮可证事实 | 解释边界 |
|---|---|---|
| 本机 | Apple M4、10 核（4P/6E）、16 GiB；macOS 27.0.1 `26A434`；Xcode 27.1 `27A9275` | 只读 `sysctl`、`sw_vers`、`xcodebuild -version`；不是 M1／8 GiB／最低系统验收 |
| 工程 | arm64；当前项目配置最低 macOS 26.0 | 发行实际嵌套二进制的架构、签名仍另验，不由配置推断 |
| Scene 启动 | layer、stage、PSO 三处最多 4 worker 固定 stride；总 stage 预算已有约束 | 可证明分工方式，不能证明 4 槽不足或每次发生长尾 |
| 管线缓存 | miss 后先完成 PSO，再同步 archive add／serialize／发布，最后返回 ready cache | 位于启动汇合路径；耗时和占比未知 |
| Web 输入 | 事件 monitor 加 30 Hz pointer 兜底；被动位置去重分属两条路径 | 名义轮询周期约 33 ms；不是实际 JS 投递量或能耗 |
| Web 频谱 | 常规 128 值在每 endpoint 各格式化一遍；约 30 Hz 投递 | 无背压时理论为 `3,840 × endpoint 数` 次格式化／秒；已有 latest-only 背压 |
| 共享封面 | 带 current artwork 的新 media generation 会提交 Web 转换尝试；成功产物最长边512 px、PNG≤1 MiB | 当前无 Web 消费者时仍会尝试；非法／超限／解码失败会拒绝，成本未测 |
| 网格探针 | Video／SIL 活跃网格每 2 s 查可见路径；已有 300 ms leeway | 每个活跃实例名义 1,800 tick／小时，不代表 1,800 次全库扫描；切模块会退役旧网格 |
| 状态栏 | 每 2 s 在主队列采样并更新图标，菜单关闭也执行 | 是否形成可见工作、CPU 占比与功耗尚未量化 |
| Video 索引 | 250 ms 合并后，主调用者仍等 SQLite 全表替换事务 | WAL、事务、连接复用已经具备；不是“尚未后台队列化” |
| 缓存／预算 | Scene 总账 `min(recommended/4, 3 GiB)`；decoded 同受总账约束；上传未提交 CB 上限 32 | 不能把 decode、pool 各名义上限相加，也不能删 GPU 完成等待 |

源码核对覆盖 App、Scene、Web、Video、共享播放、UI 与存储；扫描文件数不是覆盖率或性能结果。工作区存在并行 StaticModel／Puppet／shader 变更：涉及 `SceneMetalRenderer*`、`SceneMetalView*` 及其新文件的观察不得归入本轮成果；实际实验先冻结 owned 输入或等职责交接。

已核对[准备链收敛归档](../history/cross-topic/playback-preparation-convergence-2026-10-19.md)、[Scene 性能卡](../scene/roadmap/performance-convergence-card.md)及明确相关历史。旧链接产物复用五对冷启动中位 `4869→4331 ms` 仅属原优化诊断配置；暖启动无确定收益。上一批合作取消缩短过期工作的占用，函数内 memo 减重复投影，均不能外推本轮新提速。

## Apple 官方指导如何落实

下列来源于公开正文／WWDC，访问日期 2026-10-19；短摘要只作本项目决策依据，不照搬平台不同的样例。

| 编号 | 官方来源 | 对本项目的约束／启发 |
|---|---|---|
| A1 | [Apple silicon 调优](https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon/)；[大小核调度](https://developer.apple.com/news/?id=vk3m204o) | QoS 表达紧迫性；动态分配独立工作；不绑核、不把所有工作升到最高优先级 |
| A2 | [高效 CPU 调度](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently) | 先省重复工作、复用对象、事件驱动，再考虑线程；不自建无界线程池 |
| A3 | [减少启动耗时](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time) | 分开冷／暖、进程加载、首窗和内容真正可用；少显示一个 spinner 不算提速 |
| A4 | [提升响应](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) | 绘制／cell 配置不做同步 I/O；主线程只提交 UI 所需状态 |
| A5 | [减少磁盘写入](https://developer.apple.com/documentation/xcode/reducing-disk-writes) | 用 File Activity 找实际写入，合并重复提交；持久化原子性与退出落盘不能牺牲 |
| A6 | [减少 Timer](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)；[主动闲置／App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) | 需求消失就停工；保有明确兼容职责的兜底，不因 timer 存在就删 |
| A7 | [App Activity](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html)；[Process QoS](https://developer.apple.com/documentation/foundation/process/qualityofservice) | assertion 随实际工作配对；主 App 前台不证明 renderer／compiler 的调度合适 |
| A8 | [Metal 存储模式](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus)；[load/store](https://developer.apple.com/documentation/metal/setting-load-and-store-actions/) | 统一内存仍有带宽与同步成本；先证明后继不消费，再省写回 |
| A9 | [Apple GPU 优化](https://developer.apple.com/videos/play/wwdc2020/10632/) | 检查真实 pass 依赖、读写和寄存器压力；不全局改 half、不关闭 hazard tracking |
| A10 | [CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink) | 可用显示同步回调替代不合适的周期驱动；仍保唯一场景时钟和每屏生命周期 |
| A11 | [管线二进制归档](https://developer.apple.com/documentation/metal/metal-binary-archives)；[编译并发](https://developer.apple.com/documentation/metal/mtldevice/shouldmaximizeconcurrentcompilation) | 重用已编译结果；更多编译线程有 CPU／内存代价，不默认开启最大值 |
| A12 | [Metal 4 编译](https://developer.apple.com/documentation/metal/using-the-metal-4-compilation-api) | 可渐进采用；不为 API 新旧全面重写，不预编译未知作者内容 |
| A13 | [GPU working set](https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize) | recommended 值是性能相关近似，不是 App 独占 RAM 配额 |
| A14 | [Accelerate](https://developer.apple.com/accelerate/)；[vDSP stride](https://developer.apple.com/documentation/accelerate/controlling-vdsp-operations-with-stride) | 已有 FFT/vector 路径继续使用；先省分配与复制，不将小 FFT 搬到 GPU／Neural Engine |
| A15 | [降低内存使用](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use)；[图像内存讲解](https://developer.apple.com/videos/play/wwdc2018/416/) | 缩略图用 ImageIO 按显示用途下采样；不降低实际壁纸纹理／静帧精度 |
| A16 | [异步视频取图](https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset) | 有界派生任务可异步完成与取消；放宽取帧容差可能改变画面，须单独裁决 |
| A17 | [WKWebView 隔离](https://developer.apple.com/videos/play/wwdc2020/10188/)；[原生媒体暂停](https://developer.apple.com/documentation/webkit/wkwebview/setallmediaplaybacksuspended%28_%3Acompletionhandler%3A%29) | 网页内容本已独立进程；换宿主不是换渲染器，原生媒体暂停不能代替 JS／CSS 暂停 |
| A18 | [Swift 并发执行机制](https://developer.apple.com/videos/play/wwdc2021/10254/) | 不把阻塞等待塞入协作线程池；异步不等于取消／有界／离开 MainActor |
| A19 | [Metal 联合归因](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) | 同时看 CPU／GPU／display／thermal，先区别 CPU 等待与 GPU 饱和；外部 Instruments 不要求产品新增周期诊断 |

更底层的 [CPU Optimization Guide](https://developer.apple.com/documentation/apple-silicon/cpu-optimization-guide) 需要开发者登录与额外协议，未读取受限全文。公开文档足够指导当前高层优化，不假称已据芯片内部延迟表调优。

## 候选总览与阶段

P1 优先取得可行动证据；P2 在规模或实际消费出现时推进；P3 只保留取证／备选。优先级不是已确认缺陷等级。以下共 24 项，每项仍须先确认当前代码和原 consumer 没有变化。

| 阶段 | 候选 | 最小结果与退出 |
|---|---|---|
| 0：冻结与联合取证 | 启动 S1–S4；主线程 U1/U2；媒体 M1/M2 | 一次有身份的时间线和现有输入／输出基线，不先给全模块打补丁 |
| 1：启动优先、低复杂度伴随项 | 先 S1、S2，再按成本决定 S3；可穿插 M1/M2/W3/U6/U4 | 每次只改一个因果点；不把 UI 小修拖成引擎改造前置，不同时叠加 S1/S4 |
| 2：UI／存储与批量派生 | U1/U2/U3/U5/U7/U8/V1 | 持久化先补失败／退出门，保数据与外部文件变化；大库有实际成本再扩大 |
| 3：播放节奏与暂停／输入 | S5/W1/W2 | 原 owner 内完成状态设计，验证多屏／Space／恢复与下一次操作，再谈能耗 |
| 4：仅在新证据解锁后 | S4/S6/S7/S8/M3/W4 | 找不到实际 consumer／可省成本即停，不重跑旧 STOP 或扩缓存凑收益 |

没有硬编码“必须全改完”。每阶段完成最近门与真实操作后独立子代理审查；高风险项复审修订点。收益递减、两次有区分力实验不支持假设、或为微小收益必须增加明显复杂度时，保留证据并换方向。当前并行任务正在使用的帧／模型 owner 不抢改。

## Scene：8 项

### S1｜P1：有界 worker 动态领取独立启动任务

- **F／owner**：[PSO warmup](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Warmup.swift) 98–113 行固定四组 stride；[layer 准备](../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift) 373–399 行与 [stage 准备](../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift) 61–67 行相同模式，已有共享预算。
- **取证／最小改法**：先只测 PSO 分组任务起止、剩余独立工作和空槽重叠。成立后由原四个 worker 领取下一个 index，保去重、结果锁、排序、负缓存、取消；后续 layer/stage 扩展另核全局预算，不新增线程池或就绪波次状态机。依据 A1/A2。
- **反例／验收**：少于四项、单个超重 shader、共享 library、同 key 失败、取消在途、已有壁纸播放；T1 与真实冷暖启动，比较总首呈现、编译 CPU／峰值及旧输出尾部。
- **停止**：不存在分组长尾，或领取开销抵消收益。旧 ready-request 调度曾使两次冷启动 `23778→30811 ms`、`25524→32075 ms`，已撤；此项不得恢复旧方案，须有不同机制证据。

### S2｜P1：编译子进程与管道 reader 的任务优先级

- **F／owner**：[CompilerProcess](../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderCompilerProcess.swift) 61–91 行 Process 未显式 QoS，reader 为 utility；[启动任务](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift) 597–599 行为 userInitiated。不能据此认定 helper 在 E 核或发生反转。
- **取证／最小改法**：System Trace 看实际运行／可运行等待，再单独比较显式 userInitiated 的 helper 和必要 reader；不调 raw priority、不绑核，不提高常驻播放全部任务。依据 A1/A7。
- **反例／验收**：T2 的成功、拒绝、signal、timeout、诊断／驻留超限；旧壁纸同时播放与取消后无孤儿。比较 wall 与 CPU，不能以更高占用冒充优化。
- **停止**：无可归因调度等待或旧输出变差。10 ms semaphore 等待还执行资源保护；不得删除或拉长预算检查来省唤醒。工具链资格缓存的旧 STOP 不重开。

### S3｜P1：首次可用 PSO 与缓存落盘解耦的资格

- **F／owner**：[PassEncoder](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift) 624–630 行 make PSO 后同步 recordReadyOutcome；[archive](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPipelineBinaryArchive.swift) 106–125 行 add／serialize／移动／prune 后才返回 warmup。UI 未必阻塞，启动汇合仍会等。
- **取证／最小改法**：分开量 load、PSO、add、serialize 与发布。若确占关键链，在同 launch owner 内先登记可用 PSO，把有限缓存发布延到首呈现后；保持条目／字节上限、原 key、损坏回退与取消退出。没有显著等待就不引入队列。依据 A3/A5/A11。
- **反例／验收**：T1 补发布失败／退出／取消；下一次暖命中、损坏自动重建、同源并发发布和无临时文件泄漏。落盘失败只损下次命中，不能影响当前画面；延后工作不得重新编译作者内容或在主线程 drain。
- **停止**：写出不在关键链，或短收益需要长期后台状态／显著 archive 峰值。当前没有此项 A/B，不能承诺固定提速。

### S4｜P2：Metal 内部编译并发与外部四槽的叠加

- **F／owner**：当前未设置 `shouldMaximizeConcurrentCompilation`；[MSL library single-flight](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift) 674–721 行已经缓存完整 MSL 成功／失败并等待同源结果。
- **取证／最小改法**：先确认 Metal 编译占比；仅在隔离候选进程比较默认与开启，记录 `maximumConcurrentCompilationTaskCount`、RSS、CPU、首呈现及旧输出。一次只变 Metal 选项，不提高外层 worker 数；不在共享 active device 上临时来回切设置。依据 A11/A12。
- **反例／验收**：T1，冷暖缓存与重材质／轻场景。不得再加 library cache 或引入全量 Metal 4 迁移。
- **停止**：编译占比低、争核／内存更重、只有局部 compile 更快但用户等待无改善。

### S5｜P2：显示同步帧驱动

- **F／owner**：[FrameDriver](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift) 13–19、121–132 行为 30/60 FPS 单次 Timer，busy 间隔为目标周期的 1/8。该事实不证明当前抖动。
- **取证／最小改法**：先联合看 callback、busy、drawable wait、GPU 与 actual present。需要时在原 Session 接入 CAMetalDisplayLink 的一次共享 admission，保持唯一 sceneClock／VM／粒子推进，各屏消费同状态。依据 A10/A19；先修订原 frame-admission 设计。
- **反例／验收**：T3；30/60 FPS、60/120 Hz、不同刷新率多屏、拔屏、Space、sleep/wake、暂停首帧有限重试、缺 drawable 恢复、history 单帧在途。检查结束后下一次启动无残回调。
- **停止**：现节奏已足够，或新显示 leader／多屏协调状态成本超过收益。不能按每屏回调重复推进世界时钟，也不能放松 GPU 完成与历史门。

### S6｜P3：只有真实热点成立才省帧内投影／短命容器

- **F／owner**：[FrameDriver](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift) 207、261–280 行构造／合并帧表；[纹理组装](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFrameLayerTextureAssembly.swift) 13 行起叠加动态来源。部分粒子 parent 表已有 consumer 需求门，不能重复做。
- **取证／最小改法**：先定位当前普通优化配置中的分配 caller／CPU 占比。仅由 prepared demand 证明没有消费者时跳过投影，或做同调用内复用；依据 A2/A18，不建立跨帧 publication cache。
- **反例／验收**：T3/T4 与动态资源、属性、JS 引用 identity、事务失败回滚；实际 renderer 消费必须被触达。每帧表数量不能代替整进程成本。
- **停止**：只有旧累计分配数字或需要改变值 identity／回滚基线；overlay 容器、旧材质帧载荷等 STOP 未取得新资格不重开。此处只是取证任务。

### S7｜P3：末次 depth 写回是否确无消费者

- **F／owner**：[MainPassEncoder](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneMainPassEncoder.swift) 106–115 行 color/depth store，后续重开会 load；模型帧路径当前由并行任务修改，暂不实施。
- **取证／最小改法**：从实际命令与资源依赖证明“末次 depth 无后继读取”，再筛末 encoder 的 dontCare；先不改变 allocator／storage mode。依据 A8/A9。
- **反例／验收**：T4；offscreen 插入、主目标重开、背景 capture、模型／图像共深度域、shadow、下一帧 history。Color 中间结果和需要后续 load 的 depth 必须保留。
- **停止**：没有真实 liveness 证明或是旧“空 main pass”观察。空重开旧筛未命中真实无 draw consumer；不能全局改 memoryless／store 或重排作者 pass。

### S8｜P2 取证：切换后的内存持有者与统一预算

- **F／H／owner**：[总账](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift) 10–35 行约束 GPU 与 decoded；[目标池预算](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureResidentBudgetPolicy.swift) 16 行起另限 pool。历史轻重切换返回轻场景 footprint 上移约 25.4/47.9 MB，但 GPU allocated 恒约 94.3 MB，不能直接认定泄漏。
- **取证／最小改法**：依据 A13/A19，先定位 allocation／retain caller，区分在途 pin、有效 cache、allocator 驻留、compressor 和真实遗留 owner。只修已定位持有者，复用原总账和 memory-pressure 路径。
- **反例／验收**：T4；退出 drain、pin 归零、cache 平台、内存压力、失败准备和多次轻重切换，保有效暖启动收益。三引擎交接期间两个进程的峰值要一起观察。
- **停止**：无 caller 证据；不重复整轮无归因切换，不清空所有 cache、不调大安全预算、不把 recommended 工作集当独占 RAM。

## 共享媒体、Web、Video：8 项

### M1｜P1：FFT 工作缓冲复用

- **F／owner**：[统一频谱分析器](../../MyWallpaperX/Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift) 79 行复用 FFT setup，但 216–217 行每次分配 real／imaginary，输入窗也有临时准备。
- **最小改法／依据**：先用 allocation 计数及既有音频输入确认成本，在同分析器复用串行工作缓冲，仅尺寸变化时调整；不改变窗函数、频带、包络、输出数组所有权。A2/A14；不搬 GPU，不额外启动采集。
- **反例／验收**：T5；左右不对称、换采样率／窗尺寸、静音、停止重启，连续帧不能残留前帧数据；真实音乐对照 Video/Web/Scene 柱形与环形，作者样式不变。
- **停止**：缓冲共享引入竞态或保有内存明显抵消收益。局部少分配不称整体能耗完成。

### M2｜P1：按 Web 消费需求生成歌曲封面

- **F／owner**：[SystemMediaService](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaService.swift) 390–405 行在新 media generation 且 current artwork 非空时提交 Web 转换尝试；当前订阅仅 needsMedia，Scene-only 也会尝试。[WebArtwork](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaWebArtwork.swift) 已有解码／合法性和512 px／1 MiB限制。
- **最小改法／依据**：原 subscription 区分是否需要 Web artwork；首个 Web 消费者晚到时对当前原图按需生成一次，无 Web 时省转换和额外 revision。只变 Web artwork 需求不调用 `reloadSource()`，不推进媒体 epoch／重启或清空 Scene 会话；转换回包另核当前 Web 需求租约／revision。仍由同一 artwork owner，Scene 原图／调色板保留；A2/A15。
- **反例／验收**：T6 补 converter 计数，Scene-only 零 Web 转换；Web 晚订阅出当前封面；最后 Web 退出拒绝在途回包，重订阅不接收旧需求结果；换曲 A→B→A、清空、坏图、授权拒绝／恢复。Scene 持续订阅时 Web 加入／退出不得增加 source start/stop 或清空 Scene snapshot。真实 Music 与系统来源均验。
- **停止**：要新增长期缓存或第二媒体采集者。若跨进程需求类型变化，先补原媒体协议的兼容／清空设计。

### W1｜P2：Web 被动鼠标位置共享去重

- **F／owner**：[Monitors](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwardingMonitors.swift) 22 行起同时用事件和 30 Hz 轮询；[Forwarding](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift) 12 行起两套位置／throttle 状态；轮询先做原生 hit test。
- **取证／最小改法**：计同一 surface 的原生采样和 JS 被动位置投递，先共享已投递位置，减少重复 JS；保按下／拖动／抬起、hover preheat 和兜底。依据 A6；首批不删／降 30 Hz。
- **反例／验收**：现测试缺原生两路径行为门，需补事件 harness，再真实验 Finder、覆盖窗口移动、外部拖入、多屏、Space、monitor 恢复。指针静止但窗口移到其下时仍必须清 hover；不能把坐标去重简单移到 hit test 前。
- **停止**：无法保持命中与手势安全或没有重复投递；不能用“少轮询”替代完整输入语义。

### W2｜P2：稳定暂停时的 Activity token 生命周期

- **F／owner**：[Lifecycle](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift) 11–16、42 行持 userInitiated Activity，pause 243–246 行未释放；停止／surface teardown 才结束。
- **最小改法／依据**：先限定已完成准备、明确暂停且媒体门完成的状态，按既有生命周期配对释放／恢复前重获；保候选装载与激活期。A6/A7，不把“主窗口隐藏”视为壁纸没有需求，outputActivityAllowed=false 不自动等于 JS 已停。
- **反例／验收**：T7/T14，加真实 host token 状态门；暂停中导航、WebContent 重启、恢复连选、激活失败回滚、锁屏／Space；比较暂停 wakes、App Nap 与恢复首呈现。
- **停止**：恢复迟滞或可见输出／媒体退步；不全局禁用或强制启用 App Nap。

### W3｜P2：一次频谱推送只格式化一次共同数值

- **F／owner**：[FrameReply](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift) 118–140 行每 endpoint 对同一 128Float 重复格式化，已有每 endpoint 一个在飞和一个 latest pending。
- **最小改法／依据**：命令内惰性生成共同 immutable 数值 body，endpoint 保各自序号／定向包装；全忙时不提前格式化。只做短命值复用，A2，不改精度、不跨帧缓存。
- **反例／验收**：T7 加真实 FrameReply 多 frame／slow endpoint 数值、序号、清零屏障、导航拒收门；不能只发给 audio listener，因为还有公开 `wallpaper-audio-spectrum` 事件消费者。真实音乐长播和 iframe 内容均验。
- **停止**：单 endpoint 纯增成本或没有实际多消费场景；不宣称修复未知长播停顿。

### M3｜P3：歌曲 helper 等待循环的空唤醒

- **F／owner**：[SystemMediaSource](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSource.swift) 272 行起 poll 最多 1 s 返回一次，心跳 deadline 12 s；helper 常规约 2 s 一条。取消已有 terminate／0.5 s KILL 与 pipe EOF。
- **取证／最小改法**：先验证 EOF／取消可靠唤醒且确有空 poll，再用剩余心跳 deadline 等待；不弱化心跳／ACK／预算，不加第二 timer。依据 A6。
- **反例／验收**：T6 的 source 门，补 TERM 忽略、继承管道未关、部分帧、EINTR、cancel-launch 竞态；退出墙钟不得退步。
- **停止**：任何退出边界需复杂补偿或收益不可归因。它不是引擎启动／FPS 优化，不顺带改 Music PID 查询节奏。

### V1｜P2：视频派生图像的有界异步完成与取消

- **F／owner**：[CachePipeline](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+CachePipeline.swift) 205 行在并发 utility 队列等二槽 semaphore，263–273 行异步取图后同步 wait；已有缓存、同路径合并与 generation。
- **最小改法／依据**：原派生 owner 维持二槽 admission，用 completion／异步取图释放等待线程，并取消不再需要的 generator；保候选时间、400 px 缩略图、4096 px 静帧和 cache key。A16/A18；不放宽静帧零容差、不降精度。
- **反例／验收**：现门缺该 helper 的行为覆盖，补可控 generator 的完成一次／取消／坏媒体／后备时间；删除重导入同路径不得写旧 cache，系统静态壁纸提交身份保持。隔离少量／批量导入比线程、完成时间和取消后写入。
- **停止**：需新建常驻 pipeline/cache 或正常小批量成本退步；不能声称改善稳态 Video FPS。

### W4｜P3 仅测量：已有空预热的净收益

- **F／owner**：[WebDaemonHostAdapter](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift) 151、213 行已有一个空 prepared process、30 s TTL，84–88 行 memory pressure 退出；没有 WebView／媒体需求／作者编译。
- **任务／依据**：记录真实切换节奏中的预热命中、空进程保有时间／内存与冷切换等待，评价现策略净收益；A3/A6。只在已有策略内调参需要另有对照，不默认延长 TTL 或重复补热。
- **反例／验收**：T14 加 TTL 精确边界、hello 前后接管、取消和压力退出；保下一次请求的 UUID 与进程退出闭环。
- **停止**：无新使用数据，维持现状。“加 TTL／压力回收”已实现，不能再作为新优化。

## UI、列表与存储：8 项

### U1｜P1：Video 索引事务不再让主线程同步等待

- **F／owner**：[Persistence](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift) 22–41 行合并 250 ms 后仍在 main 调 save；206–214 行同步 store／失败回退；[IndexStore](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperIndexStore.swift) 113–128 行 queue.sync 全表 DELETE／INSERT 事务。
- **最小改法／依据**：MainActor 捕获值快照，交原 store 串行队列有序提交；失败回原 fallback，保存 revision 防旧失败覆盖新成功。首批不改增量 SQL、不换数据库。A4/A5；先补持久化提交／退出设计。
- **反例／验收**：T10 只是相邻门，必须新增真实 SQLite harness：A→B、A 迟到失败、reset 排序、不可写 DB、立即退出后重启。真实退出／reset入口使用 `WallpaperManager.flushPersistentState()`（Persistence 460–474行），其有序 flush 不能靠 fire-and-forget 替代。
- **规模／停止**：隔离 1k/10k 值索引看 main 等待、事务写量和交互；若小库成本可忽略，不扩到整套增量存储。数据丢失／旧回包复活是硬失败。

### U2｜P1：SIL 首次装载和保存都沿唯一快照 owner

- **F／owner**：[DetailHost](../../MyWallpaperX/Shell/AppKitDetailHostViewController.swift) 23–26、89 行初始化即访问 SILService；[SILService](../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift) 117–160 行同步 JSON／旧图片 metadata，177–191 行全路径 stat 和缺失后保存。后台补尺寸 save 闭包仍读 live wallpapers。
- **最小改法／依据**：现 JSON 格式不变，后台读取／补 metadata／检查后回 MainActor 以 load generation 加库状态 revision 提交，导入／删除／reset 均改变后者，晚到装载不得覆盖新修改；保存捕获 immutable 快照，由单个串行 writer 合并，reset／退出 flush 进入同一有序提交边界。先消除非图片首窗的同步 I/O；只延迟 singleton 订阅不足以解决首次打开图片库。A3/A4/A5。
- **反例／验收**：T10 外补真实装载／writer 门；旧缺尺寸库、装载中导入／删除／reset、慢卷／离线卷、保存失败／退出。异步不能把暂不可达文件错误视为用户删除；保原缺失提示与合法恢复语义，任何改变须明确设计。
- **规模／停止**：齐全／旧格式各 1k/10k 元数据，媒体用自有小 fixture／隔离副本；分别量首窗和首次进图片库。无实际等待时不迁移数据库或引入新缓存。

### U3｜P2：可见路径探针停启与 SIL single-flight

- **F／owner**：[Video grid](../../MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridView.swift) 885 行、[SIL grid](../../MyWallpaperX/Modules/StaticImageLibrary/UI/SILGridContainerView.swift) 444 行每 2 s 后台查可见项；Video 已有在飞门，SIL 缺。未见按窗口可见性停表，旧 controller 离场则释放。
- **最小改法／依据**：SIL 补同 owner 在飞和完成身份复核；真正离窗／最小化时停现 timer，重新可见即时探测。全遮挡是否停先验证通知可靠性，不把桌面 renderer 也一并停掉。A6；不新建全库 watcher。
- **反例／验收**：T11 目前偏 Video，补 SIL、在飞离窗再回、同 ID 换路径、排序、外部删除／恢复。正常／慢卷观察 10 min 可见与最小化的批次数及叠加。
- **停止**：恢复反馈退步或只能靠新全局观察平台实现；2 s 是活跃检测周期，不能直接设长周期掩盖问题。

### U4｜P2：状态栏先省相同图标，再测采样体

- **F／owner**：[StatusBarController](../../MyWallpaperX/App/StatusBarController.swift) 56 行每 2 s 主队列 refresh／update；75–97 行同百分比仍新建图标；[SystemMonitor](../../MyWallpaperX/Core/System/SystemMonitor.swift) 66 行起采 CPU／VM／网卡／GPU registry。SMC 温度已不在高频路径。
- **最小改法／依据**：先按已显示百分比及外观状态省重复绘制；采样本体若有成本，再由原唯一串行采样 owner 离主采集、主线程发布。菜单打开仍完整更新；A2/A4/A6。
- **反例／验收**：需轻量采样／图标投影门；nil GPU、暗亮模式、网络差分首样、菜单打开的即时新鲜度、并发重入。固定播放 30 min 观察采样 CPU／wakeups／重绘次数。
- **停止**：只减少代码调用却没有实际绘制／开销，或后台采样引入差分竞态。先不做第二套“菜单／图标”监控器。

### U5｜P2：Online cell 只消费下载状态，不同步探盘

- **F／owner**：[OLBrowserGrid](../../MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLBrowserGridView.swift) 246、267–272 行 cell 配置／刷新调用 isItemDownloaded，对未知 ID fileExists，命中还会发布集合变化。已有进度 throttle 与定向刷新。
- **最小改法／依据**：cell 消费服务现有 downloadedIDs；初次／页面进入／显式刷新，以及视口中新出现的未知ID，都由原服务合并后台校准，同一视口不反复探盘、不增加常驻watcher。提交绑定 generation 和下载集合本地修改 revision，扫描期间下载／删除事件须合并或重扫，旧集合不得覆盖新修改；真实点击播放仍最终核文件。A4，不能因缓存优化删存在性校验。
- **反例／验收**：T10 相邻门外补目录校准；页面保持打开，外部添加／删除后滚入、滚出再滚回；扫描A在飞时下载B完成，A不得移除B；另验搜索换代和旧点击。滚动未下载卡片时 main File Activity 不再反复 stat。
- **停止**：目录很小且成本无贡献，不增加持续 watcher；不让外部文件永远无法被发现。

### U6｜P2／极小：SIL 标签键盘导航先筛选再排序

- **F／owner**：[SILService](../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift) 410 行方向键先 sortedWallpapers 再筛 tag；329 行已有 `sortedWallpapers(forSILTag:)`，网格已用。N 大、标签 K 小时做 N log N 而非 K log K。
- **最小改法／依据**：复用已有标签投影，不添缓存／导航 owner；A2。先验证 comparator 对并列项稳定，过滤与排序可交换的条件成立，再改一处调用。
- **反例／验收**：T10 加真实方向键输出，tag／search、同名／同排序值、首尾、跨列、无选中。不要顺手改删除后邻选的 `resolveNextSelectionID`。
- **停止**：排序不稳定导致相对顺序不同；先修或限定等价性，不能仅据复杂度公式认领 App 提速。

### U7｜P2：Steam 详情缓存 I/O 与呈现隔离

- **F／owner**：[DetailPresentation](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+ItemDetailPresentation.swift) 46 行冷详情读 cache；[DownloadSelection](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadSelection.swift) 177 行读 metadata/cache；[LibraryRecords](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift) 162 行同步 Data／JSON；网络完成后也同步保存。
- **最小改法／依据**：复用单一 cache，内存已知详情先显示，后台读写以 item／消费方／generation 提交；TTL、过期后台补全、离线展示、作者来源沿原常量和合同，不在此重设。A4/A5；nonisolated static 不等于异步。
- **反例／验收**：T12 的隔离 HOME 门补 A→B→A、关闭、下载／浏览详情互换、坏缓存／过期／网络失败保旧值；快速开 100 项时区分磁盘读与网络等待。
- **停止**：小 JSON 本已很快，或要增加第二长期缓存。已经修好的 stale 展示／作者返回不能回退为前台 loading。

### U8｜P3：Steam 下载列表一次提交只派生一次

- **F／owner**：[Service](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift) 548 行合成 failed intents，随后 [DownloadFiltering](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadFiltering.swift) 12 行再次合成；didSet 有一次重入，displayed 数组相等未抑制发布。progress 已独立，失败历史最多 100。
- **最小改法／依据**：同 owner 内“已合成记录 → 筛选排序”私有阶段复用，最终相等不发布；必要时只合并同一 main turn 的派生。A2/A4，不延迟 downloads 删除意图本身，Web store 清理依赖它。
- **反例／验收**：T13；账号切换、失败重试、ready 不被旧失败覆盖、清历史、过滤／排序／搜索和选择消失。1k/10k 自有记录观察合成／排序次数与可见响应。
- **停止**：正常规模成本很低或抑制发布吞掉实际状态；不建持久索引，也不声称每个进度 tick 都全量排序。

## 已完成、停止或不建议的方向

以下不是 24 项待实施任务。重开须先有新的实际 consumer／成本证据，并引用原停止原因；不能把上下文遗失当新发现。

| 方向 | 当前事实／原结论 | 后续边界 |
|---|---|---|
| 共享上传 queue／批量 mipmap 与 BC conversion | 已按设备复用；批提交／32 未提交上限／完成失败 identity 已具备 | 不删完成 wait；新瓶颈需具体 conversion／提交证据 |
| 全部静态 TEX shared→private | [旧筛](../scene/history/static-tex-storage-screen-2026-10-15.md)相同 3427×897／5 mip：预算峰 18,711,040→37,422,080 B，额外 copy 中位约236/411 µs，STOP | 统一内存不等于 private 总更快；不得重跑同输入挑好结果 |
| shader／模型／descriptor 扩缓存 | 资格缓存、MDL重复验证、长期 descriptor、panel DTO 等已有停止／撤回；P4 成功投影函数内复用已保留 | 不加新 cache owner、永久可信 token、额外完整资源见证 |
| IPC 背压／主界面逐帧驱动 | DaemonCommandBuffer 已 latest-only、控制屏障；接收量／单次 drain 有界，音频后台直投 | 没有传输瓶颈不改 XPC／合并 daemon；ProcessType 不机械套 AppKit renderer |
| Video 硬件路径／Scene 视频纹理桥 | AVPlayerLayer／AVQueuePlayer，Scene AVPlayerItemVideoOutput＋CVMetalTextureCache 已具备 | 不称全部 codec 必然硬解，不默认改像素格式或自行造 decoder |
| 缩略图／GIF／diffable | ImageIO 最长边800、GIF静态候选最多8帧、动画激活租约、预算、同ID跳过结构snapshot与串行apply已具备 | 实际大量GIF峰值／scale问题出现再局部查，不重写全缓存／snapshot framework |
| 系统暂停与 Web shadow CSS 兜底 | 系统事件／idle deadline 已有；shadow animationstart 不冒泡，暂停期1 s扫描是[既有设计](../web/css-animation-freeze-redesign.md)取舍 | 没有等价覆盖不删；native media gate 不代替作者CSS／JS暂停 |
| fetchall 目录监听 | 事件＋10 s恢复兜底、0.5 s trailing debounce、后台枚举与revision拒收已具备 | 缺失目录恢复仍需要；不直接删补偿timer |
| 降精度／全局重排／新后端 | half、memoryless、untracked hazard、Metal4、tile shader都有适用条件 | 不改作者数学／排序／格式／阴影范围来换性能；不引入另一renderer或语言所有权 |
| 后台预编译／长期预热／Release探针 | 用户明确不采用后台预编译，Release开发入口已剥离；空Web预热有限寿命 | 研究工具只放隔离开发链，不能重新塞周期采样／selftest进发行版 |

## 如何做可比较的测量

### 冻结输入与避免并行污染

1. 每批从 Git 状态列出 owned 文件，基于确切提交＋owned 导出固定构建输入，排除并行改动；记录 App／主 binary／helper／优化配置／签名、样本与属性、窗口尺寸、目标 FPS、显示器、音频来源、系统状态及缓存目录。
2. 构建与性能运行串行使用仓库现有锁；锁只能约束合作方，无法排除另一个会话手动跑样本。观察同时活跃的 renderer／编译任务、热状态与时间段，污染窗口单列，不混入配对结果、不改并行任务的 App／媒体／进程。
3. 区分主 App 冷启动、renderer 冷进程、项目／编译缓存冷、OS文件页缓存冷热、已有daemon接管。只清本任务指定缓存；不清用户真实缓存、不执行系统 purge，不把“删除一份shader cache”称整机冷启动。
4. 主指标是点击／原请求发出到目标实际可见且原输出交接完成。Scene presented 与 Web/Video 可见确认的证据等级不同，分别报告；hello／ready／主窗口出现不是同一个终点。属性准备另记请求到可操作控件，不与播放首帧混算。
5. profiler／详细截图／Debug 诊断另开资格窗口；普通优化产品的性能窗口不混进去。系统 CPU 时间先核单位，GPU allocated 与进程footprint分别报；局部阶段不能相加成总耗时，均值不能冒充分位数。

### 短筛、保留与正式声明

- 第一轮用受控输入／行为门、一次联合归因和少量交替 A/B 排除明显无效方向。证据应能说明“确省了哪份工作”，不是只看一段wall数字。
- 低复杂度局部修改：需要原输出／失败反例等价，真实操作通过，主要成本没有稳定负面变化；省调用／分配可如实标局部机制收益。噪声导致整体提速比例未知时保留未知，不为凑10%撤回可靠小改，也不直接认领稳定提速。
- 声称整体稳定收益：使用原专项相称的正式窗口。稳态通常每轮30 s预热＋至少60 s计量，至少3份有效基线与3份候选；启动冷／暖各至少5次交替比较，不用5个点声称p95/p99。必要的30 min稳态／20次轻重切换只在高风险生命周期或阶段收尾执行，不能每个小修重跑全矩阵。
- 任何功能／安全／用户数据回归先修；增加的排队、内存保有、状态数、冷失效成本与维护面必须列账。只有全面量化达到现役性能卡要求时才标正式专项验收，局部保留不是篡改原始门或完成全引擎优化。

### 最近行为门与明确缺口

所有以下模块文件已在本轮确认存在；列出入口不表示已执行或已有足够行为覆盖。实施前读断言和真实输入。统一运行形式：`python3.12 -B script/run_scene_tests.py --module <模块> -j 1`；只选本次涉及模块，不把整表当每批必跑。

| 门 | 可复用模块／仍需补的覆盖 |
|---|---|
| T1 PSO | `test_scene_resolved_material_pass_encoder`：去重、共享library、负缓存、archive；S3补退出／发布取消 |
| T2 compiler | `test_scene_generic_shader_compiler_process`：正常、signal、timeout、诊断／驻留限额 |
| T3 frame | `test_scene_paused_frame_recovery`、`test_scene_surface_evaluation_transaction`、`test_scene_frame_context`、`test_scene_cursor_surface_routing`；S5仍需真实多屏时序 |
| T4 resources | `test_scene_resource_budget`、`test_scene_tex_cache_budget`、`test_scene_geometry_auxiliary_lifetime`、`test_scene_directional_shadow_frame_owner`、`test_scene_frame_texture_registry`、`test_scene_particle_runtime`；S7/S8必须新consumer／allocation证据 |
| T5 audio | `test_system_audio_spectrum`、`test_audio_spectrum_response`、`test_system_audio_spectrum_recovery`；补连续帧缓冲复用与尺寸切换 |
| T6 media | `test_scene_system_media_provider`、`test_web_system_media`、`test_scene_system_media_ipc`、`test_scene_system_media_source`；补Web封面需求／晚订阅与转换计数 |
| T7 Web | `test_web_playback_pause`、`test_web_compat_parity`、`test_playback_switch_endpoints`；未覆盖token原生生命周期、全部频谱endpoint背压，须补真实owner门 |
| T10 UI算法 | `test_ui_library_algorithms`、`test_ui_projection_efficiency`、`test_library_toolbar_behaviors`；不证明SQLite/SIL持久化、目录校准、视频generator正确，须各补行为harness |
| T11探针 | `test_ui_visible_path_probe`、`test_ui_projection_efficiency`；现探针重点为Video，补SIL／窗口停启 |
| T12详情 | `test_steam_detail_navigation`、`test_steam_detail_layout`；保隔离HOME和实际cache消费者 |
| T13下载 | `test_steam_download_history`、`test_steam_download_sorting`、`test_steam_library_interactions`、`test_steam_grid_updates` |
| T14进程 | `test_daemon_process_transport`、`test_playback_process_isolation`、`test_daemon_process_lifetime`；预热TTL精确边界仍需补 |

Swift产品变更做Debug build；时钟／GPU／VM／IPC／持久化与可见变化做隔离代表运行，最终Release实际产物核无新增开发入口／周期诊断、签名及arm64。Debug内部runner只证明其路径，不能直接当普通Release性能或线上Steam验收。

### 实际工具入口

复用现有工具，不新增 benchmark 框架或常驻监控；以下参数已通过本轮 `--help` 核实。执行时先核当前版本，隔离目录由任务自行建立。命令是后续模板，本轮未运行它们；不得给真实媒体目录作为可写runtime root。

```bash
# 构建和触达门先预览；owned参数逐个声明，不卷入并行变化。
python3.12 -B script/verify_scene_change.py --phase checkpoint --base HEAD --owned-path <本批真实文件>

# 代表Scene的Debug资格运行；app参数是已签名的可执行文件。
python3.12 -B script/scene_wallpaper_benchmark.py --app <隔离Debug可执行文件> --sample-root <隔离样本根> --sample-id <代表ID> --output-dir <本轮输出> --no-execution-observations --performance-fps 30 --performance-warmup 30 --duration 61

# Web行为运行；不使用--kill-existing干扰并行实例。
python3.12 -B script/web_wallpaper_benchmark.py --app <隔离Debug可执行文件> --workshop-root <隔离发现根> --runtime-workshop-root <隔离运行根> --runtime-home <隔离HOME> --ids <代表ID> --duration 60 --output-dir <本轮输出>

# 跨引擎隔离/交接行为；仍不是Release速度测量。
python3.12 -B script/playback_process_isolation_benchmark.py --app <隔离Debug可执行文件> --runtime-home <隔离HOME> --scene-root <隔离Scene副本> --output-dir <本轮输出>
```

普通优化产品通过外部 Instruments 的 App Launch／Time Profiler／Thread State／File Activity／Allocations／Metal System Trace／Display 联合采样，先确认当前工具模板支持；不把iOS专属指标强套macOS，不要求Xcode Organizer线上聚合或新增埋点。实际Music验证固定同一片段／音量／输出设备／采集权限；合成正弦／静音只作可复现反例，不代真实音乐。画面截图与功耗窗口分开。

## 交付、记录与退役

每项开始时只在所属现役计划／合同记录当前owner、冻结身份、假设与最近门；完成后保存一份简短结果：改了什么、去掉的工作、实际数据与噪声、功能／失败反例、负面成本、保留／停止理由、未覆盖项及后继指针。失败或放弃的原数保留，不挑最好值；正文不不断追加campaign日志。

本轮文件范围仅本文、`docs/README.md` 的入口、`docs/document-role-index.json` 的唯一角色登记和必要的 `script/document_health_baseline.json` 精确预算。新文档预算是用户要求的跨模块执行方案，不复制既有架构／能力台账。共享JSON逐项增量合并，不覆盖并行条目；不修改产品、项目配置、测试断言基线或他人源文件。

后续各实现批次分别列 owned 文件、验证、独立审查、产物去留、Git状态；提交／推送需当时授权。本计划所有候选已作保留／停止／转入原专题的决定，或用户结束研究专项后，将过程归档，稳定合同回原owner，不留下第二条长期任务队列。
