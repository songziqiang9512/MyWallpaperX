# Scene 启动响应与按需诊断合同

<!-- document-role: stable-contract -->

> 状态：现役稳定合同
>
> 当前实现程度、性能数字与运行证据只查[能力台账](semantics/coverage-ledger.md)和[运行证据索引](semantics/runtime-evidence-index.md)。
>
> 本文服从[兼容运行时架构](runtime-architecture.md)并由[兼容执行路线](scene-compatibility-roadmap.md)决定进入时机；它不是第二份 Scene 现役计划，也不改变 V0-V5 的任务顺序。

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

### 3.1 默认状态

Scene 详情包含一个默认折叠的诊断区。折叠区初始状态为 `idle`，展开只显示说明或已经存在的结果，不开始诊断。只有用户点击“开始诊断”才可创建诊断请求。

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

候选和 active 可以在迁移期间作为同一 host 内的两个 session role 共存，但每个显示器始终只有一个可见产品输出决定；不得静默双输出。

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
