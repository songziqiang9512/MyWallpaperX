<!-- document-role: active-plan -->
<!-- retirementCondition: App 唯一 power 裁决与版本化三态 IPC 验收，旧重复观察和布尔适配撤权后归档。 -->

# D9 — 宿主到渲染的 run、throttle、pause 协议

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；合并到 `codex/engine-refactor-program` 时重新核对所列 owner。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

App 汇总用户意图、系统中断、窗口/电源策略，向 Scene 渲染进程发送唯一有效结果：run、throttle 或 pause。渲染端执行命令，不自行推断电源/窗口状态。跨 App policy、IPC、session clock 和 frame driver，触及唯一时钟/暂停裁决。

## 当前事实与证据

- `MyWallpaperX/Core/PlaybackControl/PlaybackPolicyController.swift:5` 已声明唯一 macOS policy observer；`:94` 计算 pause，`:97` 交 PlaybackCommandMultiplexer。
- `MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol.swift:27` 已有 pause，`:204` 解析；`SceneDaemonClient.swift:191` 接 paused Bool，`:479` 重发状态；`SceneDaemonRuntime.swift:328` 消费 pause。
- `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+FrameDriver.swift:80` 根据 sceneClock 停止/保留首帧重试。现有边界已经部分满足目标，不能再造 PowerController。
- 交接的 Mirage clock-3/4 是结构候选；此基线 [Mirage 文档](../semantics/miragewallpaper-rendering-reference.md) `:402` 只提供时间职责参考，不证明新的协议必要性或官方时序。

## owner

PlaybackPolicyController/PlaybackCommandMultiplexer 为唯一裁决与 fan-out；SceneDaemonClient 是唯一序列化发送 owner；daemon session 接收最新结果；现役 sceneClock 与 frame driver 执行时间/调度。renderer 不注册额外电源、前台窗口或电池 observer。

## 方案设计与选型

选择**扩展既有 typed command**；不另开 IPC 通道，也不把 App 原始事件逐条传到 renderer 重判。

| 状态 | 执行语义 |
|---|---|
| run | 按宿主下发的有效 FPS 运行；仍受现役资源/提交预算约束 |
| throttle | 使用宿主给定的较低 FPS；scene 时间按真实经过时间与既有 bounded delta 前进，不能把动画速度按 FPS 比例放慢 |
| pause | 冻结 simulation/script 时间与常规 tick；已有在途 GPU 允许完成；保留现役有界首帧/必要显示刷新，不重放暂停期间的模拟债务 |

命令携带协议版本、session/intent epoch、递增 revision、mode 与已验证 target FPS。reason 仅诊断，不能被 renderer 再次判定。App 合成优先级：显式用户暂停或系统强制中断高于 throttle，高于 run；多屏差异由 App 为各 session 发结果。数值合法域复用现役 FPS 设置范围，throttle 不得为零或高于有效 run 上限。

同一 epoch 内只接受更新 revision；迟到旧命令无副作用。新 daemon 完成握手、尚未激活前取得完整当前状态；断线恢复不默认 run。IPC 版本不支持三态时：pause/run 映射既有命令，throttle 映射 pause 作为保守兼容并报告不可用；不能静默当 run。版本与 route 在握手固定，不每帧协商。

throttle 的具体 FPS 和触发条件是 App 设置政策，本设计不新增“自动低电量 15 FPS”等无授权产品规则。只在确有 App 可表达的 throttle 需求时实施第三态。帧门与短重试只由 [D10](frame-admission-retry-design.md) 执行；频繁 policy 事件合并为最新 revision，不累积待播放命令队列。

## fallback / route

协议/epoch 非法拒绝该命令并保持最后有效状态；连接失联按现役会话中断策略暂停/退出，不能由 daemon 推测用户意图。执行端错误保留最后安全画面，App 得到不可用反馈。迁移适配期只由 multiplexer 选一个结果 route，删除旧命令直写点后转 `generic-only`。

## 纠正门

- 伪造 policy 输入验证 pause>throttle>run、设置变化和多屏独立命令；渲染端不重复观察系统。
- 真 IPC/会话 fixture 注入乱序 revision、重复命令、旧 epoch、断线重连与低版本 peer；首次可见帧已使用当前策略。
- 时间门检查 throttle 下动作时长、pause 的零模拟推进、resume 无追债；GPU completion 不因 pause 丢失，取消的 timer 不在新 session 触发。
- 物理电源/锁屏/全屏/多显示器与三次同窗口 CPU 基线在实施后按风险执行；仅模拟策略不声称节能已达成。

## 退役条件

协议纳入稳定 daemon 合同，重复 observer/直写暂停已撤权，握手与跨版本恢复验收后归档。无第三态需求时保留此设计而不制造空转代码。
