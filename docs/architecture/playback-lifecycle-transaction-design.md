<!-- document-role: active-plan -->
<!-- retirementCondition: 三引擎退出、可见交接与唯一产品事务实施并完成有界验证，稳定合同接管后归档。 -->

# 播放进程退出与统一切换事务

状态：2026-10-18 已按退出闭环、可见确认、产品事务顺序实施；冻结源码的有界验证和用户测试分别记录，不表示所有作品、设备或长期运行已验收。

## 目标与取舍

保留 Video、Web、Scene 的独立播放进程和作者样式，改善正常退出、异常父死亡和跨类型交接。最小结果是所有播放进程有独立退出兜底、旧输出保留到新输出可交接、所有产品提交经同一意图事务；快速撤销和失败仍恢复此前已提交内容。无需主 App 每帧许可。

参考评估只提供结构依据。先补现役 DaemonKit 和执行端，不新增完整进程平台、精简 executable 或 Scene 渲染线程迁移。每屏异类作品、全作品兼容、物理 Space 零停顿、长期能耗与官方像素一致不属于本片验收。

## 一、退出闭环

- DaemonKit 是进程物理生命周期的唯一公共实现；引擎保留请求、重试和资源租约。播放 transport 明确登记，物理清单覆盖 active、candidate、空宿主和 retiring，不能以字典移除冒充进程退出。非播放 Steam/编译服务不受播放退出登记影响。
- 子进程在 AppKit/内容初始化前安装父进程退出事件，入口及注册完成时核实际父进程，覆盖安装竞态，不常驻轮询。正常 EOF、父死亡和握手期间失联进入同一有界退出路径：子主循环撤输入、音频、窗口并回收 GPU，主线程堵塞仍有独立后台硬截止期。只作用于自身进程，不能按名字终止其他实例。
- 主 App 退出先关闭新播放进程准入并撤销意图/异步任务，再向三引擎发正常停止；所有精确登记进程共享墙钟上限并并行回收，按正常停止、TERM、KILL分级。AppKit terminateLater 的回复必须在实际退出后完成；异常无法退出要有明确失败状态，不能静默宣称成功。
- 资源租约保持到实际退出或既有 CPU/GPU 释放确认。退出回调、取消和升级终止均幂等；过期 PID、旧 transport 回调和旧完成不能影响新实例。
- Web worker 若后续采用退休复用，只允许在原事务已退休 endpoint、该 execution 的 producers/授权撤销且任务 drain 后，用精确 instance/request/session/reset 身份 ACK 结清资源；ACK 不冒充进程退出。空闲 worker 仍登记于原进程 registry，App 退出继续等待实际退出；协议未迁移前保留原一次性进程合同。 当前未采用 WebView 退休复用；原成本 STOP 与设计依据见[完成记录](../history/cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md)，不由历史设计自动重开。

启动专项 D23 的 Scene 保留只服务已提交 Web/Video 后的短时重入：原 retire 接收可选后继 ticket，只有真实 handoff 提供，普通 retire/Stop 不授保留。原 Host 精确请求 CPU/任务/GPU 成功终态、窗口撤回、空 owner 与能力协商共同授权原 transport 的最多30秒空闲，原控制屏障和 source lease 在成功或真实退出后才结清。失败和到期沿原精确退出；新 Scene 捕获当前来源和读取租约并获新请求，旧 ACK/timer 不操作后继。下一非 Scene 意图撤 idle/强退役保留，仍有回滚职责的 active Scene 保持；原 App 装配让 Scene 保留/真实退出中的事实抑制 Web 可选空预热，并取消非 Web 意图的已有空预热，不另建槽调度器。Web 两槽只指原 adapter 角色，跨引擎、多屏与有界 retiring 不承诺全局两物理 PID。原 registry 继续登记，普通 App quit 仍等物理退出；详细合同见[Scene daemon 合同](../scene/architecture/scene-runtime-daemon-contract.md)。已接入并完成限定请求/退出运行，实际验收范围与未覆盖项按[运行证据](../scene/capabilities/runtime-evidence-current.md)和[专项结算](../history/cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md)解释，不授整体性能通过，原点归[D23历史](../scene/history/scene-startup-d23-2026-10-25.md)。

## 二、可交接确认

- 新 Web 保留每屏 snapshot preparation；新 Video 保留 AVPlayerItem/AVPlayerLayer readiness。激活后逐目标屏核对窗口身份、目标几何、alpha、层级和 WindowServer onscreen 状态；有界重试绑定 request、surface/preparation generation。不能把 onscreen 叫物理视频帧呈现。
- Web/Video 激活临时使用 desktop + 2（仍低于桌面图标），确保新输出不会被旧 Web 窗口覆盖；旧端点退休后 finalize 恢复原层。当前不在活动 Space 的表面不冒充上屏成功：激活有界退出并保留旧壁纸，不持续轮询；用户重新选择可重试。
- Web 原生媒体恢复 completion 也属于激活代际，失败、超时、拓扑改变或导航替换撤销该确认。只有所有目标窗口和媒体状态就绪才发可交接事件。
- 候选准备期间静音且不拥有输入。统一事务在旧输出撤音频/输入与新输出启用之间安排有序交接；旧画面可继续保留。激活失败恢复旧策略，不覆盖用户暂停、音量、显示和属性的新值。
- Scene 保留真实 drawable presented，不降为一般窗口 ready；既有本地呈现截止期与父端 finalize、GPU drain/版本租约合同继续成立。

## 三、唯一产品事务

唯一产品意图/提交 owner 仍为 WallpaperManager，其拥有一个 typed 切换事务状态；App 只装配端点和入口，不通过 Shell 通知另存 Scene handoff 身份。Core 的事务状态只描述 epoch、runtime、执行请求/目标显示集和阶段，不接管作者资源、graph、窗口或播放器。

数据流：用户选择 → Manager 新意图/事务 → 引擎准备 → 同请求全部目标 prepared → 旧输出撤音频/输入 → 事务授权激活 → 引擎专属可见确认 → 事务提交产品投影 → 旧端点退休完成 → finalize 新端点。失败或新意图按精确身份撤候选、恢复旧输出；旧终态不能提交新选择。端点提供准备、激活、回滚、确认和退役事实，不能自行改变跨引擎产品真值。

- Video 多屏 cohort、Web surface generation、Scene wire UUID/实际呈现保持各自权威，由事务绑定，不使用路径或 recordID 单独作为完成身份。
- 已提交内容的崩溃恢复、同内容属性重建和拓扑重建属于执行代际更新，不能成为新的用户选择或抢占正在准备的新意图；保留已提交输出的修复须有明确路由。
- 候选失败与已提交输出最终丢失分别报告。后者仅结算匹配的已提交票据，保留更新选择；退休屏障未完成时保留一次性可见证明，等待后再提交，不能丢证明或越过退出屏障。
- 同内容健康复用也结算事务；已结束 Video 必须建立新播放身份。暂停、自动切换、ended、失败回退、删除/停止及启动恢复仍沿同一选择权威。
- 静态图片应用纳入同一提交出口；先收集每屏实际成功结果。全部失败不退休动态输出，部分失败必须明确保留/恢复政策，不能用 try? 后无条件提交。
- 迁移时撤销 MainWindowCoordinator 的播放状态与 Scene handoff 字段；原 runtime 切换通知只投影已提交事实，不再触发另一个隐藏的退休决策。引擎内部的 slot、候选与 drain 仍是执行事实，不能演变为第二产品切换 owner。
- 系统音频采集按执行端存活的真实需求聚合。配置在恢复播放前沿原 Manager seed 一次，后续只投影真实设置差分；新 helper 的 play 载荷完整，不靠每次播放重推或延迟补配 timer。Web 准备无需等待产品 ID 提交，旧端点退休不能撤销后继需求；最后一个未提交候选取消也必须发布需求归零，空宿主不申请采集。

## 失败、退出与验收

先做退出故障注入：正常退出含候选/预热/retiring、父 SIGKILL、子主线程阻塞、初始化期父退出、重复停止及新实例隔离。再验证 Web/Video 错屏/不可见/低alpha/旧代际、媒体 completion 延迟/失败、激活超时与旧输出恢复。最后以相同事务测试六方向、同类型、A→B→C、取消/失败、恢复/拓扑、静态图失败、同路径重选及结束事件。

Swift 产品变更做签名 Debug 构建；所有测试从固定 HEAD 加 owned diff 的隔离源运行。真实音乐、代表 Web/Scene 只读副本和生成 Video 通过正式产品入口验证画面、音频/输入归属、进程真实退出和无焦点/Dock回退。独立子代理对最终冻结差异和证据做对抗审查，有问题直接修并复验；最终启动新版正常实例供用户测试。本轮不提交、不推送。
