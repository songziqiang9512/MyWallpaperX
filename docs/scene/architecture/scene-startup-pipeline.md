# Scene 启动接线与证据入口

<!-- document-role: current-state -->

> 源码复核：2026-10-23。这里保存当前接线与工具边界，不维护执行顺序或历史性能数字。
> [启动合同](scene-launch-responsiveness-contract.md)拥有稳定语义；[冷暖启动专项](../../development/wallpaper-startup-optimization-plan.md)拥有用户指定改进步骤；运行结果仍从[证据索引](../capabilities/runtime-evidence-current.md)进入。

## 产品入口与执行所有权

`SteamWorkshopService.requestSceneRender → 原产品切换事务 → SceneDaemonClient → daemon 内 Host → 后台 prepareLaunch → Session/每屏 surface → 实际 presented → 产品 finalize`。

WallpaperManager 拥有产品意图和跨引擎提交；Host 拥有 Scene 执行候选/提升，Session 拥有 VM/clock/provider/资源与 GPU 排空。候选 prepared、实际 presented 和产品提交是不同事件。

Scene→Scene 请求可复用仍存活的 transport；stop/跨引擎停止会 shutdown 并退租。`warmSession()` 已有握手预备，App 延后触发受 active/requested Scene 意图约束；不是每次会话都重新孵化，也不是无条件常驻保温。事实落点见 `AppDelegate.swift`、`SceneDaemonClient.swift` 和[daemon 合同](scene-runtime-daemon-contract.md)。

## 当前准备与缓存落点

- 每次 launch 仍进入 ModelBuilder/SourceFacts。package 路由使用全量 extractor；命中前完整包/entry 摘要与缓存读取比较。ResourceView 为 package/loose/stock 建索引，Host 仍要求 package cache URL。专项 P2/P3 是替代目标，尚未实施。
- CPU 前端/作者 preparation、generic/demand/variant 和外部编译产物已存在持久缓存；按完整来源/规则/工具身份校验。binary archive 已接线，不能说尚无 shader 磁盘缓存。
- 固定 pipeline、base texture 有共享；authored library/PSO 存储仍在各 encoder。初始隐藏资源延后、CPU/GPU 准备重叠已存在；同 launch 成功产物共享是专项 P4 的待实施范围。
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
