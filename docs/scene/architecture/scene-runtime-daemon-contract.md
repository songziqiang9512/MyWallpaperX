# Scene daemon 与 IPC

<!-- document-role: stable-contract -->

<a id="process"></a>
## 进程与职责

App 通过公共 `DaemonProcessTransport`启动自身可执行文件的 `--mwx-scene-daemon`分支。daemon 跳过主 UI 协调器，由 `SceneDaemonRuntime`私有持有产品 Host；窗口、QuickJS、资源和 Metal 留在该进程。普通产品不在主 App 另建 Scene Host，显式 DEBUG runner 只服务隔离观察。

| owner | 实际职责 |
|---|---|
| App / 产品服务 | 用户意图、持久设置、跨引擎选择、显示配置及共享系统采集 |
| SceneDaemonClient | 端点代次、命令投影、回执过滤、候选授权及重放 |
| DaemonProcessTransport | Process、newline 分帧、保序写入、背压及真实退出通知 |
| SceneDaemonRuntime | 解码 typed command，调用私有 Host，发布原请求身份事件 |
| Host / Session | 准备候选、帧推进、Surface、最终输出及资源退出 |

同二进制不复制另一份 target 或渲染器，不经主 App 转运 Metal 纹理。进程重启丢失瞬时 heap/模拟/history；重放当前 authored intent，不重建一个虚构的完整运行快照。总体内部链见[架构](runtime-architecture.md)。

<a id="protocol"></a>
## 消息与身份

stdin/stdout 使用 newline JSON。字段、版本、合法域及命令解码的唯一实现为[SceneDaemonProtocol](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol.swift)，不在文档复制第二份 schema。

| 命令族 | 当前入口 |
|---|---|
| 加载 / 取消 | loadScene、cancelLaunch |
| 候选 | commitCandidate、finalizeCandidate、cancelCandidate |
| 输出活动与退役 | setOutputActive、retireOutput |
| 属性 / 用户资源 / 快捷方式 | setProperty、setUserTextures、setUserShortcuts |
| 宿主策略 | setDisplayConfiguration、setPerformanceProfile、pause、resume、setVolume、setMuted |
| 系统输入 | publishAudioSpectrum、publishSystemMedia、publishSystemMediaArtwork、controlSystemMedia |
| 截图 / 退出 | captureFrame（ScreenCaptureKit → JPEG → frameCaptured）、shutdown |

request、record、revision 与 endpoint generation 保持原身份。普通控制保序，高频可丢弃输入只在相邻控制屏障内 latest-only；不能越过 load/pause/shutdown。控制无法接纳则终结该端点，不静默沿旧状态继续。协议不匹配拒绝本端点，不改变其他引擎协议。

事件的语义不能混同：launchStateChanged 是准备状态；candidatePrepared 是当前候选所需 Surface 首帧 GPU 完成；firstFramePresented 是 drawable 实际呈现。property/textureUpdateResult 是原 revision 的接纳回执；launchResourcesReleased 才允许结算对应来源租约。统计/截图不授播放权，exited 消息也不代替 transport 的真实进程退出。 captureFrame 在普通构建中可用；DEBUG PNG/Metal readback 是独立验证入口。

<a id="candidate"></a>
## 候选交接

1. App 接纳新意图，Host 后台准备候选，旧有效输出保持。
2. 候选 Surface 首帧 GPU 完成后发 candidatePrepared；父端核当前请求并授权 commit。
3. daemon 推广候选，保一份可回滚旧 Session；实际 presented 后由父端 finalize。
4. 失败、取消或呈现超时回滚。真实 presented 撤销本地呈现计时，父端忙不能误判未呈现。
5. finalize 后旧 Session 才退役；读取租约继续等待资源退役回执或实际进程退出。

首帧 cohort 只协调候选，稳态每屏独立提交。缺 drawable 不重跑共享 VM，也不阻塞正常屏。CPU 采用或 GPU completed 不能替代父端产品提交。

<a id="replay"></a>
## 重连与策略

client 沿公共有界退避重启端点并重放当前意图；恢复请求真正 first-present 后才重置连续故障。持续失败停止重试并反馈，旧端点或 request 的晚事件不得进入新会话。

App 的原 PlaybackPolicyController / command multiplexer 汇总用户与系统策略，daemon 执行性能配置和暂停状态，不另注册电源/前台窗口 observer。当前协议提供 profile 与 pause/resume，尚无独立 run/throttle/pause revision 协议。降低 FPS 不应按比例放慢 scene 时间，pause 冻结模拟并允许已有 GPU 完成。

<a id="shutdown"></a>
## 有序退出与强退役

shutdown 先撤新工作，再关闭 Session/worker/窗口，等待已接纳 CPU 准备和已提交 GPU 各自终态。App 只在匹配的成功资源回执或实际退出后退来源租约；有界强退由 transport 执行，不能把强杀称为 graceful drain。

request retirement 使用原协议能力协商；要求强退役时，成功回执须确认指定已知请求的准备、会话、窗口和 GPU 定义范围已经退出。未知请求或缺字段不冒充成功；该回执不承诺 AV 系统缓存、RSS 或所有外部 borrower 立即归零。

App 终止等待实际 retiring transport；回执与强退时限须能在 AppKit 嵌套主循环中投递。Session 的 CPU/GPU 关闭链归[架构退出](runtime-architecture.md#threads)，诊断 PNG 另等[导出 drain](gpu-stage-timestamp-diagnostics.md#drain)。

<a id="inputs"></a>
## 系统输入与存储

系统频谱采集/分析和系统媒体来源在 App；daemon 按实际活 consumer 发布 demand，接收同 scope 的 snapshot。候选/重建期间未知需求不偷换成 false；hidden、paused、随机 Sound 等待或 bad return 不冒充永久退休。最后真实 consumer 退出才撤原订阅。

快捷方式仅执行用户配置与合法输入 scope，不提供任意 native module 权限。daemon 帧、VM 与编码仍在主 RunLoop；后台 worker 不随意访问 QuickJS。localStorage 是同 Session 的持久服务，准备、事务和写回按[启动合同](scene-launch-responsiveness-contract.md#preparation)执行。

源码：[应用分支](../../../MyWallpaperX/App/MyWallpaperXApplication.swift)、[client](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift)、[endpoint](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift)、[Host 候选](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift)。
