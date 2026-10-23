# Scene 启动响应与按需诊断合同

<!-- document-role: stable-contract -->

> 状态：现役稳定合同
>
> 当前实现程度、性能数字与运行证据只查[能力台账](../capabilities/coverage-ledger.md)和[运行证据索引](../capabilities/runtime-evidence-current.md)。
>
> 本文服从[兼容运行时架构](runtime-architecture.md)，不拥有任务顺序。用户指定的冷暖启动改进按[Scene/Web 启动专项](../../development/wallpaper-startup-optimization-plan.md)执行；自主兼容选题仍由[兼容路线](../roadmap/scene-compatibility-roadmap.md)决定。

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

正式 Release 从编译输入、实现与 IPC 入口排除开发观测链：启动/逐帧计时、带锁性能计数、signpost、GPU census/完成日志、周期资源统计、诊断 IPC、Web 事件缓存/通知及脚本日志桥均由 `DEBUG` 编译条件隔离。Steam helper 的 `Probe/` 与 `*SelfTest.cs` 不参与 Release 编译，`probe`／`selftest` 和 Web `inspect`／诊断事件只在 Debug 提供；Scene／Web 详情隐藏诊断面板及其专属样本报告、完整 Web 依赖诊断扫描与报告缓存已退役；普通 Web 发布播放不开放 Web Inspector。Scene 的资源引用与能力缺口汇总、effect 报告和 descriptor 诊断投影也只在 Debug 构造，真实资源解析与编译准入继续执行。产品 Web 启动准入只检查入口与依赖可用事实，不调用样本诊断；runtime profile 仍由产品 descriptor 风险事实决定。Scene 属性准备由现有独立 owner 处理，不再持有详情诊断 consumer。着色器归一化源码与编译后 MSL 的证据目录解析和写盘也仅在 Debug 构建；工具版本探测继续承担安全身份校验。Debug 保留现有显式证据入口，helper 随 App 的构建配置发布；不能用运行时开关冒充 Release 编译隔离，也不能在空日志调用前计算 payload 或注册 observer/timer。发布验收核对实际无 `DEBUG` 的构建、主 App／Video helper 符号、Steam 程序集类型与成员、开发命令拒绝及普通播放运行，而不是带 DEBUG 的优化诊断配置。

播放请求/代次、首帧与可见确认、资源预算、GPU drain、错误返回和局部降级是产品控制，继续由原 owner 执行；它们不能依赖统计或诊断返回值。共享渲染签名只可保留无观测实现的占位类型；已有只做 GPU 观测的参数通道在 Release 使用无状态且可内联消除的值，不分配观测对象、加锁或安装 GPU handler。失败原因仍作为用户可见 typed 状态返回。

验收为 Debug 观测仍可用；普通 Release 无统计 timer/诊断事件/日志桥活动，真实冷暖启动及暂停/恢复/切换/退出可执行；资源归因和启动优化用同构建/同入口交替对照，不跳过校验、提前报告 ready 或增加常驻调度器。

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

取消沿原请求 token 在完整同步准备阶段、直接模型和材质 pass 的边界合作检查，不能等完整 ModelBuilder 结束才发现过期。检查放在普通读取失败的 `try?`/catch 之外，原取消错误必须上抛，不得翻译成缺资源或视觉降级。保留每份资源及接口证明，不承诺抢占单次 reader、hash 或 flock；取消后的资源释放仍等待原 preparation 队列尾屏障与 GPU drain，不能为提早响应提前释放租约。

Program capability 准备沿用该 token，在领取下一 layer、stage 或 material 批次前合作检查；编译层只接收原 throwing check，不拥有第二份请求状态。并行入口用原结果锁保存首个取消错误，停止领取后继批次；已经进入的同步工作允许完成，原四 worker 总预算、作者顺序归并及完整 join 不变。join 后在归并或发布部分 capability 前上抛原错误，不能将取消折成 `Rejection`、缺失结果或视觉 passthrough。取消上下文只属于本次调用，不能污染后继请求。

本边界不进入单个 variant envelope、negative cache、single-flight wait 或 RuntimeCatalog/AssetCatalog；其锁、发布、唤醒与失败语义保留。行为门使用真实 capability/stage/material 链和受控目录读取叶，验证取消分类、后继批次停止、在飞工作 join、普通结果和下一次调用；这不证明单次编译可抢占或实际切换耗时已改善。

### 4.2 两阶段准备与提交

```text
accepted
  -> validate-content
  -> prepare-model
  -> prepare-programs-and-shaders
  -> prepare-resources
  -> prepare-candidate-surfaces
  -> await-first-frame
  -> commit-visible
```

第一阶段在专用、可取消的 preparation executor 上形成不可变候选：

- 安全内容 identity、已验证 generation 与 resource view；包内按需读取或必要物化均由同一资源入口提供，不要求全量解包；
- project、scene、asset、property、Program 和 graph 输入；
- 当前内容实际需要的 authored shader variant、reflection 与 pipeline preflight；
- 可共享的纹理、字体、静态 text、material asset、sprite atlas 和其他 device-scoped immutable 资源。

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

缓存分三层，这是目标分工而非全部已实现。具体迁移、成本门和旧链退出归[启动专项](../../development/wallpaper-startup-optimization-plan.md#decision)：

1. `PreparedContent`：内容/依赖 digest、generation 与不可变作者 bytes/IR；不携属性投影、VM、clock、storage session、播放器或 graph/history；
2. `PreparedLaunchPlan`：PreparedContent + 属性快照 + runtime/compiler schema；
3. `PreparedDeviceResources`：PreparedLaunchPlan + OS/Metal/compiler/device identity。

先在真实请求中有界复用；完整模型常驻和下载后默认预解析不作为必需步骤。预热只有在真实命中率、内存与争用证据支持后进入；沿同 key single-flight，点击提升同次工作，压力、新意图与退出取消。历史暂缓结论不禁止按新成本重构，也不能直接重启旧方案。

内容身份与 byte 完整性分开：版本租约只防 App 回收，App 自有目录/mtime/size/marker 不能自行证明内容可信。首次准入完整验证索引、路径、range 与冲突，receipt 另绑定预期摘要。暖挂载核对索引，实际消费 entry 的自持字节验证成功后才能发布；缺可信 receipt 回完整准入，managed 来源失配不得静默收养。未使用 payload 的损坏可延至首次使用发现，索引安全错误仍在挂载拒绝，同大小篡改不得漏检。详情不触发此工作；不为暖命中跳过安全或 ABI 检查。

ResourceView 唯一决定 package/loose/stock 顺序，允许内部以 package index-backed handle 替代解包目录。URL-only 消费者走有界、验证后原子完成的物化桥；来源/物化 pin 保持到在途 CPU 与 GPU/provider 排空。缓存自持 bytes/IR 优先，跨请求保留 lazy handle 须显式延长原租约并验证更新/删除退出。全量 extractor 的产品调用在迁移验收后退役，不长期维持第二资源路径。

项目固定 MSL 必须构建期编译。Workshop 作者 shader 只在 preparation 阶段按当前内容需求编译和 preflight；不得在 draw/pass encode 热路径首次同步编译，也不为未使用的完整 catalog 做无界 eager compile。

作者 shader 的 CPU 跨进程缓存只保存已经 accepted 的前端 Program 与 preparation 产物。identity 至少覆盖完整作者 source/source graph、combo、inactive/optional provider、资源 readiness/format、render contract 和 frontend/compiler schema；读取时同时校验 key digest、payload digest、stage/backend 和产物自报 identity。device/backend 磁盘产物另受 OS/compiler/GPU/attachment 身份、损坏回退和容量合同约束，不与 CPU 层混同。失败结果、诊断、超时和损坏文件不落成 success，读取异常统一作为 miss 并在后台重建。淘汰只影响性能，不能改变输出或失败语义。

同 launch/device 的成功 MTLLibrary/PSO 可由现有 prepared-device owner 共享，完整 compile key 与 single-flight 不变；每屏 encoder token/reset、graph/history、binding 与 publication 独立。最后一次 drain 后释放，跨 launch 保温需另有收益/驻留证据。

CPU Program/preparation 命中不等于 `PreparedDeviceResources` 命中。Metal library、pipeline、texture、surface 与 publication 仍属于当前进程和 device generation；在 OS/compiler/device/attachment identity 完整闭合并有真实首帧证据前，不得把磁盘 Program 命中表述为壁纸已经 ready。

### 5.1 编译缓存身份与恢复

编译规则或源码依赖变化后必须拒绝旧结果，同时保留无关 App/UI 修改后的暖启动收益。格式 schema 校验存储与 ABI，构建指纹负责生产规则失效，完整源码图负责内容依赖失效；不以手工 schema 作为唯一失效手段。

构建阶段将 Compilation 自有 Swift、其显式共享输入类型、生成器规则与配置的内容摘要写入 App 的 `SceneShaderCacheIdentity.json`；工具链身份另覆盖受控 manifest、依赖锁定与实际 helper 字节。规则扫描包含新增/删除文件，不含路径根、mtime、Git/App 版本或 UI 源码；普通增量构建也重新检查，但摘要相同不重写资源。App 每进程只读取一次小型身份文件，所有 CPU 分析/准备/Program 键包含语义指纹，外部编译产物键再包含工具链指纹。身份文件缺失或非法时使用进程私有身份，继续正常编译但不跨进程复用未知产物；不从源码树或可执行文件运行时补算摘要。

完整不可变 source graph 的实际内容摘要在 contract 构造/解码时计算一次，不能信任输入携带的 raw/dependency 摘要；preparation、variant 与 resource-demand 分析共用它，后两者的进程内与磁盘键都必须覆盖依赖。此摘要不进入逐帧路径，不改变根 stage 的既有 canonical admission identity。

通用产物由原读取 owner 完整解码/合同校验，命中立即返回；无效或缺失则进入现有同键 single-flight，在锁定的工作内再检查一次，仍未命中才编译并原子发布一次，完成后再次完整校验。坏发布或真实编译失败返回原局部失败，不递归重试、不保存为成功；成功 URL 不长期充当内容有效性证据，已接受 CPU Program 的现有有界内存复用保留。不同进程可重复编译但只能原子发布完整产物，不先删除可能已被另一进程修复的文件。

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
