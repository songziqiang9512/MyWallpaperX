<!-- document-role: active-plan -->
<!-- retirementCondition: 失败项可见、重试、计数、空态与多选通过行为门，稳定 App 交互合同接管后归档并删除设计登记。 -->

# D7 — Steam 下载页失败条目可见性

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；合并到 `codex/engine-refactor-program` 时重新核对所列 owner。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

下载页既显示可用内容，也保留失败的下载意图及明确恢复入口；失败项不能被当作可播放文件。此次是 App Shell 数据源语义扩张，影响筛选、计数、多选和下载弹窗。本文按 Batch 2 约定存于 Web/App 文档区域，owner 始终是 app-shell，不是 Web runtime。

## 当前事实与证据

- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadFiltering.swift:9` 的过滤入口在 `:11` 只接受 `.ready`；`:28` 再做搜索，`:43` 排序。
- 同文件 `:67` 的 selection sanitation 仅以 displayed IDs 约束；放开数据源必须同时定义各批量操作的适用集合。
- `MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopDownloadsGridView.swift:244` 以可见 ID 数控制空态；`:631` 已有 ready/retry/cancel 主动作分流，不能重造另一套重试。
- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift:104` 已按账号匹配失败 job 后推进 attempt；`:416`/`:429` 记录失败状态。跨账号不能接管旧失败意图。

## owner

SteamWorkshopService/既有 job store 拥有意图、attempt、账号与状态；DownloadFiltering 拥有唯一可见列表；AppKit grid/inspector 展示状态和动作；下载弹窗展示同一 job 的进行中状态。UI 不复制 job store，不把 failure message 当稳定 identity。

## 方案设计与选型

选择**同一下载页显示 ready 与 failed，重试中的可见意图保留**。另建“失败仓库”会制造重复列表和计数；只显示 toast 会丢失恢复入口；仅删除 ready guard 又会把临时下载状态混为可播放内容。

| 状态 | 下载页显示 | 主动作 | 计数口径 |
|---|---|---|---|
| ready | 常规内容卡 | 设为壁纸/按既有 launchability | 可用内容 |
| failed | 标题、类型或未知类型、失败摘要、最后尝试时间；无封面用占位 | 重试；需要登录时进入既有登录恢复流 | 失败意图 |
| 该失败意图的 retry queued/downloading | 同一卡显示进度，避免点击后消失 | 取消，不重复入队 | 进行中意图 |
| 从未失败的新 queued/downloading | 保持既有弹窗展示，不重复新增页卡 | 弹窗已有动作 | 弹窗队列 |
| retry 取消 | 原卡回到可恢复的未完成状态 | 重试或移除记录 | 未完成意图 |

最后一行是投影状态，不把取消谎报成下载失败。稳定行键由现役账号隔离后的 workshop intent 决定，attempt 变化不创建新卡。已存在 ready artifact 又发生更新失败时保留 ready 卡及“更新失败”附加状态，播放旧有效文件，重试更新；不能用失败覆盖已验证产物或产生同 item 两张卡。投影可从现役 job 历史推导；若历史不足，下一实施片须明确最小持久化迁移，不能由临时 UI Bool 决定重启后的可见性。

搜索仍覆盖标题/描述/tag/ID；失败摘要不加入隐式搜索字段以免泄露本机路径。all 含未知类型失败；video/web/scene 只含已知类型，未知不猜。missingDependency 仍按已解析的 dependencyStatus，下载网络失败不等于缺依赖。

排序继续使用用户选项，增加稳定 ID 作为最终 tie-break；失败未知 size 放在已知 size 之后，不把它当零大小完成包。页头显示“可用 N · 失败 M · 进行中 K · 未完成 C”，搜索/筛选时另报“显示 X 项”，不改变侧栏已有“已下载”若其合同是可用内容计数。

空态：没有任何可见意图/内容为“还没有下载内容”；搜索为“没有匹配的下载记录”；类型筛选为“此分类暂无下载记录”。只有失败项时必须显示失败卡，绝不可进入空态。

多选允许选择当前可见失败项；每个动作有能力集合：重试仅 eligible failed/未完成，设为壁纸只允许单个可播放 ready，移除记录与删除本地文件语义分离。菜单显示“重试 N 项”，不悄悄作用于不可重试项。selection 始终是可见 IDs 的子集；状态/筛选/账号变化后重新 sanitation。移除记录复用现有删除确认语义，不授权递归删除失败 staging 或未知目录。

## fallback / route

错误详情缺失显示通用失败文案与 item ID；服务端/本机路径敏感细节不直接呈现。重试失败保留同卡及新 attempt 信息；账号不匹配或认证过期交给既有认证 owner，不自动换账号。UI 投影异常不删除 job/文件。以单一投影替换旧 ready-only filter，不能后台同时跑两份计数来源。

## 纠正门

- 内存 service fixture 覆盖空列表、全失败、ready+failed、未知类型、同项更新失败、重试成功/失败/取消和重启恢复；精确断言可见 IDs、状态与分类计数。
- 过滤变化、多选混合、快速重复重试、账号切换，验证 selection 不悬挂、每 intent 只有一个 active attempt、失败项从不触发 launch。
- AppKit 运行检查网格/检查器/弹窗同状态，键盘 Space/Enter、上下文菜单与无障碍标签可区分失败/可播放；执行身份和真实截图只在实施后记录。
- 实施 Swift 改动后定向 service/UI 门与 Debug checkpoint；offline 测试不证明 Steam 实际账号下载可恢复。

## 退役条件

列表、计数、动作与持久恢复语义统一且上述门通过后归档。下载页显示失败不等于 Steam 下载成功率已提高。
