# Scene 启动响应与按需诊断合同

<!-- document-role: stable-contract -->

> 状态：现役稳定合同
>
> 当前实现程度、性能数字与运行证据只查[能力台账](../capabilities/coverage-ledger.md)和[运行证据索引](../capabilities/runtime-evidence-current.md)。
>
> 本文服从[兼容运行时架构](runtime-architecture.md)并由[兼容执行路线](../roadmap/scene-compatibility-roadmap.md)决定进入时机；它不是第二份 Scene 现役计划，也不改变 V0-V5 的任务顺序。

## 1. 目标与边界

Scene 详情和壁纸切换必须满足两个独立目标：

1. 打开详情只展示廉价、已有的项目元数据，不隐式触发 package 校验、解包、资源遍历、scene 解析、shader preparation、纹理解码或 GPU pipeline 创建；
2. 设置壁纸立即接受用户意图并保持主界面响应。候选内容在后台准备，当前壁纸在候选可提交前保持可见；不可避免的长准备必须有真实阶段、可取消状态和失败反馈。

本合同不建立第二 renderer、resource registry、property tree、frame clock、graph、history、compositor 或最终输出 owner。`SceneDesktopWallpaperHost` 继续持有唯一 Scene 桌面输出决定；新协调职责只管理请求、准备和提交事务。

MirageWallpaper 只提供 `candidate / active / standby`、request generation、首帧后提交和失败回滚的 clean-room 职责/时序对照。不得复制其 GPL 源码、shader、常量、payload、算法表达、独立 C++/Vulkan renderer 或按显示器启动进程的产品结构，也不得把第三方静态结构当作性能或官方语义证据。

## 2. 目标合同、当前事实与偏差债务

每个实施批次都必须分别记录：

- **目标合同**：本文与兼容运行时架构规定的按需诊断、异步准备、单一输出 owner、候选提交和失败回滚；
- **当前事实**：只由当前源码、能力台账和可复现运行证据说明同步工作发生在哪里、各阶段真实耗时和当前可见结果；
- **偏差债务**：首个错误 owner、同步边界、重复工作、当前 fallback、纠正门和旧路径退役条件。

静态审查可以证明同步 I/O、编译或资源创建位于 UI 调用链上，但不能单独给出耗时占比。性能优化前后必须在同一硬件、系统、构建、显示器拓扑和代表内容上重新采集 cold/warm 数据。

## 3. 详情与诊断合同

### 3.0 发布构建的诊断边界

正式 Release 从编译输入、实现与 IPC 入口排除开发观测链：启动/逐帧计时、带锁性能计数、signpost、GPU census/完成日志、周期资源统计、诊断 IPC、Web 事件缓存/通知及脚本日志桥均由 `DEBUG` 编译条件隔离。Steam helper 的 `Probe/` 与 `*SelfTest.cs` 不参与 Release 编译，`probe`／`selftest` 和 Web `inspect`／诊断事件只在 Debug 提供；Scene／Web 属性面板的样本诊断、完整 Web 依赖诊断扫描及报告缓存仅在 Debug 存在；普通 Web 发布播放不开放 Web Inspector。Scene 的资源引用与能力缺口汇总、effect 报告和 descriptor 诊断投影也只在 Debug 构造，真实资源解析与编译准入继续执行。产品 Web 启动准入只检查入口与依赖可用事实，不调用样本诊断；runtime profile 仍由产品 descriptor 风险事实决定。Scene／Web 属性面板的样本诊断、完整 Web 依赖诊断扫描及报告缓存仅在 Debug 存在；普通 Web 发布播放不开放 Web Inspector。Scene 的资源引用与能力缺口汇总、effect 报告和 descriptor 诊断投影也只在 Debug 构造，真实资源解析与编译准入继续执行。产品 Web 启动准入只检查入口与依赖可用事实，不调用样本诊断；runtime profile 仍由产品 descriptor 风险事实决定。Scene 详情的诊断构建与属性准备分离。Debug 保留现有显式证据入口，helper 随 App 的构建配置发布；不能用运行时开关冒充 Release 编译隔离，也不能在空日志调用前计算 payload 或注册 observer/timer。发布验收核对实际无 `DEBUG` 的构建、主 App／Video helper 符号、Steam 程序集类型与成员、开发命令拒绝及普通播放运行，而不是带 DEBUG 的优化诊断配置。

播放请求/代次、首帧与可见确认、资源预算、GPU drain、错误返回和局部降级是产品控制，继续由原 owner 执行；它们不能依赖统计或诊断返回值。共享渲染签名只可保留无观测实现的占位类型；已有只做 GPU 观测的参数通道在 Release 使用无状态且可内联消除的值，不分配观测对象、加锁或安装 GPU handler。失败原因仍作为用户可见 typed 状态返回。

验收为 Debug 观测仍可用；普通 Release 无统计 timer/诊断事件/日志桥活动，真实冷暖启动及暂停/恢复/切换/退出可执行；资源归因和启动优化用同构建/同入口交替对照，不跳过校验、提前报告 ready 或增加常驻调度器。

### 3.1 默认状态

Scene 详情的齿轮次级菜单提供“播放诊断”入口（2026-10-07 起该菜单入口仅 Debug 构建提供；Release 详情面板没有诊断入口，诊断能力保留给开发调试）。打开诊断面板只显示说明或已存在的结果，初始状态为 `idle`，不开始诊断；只有用户点击“开始诊断”才可创建诊断请求。

详情先显示本地元数据。缺少作者昵称或链接时可异步补充公开作品资料，沿用统一 Steam 获取链的请求取消与身份检查；不得借元数据补全触发 Scene 文件解析或 preparation。

详情普通内容不得调用完整诊断来生成摘要，也不得为了决定是否显示属性入口而构建完整诊断报告。Scene 属性准备和 Scene 诊断是两个显式、可取消的 consumer；两者可以复用同一份基础解析产物，但不能互相成为启动前置。

### 3.2 状态机

```text
idle
  -> running(stage, completed?, total?)
  -> success(report, contentIdentity)
  -> failed(typedError)
  -> cancelled
```

- `success` 报告按稳定 content identity 缓存；内容或会影响解析拓扑的属性 identity 改变后标为 stale，不自动重跑；
- service 的无关状态变化不能重新开始诊断；
- 新请求原子取消同记录旧请求，旧 generation 的完成结果不得覆盖新记录或已经关闭的详情；
- 诊断失败只影响诊断区，不能改变下载记录、属性值、运行缓存或当前壁纸；
- UI 更新回到 MainActor/AppKit owner，文件、解析和 hash 工作不得占用主线程。

## 4. 壁纸启动事务

### 4.1 唯一请求与准备 owner

启动协调器只拥有以下状态：

- request ID、intent generation、目标记录和内容 identity；
- 属性快照 identity、显示器拓扑 generation 和目标 device identity；
- preparation stage、取消、超时和 typed failure；
- `active`、`pending` 与提交结果的事务角色。

产品状态和持久化当前壁纸只在提交成功后更新。新请求采用 newer-wins；过期准备结果必须在接触 surface、publication 或持久化以前被拒绝。

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

- 安全 package identity、解包 generation 与 resource view；
- project、scene、asset、property、Program 和 graph 输入；
- 当前内容实际需要的 authored shader variant、reflection 与 pipeline preflight；
- 可共享的纹理、字体、静态 text、material asset、sprite atlas 和其他 device-scoped immutable 资源。

第二阶段由 Scene desktop host 在主线程执行最小 AppKit 提交：

- 复核 request、content、property、display topology 和 device generation；
- 为目标显示器创建候选 surface，并复用同 launch/device 的不可变资源；
- 候选在当前输出之后完成 GPU/terminal compositor 首帧准备；
- 所有必须 surface 就绪后原子提升候选，随后退役旧 active；
- 失败、取消、超时、显示器变化或 App teardown 时销毁 pending，保留或恢复旧 active。

候选和 active 是同一 host 内两个有界 session role。Host 唯一拥有请求、目标拓扑、公共播放意图和可见性提升；Session 拥有该场景的 VM、clock、provider、surface 与 GPU 租约。旧 Host 的播放字段和方法迁入 Session，不保留双执行路径。候选窗口在首帧 GPU/terminal compositor 完成前透明，声音暂停，不订阅鼠标边沿；必须 surface 集合全部成功后 Host 在主线程提升可见性，才退役旧 active。首帧 presented 观测在提升时才安装，不能把透明候选的 GPU completion 当作可见证据。

候选的 localStorage 仍使用现有 session owner，但延迟持久化；候选取消、超时或被新请求替代不会把写入送到 persistence coordinator。同 record 替换时，提升只合入候选相对准备基线实际修改的键，保留旧 active 在此期间对其他键的写入。音频采集需求由 Host 聚合 active 与 candidate 的声明后送入既有 inbox，任一 session 退场不得清掉另一 session 的需求。

设计前置范围：Session 提取、Host 首帧提升、localStorage 激活提交和 GPU drain，横切 identity／clock／publication／持久化，走 generic-only 迁移。请求 supersede、candidate 创建失败、首帧 GPU 失败、超时、拓扑变化和 stop 必须保留旧 active 或完成既有停止意图；retiring session 直到自己的 queue drain 完成才释放资源。验证必须执行 A→失败 B→成功 C、首帧迟到、同 record 存储写入、所有 owner 退场，以及正常逐帧脚本/多屏回归。门闭合后删除本批设计登记，保留本节唯一职责合同。

已接受但仍等待 deferred 图片资源的属性修改由 Session 的单个 pending transaction 保存：独立键累积，同键以最新值（含删除）覆盖，先验证完整候选，再按完整所需 layer 集合请求当前 generation。无重叠且无需 deferred 资源的新修改立即提交，不扩大到其他图片的等待/失败范围；新命令被拒绝时不得破坏已接受 pending；所有 surface 资源接入成功后才提交同一 typed liveState，部分接入失败沿现有回滚边界处理。

## 5. 缓存与预热

缓存分三层，失效条件必须显式且不得绕过安全校验：

1. `PreparedContent`：内容 digest、package generation、基础 project/scene/asset/resource/descriptor；
2. `PreparedLaunchPlan`：PreparedContent + 属性快照 + runtime/compiler schema；
3. `PreparedDeviceResources`：PreparedLaunchPlan + OS/Metal/compiler/device identity。

首次下载或首次解包完成时可低优先级预热 `PreparedContent`。用户点击设置后复用并提升同一请求，不能并行重复解析。预热在内存压力、温度压力、新用户意图或 App teardown 时可取消。

完整 package/hash/path/range 校验在首次建立可信 generation、来源变化、marker 损坏或 identity 不匹配时执行。已经原子完成且位于 App 自有 content-addressed cache 的 generation 可以使用廉价 identity 检查；不得每次详情打开重复读取并 hash 全部 package 和所有缓存文件，也不得为了命中缓存跳过路径逃逸、entry range、ABI 或完整性失败。

项目固定 MSL 必须构建期编译。Workshop 作者 shader 只在 preparation 阶段按当前内容需求编译和 preflight；不得在 draw/pass encode 热路径首次同步编译，也不为未使用的完整 catalog 做无界 eager compile。

作者 shader 的跨进程缓存只保存已经 accepted 的前端 Program 与 preparation 产物。identity 至少覆盖完整作者 source/source graph、combo、inactive/optional provider、资源 readiness/format、render contract 和 frontend/compiler schema；读取时同时校验 key digest、payload digest、stage/backend 和产物自报 identity。失败结果、诊断、超时和损坏文件不落成 success，读取异常统一作为 miss 并在后台重建。缓存容量必须有界，淘汰只影响性能，不能改变产品输出或失败语义。

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

以下是职责分解，不是第二份任务队列；具体进入时机仍由唯一现役 roadmap 决定，并且每次只冻结一个结果：

1. **按需诊断**：详情默认不诊断，显式异步运行、取消、缓存和 stale rejection；属性入口不依赖完整诊断。
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

静态审查、compile、route count、非黑画面和单次启动都不能证明性能闭合。性能结论需要冻结 source/build/input identity 下的 cold/warm 分布、主线程 stall、first visible frame、多屏内存与失败/回滚反例；视觉兼容声明仍须满足现役 Scene GPU/compositor/next-frame 和相称 ROI/事件证据门。
