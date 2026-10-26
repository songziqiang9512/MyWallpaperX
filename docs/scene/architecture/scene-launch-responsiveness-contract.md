# Scene 启动响应与按需诊断合同

<!-- document-role: stable-contract -->

> 状态：现役稳定合同
>
> 校验与重复工作精简的实施、取舍和验证状态查[精简方案](../../development/validation-simplification-plan.md)；能力覆盖、性能数字与运行证据查[能力台账](../capabilities/coverage-ledger.md)和[运行证据索引](../capabilities/runtime-evidence-current.md)。
>
> 本文服从[兼容运行时架构](runtime-architecture.md)，不拥有任务顺序。上一轮冷暖启动专项的实施与 STOP 留在[完成记录](../../history/cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md)，不代表本轮精简已完成；自主兼容选题仍由[兼容路线](../roadmap/scene-compatibility-roadmap.md)决定。

## 1. 目标与边界

Scene 详情和壁纸切换必须满足两个独立目标：

1. 打开详情只展示廉价、已有的项目元数据，不隐式触发 package 校验、解包、资源遍历、scene 解析、shader preparation、纹理解码或 GPU pipeline 创建；
2. 设置壁纸立即接受用户意图并保持主界面响应。候选内容在后台准备，当前壁纸在候选可提交前保持可见；不可避免的长准备必须有真实阶段、可取消状态和失败反馈。

本合同不建立第二 renderer、resource registry、property tree、frame clock、graph、history、compositor 或最终输出 owner。`SceneDesktopWallpaperHost` 持有 Scene 执行端候选与表面提升事实；产品意图与跨引擎提交仍归 WallpaperManager 的[唯一切换事务](../../architecture/playback-lifecycle-transaction-design.md)，不能由 Host 另作产品决定。

MirageWallpaper 只提供 `candidate / active / standby`、request generation、首帧后提交和失败回滚的 clean-room 职责/时序对照。不得复制其 GPL 源码、shader、常量、payload、算法表达、独立 C++/Vulkan renderer 或按显示器启动进程的产品结构，也不得把第三方静态结构当作性能或官方语义证据。

## 2. 目标合同、当前事实与偏差债务

每个实施批次都必须分别记录：

- **目标合同**：本文与兼容运行时架构规定的按需诊断、异步准备、单一输出 owner、候选提交和失败回滚；
- **当前事实**：只由当前源码、能力台账和可复现运行证据说明同步工作发生在哪里、各阶段真实耗时和当前可见结果；
- **偏差债务**：首个错误 owner、同步边界、重复工作、当前 fallback、纠正门和旧路径退役条件。

静态审查可以证明同步 I/O、编译或资源创建位于 UI 调用链上，但不能单独给出耗时占比。性能优化前后必须在同一硬件、系统、构建、显示器拓扑和代表内容上重新采集 cold/warm 数据。

## 3. 详情与诊断合同

### 3.0 发布构建的诊断边界

正式 Release 从编译输入、实现与 IPC 入口排除开发观测链：启动/逐帧计时、带锁性能计数、signpost、GPU census/完成日志、周期资源统计、诊断 IPC、Web 事件缓存/通知及脚本日志桥均由 `DEBUG` 编译条件隔离。Steam helper 的 `Probe/` 与 `*SelfTest.cs` 不参与 Release 编译，`probe`／`selftest` 和 Web `inspect`／诊断事件只在 Debug 提供；Scene／Web 详情隐藏诊断面板及其专属样本报告、完整 Web 依赖诊断扫描与报告缓存已退役；普通 Web 发布播放不开放 Web Inspector。Scene 的资源引用与能力缺口汇总、effect 报告和 descriptor 诊断投影也只在 Debug 构造，真实资源解析与编译准入继续执行。产品 Web 启动准入只检查入口与依赖可用事实，不调用样本诊断；runtime profile 仍由产品 descriptor 风险事实决定。Scene 属性准备由现有独立 owner 处理，不再持有详情诊断 consumer。声音 timeControlStatus 的纯日志 KVO、未知文本脚本的 SHA/报告只在 Debug 生成和注册；实际播放器状态、回退及用户可见错误不依赖它们。Video helper 的 launched/accepted 事件及父端仅供调试的请求镜像也只在 Debug；实际 prepared/ready/failed/cancelled、活动状态 ACK 和物理退出继续沿原身份链。共享音频 buffer 配置后的纯日志 actualFrames 读回、系统媒体 report 的状态存储/调用/字符串插值也只在 Debug 存在；实际 CoreAudio 范围/设置、媒体授权/来源/发布及清空继续由原 owner 执行。粒子 Simulator/Runtime 的纯运行报告及快照字段、成功 marker 和 child census 也只在 Debug 生成；Definition/graph 的真实执行判定、容量、事件、随机、worldspace 与 rope history 不依赖运行报告，继续留在原 owner。着色器归一化源码与编译后 MSL 的证据目录解析和写盘也仅在 Debug 构建；默认 App 的固定编译工具沿原 Bundle owner 首次解析并严格核签名，后续复用同一结果；不为每个 shader 启动 `--version` 子进程，实际编译保退出码、超时、内存和输出/ABI 边界。Debug 保留现有显式证据入口，helper 随 App 的构建配置发布；不能用运行时开关冒充 Release 编译隔离，也不能在空日志调用前计算 payload 或注册 observer/timer。发布验收核对实际无 `DEBUG` 的构建、主 App／Video helper 符号、Steam 程序集类型与成员、开发命令拒绝及普通播放运行，而不是带 DEBUG 的优化诊断配置。

播放请求/代次、首帧与可见确认、资源预算、GPU drain、错误返回和局部降级是产品控制，继续由原 owner 执行；它们不能依赖统计或诊断返回值。共享渲染签名只可保留无观测实现的占位类型；已有只做 GPU 观测的参数通道在 Release 使用无状态且可内联消除的值，不分配观测对象、加锁或安装 GPU handler。失败原因仍作为用户可见 typed 状态返回。

验收为 Debug 观测仍可用；普通 Release 无统计 timer/诊断事件/日志桥活动，真实冷暖启动及暂停/恢复/切换/退出可执行；资源归因和启动优化用同构建/同入口交替对照，不跳过解析边界与播放代次检查，不提前报告 ready 或增加常驻调度器。

### 3.1 默认状态

详情只保留本地元数据、预览、播放/下载与属性入口。原仅 Debug 挂在属性按钮次级菜单的 Web/Scene 样本诊断面板及报告专属链已退役；属性齿轮的普通点击、Scene 属性准备与真实开发工具保留。详情不得为了摘要或决定属性入口而构建完整诊断、解析 Scene 或触发 preparation。

缺少作者昵称或链接时可异步补充公开作品资料，沿用统一 Steam 获取链的请求取消与身份检查，不借元数据补全触发 Scene 解析。开发诊断继续通过现有 DebugApp、CLI、benchmark、runtime evidence、GPU/FrameCapture 与 telemetry 入口显式执行，不借详情页保留另一条请求链。

### 3.2 状态机

属性请求直接进入现有唯一 preparation owner。命中同身份 prepared context 时复用，否则沿原异步准备、加载反馈和窗口 token 发布；记录/属性/locale/active-session 版本、cache epoch、关闭/压力与取消检查共同拒绝陈旧结果。无关 service 更新不得重启工作，失败只影响本次属性准备，不改变当前壁纸或持久记录。文件、解析和 hash 工作保持在原后台队列，UI 提交回 MainActor/AppKit；不因诊断退役新增 owner、轮询或缓存。

<a id="timeline-frame-input-observation"></a>
### 3.3 有界 Timeline 帧输入观测

配置入口为`MYWALLPAPERX_SCENE_DEBUG_TIMELINE_EVIDENCE`的JSON对象，完整字段为`layerIDs/sceneTimeWindow/interval/maxSamples`。为区分作者动画未准备、typed发布缺席及后继几何问题，仅DEBUG且显式opt-in、使用现有证据窗口时，允许旁路读取当前launch实际TimelineProgram与实际surface的SceneFrameContext。原compiler、PlaybackRuntime、Resolver、clock和提交保持唯一权威；observer不调用compile/values/apply、不改snapshot或播放状态，不在通用makeFrameContext重复采集。普通播放关闭时无逐帧投影、编码或分配。

launch仅一次投影选层binding的target/type、authored base、composition、playback owner、播放选项及lane/keyframe计数，不导出整段曲线、脚本或整图；最多8层、24 bindings、64 diagnostics及64KiB，截断必须标incomplete。renderFrame选定实际context后，只取这些层origin/angles/scale的resolved value/type/source与authoredValue，并携既有presentationStreamID、frameIndex、sceneTime、snapshot frame/generation；missing与非有限值明确记录，不补零或伪称timeline。该输入观察不证明GPU完成、pose/world或截图同帧。

配置须完整合法：sceneTime窗不超过10秒、interval至少0.2秒、每surface最多32次，同stream/frame去重，最多8 streams且总输出不超过512KiB；非法、溢出、身份不一致或无窗口样本使本次资格不完整，不改产品行为、不自动重试。逐surface计数随原view退休；进程预算只保累计streams/bytes标量，退休不退款，避免反复launch绕过上限；不持有Scene、Program或资源。此处采用选层数值旁路，避免新建完整trace框架；取得缺口数据后据实选下一owner，不扩成常驻全图诊断。最近真实parser→生产Program DTO→runtime/resolver门验证过滤/改ID、来源/missing、frame原样、限额、disabled和观测无副作用，不外推compiler准入；Swift修改补一次固定源Debug及一份原包实际Program/目标窗资格，无新产品正确性或性能收益预支。

## 4. 壁纸启动事务

### 4.1 唯一请求与准备 owner

启动协调器只拥有以下状态：

- request ID、intent generation、目标记录和内容 identity；
- 属性快照 identity、显示器拓扑 generation 和目标 device identity；
- preparation stage、取消、超时和 typed failure；
- `active`、`pending` 与提交结果的事务角色。

产品状态和持久化当前壁纸只在提交成功后更新。新请求采用 newer-wins；过期准备结果必须在接触 surface、publication 或持久化以前被拒绝。

播放与属性在原 service 捕获当前记录、版本与读取租约后直接进入后台准备。启动关键路径不得为了加速缓存而复制作者目录、创建/发布新库版本、升级旧版 receipt，或将整棵目录与历史入库摘要比较。入库 receipt 证明下载和发布事务当时完成，不是本地壁纸日后播放的许可；Finder 元数据、作者新增资源、截图或旧工具产物不得令仍有效的项目拒播。原下载阶段的完整性核验、当前删除/代次与租约仍归原库 owner。Scene IPC 只携当前来源 root 与 managed generation/storageIdentity，不再携无播放消费者的历史 contentDigest/receipt；旧字段解码忽略，不能作为额外许可。

原产品共享准备 Task 与属性 Request 仍各自持请求；同 ticket 重备除 epoch 外还核 preparation ID，旧成功、失败或取消均不得撤销新准备。普通取消、删除与退出保留实际准备工作 join、播放进程退出和原资源释放时序，不增设独立升级 owner、等待者或出版状态机。

取消沿原请求 token 在同步准备阶段、直接模型和材质 pass 的边界合作检查，不能等完整 ModelBuilder 结束才发现过期。检查放在普通读取失败的 `try?`/catch 之外，原取消错误必须上抛，不得翻译成缺资源或视觉降级。只在实际读取与消费处保必要边界，不承诺抢占单次 reader、hash 或 flock；取消后的资源释放仍等待原 preparation 队列尾屏障与 GPU drain，不能提前释放租约。Host停止须经过原launchPreparationQueue尾fence，没有Session时也等待已接纳准备终态；DEBUG完成沿原common/modal RunLoop投递，主线程不阻塞。

Program capability 准备沿用该 token，在领取下一 layer、stage 或 material 批次前合作检查；编译层只接收原 throwing check，不拥有第二份请求状态。并行入口用原结果锁保存首个取消错误，停止领取后继批次；已经进入的同步工作允许完成，原四 worker 总预算、作者顺序归并及完整 join 不变。join 后在归并或发布部分 capability 前上抛原错误，不能将取消折成 `Rejection`、缺失结果或视觉 passthrough。取消上下文只属于本次调用，不能污染后继请求。

上述 capability 批次取消不改单个 variant envelope、negative cache 或 single-flight wait 的锁、发布、唤醒与失败语义。资源准备沿同一个请求检查进入 ResourceView 的读取叶；Catalog/SourceFacts 只传递该检查与原错误，不另持取消状态。行为门使用真实 capability/stage/material 链和受控目录读取叶，验证取消分类、后继批次停止、在飞工作 join、普通结果和下一次调用；这不证明单次编译可抢占或实际切换耗时已改善。

ResourceView 的 handle 由具体 Root 产生并持有同一来源；目录资源以当前文件 revision 识别缓存，包资源以实际打开包的文件 revision、当前索引及条目范围识别缓存。包在同一 Reader/FD 解析索引一次，全部名称沿同一 Root 按需读取，不做全量 snapshot、哈希或物理解包。坏存储名和越界 payload 表项在 Root 原同一次投影中局部略去，不因未用坏项拒整包；Reader 保完整表结构边界。分隔符/Unicode canonical 等价的 exact 目标确定性选择首个安全可读条目，后续同目标条目不投影、不读取或比较内容；身份与字节均由所选条目确定。大小写邻居不合组，保 exact 优先及原排序折叠；文件与同名目录可共存。Scene/字体的 literal 文件查找沿原根顺序略过裸包目录，显式 /、/.、/.. 仍保目录意图并拒读，不误读同名或低根文件；已选有效范围文件内容坏不改选后条或低根。实际路径入根、格式/范围/长度、同 FD 稳定性、预算和取消由原消费处负责。旧 receipt 或派生缓存缺坏不构成播放许可，陈旧提取文件不参与选根；已选条目失败不得重选另一来源。

目录 metadata 查询只作一次入根解析和 `lstat`，下一独立查询重取 revision。实际 FD 读取保 expected identity、读中变化、越界及非法 handle 的 typed 失败；可选资源失败局部处理。父端 Request/Task 持 lease 到实际 join，取消不先退租。固定 stock Root 共享不可变事实，不持请求 lease、取消或错误状态；首帧与缓存命中不承担证据采集或历史完整性审计。

AssetCatalog沿原Loader局部引用闭包读模型、材质、effect和shader，保完整文件名索引、隐藏/潜在层、动态及材质脚本、MDL材质与粒子根/子依赖，不预读未引用作者正文。粒子递归定义沿同ResourceView在SourceFacts阶段由原GraphLoader读/解析一次，短值沿原launch交原Host throwing prepare消费并清理，普通坏定义局部；硬错与取消在候选发布前沿原失败链上抛。LaunchContext携带定义图，surface只消费它构建自身playback、纹理GPU与模拟状态，不能在非throwing帧设置中吞错或重读定义。图携带所选纹理Input与Root引用，只属同launch准备结果，不直接成为跨launch纯产物缓存。

短时跨类型重入按[Scene daemon 合同](scene-runtime-daemon-contract.md)执行：只在已提交 Web/Video 的合格 handoff 后，成功结清精确 Scene 请求及空 Host 才保留原进程最多30秒；新非 Scene 意图撤销空闲或在途保留资格，Scene 新请求可重新准入并采用原 transport。所有新来源/lease、候选/呈现与回滚仍沿原入口，普通 Stop/quit、失败与到期物理退出。user texture/initial video prime 的实际终态进入原 Session drain，取消不等于 join。实际运行、性能与未覆盖组合统一以[专项结算](../../history/cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md)和[运行证据](../capabilities/runtime-evidence-current.md)为准；进程复用不承诺首次冷起改进或AV/RSS归零。

### 4.2 两阶段准备与提交

```text
accepted
  -> prepare-model
  -> prepare-programs-and-shaders
  -> prepare-resources
  -> prepare-candidate-surfaces
  -> await-first-frame
  -> commit-visible
```

第一阶段在专用、可取消的 preparation executor 上形成不可变候选：

- 当前来源/读取租约与 resource view；包内按需读取或必要物化均由同一资源入口提供，不全量认证或解包；
- project、scene、asset、property、Program 和 graph 输入；
- 当前内容实际需要的 authored shader variant、reflection 与 pipeline preflight；
- 可共享的纹理、material asset、sprite atlas 和其他 device-scoped immutable 资源；初始 text 当前仍按 surface 准备，同次字体复用边界见第 5 节，不能据此宣称已跨屏共享。

第二阶段由 Scene desktop host 在主线程执行最小 AppKit 提交：

- 复核 request、content、property、display topology 和 device generation；
- 为目标显示器创建候选 surface，并复用同 launch/device 的不可变资源；
- 候选在当前输出之后完成 GPU/terminal compositor 首帧准备；
- 所有必须 surface 就绪后原子提升候选，随后退役旧 active；
- 失败、取消、超时、显示器变化或 App teardown 时销毁 pending，保留或恢复旧 active。

候选和 active 是同一 host 内两个有界 session role。Host 唯一拥有 Scene 执行请求、目标拓扑与可见性提升，消费产品事务的授权；Session 拥有该场景的 VM、clock、provider、surface 与 GPU 租约。旧 Host 的播放字段和方法迁入 Session，不保留双执行路径。候选窗口在首帧 GPU/terminal compositor 完成前透明，声音暂停，不订阅鼠标边沿；必须 surface 集合全部成功并取得产品授权后才提升可见性，旧输出沿原 finalize/退休屏障退出。首帧 presented 观测在提升时才安装，不能把透明候选的 GPU completion 当作可见证据。

候选的 localStorage 仍使用现有 session owner，但延迟持久化；候选取消、超时或被新请求替代不会把写入送到 persistence coordinator。同 record 替换时，提升只合入候选相对准备基线实际修改的键，保留旧 active 在此期间对其他键的写入。音频采集需求由 Host 聚合 active 与 candidate 的声明后送入既有 inbox，任一 session 退场不得清掉另一 session 的需求。

<a id="initial-video-presentation"></a>
### 可见普通视频的首呈现完整性

候选的GPU完成必须包含当前普通image消费者实际选中的authored video，不能把尚无buffer的成功空绘制当作内容完整。本合同不扩大到所有材质/命名依赖或后续active reveal/seek。Source仍唯一拥有AVPlayer、定位、buffer和commit/discard；初始property-video零帧seed不推广到普通视频，不覆盖首VM的seek/pause命令。

Source在原prepareFrame旁暴露pending/已建立terminal失败；BaseImage snapshot携候选期可选事实，原BaseMaterial resolver保留实际fallback选择。Renderer只在当前projection/visibility与真实普通image分支收集所选视频，冻结到PreparedFrame：缺buffer仍pending，现成still/provider替换不等未选视频，真实失败只归该消费者局部fallback。不能靠资源列表、generation、诊断字符串、alpha或offscreen猜可见性/就绪；不新增播放器、时钟、可见性或资源registry。

候选Session沿原renderSurfaces每次提交顺序生成独立attempt token，只有同一次全部prepared surface对象都实际提交且内容合格，才保留一个cohort并暂停后续候选cadence。各GPU完成后一次主线程批量调用原Host首帧回调；不能混合A旧attempt与B新attempt，也不能在父级延迟提升时覆盖已资格drawable。pending期间照常提交/commit，不能以GPU defer触发首start rollback/seek循环。暂停启动只重试既有simulation的资源/渲染，不重跑VM/粒子；复用原Timer直到原Host5s结果，不另造超时或“等够时长即ready”。

promote释放cohort并恢复原driver；stop、surface对象替换及真实render invalidation先撤销attempt，迟到成功无效，任何候选GPU失败继续失败。已向父级交付的cohort若被真实surface变更撤销，沿原Host失败取消，不能保留旧promotion token重备；尚未adopt的media与text provider发布通知不改变已提交的冻结帧，held期间不撤销cohort；提升后沿原补画读取最新publication。文字发布使用独立typed原因，未held时保留原补画；不能借用media专属暂停刷新而漏文字，也不增加待办队列。真实尺寸、输出环境或资源失效仍撤销。首次媒体命令仍在原render后commit、下一帧可见；本片不承诺初始seek目标像素额外同步。Host仍唯一拥有candidate/old-active、5s超时、提升、父级确认/撤回和drain；旧壁纸与声画意图在候选等待期间保持。cohort只是Session首呈现状态值，PreparedFrame事实不成为第二个提升权威。

长期门使用自有红色视频、静态青色peer、隐藏坏视频及改名双屏；暂停的真实脚本计数经peer alpha送到末端像素，不能以去重日志声称无重放。纯cohort门覆盖异步先后、不同attempt及对象替换；原Host门覆盖父级延迟commit期间的失败/取消、旧active与drain，实际App另验回调与旧输出。真实样本和已知失败、显式失败与相邻property-video边界归[有界验收](../history/initial-video-presentation-2026-10-23.md#initial-video-presentation-20261023)；不自动证明全视频、性能或官方一致。

设计前置范围：Session 提取、Host 首帧提升、localStorage 激活提交和 GPU drain，横切 identity／clock／publication／持久化，走 generic-only 迁移。请求 supersede、candidate 创建失败、首帧 GPU 失败、超时、拓扑变化和 stop 必须保留旧 active 或完成既有停止意图；retiring session 直到自己的 queue drain 完成才释放资源。验证必须执行 A→失败 B→成功 C、首帧迟到、同 record 存储写入、所有 owner 退场，以及正常逐帧脚本/多屏回归。门闭合后删除本批设计登记，保留本节唯一职责合同。

已接受但仍等待 deferred 图片资源的属性修改由 Session 的单个 pending transaction 保存：独立键累积，同键以最新值（含删除）覆盖，先验证完整候选，再按完整所需 layer 集合请求当前 generation。无重叠且无需 deferred 资源的新修改立即提交，不扩大到其他图片的等待/失败范围；新命令被拒绝时不得破坏已接受 pending；所有 surface 资源接入成功后才提交同一 typed liveState，部分接入失败沿现有回滚边界处理。

## 5. 缓存与预热

缓存分三层，这是目标分工而非全部已实现。稳定职责与寿命边界归本文，实施取舍和验证状态按页首引用；历史目标与结算不等于当前实现：

1. `PreparedContent`：内容/依赖 digest、generation 与不可变作者 bytes/IR；不携属性投影、VM、clock、storage session、播放器或 graph/history；
2. `PreparedLaunchPlan`：PreparedContent + 属性快照 + runtime/compiler schema；
3. `PreparedDeviceResources`：PreparedLaunchPlan + OS/Metal/compiler/device identity。

先在真实请求中有界复用；完整模型常驻和下载后默认预解析不作为必需步骤。预热只有在真实命中率、内存与争用证据支持后进入；沿同 key single-flight，点击提升同次工作，压力、新意图与退出取消。历史暂缓结论不禁止按新成本重构，也不能直接重启旧方案。

下载完整性与播放缓存身份分开：下载/入库核对当时传输内容；播放使用当前已打开来源的 revision 与有界索引，不把目录/包必须永远等于历史摘要作为许可。首次读取解析包头、路径和 entry range；暖复用不重新扫描全部 payload。实际读取中来源变化、截断或越界拒绝受影响单元；未使用文件变化不牵连整个场景。

ResourceView 唯一决定 package/loose/stock 顺序，index-backed handle 保留同 Root、完整 literal namespace 与所选 raw 身份。URL-only 消费者走有界、完整交付的物化桥；仍读作者 Root/FD 的工作持原 lease 至实际 join，自持 Data 的媒体 worker 只保其 OwnedFile/磁盘预约。私有文件保持到实际 worker 和最后 AV asset 借用释放，GPU drain 不能替代 CPU 或 AV 终态。缓存自持 bytes/IR 优先，跨请求保留 lazy handle 须显式延长原租约并验证更新/删除退出。包表结构不可解析时只隔离该包，完整 loose 内容仍可正常播放；包的逻辑命名及选中读取语义见上文，旧解包链已退役。

纹理 Input 区分已选 Root handle 与独立外部文件，不从任意 URL 猜 Root。每个独立 prepare 入口取得一次当前身份，再查原缓存；实际 miss 沿 readSnapshot 交付同次 bytes 与 revision，保同 FD 读中稳定性。持有完整 bytes/container 或 CGImage 的 PreparedSource 直接供尺寸、decode、upload、candidate、动画和视频声明消费，不再重查作者文件。作者在读取完成后另写文件不拒绝当前完整 snapshot；下一次独立 prepare 仍重新取得当前 revision。input/key 不符、实际读取错误、非法 handle 和取消沿原事务的最小失败范围返回；外部用户文件继续受原 security scope、冻结资源及 revision 事务约束。

跨 metadata→GPU 相位保留完整纹理 snapshot 须服从原 decode budget，领取后移出排队集合，当前操作完成后释放短值；不额外保活所有层的 TEX 来消除一次身份查询。未保留完整 snapshot、只留 scalar facts/Input/身份时，下一阶段是独立捕获，须将其当前身份与原 expected identity 比较，不能把新读 bytes 标成旧 key。原 parsed cache 命中可免重读/重解析，预算拒绝则允许重新捕获，不能承诺两阶段只读一次；deferred 队列同样不持完整 snapshot。sprite 尺寸 sidecar 沿选中纹理的同 Root raw sibling 读取，只作用于原粒子动画消费者，不扩张普通动画语义。

作者字体沿本次完整 ResourceView 的 literalEntry 按 package→loose 选根，以所选 Handle 的自持 Data 进入原 CGDataProvider/CGFont/CoreText；入根路径与范围由原 Root 决定，不另设更严的字体路径语法或字体 cache。仅未选中文件允许原 known stock 回退；选中后普通缺失/不可读/坏字体保原局部 Helvetica，来源硬错/取消拒当前 text 或动态新 raster，保旧完整输出。

同次初始 text load 只复用此前成功 raster 已持有、requestedPath 相同的 sourceFont；布局失败不提供可复用字体。不同字号交原 Resolver 从源字号字体派生，raster scale 不成为下一层的字体尺寸；不同 path 重新解析。该复用只属于当前 load，各 surface 和下次独立 load 仍各自准备，不新增跨屏或跨请求字体缓存。动态文字沿原 currentRasters 保当前 sourceFont，内容/颜色/宽度变化复用，同 path 字号变化派生，path 变化重新解析；不为同次已准备字体再查作者文件。

动态文字在途 token 跨 unregister/reset 不复用，连续新值保原单在途进度；Store 在原锁内关闭准入并将原 queue 尾 fence 与入队线性化；每屏退休须等字体 CPU、GPU 及已有 export 终态。共享 baseImages 仅在全 clearContext 关闭，其 deferred 尾在清 context 前纳原 Session 退休 group，先 stop 后 drain 也不丢。全停先等这些 CPU/退休工作，再提交最终 surface GPU barrier；GPU drain 不替代 CPU 确认，exited.gpuDrained 不扩为 AV drain。

Sound 在查询来源前跳过格式能力明确不支持的候选。路径选择归同一 ResourceView/Root，保索引别名、exact/case、stock/assets 与原选根顺序；./ 和重复分隔可指同一索引叶，.. 交 Root 的真实文件系统/包目录解析，不在 Sound 文本折叠。首次选择仅 invalidPath/symlinkEscape 局部拒本源；sourceChanged、invalidHandle 及取消即使发生在选择阶段也沿原事务上抛，选中后硬错不换根或吞掉。原作者 literal 默认不选 stock。

Sound 选中作者 Handle 后沿同 Root/FD 流式写入原 App 私有文件，实际读取稳定性与 close 成功才交付，失败清 partial。包路径在 snapshot 入口确认一次当前包 revision/条目身份，再查仍被 Program/实际 AVAsset 保活的成功文件；命中只检查完成私有输出的 revision 与取消，不在借用前后再次检查原作者文件。miss 的 readChunks 在原 prepare 闭包比较入口 expected identity，并保实际同 FD 读取期间的范围、稳定性与取消；writer.finish 后不再查原来源。读取完成后的作者改写不废本次完整私有 snapshot，下一独立请求仍按当前来源选身份，陈旧 Handle 不得借旧文件兜底。这不免除未来媒体 FD 或分段读取的原边界。

Sound 成功复用以当前打开包的文件 revision/条目身份、实际私有写域、suffix 与原磁盘账本实例共同分区。成功表仅弱持文件及其完成 revision，不存 Root/grant/版本 lease、失败或延长文件寿命；目录保原单次 stream。私有 output 缺失/变动只撤复用并由当前合法 Handle 重建。不保证跨停播/进程命中，并发 miss 保各自生产，不合并在途工作。普通不可用保原槽位，来源硬错/取消不得重选低根。

Host在既有launch直接构造App私有cache根，经privateMediaCacheDirectory供Sound、普通TEX MP4/WebM、material video、初始与动态外部属性video写私有池；作者cacheDirectory、ResourceView/Input与来源边界不因此替换。合法坏包/无包的loose分支也不能写作者根，不从旧解包outputURL或其父目录推断写域。文件pin唯一由原OwnedFile.retainForLifetime(of:)关联到实际AVAsset。Sound保D6的AVURLAsset(url:)→AVPlayerItem(asset:)构造，因活跃期可换item而在创建时pin实际asset。Video保原AVPlayerItem(url:)及活跃路径，期间由Source强持file；仅lifecycle.stop()获准后，在cancel/replace/nil之前将file交接给当前item.asset，deinit仍调用stop，不以统一factory或安装时pin改变活跃播放。退休后实际asset借用与原WebM worker仍持各自lease，最后释放才unlink；未安装item的WebM继续由原worker持lease至writer终态。原OwnedFile另以进程聚合磁盘账本计入预约、partial与已发布文件；已知长度须在payload读取/写入前预约，WebM公开segment由薄Objective-C delegate原生接收NSData，同步借bytes/length/type给原Swift SegmentSink及Writer.rawbuffer，在原受控FD sink逐段预约后写入，失败清partial，退款随实际file/worker/最后借用。超额保原不可用source槽位，不重选作者URL或低根；不驱逐在用文件。薄delegate强持原sink，worker保活AV弱delegate到原finish/cancel/abort；sink不反持delegate，回调精确保活owner与NSData至同步返回，借用指针不逃逸、不转Data或手动free，无另一队列或资源owner。此磁盘账本不覆盖AV内部workspace或native RSS，pin也不证明通用AV decoder/callback drain；实际来源边界与读取稳定性仍归原Root，不由pin替代。

包内WebM完成转换文件可沿同一OwnedFile弱成功表借用，与原样snapshot按用途分区；完整package identity、实际私有域、扩展名及原磁盘账本共同定键。Registry的package入口只核当次Handle的当前身份一次，再查原同owner/device活Source及完成文件；独立传入、可能跨重建保留的声明也在其公开入口核当前身份一次。同次Loader刚完整捕获的声明直接进入原私有消费，不再重查作者文件；活Source同步查找与已完成私有文件借用均不重复核原来源，取消点保留。命中凭同内容身份下原成功声明/输出跳过payload读取，旧成功文件不替代独立请求的当前身份。仅miss才取得原Loader声明；loose/external、非TEX和无成功凭据的非视频/坏内容保原处理，不长期保存声明或绕过decoded/磁盘预算。后台worker在实际转换/close成功并检查取消后仅登记已捕获不可变payload的纯identity和完成输出revision，不持Root、Handle或版本lease。并发miss各自生产/取消，不共享播放器或时钟；同一Registry核心负责构造失败、epoch/rebuild与发布，不因完成文件构造失败而二次转换。弱表不延长文件寿命，原Source/worker/实际AVAsset最后借用释放才unlink退款；不承诺跨停播/进程命中或长期驻留。

本进程 App bundle 内固定 stock 可由同一 ResourceView 共享一份完整不可变 namespace/index/lookup，保留原路径顺序、大小写与当前 Locale 语义；不能缩成静态引用子集。默认首建可消费原索引核从实际打包资源生成的有界清单，沿当前 Locale 分类/排序和原Root查找表投影；不能采用构建机的locale表或省略资源。信任边界仍是本App不可变bundle，清单自摘要不认证作者内容或识别一份自洽的陈旧清单。缺坏、越界、重定向或排序歧义只撤清单快路，回原完整枚举；生成失败不得沿用旧清单。显式自定义 stock、package 和 loose 仍各自重建/失效，不以目录 mtime 或 App 版本推导不变。枚举或 metadata 不完整不得常驻为成功；索引共享不缓存属性/模型/VM，也不延长作者版本租约。采用与撤回沿启动专项 P3a/P3b 的同条件产品验证。

项目固定 MSL 必须构建期编译。Workshop 作者 shader 只在 preparation 阶段按当前内容需求编译和 preflight；不得在 draw/pass encode 热路径首次同步编译，也不为未使用的完整 catalog 做无界 eager compile。

作者 shader 的 CPU 跨进程缓存只保存已经 accepted 的前端 Program 与 preparation 产物。identity 至少覆盖完整作者 source/source graph、combo、inactive/optional provider、资源 readiness/format、render contract 和 frontend/compiler schema；读取时核对当前 key/identity、payload digest、stage/backend 和产物自报 identity 一次；副本已等于当前 key 时不再对副本重算同一个 SHA。device/backend 磁盘产物另受 OS/compiler/GPU/attachment 身份、损坏回退和容量合同约束，不与 CPU 层混同。失败结果、诊断、超时和损坏文件不落成 success，读取异常统一作为 miss 并在后台重建。淘汰只影响性能，不能改变输出或失败语义。

同次 generic analysis miss 的六个源分析器直接消费原严格 fragment Unit/main/outputUses，不重做相同 lexer/syntax；raw 与 normalized 语义分开，实际 compiler 预算不变，不增跨 variant memo。该次已成功的 normalized Pair 直接交原 Compiler miss 消费，持久 analysis 命中不保留或补造 Pair；不重复归一化，也不把 Pair 另存为凭证。Compiler 先解析原 Bundle，仍按真实配置核 raw 输入与 normalized 输出预算；route 无 Pair 时走原编译尝试，不把 route 失败升级为拒编，key/作者导出继续使用原 raw 源。lexical scanner 在原 Segment 内追加同类文本，不逐字符重建累计字符串；引号、注释、Unicode 和跨行状态保持原语义。同一帧当前/上一指针及所需 effect projection 复用该 caller 的同一 Double 逆矩阵，各点仍独立处理投影失败，不跨帧缓存。

DirectModel 发布直接消费 Reader 已验证的不可变 bind 或 Skinning 完整成功的当前顶点，不在 VertexStream 重复逐通道 finite 检查；Skinning 后段失败始终选整份 bind，不发布半写 scratch。发布仍从当前 position 求精确 bounds，保数量、设备、commandBuffer、generation 与存储 lease 的原边界。球形粒子在原 EmitterSpawnPlan 准备维度、半径幂端点和倒数，出生只执行随机半径采样和原变换；动态输入、RNG 调用顺序、ID、事件、回滚及不安全出生的局部拒绝保持原 owner，不建另一信任标记或缓存。

同 launch/device 的成功 MTLLibrary/PSO 可由现有 prepared-device owner 共享，完整 compile key 与 single-flight 不变；每屏 encoder token/reset、graph/history、binding 与 publication 独立。最后一次 drain 后释放，跨 launch 保温需另有收益/驻留证据。

CPU Program/preparation 命中不等于 `PreparedDeviceResources` 命中。Metal library、pipeline、texture、surface 与 publication 仍属于当前进程和 device generation；在 OS/compiler/device/attachment identity 完整闭合并有真实首帧证据前，不得把磁盘 Program 命中表述为壁纸已经 ready。

### 5.1 编译缓存身份与恢复

编译规则或源码依赖变化后必须拒绝旧结果，同时保留无关 App/UI 修改后的暖启动收益。格式 schema 校验存储与 ABI，构建指纹负责生产规则失效，完整源码图负责内容依赖失效；不以手工 schema 作为唯一失效手段。

构建阶段将 Compilation 自有 Swift、其显式共享输入类型、生成器规则与配置的内容摘要写入 App 的 `SceneShaderCacheIdentity.json`；工具链身份另覆盖受控 manifest、依赖锁定与实际 helper 字节。规则扫描包含新增/删除文件，不含路径根、mtime、Git/App 版本或 UI 源码；普通增量构建也重新检查，但摘要相同不重写资源。App 每进程只读取一次小型身份文件，所有 CPU 分析/准备/Program 键包含语义指纹，外部编译产物键再包含工具链指纹。身份文件缺失或非法时使用进程私有身份，继续正常编译但不跨进程复用未知产物；不从源码树或可执行文件运行时补算摘要。

完整不可变 source graph 的实际内容摘要在 contract 构造/解码时计算一次，不能信任输入携带的 raw/dependency 摘要；preparation、variant 与 resource-demand 分析共用它，后两者的进程内与磁盘键都必须覆盖依赖。此摘要不进入逐帧路径，不改变根 stage 的既有 canonical admission identity。

通用产物由原读取 owner 完整解码/合同校验，命中立即返回；无效或缺失则进入现有同消费合同 single-flight，在锁定的工作内再检查一次，仍未命中才编译并原子发布一次，由原读取 owner 接受后直接返回 Program 给当前等待者，不在 flight 退出后再次打开同一文件。flight 身份包含真实 Program 消费的输出语义、premultiplied slots、颜色边界/transfer 与输出通道，不合并不同消费者；磁盘 artifact 身份保持原编译语义。坏发布或真实编译失败返回原局部失败，不递归重试、不保存为成功；成功 URL 不长期充当内容有效性证据，已接受 CPU Program 的现有有界内存复用保留。不同进程可重复编译但只能原子发布完整产物，不先删除可能已被另一进程修复的文件。

验收包括规则/工具变化与无关 UI 变化的指纹正反例、include-only 与陈旧自报摘要反例、各层独立进程冷暖读写、坏 JSON/旧合同/坏发布及并发单次重建，以及 Debug 构建和隔离真实 Scene 冷暖启动。旧磁盘条目按新身份成为 miss，沿既有有界淘汰退出；不全盘清缓存、不新增常驻调度器或第二缓存 owner。停止条件是这些边界闭合，不能将少量样本结果外推全量兼容或发布。

<a id="ready-request-preparation"></a>

### 5.2 ready-request 波次试验（已撤回）

将原 Variant/Material 准备拆为有界 prepare/execute/resume、让重复请求等待释放四槽 worker 的候选已在真实冷启动短筛中撤回；两次分别慢29.58%和25.67%，无产品收益。产品保原启动链，不能将该设计当待执行前置或继续扩建调度器。方案、输入身份与验收边界见[筛选记录](../history/shader-identity-hash-screen-2026-10-14.md#ready-request-screen)。只有新的实际瓶颈及可区分实验才重开；完整身份、失败回退、Catalog原子发布与现launch代次/取消owner仍是后续准备优化的边界。

## 6. 反馈与进度

用户点击设置后应立即看到非模态状态。详情 footer 和主窗口可投影同一个中心状态，使详情关闭后任务仍可观察。

推荐阶段文案：

- 正在验证资源包；
- 正在解析场景；
- 正在准备材质；
- 正在编译所需 shader；
- 正在加载纹理；
- 正在准备显示器；
- 正在等待首帧；
- 正在切换壁纸。

只有 bytes、entry、Program、shader、texture 或 surface 存在真实分母时才显示 `completed / total` 和确定进度条；不可准确计数的阶段使用不定进度，禁止用静态权重伪造总百分比。当前壁纸继续运行时明确显示“当前壁纸将继续播放”。取消和 newer-wins 不显示为产品错误；真实失败提供重试和用户主动“查看诊断”入口，但不自动执行完整诊断。

没有旧 active 时，允许按产品策略显示同一内容的 last-known frame 或 Workshop preview 作为明确的 loading placeholder；placeholder 不得发布为 Scene ready、GPU completion 或可见兼容证据。

## 7. 局部失败与回滚

- 路径逃逸、非法 range/ABI/target hazard、stale generation、生命周期破坏、编译/VM 超时、OOM 和预算超限继续硬拒绝最小不安全单元；
- 普通 shader/pass、optional provider 或资源视觉失败继续按兼容运行时架构 fail soft，不能因为启动事务而扩大为整 Scene 拒绝；
- 尚未提交的候选失败不能改变 active、持久化状态或其他 runtime；
- 提交开始后必须有明确的 visibility blocker、completion、rollback 和 timeout；不能在候选可见性未知时销毁 standby；
- display hot-plug、sleep/wake、device loss 和 App teardown 必须使过期 session generation 失效并释放 pending 资源。

## 8. 可独立交付的纵向结果

以下是职责分解，不是第二份任务队列；具体进入时机由用户指定专项或对应现役路线决定，并且每次只冻结一个结果：

1. **详情与开发观测分离**：详情不再提供样本诊断链；属性准备保持异步、可取消、缓存与 stale rejection，开发证据沿独立显式工具入口。
2. **异步准备与状态反馈**：点击立即返回，CPU preparation 离开主线程，中心状态可观察，成功前不改变持久化当前壁纸。
3. **候选首帧与原子切换**：active/pending/standby、首帧门、失败回滚和 newer-wins 在单一 Scene host 内闭合。
4. **内容缓存与 device 资源复用**：分层 cache、下载后预热、固定 MSL、按需作者 shader preflight 和多 surface immutable resource sharing。

共享权威文档、验证 manifest、build、App runtime、benchmark 和 GPU 证据必须由同一整合 lane 串行处理。并行实现只允许认领互不重叠的 UI、preparation、host 或测试职责；触达共同 owner 前必须重新检查工作区状态并完成显式交接。

## 9. 验证与声明边界

实施前后至少分别采集：

- 点击到请求 accepted、主线程最大 stall/hang；
- package、model、Program/shader、resource、surface 和 first-frame 阶段耗时；
- cold start、warm switch、同 Scene 重设；
- 单/多显示器耗时、CPU 内存和 GPU/VRAM；
- first GPU completion、publication、terminal compositor、visible 和 next-frame；
- A→B 快速连点、取消、坏 package、shader/资源失败、显示器变化、sleep/wake、teardown；
- 候选失败时旧输出连续性，以及成功前持久化状态不变。

首次基线只记录实际数字，不预写未经测量的百分比目标。UI 线程不执行 package I/O/hash、解包、作者 shader 编译或纹理解码，旧 generation 不提交，候选失败不撤销 active，进度只使用真实阶段/计数，这些属于不依赖性能阈值的结构合同。

静态审查、compile、route count、非黑画面和单次启动都不能证明性能闭合。性能结论需要冻结 source/build/input identity 下的 cold/warm 分布、主线程 stall、first visible frame、多屏内存与失败/回滚反例；视觉兼容声明仍须满足现役 Scene GPU/compositor/next-frame 和相称 ROI/事件证据门。专项明确区分空产品 cache、新进程磁盘暖、同进程暖与跨引擎返回；direct Host 的 ready、保留本轮目录或 Web forcedCold 标签都不能替代实际缓存/进程身份与可见终点证明。
