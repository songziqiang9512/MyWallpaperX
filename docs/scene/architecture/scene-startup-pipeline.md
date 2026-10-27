# Scene 启动接线与证据入口

<!-- document-role: current-state -->

> 本页保存接线与工具边界；精简代码的当前实现、构建、代表运行和剩余验证统一查[精简计划](../../development/validation-simplification-plan.md)，不在本图重复维护过期批次状态或历史性能数字。
> [启动合同](scene-launch-responsiveness-contract.md)拥有稳定语义；当前按[全仓精简方案](../../development/validation-simplification-plan.md)清退误拒播与重复工作。此前冷暖启动[完成记录](../../history/cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md)只证明当时版本；运行结果从[证据索引](../capabilities/runtime-evidence-current.md)进入。

## 产品入口与执行所有权

`SteamWorkshopService.requestSceneRender → 捕获当前记录/source/读取 lease → 原产品切换事务/SceneDaemonClient → daemon 内 Host → 后台 prepareLaunch → Session/每屏 surface → 实际 presented → 产品 finalize`。属性 Request 使用同一当前来源入口。播放不升级 receipt、不复制目录、不重核历史入库摘要；下载出版、读取与退出边界归[启动合同 §4.1](scene-launch-responsiveness-contract.md#41-唯一请求与准备-owner)。

WallpaperManager 拥有产品意图和跨引擎提交；Host 拥有 Scene 执行候选/提升，Session 拥有 VM/clock/provider/资源与 GPU 排空。候选 prepared、实际 presented 和产品提交是不同事件。

Scene→Scene 请求可复用仍存活的 transport。仅已提交 Web/Video 的合格 handoff，在精确请求强退役成功且 Host 已空后，可沿原 Client 保留该 transport 最多30秒；新非 Scene 意图只撤销已有空闲或在途保留资格，active Scene 的候选与回滚仍沿原提交事务。普通 Stop/quit、失败、非保留退休及到期走原物理退出，Scene 新请求重新准入来源与 lease。Web 可选空预备与此保留互斥，真实 Web 请求不受阻断；实际组合及未覆盖范围以[运行证据](../capabilities/runtime-evidence-current.md)为准，具体准入归[daemon 合同](scene-runtime-daemon-contract.md)。`warmSession()` 保持原受 active/requested Scene 意图约束的握手预备，不是无条件常驻保温；事实落点见 `AppDelegate.swift`、`SceneDaemonClient.swift` 和[daemon 合同](scene-runtime-daemon-contract.md)。

## 当前准备与缓存落点

- 每次 launch 进入 ModelBuilder/SourceFacts。父端捕获当前版本 lease 与 ScenePlaybackSource，经原请求、Shell 和版本化 IPC 交给 daemon。SourceFacts 建立当前 loose Root，包沿同一 Reader/FD 一次索引、单一逻辑 Root 按需读 entry，命名与局部失败归[启动合同](scene-launch-responsiveness-contract.md)。坏包不挂旧提取目录，完整 loose scene 仍可播放；当前来源变动、无效句柄与取消保留原失败语义。属性准备沿同一来源输入，lease 持有到实际工作退出或交接。
- 同 Root handle 供 shader、结构/播放 JSON、模型、TEX/直接图片、粒子定义、字体和媒体使用；package 保完整 literal namespace，ordinary index 仅投影可见项。固定 bundled stock 共享成功 Root/index，粒子定义图沿 LaunchContext 传给各 surface 建立自身 GPU/模拟。目录缓存身份是当前文件 revision，包缓存身份是当前包 revision 与 entry 范围；命中不再读取全文/哈希，实际读取保路径、范围、稳定性和取消检查。
- Host 在既有 launch 直接构造 App 私有 cache 根，经独立 privateMediaCacheDirectory 供 Sound、TEX MP4/WebM、material video 与初始/动态外部属性 video 写私有池，作者 cacheDirectory/ResourceView 不换。原 OwnedFile 统一 8GiB 进程磁盘预约，计入 partial、已发布文件、worker 和最后 AV asset 借用；已知长度先预约，WebM 保原 VP9 passthrough，以公开 segment delegate 向受控 FD sink 逐段预约后写入，完成才交付。Sound 保原 asset/item 构造与创建时 pin；Video 保原 URL item/活跃路径，仅有效 stop 后在取消/replace/nil 前交接给当前 asset。pin 不等于通用 AV drain，也不承诺 native workspace/RSS 归零；跨 provider 文件 single-flight 未采用，成本不足时保持 STOP。字体/deferred 和无 Session 的 launch 队列尾仍归原退休链。限定接线不代表全部回归、首帧收益或完整 P2 验收，阶段与未解 seek 查[专项结算](../../history/cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md)。
- 目录纹理 snapshot 交付同 FD 的 bytes 与 FileIdentity，原 Loader 以所选 Input 解释 TEX/图片、尺寸/opacity 与嵌入视频声明。direct encoded bytes 的留存仍计原 decode budget，领取后移出队列；超额只保 metadata，GPU 读取时以原身份确认当前来源。已备 GPU 结果按原 selected Input/device 采用，不在主线程重读作者文件。sameRoot raw sidecar 与外部用户文件 scope 保原边界，来源硬错/取消不重选其他根。本轮行为和性能复验完成前，不用旧 D4 证据宣称当前无回退或提速。
- CPU 前端/作者 preparation、generic/demand/variant 和外部编译产物已存在持久缓存；按完整来源/规则/工具身份校验。binary archive 已接线，不能说尚无 shader 磁盘缓存。
- 固定 pipeline、base texture 有共享；authored library/PSO 存储仍在各 encoder。初始隐藏资源延后、CPU/GPU 准备重叠已存在；同 launch 成功产物共享未采用，专项 P4 因已测重复窗口不足而 STOP，只有新的实际热点证据才重开。
- 属性 preparation 的单份 context 有独立身份、预算与关闭/压力失效；它不是可直接驻留复用的产品 RuntimeModel。

当前 owner 查[源码职责图](runtime-as-built-map.md)，完整资源、identity 与释放边界查[运行架构](runtime-architecture.md)。模型预解析与 device 保温的旧否决仅保其成本/风险依据，新方案须重新证明收益，不把历史“暂不做”当永久禁令。

## 测量入口与边界

- `MWX LAUNCH-STAGE` 含多个累计起点，异步/嵌套区间不能机械相加。产品总账从 selection 开始，accepted、prepared、presented、finalize 分段绑定同 request。
- `scene_wallpaper_benchmark.py` 默认 direct Host；runner ready 不是物理首呈现。`--keep-runtime` 只保本轮目录，暖测须实际复用同 HOME/cache 并另记 daemon PID。
- `DebugSceneDaemonClientRunner` 已监听实际 first-present；沿现产品入口补完整时间线，不另建执行旁路。正式统计、噪声和失败反例由[性能卡](../roadmap/performance-convergence-card.md)与专项定义。
- 普通产品、优化 Debug 观测、历史结果分别报告；没有本轮 cold/warm 数据就不认当前提速或全样本通过。

## 历史快照的永久入口

旧正文整体保留于历史；以下锚点仅供既有引用定位，不恢复其中任务顺序或当前状态。

<a id="1-两条启动路径"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#1-两条启动路径) <!-- archive-redirect -->
<a id="2-启动阶段表launch-stage-标记"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#2-启动阶段表launch-stage-标记) <!-- archive-redirect -->
<a id="3-暖启动持久层导航"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#3-暖启动持久层导航) <!-- archive-redirect -->
<a id="4-daemon-预热l1"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#4-daemon-预热l1) <!-- archive-redirect -->
<a id="5-按需加载与失效域"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#5-按需加载与失效域) <!-- archive-redirect -->
<a id="6-测量方法与已知陷阱"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#6-测量方法与已知陷阱) <!-- archive-redirect -->
<a id="7-当前边界与未验收项"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#7-当前边界与未验收项) <!-- archive-redirect -->
<a id="preparedcontent-预解析场景-a已评估决定暂不做2026-09-30"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#preparedcontent-预解析场景-a已评估决定暂不做2026-09-30) <!-- archive-redirect -->
<a id="scene-启动流程与运行机制启动专题"></a> [归档记录](../history/scene-startup-pipeline-before-optimization-2026-10-23.md#scene-启动流程与运行机制启动专题) <!-- archive-redirect -->
