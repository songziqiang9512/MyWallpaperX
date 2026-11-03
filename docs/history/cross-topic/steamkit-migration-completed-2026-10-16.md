# SteamKit 迁移完成与计划退役（2026-10-16）

> **历史证据 — 非现役入口**
> 用户于 2026-10-16 明确要求将 SteamKit 迁移作为已完成专项退役。当前职责以[Steam 获取合同](../../architecture/steam-workshop-acquisition-contract.md)、当前源码和[发布流程](../../release/release-signing.md#steamservice-build-and-signing-boundary)为准；本文不是执行队列或重新验收报告。

迁移的工程结果是 AppKit/Swift 产品状态经唯一 client 调用独立 SteamService/SteamKit，接通结构化浏览、认证、订阅、下载、持久任务和本地发布，旧 SteamCMD/社区自动登录获取职责退出。计划完成退役不表示旧 SK7 所列每项账号、发行、长稳与性能场景都已通过；未验证项保留其边界，按正常产品维护与发布验收处理，不再维持一套 SK 工作卡。

## 完成结果与既有依据

| 原阶段 | 已完成的工程结果 | 保留的依据及上限 |
|---|---|---|
| SK0 | 固定 helper/依赖与结构化能力方向 | 旧计划 §10.1/10.2 记录早期匿名查询、密码+Guard、token 恢复、订阅/收藏及单条真实下载探针；QR 只到 challenge，未完成扫码闭环。这些是当时探针，不能替代后继 App/helper 的账号验收。脱敏输入保留在 [steam-probe fixtures](../../../script/tests/fixtures/steam-probe) |
| SK1 | 有界 NDJSON、进程换代、取消与唯一 terminal | [Swift client/protocol](../../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceClient.swift)及 [helper Protocol](../../../SteamService/Protocol.cs)，现有 protocol/lifecycle 门。旧计划记录匿名读及精确 helper crash/replacement 观察，非长期 crash-loop 证明 |
| SK2–3 | 单账号认证/token owner、结构化浏览与同账号订阅状态 | [AuthRoute](../../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamAuthRoute.swift)、[BrowseStore](../../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+SteamKitBrowse.swift)、[SubscriptionStore](../../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopSubscriptionStore.swift)。普通 App 匿名列表/搜索和 QR challenge 有历史观察，未因此宣称扫码、账号 terminal 或订阅写入完整通过 |
| SK4–5 | JobStore、完整 staging identity、取消排空、receipt、队列/进度/历史与原子入库 | 旧计划 §9.1 的 2026-09-28 记录 Steam 136 tests、49 项定向回归、helper 361 checks 与隔离 Debug build；生命周期收敛另记录 83 项事务/生命周期 tests。这是历史分批结果，不合并为本次新跑计数。后继纯 ID 发布/删除与消费生命周期实现已记录在 `931f45a2`、`7f6e9674` 两批及旧计划 Git 对象 |
| SK6 | 产品切到单一获取链，旧获取源码/资源与专用状态退出 | 当前 [LegacyAcquisitionRetirement](../../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLegacyAcquisitionRetirement.swift)由服务启动调用；旧社区/SteamCMD 不作 fallback。历史 JobStore、v1/v2 库内容仍由现兼容/租约 owner 安全处理，计划退役不授权删除这些兼容数据 |
| SK7 交接 | helper 内嵌、固定运行时、签名与许可职责已交现役发布 owner | [发布边界](../../release/release-signing.md#steamservice-build-and-signing-boundary)已有正式合同；本记录不将未测最低支持机、Release 公证/Gatekeeper、完整账号/下载、20 次交互、VoiceOver、长稳、跨卷/断电与性能目标改成通过 |

旧计划还保留 2026-09-22 的安装包身份分歧：当时 `/Applications` 2.0.8 包缺 helper，隔离 Debug 候选含 bundled helper。该观察只能说明当时两份 bundle 不同，不能归因今天的安装包。2026-09-28 连续 HTTP 403 与更早 completed 记录也缺少同一完整构建身份；不据此宣称当前下载已恢复或仍失败。
