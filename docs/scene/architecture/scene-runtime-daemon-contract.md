# Scene Runtime Daemon 契约

<!-- document-role: stable-contract -->

> 状态：现役控制面与播放面进程合同。
>
> 复核：2026-11-01，按当前应用入口、SceneDaemonProtocol、client、endpoint 与 Session 生命周期静态核对；不代表本轮重新通过运行验收。
>
> 本文规定 App 与 Scene daemon 的职责、命令、发布与退出边界。引擎内部目标归[运行时架构](runtime-architecture.md)，实际 owner 与线程查[事实地图](runtime-as-built-map.md)，完整跨引擎交接查[播放切换事务](../../architecture/playback-lifecycle-transaction-design.md)。

## 1. 目标与非目标

Scene 播放在独立 daemon 进程运行。主 App 负责 UI、用户选择、产品设置、共享系统采集和粗粒度会话控制；daemon 负责 Scene 窗口、时钟、输入、QuickJS、资源、Metal 执行与最终输出。隔离的收益是主界面与播放执行域分开、播放故障可重启；不能据此承诺总 CPU、GPU 或内存降低。

进程隔离不建设第二 renderer、clock、property tree 或资源系统。普通帧不依赖主 App 心跳，也不跨管道逐节点、逐属性或逐 draw 调用。

## 2. 进程模型

当前采用同二进制 daemon：App 通过公共 DaemonProcessTransport 孵化自身可执行文件，传入 `--mwx-scene-daemon`。daemon 走应用入口的专用分支，设置 accessory，跳过主 UI 协调器；SceneDaemonRuntime 的私有 Host 是唯一产品执行入口。

| 边界 | 职责 |
| --- | --- |
| App | 持有产品选择、可重放 authored intent、请求与属性 revision，配置系统输入和显示拓扑 |
| Scene client | 端点生命周期、命令投影、回执过滤、候选授权及重放裁决 |
| 公共 transport | Process、管道分帧、写入顺序、背压和进程终止通知 |
| Scene endpoint | 按协议解码，调用私有 Host，发布对应请求的事件 |
| Scene Host/Session | 候选与当前会话、帧推进、Surface、资源及释放 |

所有 Scene 源码继续属于原 App target，不为同二进制模式复制到另一 Target。实际运行隔离由入口分支和实例所有权保证。当前不采用 XPC，也不需要经主 App 共享或呈现 Scene 的 Metal 纹理。

App 持久化产品设置，daemon 可维护已有 Shader 缓存和 SceneScript localStorage 等引擎数据。进程重启会丢失瞬时 VM/模拟状态，client 重放的是当前用户意图，不是完整场景 heap 或播放历史。

源码：[应用入口](../../../MyWallpaperX/App/MyWallpaperXApplication.swift)、[client](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift)与[endpoint](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift)。

## 3. IPC 合同

### 3.1 命令

传输采用 stdin/stdout newline JSON。实际字段、类型和版本由 [SceneDaemonProtocol](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol.swift)及其 typed command 定义维护，本文只保留语义，避免复制另一份 schema。

| 命令族 | 命令 | 语义 |
| --- | --- | --- |
| 内容准备 | loadScene、cancelLaunch | 完整 authored 请求及资源来源；按当前请求身份接纳与取消 |
| 候选交接 | commitCandidate、finalizeCandidate、cancelCandidate | 授权推广、实际 presented 后确认或撤销，旧 active 在确认前可恢复 |
| 输出控制 | setOutputActive、retireOutput | 暂停输出活动或撤回指定请求，和用户暂停、静音分别表达 |
| 属性 | setProperty | typed values、revision、recordID；拒绝热更新时使用 client 已合并的当前意图重载 |
| 外部纹理 | setUserTextures | selected/reset 的资源事务；成功回执后提交用户配置，坏资源保旧 |
| 用户快捷方式 | setUserShortcuts | 用户明确配置的目标及版本，绑定到对应请求 |
| 宿主配置 | setDisplayConfiguration、setPerformanceProfile | 显示拓扑和既有性能策略，daemon 持有帧驱动 |
| 声音与播放 | setVolume、setMuted、pause、resume | 共享意图下发，保留作者自己的播放/停止状态 |
| 外部输入 | publishAudioSpectrum、publishSystemMedia、publishSystemMediaArtwork、controlSystemMedia | 共享来源的 snapshot、需求控制和有序异步结果 |
| 诊断与退出 | captureFrame、shutdown | 观察同一最终输出；有序停止并排空已接纳工作 |

普通产品 load 带 requestID/recordID；属性和资源更新使用其 revision。首次准备、快速切换、重连和媒体结果的回执只能进入对应端点与请求，不能读取“当前请求”再给旧结果贴身份。

### 3.2 事件与完成语义

| 事件 | 可以说明什么 |
| --- | --- |
| launchStateChanged | 指定请求的当前准备阶段或终态；不等于实际呈现 |
| candidatePrepared | 当前候选所需 Surface 已取得首帧 GPU 完成，等待父端授权 |
| firstFramePresented | 同请求 drawable 的实际 presented；不能由已编码、已提交或 completed 代替 |
| propertyUpdateResult、textureUpdateResult | 对应 revision 的接纳或失败；CPU 采用完成不等于所有屏同时可见 |
| switchControlResult | 指定 operation 的输出控制/退役结果；强退役须显式确认 requestRetired |
| launchResourcesReleased | 对应请求已接纳准备与会话资源到达定义的退役终态，才可归还请求读取租约 |
| 音频与媒体 demand | 当前 daemon scope 的真实消费者需求；不是从历史 replay 自动恢复的采集许可 |
| frameCaptured、frameStats、error | 按构建/请求启用的诊断观察与错误；不授予播放或提交资格 |
| exited | 退出前的终态报告；实际进程退出由 transport 单独确认 |

频谱、媒体、控制和统计的具体 schema 以 decoder 与真实发送代码为准。诊断事件可以按当前构建能力关闭；产品不能等待 frameStats 才判定活性。

### 3.3 传输与身份边界

普通控制命令保序。高频可丢弃输入只在相邻控制屏障之间 latest-only，不能越过 load、pause 或 shutdown 改变时序。普通控制无法接纳时终结对应端点，不静默继续使用旧状态。公共 transport 的实际容量与退出排空逻辑由其实现和行为测试维护，不在本合同重复常量。

Scene 的协议版本由 SceneDaemonProtocol.version 唯一发布。命令与事件一致使用该版本；不匹配拒绝本端点，不影响 Video/Web 自己的协议。进程间只传控制、typed 快照、资源引用与诊断；MTLTexture、registry、graph、coordinator 和内部对象均留在 daemon。

## 4. 候选、恢复与退出

### 4.1 候选事务

1. 父端接纳新的用户意图并撤销旧 pending 身份；daemon 后台准备候选，当前有效 Scene 保持。
2. 候选所需首帧 GPU 完成后发送 candidatePrepared；父端确认当前请求后授权 commit。
3. daemon 推广候选并保留一个可回滚旧 Session，直到实际 presented 后收到父端 finalize。
4. 失败、取消或本地呈现超时回滚；本地真实 presented 撤销该呈现计时，父端 UI 繁忙不能被误判为尚未呈现。
5. finalize 后才退役旧 Session，读取租约继续等待资源退役回执或实际进程退出。

稳态逐屏呈现不受候选首帧 cohort 约束。某屏 drawable 不可用不重跑已消费的共享模拟，也不阻塞其他正常屏。

### 4.2 重启

进程断连或崩溃后，client 使用公共有界退避重启并重放当前 authored intent。仅恢复请求的实际 first-present 清零连续故障状态；持续失败停止重试并报告用户。旧 generation 或已退休端点的迟到事件不能进入新会话。

### 4.3 有序退出与强退役

shutdown 撤销新工作，关闭场景、worker 和 Surface，并等待已接纳的 CPU 准备及已提交 GPU 到达各自终态。窗口关闭不等于资源已释放，GPU barrier 也不能概括所有 AV borrower。父端只在匹配的成功回执或实际退出后退还来源租约；有界强退由 transport 负责。

强退役通过现有 requestRetirementSchemaVersion 协商，并在 requireRequestRetirement 请求中显式要求。成功必须确认已知请求的准备、Session、窗口和 GPU 定义范围全部退役；未知请求或缺字段不能冒充成功。它不承诺进程 RSS、AV 系统内部缓存或所有借用立即归零。

App 退出使用原进程终止机制，等待 retiring transport；终止通知及强退时限不能被 AppKit 的嵌套主循环饿死。空进程复用只复用端点，不保留旧请求的输出权。

## 5. 输入、线程与存储边界

系统音频采集与分析唯一归 App，daemon 根据实际消费者发布 demand，接收同 scope 的 typed 频谱。来源重建期间 unknown demand 不得偷换为 false；成功后提交实际需求，失败停止并撤销旧 scope。当前 Scene 不接受退役的 setSpectrumEnabled 开关。

系统媒体同样由共享来源投影，metadata 与封面需要保持请求身份。用户快捷方式只执行 App 选定的配置，通过既有 coarse configuration 和本地合法输入 scope 触发；不增加任意文件、网络或 JS native-module 能力。

当前帧循环、VM、输入和 Metal 编码留在 daemon 主 RunLoop；准备和资源 worker 在后台。迁移 DisplayLink 或独立渲染线程属于另一个有实际证据支持的改造，不因 daemon 已隔离便默认安全。SceneScript localStorage 的范围、写入和 owner 生命周期归其原运行时，不能宣称 daemon 没有持久化。

## 6. 验证与历史

改进程、命令或生命周期时，使用实际 encoder/decoder 和 client/daemon 行为验证：拆帧与合帧、未知命令、版本冲突、A→B→C 迟到回执、候选失败保旧、热更新及重放、进程强杀恢复、停止与请求退役。改变播放算法时另验 GPU 和真实画面；进程 smoke 不证明完整兼容或性能。

M5.2–M5.6 的实施过程、原型撤回与当时实测已归[2026-09-15 前工程档案](../history/engine-refactor-program-before-2026-09-15.md)。本合同不保留完成步骤或当时待确认风险；当前能力、运行证据和后继任务分别由其现役权威维护。daemon 已是合理的产品边界，不因外部起步方案建议同进程而回退。
