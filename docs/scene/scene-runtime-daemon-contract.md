# Scene Runtime Daemon 契约（SceneRuntimeService 设计门 M5.1）

<!-- document-role: stable-contract -->

> 状态：现役设计契约（M5 进程分离的设计门交付物；实施进度查[引擎重构工程计划](engine-refactor-program.md) §3 M5 工位卡）
>
> 复核：2026-09-14
>
> 当前能力权威：[能力台账](semantics/coverage-ledger.md)。
>
> 现状权威：`docs/scene/semantics/coverage-ledger.md`。代码实际接线查[事实架构地图](runtime-as-built-map.md)。
>
> 退役条件：daemon 化完成并稳定后，本契约并入长期架构合同（runtime-architecture.md 增补进程章节），本文转 historical-evidence。

## 1. 目标与非目标

**目标**：Scene 播放引擎运行在独立 daemon 进程（与 video/web 的 `MyWallpaperXWallpaperDaemon` 同模式）；主程序只做 UI/选择/设置/命令下发；崩溃/堆/QuickJS/编译器故障与主程序隔离；UI 永不掉帧。

**非目标（如实）**：不承诺总 CPU/GPU 下降；不改变引擎内部架构（唯一权威五件套、PreparedProduct 协议、失效域合同原样保留）；不在进程间传输任何 Metal 对象。

## 2. 进程模型

**实施裁决（2026-09-14，M5.2 动工前复核修订）**：Scene daemon = **同二进制 daemon 模式**——主程序 `Process()` 自孵化自身二进制（`--mwx-scene-daemon` 参数）作为 helper 进程，不建独立 tool target。

**裁决依据**：
1. 契约原定独立 tool target 依赖同步组（PBXFileSystemSynchronizedRootGroup）共享整引擎源码（Core/SteamWorkshopScene + Properties + Format + QuickJS，数百文件）——同步组的例外机制（membershipExceptions）只支持逐文件附加，整引擎共享 = 数百条例外的维护灾难（video daemon 可行是因其自有源码面小）。
2. 同二进制消除版本偏差（helper 签名校验、license bundle、artifact 缓存协议随 bundle 自动一致）；Scene 引擎无跨 target 同步组需求；video tool 若消费共享 DaemonKit，仍需为该共享子集登记双 target membership。
3. 崩溃隔离目标不变：独立进程，主程序存活并按 §4 退避重启。
4. XPC 评估后不采用：service target 同样面临整引擎共享问题；粗粒度命令（1Hz 统计+偶发命令）下 pipe+JSON 与 Mach 消息无性能差异；桌面窗口呈现路径以 Process+管道已在 video daemon 生产验证；launchd 托管由主程序自管退避替代。

| 项 | 裁决 |
|---|---|
| daemon 进程 | 主程序二进制 + `--mwx-scene-daemon`；NSApplication 配置为 accessory（无 Dock 图标、不参与激活）；主 UI 协调器（MainWindowCoordinator）在此模式**不装配** |
| 孵化 | 主程序 `Process()` 启动自身可执行文件，三根管道；引擎 worker 源码住在 app target（零共享面问题） |
| 传输 | stdin/stdout newline-delimited JSON；无 XPC |
| 引擎代码 | Scene runtime **原样运行**（渲染/QuickJS/粒子/compositor/frame loop/预算执行）——不重写线程模型：帧循环仍在 daemon 主线程（AppKit 约束原样成立，见 §5） |
| 状态存储 | daemon 拥有运行时状态；持久化设置由主程序经命令下发；daemon 无本地持久化（除既有 shader artifact 磁盘缓存，路径不变） |
| 已知代价（接受） | ① daemon 二进制=完整 app（内存映射共享页，增量小）；② `@main` 分支需守护测试防 UI 初始化渗入 daemon 路径；③ launchd 无托管——退避重启由主程序负责（§4） |

## 3. IPC 合同（= EngineCommand 的传输化，v1 冻结）

### 3.1 命令（主程序 → daemon，逐行 JSON）

| 命令 | 载荷 | 语义 |
|---|---|---|
| `loadScene` | `{rootURL, propertyOverrides, userPropertyTextures:{path,bookmark}, profile, recordID}` | newer-wins 世代接受；外部纹理以安全作用域书签跨进程，在 daemon Host 建表面时打开；后台准备；进度经事件回传 |
| `setProperty` | `{values, revision, recordID}` | 先尝试活动记录的 typed 热更新；daemon 回传接受结果，拒绝时 client 用合并后的 authored intent 走完整 load 兜底 |
| `cancelLaunch` | `{recordID}` | 只取消匹配记录的在途 launch |
| `setDisplayConfiguration` | `{screens:[{id, frame, scale}]}` | 多屏拓扑重建 |
| `setPerformanceProfile` | `{maxFPS}` | 60/30 档热切换（下一次排帧生效） |
| `setMuted` | `{muted}` | 静音公共态（Scene Sound 层 0 增益） |
| `pause` / `resume` | — | 播放暂停/恢复（时钟+视频+音效） |
| `shutdown` | — | 有序退出（先释放表面再退进程） |

### 3.2 事件（daemon → 主程序）

| 事件 | 载荷 | 时机 |
|---|---|---|
| `launchStateChanged` | `{phase, message, requestID, recordID}` | 五阶段状态机（accepted/preparingModel/preparingPrograms/preparingResources/preparingSurfaces/launched/failed/cancelled） |
| `firstFramePresented` | `{requestID, recordID, uptimeMs}` | 同请求 drawable 的实际 present 后 |
| `frameStats` | 轻量 counter 集合 | 1Hz（hub 定长快照；textureMemory/rtMemory 等接入后自动包含） |
| `propertyUpdateResult` | `{revision, recordID, accepted}` | 热更新尝试完成；client 只消费自己登记的 revision/recordID |
| `error` | `{code, message, context}` | 引擎内部失败的可上报子集 |
| `exited` | `{code, gpuDrained}` | GPU barrier 终结后的进程退出前 |

### 3.3 硬边界

- 进程间**只传** coarse 命令与轻量统计；`MTLTexture`/registry/coordinator/任何进程内对象不跨进程。
- daemon 内保持唯一权威五件套与失效域合同；诊断旁路（evidence window/HUD）留在 daemon 内。
- 协议版本：首行 `{"v":1,"role":"scene-daemon"}` 握手；不匹配 → 主程序拒绝启动该 daemon 并报错。

## 4. 生命周期与崩溃语义

- **孵化**：主程序 `SceneDaemonClient` 经公共 `DaemonProcessTransport` 启动自身可执行文件并传 `--mwx-scene-daemon`，三根管道；单实例使用既有 Host 多表面模型。不得启动不存在的 Scene tool。
- **崩溃/断连**：主程序侧持有公共 `DaemonRestartBackoff`（0s 立即一次，随后 1/2/4/8/16s，单次连续故障最多 6 次；通用上限 30s），重启后自动重放当前 authored intent；只有恢复请求的实际 first-present 才清零退避。连续失败超阈值 → 停止重试 + UI 错误态。
- **有序退出**：`shutdown` → daemon 排空在飞 command buffer → `exited` → 进程退出；client 超时 2s 强杀。
- **世代语义**：`loadScene` 世代号新者胜——旧准备的取消/回滚全部在 daemon 内完成，主程序无感知（只看到新 launchState 事件流）。

## 5. 线程约束审计结论（M5.1 审计；细节查事实架构地图 §1.3/§4）

daemon 化采用"runtime 原样搬迁"策略——**不重写线程模型**，以下主线程约束在 daemon 进程内原样成立，因此不构成迁移障碍：

1. 帧循环/QuickJS/粒子/Metal encode 在 daemon 主线程（Timer on RunLoop.main）；AppKit 接触点（drawableSize 主线程写、指针链 NSEvent/window.convertPoint、surfaces 主线程独占、8 组 commit 栅栏）在 daemon 内与今天同构。
2. QuickJS VM 线程绑定：launch 队列创建 → adoptCurrentThread 到 daemon 主线程，机制既有。
3. 与主程序的边界只有管道 JSON：主线程事件（NSEvent 采样、窗口生命周期）全部是 daemon 进程自己的主线程事务。
4. 需要防范的两点：①daemon 内 `Task { @MainActor }` 完成回调照旧；②`framesStats` 1Hz 事件从 hub 定长快照读取（锁内拷贝），不经帧路径。

**帧线程隔离（RenderLoop 独立线程/DisplayLink）明确不在 M5 范围**——此前裁决：接触面大、无编译器护栏，daemon 边界已达成隔离目标。

## 6. 迁移步骤（M5.2–M5.6）与验收门

| 步 | 内容 | 验收门 |
|---|---|---|
| M5.2 | 同二进制 daemon 模式起桌面窗口 + 命令框架（实际 present 证据独立验证） | 手动：样本文隔离副本出首帧 |
| M5.3 | 先抽取已有双消费者的 newline 分帧/编码；Scene 同 app target，本批只新增该真实共用文件的 app + video tool 双 target membership | split/coalesced/空帧门 + video daemon 行为回归 |
| M5.4 ✅ | Scene client 接入；孵化/退避抽入 DaemonKit；命令迁移（EngineCommand→管道）+ 请求过滤事件回传 + 退避重启 | 属性热更新/拒绝重载兜底、静音/FPS/暂停、强杀恢复已过隔离实测 |
| M5.5 ✅ | 删除 Host 全局入口；daemon runtime 显式拥有唯一产品 Host，主 App 保持 client stub | 普通主程序调用面无 Host 类型引用；DEBUG direct evidence 独立持有 |
| M5.6 ✅ | 生命周期收尾 + 旧路径删除（消融） | 切换/退出/多屏/暂停全链已过；能力语义与 prepared 产品未改 |

每步过 checkpoint 构建；M5.4 起用 graph 样本隔离副本做 smoke（首帧 + setProperty 热更新 + 崩溃恢复）。

## 7. 风险登记

**M5.2 安全重做记录（2026-09-14）：** 历史 prototype 已撤回后重新实现。当前 endpoint 检查 v1 并将属性保留为 `SceneUserPropertyValue`；load 消费 profile，未知命令和坏载荷发送 error；launch/first-present 都携带请求身份。`firstFramePresented` 只在同请求 drawable 的 Core Animation presented handler 后产生，handler 先异步离开 Core Animation 回调再投递主队列，避免与主线程 `nextDrawable` 锁反转。EOF 与 shutdown 走同一路径：停止 Host，向每个现有 surface 的既有 command queue 提交空 barrier、等待 terminal，再写 `exited{code,gpuDrained}` 并退出。critical 事件串行，1Hz frameStats 只有一个可替换待写槽。签名 Debug 的 graph/simple 隔离样本均实测真实 present、持续渲染和 `gpuDrained=true`；未知命令负例也实测报错。`setDisplayConfiguration` 与主程序 Process/client/退避仍属于 M5.3/M5.4，当前普通 App 播放路径尚未迁移。

**M5.3 双消费者裁决（2026-09-14）：** Video App client、WallpaperDaemon tool 与 Scene endpoint 原先各自拼接 newline 或维护输入 buffer；现统一消费无业务依赖的 `DaemonNewlineFrameBuffer` / `DaemonNewlineJSON`，协议 payload 与事件背压策略仍留在各端。孵化与退避此时只有 video client 一个生产消费者，因此没有提前抽成公共 wrapper；它们随 M5.4 Scene client 首次接线迁移。真实 Video helper 已用拆段命令和空帧回归到 ready/stopped；两个隔离 Scene daemon 均取得实际 present、持续统计和 GPU drain。公共层只运行于 coarse IPC，不进入帧内渲染热路。

**M5.4 控制面迁移记录（2026-09-14）：** 普通产品 Scene 已由 App 内 `SceneDaemonClient` 唯一接收 `WallpaperEngineCommand`，再经同二进制 daemon 管道控制既有 Host；App 侧只保留可重放 authored intent、请求身份、属性 revision 和 1Hz 统计。`loadScene` 携带 typed 属性及外部纹理书签，子进程恢复 URL 后仍由唯一 Host 在同步纹理上传范围内开闭安全作用域；`setProperty` 以 revision+recordID 回执，拒绝时用已经合并的 authored intent 全量重载。所有 launch/first-present 事件按 requestID/recordID 投影，旧终态不能清除新 pending。graph/simple 隔离副本都通过首帧、20 秒播放、SIGKILL 后自动重放与恢复 present；数值属性样本验证热更新在同一进程生效并在崩溃后保留，非 live 属性验证拒绝后完整重载。Video daemon 拆段/空帧回归仍通过。该迁移不增加 visual owner；Metal/registry/graph/compositor 全留在 daemon。

**M5.5 Host 所有权收口（2026-09-14）：** `SceneDesktopWallpaperHost` 不再暴露全局 `shared`；`SceneDaemonRuntime` 的私有实例是唯一产品 Host。普通 App 的 AppDelegate、应用入口、窗口协调器、WallpaperEngine 与 Steam 服务调用面均无 Host 类型引用，Scene client stub 只保存控制意图和投影 daemon 事件。同二进制 daemon 仍必须让完整 runtime 源码属于 app target，因此“主程序无渲染路径”的可执行含义是主进程不装配、不实例化且无法经全局入口取得 Host，而不是复制或搬走数百个 runtime 源文件。显式 DEBUG direct evidence runner 拥有独立 Host，只用于隔离样本，并由同一 owner 停止。graph/simple 均在强杀后由新 daemon 恢复实际 present，截图构图完整；本步不触碰帧算法、prepared 产品或失效域。

**M5.6 生命周期闭合（2026-09-14）：** App 捕获 `NSScreen` 拓扑并通过 v1 `setDisplayConfiguration` 发送有限的 display ID/frame/scale 值；daemon 校验 ID 唯一、数值有限和尺寸有效后交给唯一 Host 做去抖重建。Host 删除跨进程失效的 runtime-switch 和 App screen notification 入口，活动 Space 只监听 `NSWorkspace.shared.notificationCenter`。系统睡眠/锁屏/全屏和全局热键均经 multiplexer/client 控制 Scene，暂停意图跨无活动请求及 daemon 重连保留。App 退出使用 `terminateLater` 等待 client retirement；daemon 仍先停止表面、排空 GPU barrier、发 `exited` 再退进程。Process 终止事件经主 RunLoop common modes 投递，避免 AppKit 终止内层循环阻塞主 GCD 队列；2 秒强退由 transport 后台计时。隔离 simple→graph 在同 PID 完成两个 record 的 actual present 后退出无孤儿，simple 强杀恢复后也无残留；两份最终截图构图完整且 dropped=0。本步只收敛 coarse 控制与生命周期，不改变 Metal/registry/graph/compositor、prepared 产品或帧内失效域。


| 风险 | 缓解 |
|---|---|
| 多屏单实例 vs 多实例未定 | M5.2 原型实测（单实例多表面优先，与今天 surfaces 字典同构） |
| QuickJS artifact 磁盘缓存并发（主程序预编译 + daemon 编译） | 缓存协议本就单写者原子替换；daemon 成为唯一编译者后主程序不再触发编译 |
| 管道背压（frameStats 1Hz 足够小） | 事件丢弃策略：主程序忙时 daemon 侧只保留最新 frameStats |
| 属性覆盖持久化迁移 | UserDefaults 键与持久化读写留在主程序；daemon 经命令消费运行值，重启由主程序重放 |
