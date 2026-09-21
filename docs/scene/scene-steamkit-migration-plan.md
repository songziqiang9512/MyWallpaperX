# SteamKit 统一创意工坊：浏览、登录、订阅与下载改造计划

<!-- document-role: active-plan -->

> 状态：现役专项计划。SteamKit 已有唯一 App→client→helper 查询／认证／下载链；公开内容发布 owner 已从隐藏 `.mywallpaperx-steam-versions` 迁到 `Video/Web/Scene/<WorkshopID>-<UUID>`，下载使用 descriptor identity、`jobs-v5.json` 与 `download-staging-ack-v2` 保护持久化先于写入，旧 v1 只读迁移及 previous-current 回收边界仍保留。2026-09-21 已复核 current helper 匿名列表／搜索与 QR challenge 发起，并闭合 helper 重启预算耗尽后的显式匿名读取恢复；本批又确认默认 featured/week 空页来自错误的 Swift `timeCreated` 后过滤，现已移除该第二语义 owner，把 1...365 日 `trendDays` 经唯一查询链交给远端排名，并以 `query-trend-days-v1` 阻止新 App 对旧 helper 静默退化。真实扫码／密码／Guard 终态、token 恢复、已授权真下载、迁移后播放、长期回收、普通 App 趋势页视觉验收、发行公证、最低支持机与完整性能矩阵仍待继续。本机 `/Applications/MyWallpaperX.app` 仍是缺 helper 的 2.0.8 (269)，未获授权不覆盖。当前下一批为音频剩余 no-demand／频谱公共能力，之后依次为丁达尔射线、粒子、鼠标点击／轨迹／X-Ray；隐藏 v1 根最终退役仍开放。
>
> 复核（2026-09-20 实现批）：该批依据当时的 Swift/C#、隔离文件系统 v1→v2 迁移／公开发布／generation identity／失效 marker fail-closed／lease／回收竞态／暂存 inode 清理／容量门反例、101 项 Steam 维护测试、Developer ID Debug 构建、自包含 bundle helper 直接匿名查询，以及候选 App 普通创意工坊 UI 的列表／搜索／二维码 challenge；初审的 4 项 P1、3 项 P2、首轮复审的 2 项 P1、2 项 P2，以及第二轮复审补出的 resume 前写入与多前代 sidecar 重放问题均已修正并补验证。最终产品／测试冻结 diff `e035e5c608529966a5e924f6954efbb7d7e4a3c1a1890e531a060cab1141aa30` 经独立只读复审 APPROVE，P0–P3 无遗留 finding；其中最后一个冗余源码形状断言 P3 已删除，行为 fixture 保持。该日运行归因的 docs-only 冻结 diff `b003f52e5bd0a9f57b24bf2e0425a801a5785a0fb9506aeb8b0553005843893b` 经另一名独立只读审查者检查代码、打包接缝、三份 App identity 与本机证据，首轮 2 项 P2 和复审 1 项 P3 均已修正，最终 APPROVE、P0–P3 无遗留 finding。
>
> 复核（2026-09-21 当前候选运行归因批）：基线 `d4d4d5bf`，唯一 tracked owned path 为本文；首轮 tracked diff SHA-256 `9db415dce8bda30f275b903357ecd8864f8a4949da82129dc54470b30528c64d`。ignored summary manifest 为 `docs/scene/evidence/v1/steam-current-candidate-recheck-2026-09-21/manifest.md`，修正后 SHA-256 `8446eec09af79c1ef7b1452eaf1e6668df98d5a902e2e022977a8f5f4bf657d5`。首轮独立只读审查以一项 P2、一项 P3 阻断：顶部复核 provenance 仍把 9 月 20 日实现批写成当前批，且本轮缓存只有观察摘要、没有保留 raw helper/test/build 输出或脱敏 AX snapshot。现役修正分开两批审查身份，并明确本轮运行数值只能作为观察者记录；不把 summary manifest 冒充可重放原始记录，也不因此重跑或制造数据。修正版 tracked diff `6630e311ee454dbae6cd8ac1d82d7f2c93d229c8b712d9d07cc4127feaacea73` 经同一名独立只读审查者复核 APPROVE，P0–P3 无遗留 finding；该批准只覆盖文档对当前代码、保留候选 identity、观察事实和证据上限的忠实表达，不升级账号或下载验收。没有提交账号凭据、没有完成登录、没有修改真实订阅或真实壁纸库，也没有实测已授权真下载、真实库启动迁移、迁移后播放与低配／完整 App 性能。§10.1 保留早期探针证据，不能代替当前候选的未执行场景。
>
> 复核（2026-09-21 公开入库与缓存回收运行批）：基线 `2eacca1b`，唯一 tracked owned path 为本文；ignored raw-evidence manifest 为 `docs/scene/evidence/v1/steam-publication-recheck-2026-09-21/manifest.md`，初始 SHA-256 `9d77ba0b950e779eaf584daba3ce729d71c3aa57570367954e06bbd999425a7b`，首审修正后 SHA-256 `1d7f0175a195fd06f950d21b1a6f542ac2fab3ed380c3a04be0719d9f2ebad50`，真实 staging 证据收紧后 SHA-256 `230c4bab8c3e147a0c09925e626a9083e3366c74e6065df917f8c9c980f3c945`。本批没有产品代码改动；fresh 2.0.9 (277) Developer ID Debug 构建、strict/deep 验签、三模块 50 个测试方法、真实库只读 census 与两次隔离 App 启动 v1→v2 迁移均保留 raw evidence。独立首审以一项 P2 阻断：第一份 raw audit 没有冻结 116 份 metadata 的完整分类／解析失败数和真实库前后哈希输入；复审又指出空的真实 Application Support staging 没有显式哨兵，不能冒充 App before/after 输入。修正批重新执行隔离启动迁移，逐文件冻结 Workshop metadata/marker/hidden/incoming before/after；首个比较误把 `snapshot=before/after` 标签纳入哈希而 exit 4，现保留该失败并只归一化首行标签，剩余快照字节相等、SHA-256 均为 `54eaa1ca282005719172f6855a214a21bdb52754d1eda71083fbddbfb157daf2`。真实 Application Support staging 只由两次紧邻的运行后只读快照显式记录 `EMPTY`，不声称是产品运行前后证据。另一次在首个构建仍占用同一 DerivedData 时发起的重复构建以 build DB locked/exit 65 失败并如实保留；首个 fresh 构建随后 `BUILD SUCCEEDED`，两项编排噪声均不冒充源码失败或通过。修正版 tracked diff SHA-256 `fbc31a5d9057b036a00bd7beab4f52eba0d42c0b2099b1a41a05a51a2f75ab37` 经同一名独立只读审查者复核 APPROVE，P0–P3 无遗留 finding；批准只覆盖当前公共发布链、真实库 census、两次隔离 Scene 启动迁移及证据边界的忠实记录。没有登录、订阅、helper 真下载、真实库写入或迁移后播放；Scene 产品启动迁移不能替代 Video/Web 产品运行、24 小时回收、跨卷／断电和发行门。
>
> 复核（2026-09-21 current-HEAD SteamKit 无账号重查批）：基线 `22e6835f`，唯一 tracked owned path 仍为本文；本批没有产品代码改动，ignored summary 为 `docs/scene/evidence/2026-09-21-steamkit-current-head-recheck/manifest.json`。首轮 tracked diff／manifest SHA-256=`d9232431d159bf12ccca1975ac682989fdbfd6d0cef03573e646ea3013a4bdfc / a557ab6ff50c3b017fc016a8f6c281bb234e84dafee60d09b708f6a58e893ea7`，独立只读审查以两项 P2 阻断：顶部 next action 与本轮顺序冲突、§9.1 把复用的 audio-build 候选误写为本批 fresh build；summary 又漏记 stale account epoch 负例及成功流的 process/account epoch、same-attempt cancel 和唯一 terminal 关联。修正后 tracked diff／manifest SHA-256=`ee138cff5d2ad06e2e6719b58322d10333f7a92489400b1c56d6bc6b63927bfe / a05670d7162a25df100ad820f184e4e6eef27ac75e8869521cf45bd5e1704bea`，两项 P2 均关闭；复审追加的一项 P3 要求把本批审查身份写回现役计划，本段即为该收敛。最终纯追溯复审结论为 **APPROVE / P0–P3 无遗留 finding**；批准只覆盖 current-HEAD bundled helper 的匿名首屏、QR challenge 发起／定向取消、旧安装身份分歧与证据边界的忠实表达。普通 App UI 仍引用 `d4d4d5bf`，公开迁移仍引用 `2eacca1b`；本批未扫码、未取得账号 terminal/token、未订阅／下载，也未重跑普通 UI 或发行包。
>
> 复核（2026-09-21 Steam 公开查询恢复批）：基线 `65ee316b`，owned paths 为 `SteamServiceClient.swift`、`SteamAuthRoute.swift`、compiled lifecycle fixture 与本文。首轮冻结 diff SHA-256=`b69d1c63614f2563d11e2c9b105ae061bcdae8a6cfb13047467d14b3f3c9c9d9`；独立只读首审以两项 P2 阻断：`.terminated` 恢复被错误放宽到所有命令，且 fixture 未冻结并发公共重试的单 generation、恢复后重置且仍有界的自动预算，本文还把没有跑到的第二个修复前断言写成行为红证据。修正后只允许 browse/details/author 三个匿名读取命令从 `.terminated` 的显式 request 进入既有 `start()`；账号／写入／下载／control 保持 fail-closed 并经过原 intent/session owner。compiled fixture 另冻结 `listSubscriptions` 不能复活 helper、两个并发读取共享第三 transport、恢复后恰一个第四自动 replacement、下一次 crash 重新 terminated。当前实现候选 SHA-256=`3c9b6bbafcdd906255b90cf1b36192eab881447f5754df6c71b2c637b96ccf18` 经同一审查者复审 **APPROVE / P0–P3 无遗留 finding**。最终 Steam 维护全集 125 tests 及 helper protocol/auth/manifest/staging/download/query 自测均通过，标准隔离 Debug build `BUILD SUCCEEDED` 并实际 restore/publish/embed SteamService；修复前行为红证据只覆盖匿名 disconnect/epoch，terminated notReady 明确是静态调用链断点。ignored evidence manifest 在纯追溯前 SHA-256=`af45a2fc22d3d07687376b9536c9e4db6b92423ce86a9e9c9e3e511c6b6122d0`。本批未执行异常序列的普通 App UI，也未扫码／密码／Guard、取得账号 terminal/token、订阅、真下载、安装覆盖、发行或低配性能；本段写回形成新的 docs-only diff，须经只读追溯核对后提交。

> 复核（2026-09-21 Steam 趋势时间窗批）：基线 `3b8daa7a`，owned paths 为五个 Swift 查询／协议 owner、五个 C# helper 查询／协议 owner、四个 fixture／测试与本文。首轮冻结 tracked diff SHA-256=`ac8f1b69678e5adf109ef221bbb4e1d1ba8fbede6b45bba1bef76235fc6f91ba`、ignored manifest SHA-256=`3c10d518a49d9c3f61a17cf40225e0587fae07c686df56eb723605c4f1b646cb`；独立只读首审为 **REQUEST CHANGES**：一项 P2 指出缺 `query-trend-days-v1` 的负例只测通用 client 门，无法捕获 `SteamWorkshopQueryClient` 漏传 requirement；一项 P3 指出查询 owner 注释仍声称 `days` 是缺口。修正后的 compiled fixture 让同一旧 helper 身份先完成 featured/allTime 且 payload 无 `days`，再对 featured/week 于 wire send 前返回 `incompatibleProtocol`，发送计数保持 1；入口注释改为 1...365 远端排名与能力门合同。首版反例用非十进制 fixture ID 被严格 decoder 正确拒绝，改为 `77` 后定向 2 tests 及 Steam 维护全集 20 modules 均通过。修正候选 tracked diff SHA-256=`1bef4e817264b0363c86a154003ed8ec1f72638e9cd6bb48536a5720d4f4b99c`、manifest SHA-256=`13158b9ffdb323d48e2099b14e3d8d294e86db1f7b45c0ab5413de0ff5d1495f` 经同一审查者复审 **APPROVE / P0–P3 无遗留 finding**。fresh helper 同时通过 protocol/query 27/27、1/7/30/365 日真实查询与非法／畸形输入拒绝，标准 Debug checkpoint `BUILD SUCCEEDED` 并嵌入当前 helper；文档三门 32 tests 通过。批准不覆盖普通 App 趋势网格截图、多页人工滚动、真账号、真下载、发行或低配性能；本段及 manifest 的追溯写回不改变已批准实现，提交前只需再核对追溯忠实性。
>
> 复核（2026-09-21 incoming 取消回滚批）：基线 `11c3bd34`，owned paths 为 `SteamWorkshopLibraryTransaction.swift`、`test_steam_library_transaction.py` 与本文；首轮冻结 diff SHA-256=`7c83e631ea6d083af7d14840ebd0c6e1db9ac20dd24ef2444851d627a32156fe`。旧代码在 64 MiB 受控复制已出现本批 incoming UUID 后取消，稳定留下该 UUID；实现只让 exact descriptor-bound defer rollback 忽略 sticky task cancellation，普通 staging／reclamation 仍可取消，并记录非取消型回滚失败。修后新反例、受影响三模块、全部 20 个 Steam 维护模块及三项文档门均通过；checkpoint focused tests 通过，聚合门只被批外既有 code-health ratchet／超限债务阻断而未自动构建，随后标准隔离无签名 Debug build `BUILD SUCCEEDED`。独立只读首审为 **REQUEST CHANGES**：一项 P2 指出取消反例会把任意清理干净的非取消错误误判通过，另一项 P2 指出顶部与 SK7.1 lead 的 next action 已落后；一项 P3 要求把本批身份、验证和审查边界写回现役计划。测试现只接受 typed `CancellationError` sentinel，入口已指向 durable staging acknowledgement；修正候选 diff SHA-256=`a8d39190de74fa7d2fd0b83a497164d80e0046734f7dbf0333890901f4329d36` 经同一审查者复审 **APPROVE / P0–P3 无遗留 finding**。批准只覆盖 exact incoming rollback、行为反例及文档忠实性；这仍不是账号真下载、可见播放、Video/Web 产品迁移或发行验收。
>
> 权威：本计划细化[工程路线 E2/E6/E8](engine-refactor-program.md)，覆盖 Video/Web/Scene 共用的 Steam 内容获取，不改变播放器。本文覆盖此前“双网页登录/自动弹登录/保留订阅 HTML 主路径”的方案。
>
> 退役：SK0–SK7 完成、SteamCMD 与自动社区登录/个人列表抓取产品路径撤除、交互/数据/发布门通过后，稳定合同和功能证据接管终态，本文转历史。

实施从 [§8 工作卡](#work-cards) 的当前剩余项开始；产品交互约束查 §3–§4，数据/协议边界查 §5–§7，完整验收查 §9。不要先实现整个平台再补 UI。

## 1. 确定的产品规则

1. **一个 SteamKit 服务、一个主账号、一个订阅状态源、一个下载任务源。** 完整替换 SteamCMD 与“Steam 已订阅”自动网页登录/HTML 数据获取；保留现有列表、网格和详情入口，重新接入结构化数据。
2. **登录面板由用户点击工具栏账号入口，或未登录时主动点击订阅、下载等受保护操作打开。** 后者直接打开登录，不显示额外登录提示，也不在登录成功后自动重放原操作。App 启动、进入个人列表、网络失败、token 失效、helper 重启均不得自动弹出登录、Guard 或网页窗口。
3. 未登录时主动点击下载或订阅，直接打开唯一登录面板，不叠加提示横幅。**不创建待登录下载/订阅写任务，不在之后登录成功时自动执行旧点击。** 保留页面位置，用户登录后再次确认自己的下载/订阅操作。
4. **账号密码与二维码登录都是一期必做能力。** 不把二维码当外部 Steam 网页登录的替代皮肤；两种方式均进入同一个 SteamKit Authentication 会话与 Keychain 持久化合同。
5. 公开浏览尽量支持匿名读取；能力不足时展示原因，不能自动为获取列表发起登录。登录后读取主账号“Steam 已订阅”，无第二套 Cookie 认证。公开网页仅保留用户主动“在 Steam 网页查看”的外链，不是数据、认证、订阅或下载的兜底执行器。
6. 点击下载后进度直接填充卡片现有 bar；工具栏新增“下载任务”按钮，打开队列/历史面板。校验入库成功后自动出现在“已下载”，**不自动跳页、不自动播放、不隐式订阅**。
7. 旧获取代码可以重写/删除；用户已有文件、元数据、属性、筛选习惯与播放结果必须保留。Steam 获取 helper 不进入 playback multiplexer，不控制当前壁纸。

## 2. 现状、重构落点与唯一职责

| 当前源码证据 | 改造决定 |
|---|---|
| [SteamService/Program.cs](../../SteamService/Program.cs)已有有界 IPC、认证、查询、下载；[csproj](../../SteamService/SteamService.csproj)限定 osx-arm64 | 继续真实链路与发行验收；SDK 固定、自包含、签名与许可仍属 SK7.2 |
| [SteamAuthRoute](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamAuthRoute.swift)、[AccountSession](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamAccountSession.swift)与 [TokenStore](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopTokenStore.swift)是当前唯一认证链 | 账号密码／QR／Guard 进入同一 attempt/epoch；token 与明确用户触发的登录面板是唯一持久恢复和认证 UI owner |
| [旧获取状态退役器](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLegacyAcquisitionRetirement.swift)精确撤旧凭据、专用 WebKit store、缓存与 runtime | 不读取或转换旧 Cookie/密码；不恢复社区独立账号与私人 HTML 抓取，也不触碰系统浏览器、Steam 客户端或壁纸库 |
| [来源模型](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopBrowseFilters.swift)已有“Steam 已订阅/我的收藏” | 保留标签与导航；统一从 SteamService 的结构化 queries 获取，不再新增平行订阅页 |
| [BrowseFetching](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+BrowseFetching.swift)、[SteamKitBrowse](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+SteamKitBrowse.swift)与 [Hydration](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+BrowseHydration.swift)维护结构化分页、详情与预览媒体 | SteamService 是列表／详情身份与元数据唯一 producer；Swift 仅对详情预览做有界 MIME 探测，不并行保留第二语义数据权威 |
| [Downloads](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift)已使用 JobStore、SteamKit 与独占 staging；旧全局清理已撤 | 继续真实账号下载/恢复验收；禁止恢复共享目录互删或下载自动登录 |
| [卡片](../../MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserItem.swift)与 [GlassBar](../../MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserItemSupportViews.swift)已消费 item/attempt 进度并用独立 clip layer 填充 | 保留卡片点击、标题与布局；继续只增量更新可见同 ID bar，不重建网格 |
| [工具栏布局](../../MyWallpaperX/Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Layouts.swift)、[标识](../../MyWallpaperX/Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarIdentifiers.swift)与 [任务面板](../../MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopDownloadTasksPopover.swift)已有账号旁任务入口、badge、当前队列及有界历史 | 浏览页和已下载页均保留账号入口，任务面板不另开登录入口；真实可见交互仍归 SK7 |
| [DownloadLibrarySync](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadLibrarySync.swift)维护 ready 记录与本地库 | 保留并明确为唯一 metadata ready 发布者；事务 owner 只把验证后的不可变内容放入 `Video/Web/Scene` 并写强 ownership marker，helper stagedComplete／公开目录存在都不等于 ready；启动迁移只处理 metadata 当前指向的 v1 commit |

```text
AppKit 工具栏/浏览网格/详情/卡片 bar/任务面板/已下载列表
    ↓ 用户事件，UI 仅投影状态
SteamWorkshopService
    ├─ AccountSession：唯一 activeSteamID/accountEpoch/authAttempt
    ├─ BrowseStore：query/page/detail/subscription 状态
    ├─ JobStore：持久任务意图、队列、attempt、提交状态与有界 terminal history
    ├─ DownloadProgressStore：item/jobKey/attempt 精确进度投影
    ├─ 任务历史投影：按账号读取 JobStore history，不由视图自行累计
    └─ SteamServiceClient：唯一 IPC/进程 owner
          ↓
SteamService（C#）：SteamKit Authentication / Queries / Subscriptions / CDN
          ↓ staged receipt
现有库入库事务 → ready 记录 → 各 UI 增量更新
          ↓ 仅用户明确“设为壁纸”
现有 Video/Web/Scene 播放入口
```

这些是现有 service 内的责任边界，可先用具体类型/扩展实现；不要求新建通用平台或再加 singleton。Swift 唯一决定任务排队/取消/记录，helper 唯一执行活动作业的网络调度；队列面板不是第二 JobStore。预览图片的 URLSession/cache 可以留在 Swift，只消费已验证的结构化 URL，不承担列表语义。

## 3. 登录与持久化：用户主动、过程统一

### 3.1 唯一入口与状态

工具栏账号区域：未登录显示“登录 Steam”；恢复中显示“正在恢复…”（仍可打开账号状态并取消恢复）；在线显示头像/昵称；过期显示“重新登录”。已登录菜单仅“账号信息/切换账号/退出登录”。没有“登录 Steam 社区/切换 Steam 社区账号”。

`authState = signedOut/restoring/connecting/awaitingPassword/awaitingQR/awaitingGuard/online/reconnecting/expired`。`helperReady`、网络 connected、token 已保存与 online 分开。每次认证带 authAttemptId/accountEpoch；authAttemptId 在 App 发请求前生成，事件和成功结果回传同一身份。关闭面板、切方式时先同步作废本地尝试并取消请求 Task，再发带原 authAttemptId 的远端取消；不能依赖首事件或旧账号是否在线，也不能用无目标取消影响后续尝试。迟到消息不能弹新窗口、存错 token 或恢复已取消认证。

| 触发 | 必须发生 | 禁止发生 |
|---|---|---|
| 启动，无已保存会话 | 匿名可用；工具栏显示登录 | 自动创建密码/QR/Guard 会话或弹窗 |
| 启动，用户之前明确勾选记住登录 | 一次有界、无 UI 的 token 恢复；失败显示重新登录 | 回退密码、自动打开 QR/Guard/网页 |
| 未登录点击下载/订阅 | 打开唯一登录面板；不建立任务 | 自动续接下载、重叠提示横幅 |
| 未登录进入已订阅/收藏 | 原区域显示账号空态与工具栏指引，保留筛选 | 自动 WebView 登录或把无权限误报“没有订阅” |
| 主动点击工具栏登录 | 打开/聚焦唯一登录面板，开始所选方式 | 重复点击产生多个认证窗口 |
| token 被拒绝/断线需要验证 | 已有内容保持，受影响活动任务标“需要重新登录”，等待工具栏操作 | 验证窗口自行出现或自动提交旧密码 |

账号身份由 App 的单调 accountEpoch 驱动。helper 接受新认证/退出时先作废旧连接；私有请求入队时固定 epoch、SteamID、连接代，在远端发送及返回前各复核一次。校验与同步发送和换号共用会话锁，禁止排队请求读取新账号身份。连接回调只允许完成其原连接的等待者；断线/LoggedOff 或 helper 退出立即撤销在线投影，保留已保存令牌并等待用户操作，不弹登录窗。取消与成功回包交错时，原 authAttemptId 仍可撤销其刚完成的会话，但不能撤销后续账号。下载绑定原连接并在换号时取消，内容验收仍按下载工作卡执行。

### 3.2 密码与二维码面板

当前 [AppKit 登录面板](../../MyWallpaperX/Modules/SteamWorkshop/UI/SteamLoginPanelController.swift)按内容自适应高度；由独立面板承载，不依赖浏览页必须可见。面板顶部为“二维码登录 / 账号密码”分段切换，默认二维码（不保存上次输入秘密）；关闭回到原窗口焦点。

- **二维码：**用 SteamKit `BeginAuthSessionViaQRAsync` 产生 challenge URL，由本机 Core Image 渲染。面板有说明“使用 Steam 手机应用扫码确认”、到期状态、“刷新二维码”和“改用账号密码”；challenge 更新时只替换二维码、保持清晰度与足够留白。没有扫码确认不允许自行判定成功。
- **窗口形态：**优先在同一 AppKit 面板显示二维码。需要放大时提供“在独立窗口显示”，只重用同一 authAttempt 的 QR 视图；原面板与子窗口不得各开一个认证。用户允许的网页展示不是必需方案；若采用本地只读网页渲染二维码，也不能加载官方登录页抓 Cookie、嵌第三方脚本或将 token 放进 URL。
- **密码：**账号、NSSecureTextField 密码、“记住登录”与“登录”按钮；支持粘贴/密码管理器。连接期间按钮 pending，错误在字段附近显示；错误不清账号，密码不落日志、argv、env、UserDefaults 或任务历史。
- **Guard：**手机确认、邮箱验证码、令牌分别显示对应说明、有效操作与可用重试时间；它们只在用户当前打开的认证流程内出现。错误后聚焦验证码；手机拒绝/超时可重试或切方式；验证码/密码不长期保存。
- **切换/取消：**切换登录方式先取消旧 attempt 的轮询与回调，生成新 attempt；关闭整个面板取消认证，窗口关闭后迟到成功不得持久化或弹回。单独关闭二维码放大窗口只关闭视图，主面板仍控制认证。二维码到期停止旧轮询，用户刷新生成新 challenge，不无限自动重启认证。
- **成功：**以远端 LoggedOn 与 SteamID 核验为准，关闭面板、工具栏变在线；当前若在“已订阅”则开始同账号列表刷新，否则后台标记列表待加载。保留当前来源、搜索、滚动和详情；不执行任何登录前被拒绝的下载/订阅点击。

### 3.3 保存、恢复、换号与退出

“记住登录”说明：**下次打开时自动恢复，无需重新输入**。首次不预选，有历史明确偏好则沿用；它只授权非交互 token 恢复，不授权后台发起密码/二维码/Guard 流程。两种登录方式完全共用此偏好。

Keychain 按 SteamID/accountName 保存 refresh token 与服务端需要的 GuardData；UserDefaults 仅保存账号显示名、偏好和非敏感时间。token 更新原子替换，不能先删旧 token 再写失败。不开启记住时仅驻内存；成功后清除此账号遗留的旧密码/token 持久凭据。旧密码只在用户主动密码登录迁移时使用或由用户重新输入，不能启动自动试登；新会话确认后退役旧密码条目。

退出先同步关闭记住偏好和独立的“允许恢复已保存会话”标记，再清理 Keychain；删除失败必须显示，不能在下次启动恢复残留令牌。交互换号先撤销旧恢复授权，只有新令牌原子保存成功才重新授权；仅重新勾选偏好不能使旧令牌复活。恢复失败的凭据处置归账号 owner，并校验原 epoch，浏览模块只展示结果，不自行删令牌。退出的网络收尾不得再次清理新账号状态。

token 不保证固定 200 天；以服务端过期/撤销结果为准。本地 exp 只用于提示。后台重连指数退避、有上限；网络失败不删 token，明确拒绝才标 expired。退出/换号统一增 epoch，取消旧作业的账号权限，旧私有缓存不展示给新账号；退出前一次说明活动任务将停止，保留本地文件和当前播放。对因过期而中断的**已经明确提交**的任务，登录同账号成功后先对账，再按原任务的自动恢复偏好继续；新账号不得接管旧任务。

## 4. 浏览、订阅、卡片与任务面板重新设计

### 4.1 浏览数据与分页

**所有列表/详情/账号数据经过一个 SteamService 查询入口。** SteamKit 用户/匿名会话能力优先；确需公开 Steam Web API 时由 helper 内部封装同一 query 合同，不能恢复 Swift HTML 抓取、Cookie 会话或发行商 key。是否能匿名查询、各筛选字段/排序是否成立，在 SK0 逐项验证；无法实现的项明确阻断或标不支持，不伪造完整浏览兼容。

| 来源 | 数据合同 | 未登录/失败表现 |
|---|---|---|
| 最热门/最新发布/最多订阅/最后更新 | 公开 query、明确排序、consumerAppID、内容/年龄/分辨率筛选、分页 token | 匿名可用则直接展示；匿名能力不可用则原区域提示需登录，不自动登录 |
| Steam 已订阅 | 同主账号 listSubscriptions + 详情批量补全 | 未登录显示引导空态；登录后读取，和 Cookie 完全无关 |
| 我的收藏 | 同主账号结构化收藏查询 | 不能退回网页登录；接口未通过 SK0 则该能力标待完成，不宣称迁移完成 |
| 工坊 ID/链接/作者作品 | 严格 ID/URL 解析、consumerAppID 校验、结构化详情/作者查询 | 非目标 app、集合、删除、私有/无权限分别显示；网页外链仍可主动打开 |

`QueryKey = source/accountEpoch/search/sort/trendDays/filter/contentMode/locale`；每次查询有 queryGeneration。当前协议为页码分页、每页 30 项，收藏详情批 30 项（helper 上限 80），查询并发 2。`trendDays` 只在趋势排序下取 1...365 并交由 Steam 远端改变排名区间；它不按 `timeCreated` 删除返回项，也不改变远端 collection total。仅在成功采纳当前 generation 页后推进 nextPage；hasMore 按实际返回页宽判断。将来若服务接口改游标，显式升级协议，不能继续假定页码。搜索 debounce 300 ms 是仍需实测的交互目标。

- 初次加载 skeleton；滚动近底部只预取下一页，最多一个 loadMore，generation 变化取消旧页；按 workshopID 去重。失败保留已经加载页，底部“加载失败 · 重试”，不能清空整个网格。
- 搜索/筛选变化从第一页重新开始，来源切换保留各自页面与滚动 anchor；刷新用旧数据上方的轻量状态，不闪回空白。新 query 的回包校验 generation，不能让慢旧页覆盖新页面。
- totalCount 未知时显示“已加载 N 项”，不能猜总数；hasMore/cursor 由真实响应决定。订阅列表没有稳定 snapshot 时采用游标/去重＋revision invalidation，不承诺远端实时分页快照。
- **过滤正确性：**远端支持的过滤交给服务端；只支持本地过滤时明确“在已加载项目中筛选”，或完成有界全量 ID 获取后提供全量过滤。不能用一页过滤结果代表整个订阅库；详情缺失的条目保留 ID 占位和重试。
- 列表基础字段先展示，详情与预览后补；元数据缓存按 schema/version/query/账号区分，私人缓存退出后不可见。预览 URL 更新使图片缓存失效，NSCollectionView 复用必须核对 ID，避免错图/错进度。
- 浏览列表不轮询下载，不把卡片 viewport 当任务生命周期；同 item 在多个来源出现时共用 JobStore/subscription state。外链返回只在 App 激活时对相关 ID 做一次合并刷新，不抓取网页按钮文字。

### 4.2 订阅、下载、播放是三个独立动作

详情保留主下载/设壁纸按钮，订阅是次级动作；窄窗口可移到第二行，不挤掉作者/网页/刷新。未知订阅状态显示“正在查询”，写入采用 desiredState＋operationId；超时表示“待确认”，先读后重试，不盲 toggle。取消订阅保留本地内容和播放；删除本地不取消订阅。未登录时，用户主动点击订阅、下载等受限操作直接打开唯一登录面板，不显示工具栏下方的提示横幅；浏览、分页与后台刷新仍不自动弹登录，登录完成不自动重放原操作。

下载点击立即显示队列状态，去重后提交 JobStore；校验/入库期间不是 ready；完成后主动作改“设为壁纸”。缺依赖保留“下载依赖 #ID”。本地旧版仍可播放时，更新是次级操作，失败保留旧版。未支持内容类型显示真实原因，不反复下载，也不借下载改变播放算法。

### 4.3 卡片 bar：真实填充进度

沿用 `SteamWorkshopGlassBarView` 的位置、圆角与标题层，新增 **独立裁剪的 fill layer**：中性底轨始终可见，填充宽度为 `barWidth × clamp(verifiedBytes/manifestTotalBytes, 0...1)`。分母未知用不定进度，不能整条刷绿假装百分比。网络/解压/校验采用明确阶段，网络 100% 仍要显示“校验中”，直到入库完成才显示“已下载”。

| 状态 | bar 填充/颜色（集中为语义 token） | 文本与操作 |
|---|---|---|
| 未下载/就绪 | 中性底轨，无下载填充 | 原标题/下载或设壁纸动作；就绪短暂 check 后稳定为“已下载” |
| 已排队 | 排队蓝 `systemBlue`，状态标记而非虚假百分比 | “排队 · 前方 N 项”，可取消 |
| 连接/大小未知 | 下载绿 `systemGreen` 的不定状态，减少动态效果时静态指示 | “正在连接/获取文件信息”，可取消 |
| 传输中 | 按真实比例从左至右绿色填充 | “42% · 18/43 MB”，窄卡只百分比；hover/详情提供完整数值与取消 |
| 等待重连/需登录/暂停 | 已完成比例保留，等待色 `systemOrange`，停止扫描 | 显示原因；登录只能指引工具栏。断点暂停 capability 未完成前不展示暂停按钮 |
| 校验/保存 | 保留进度背景，显示阶段指示；不伪装已下载 | 校验可取消；原子提交点后“正在保存”禁用取消且说明 |
| 失败 | 保留最后真实比例，错误标记 `systemRed`，不全条成功色 | “失败 · 重试”，错误详情在 tooltip/任务面板；可关闭任务 |

用户未指定新的 RGB 值，本计划默认沿用现有下载绿/排队蓝；所有填充色只从同一 `DownloadProgressPalette` 语义配置读取，后续指定颜色改一个位置。状态不能只靠颜色区分。标题/按钮位于填充上层，深浅色保持可读；bar 自身不把任意点击当取消，取消有独立命中区，卡片其余区域仍打开详情。

helper 进度合并最多 4Hz，Swift UI 渲染最多 4Hz，只更新可见同 ID bar；数值之间允许 150–250 ms 的短插值，不伪造进度、不周期性全量刷新网格。后台窗口降低投影频率、关闭的 popover 不持续布局；阶段/错误/取消/完成立即发送。任务重试带 attemptId，避免旧 attempt 的高百分比覆盖新任务；复用卡片必须取消旧观察并清 fill。VoiceOver 按阶段及有限增量公告，不随每次进度播报。

### 4.4 工具栏“下载任务”popover

[工具栏](../../MyWallpaperX/Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Layouts.swift)在账号按钮旁新增向下箭头/托盘图标，badge 为未终结任务数（含排队），可访问名称“下载任务，N 项”。浏览与已下载页都可呼出，同一窗口只有一个非模态 NSPopover；点击外部/Esc 关闭，不影响任务。溢出菜单仍可访问入口。

弹层建议宽 360–420 pt、高度有上限，顶部 `进行中 | 历史` 切换；列表内部滚动，底部固定“查看已下载”。普通 NSMenu 不适合频繁刷新进度，因此使用 AppKit popover，交互形态保持菜单式轻量。

- **进行中：**缩略图、标题、阶段、大小/速度（稳定后才显示 ETA）、进度、取消/重试/查看详情。排序为活动→等待→排队，队列顺序稳定；更新只改对应行，鼠标下操作按钮不因重排跳位。支持“取消全部”时列数量一次确认，已入库文件不删除。
- **历史：**成功/失败/取消分别显示；按时间倒序，默认保留最近 100 条且最长 30 天（实施前冻结配置），超限只删除记录不删壁纸。重复重试合并一个逻辑任务的 attempts；“清空历史”只删终结记录，不能清队列或库。历史不是“已下载”的权威，已下载文件被删除后跳转需提示不存在。
- **完成反馈：**toolbar badge 更新；不自动打开 popover、不自动系统通知。完成记录在历史可见；“查看已下载”由用户点击后导航并可定位该记录，自动入库与主动导航明确分开。
- **账号/恢复：**退出后仅保留不泄露旧私人信息的任务提示，旧账号任务隐藏到恢复该账号；本地已下载照常展示。过期会话任务行显示“请使用工具栏重新登录”，不在面板另放打开登录的按钮。

## 5. 下载实现、取消、恢复与入库事务

SteamKit 提供协议能力，不等于完整 Wallpaper Engine 下载器。SK0 必须证明真实账号下的授权/manifest/CDN 流程可行。helper 顺序为：item 类型与 app 校验 → 授权/内容定位 → manifest → 有界 chunk 下载/解压/校验 → stagedComplete。直接 UGC、depot 内容、依赖和集合需分别识别；集合不能当普通文件下载，未支持时给出网页/子项说明。不要用第三方私有实现填补能力。

1. **下载调度：**Swift 以统一 JobStore 保留去重、FIFO 排队和取消，App 与 helper 当前均最多 2 个活动作业；每作业最多 4 个 worker，但所有作业共享 4 个实际 CDN chunk 槽。task、observer、取消与清理全部按 `jobId-attempt` 键控，任一作业必须等自己的物理 terminal 才释放槽位；A 取消不得提前结束 B。已撤全局 staging 清理，不能为提高并行度恢复共享路径删除。
2. **路径/预算：**Swift 为每 job 分配隔离 staging 与受控根，helper 不能接受任意 outputRoot 写用户目录。拒绝 `..`、绝对路径、逃逸 symlink、大小写/Unicode 冲突、非法长度；约束文件数、展开字节、并发、重试与磁盘空间，空间估计包括旧版本＋暂存＋提交空间。持久下载暂存由任务租约管理，不在真实 Scene 样本根试验。helper 只接受已存在且祖先无符号链接的 staging 基目录；新作业排他创建随机直接子目录（0700），恢复仅可重新打开 JobStore 持久化的同一 `job-<GUID>` 直接子目录，且服务端当前 manifestID 必须一致。下载 helper 的 ready 必须声明 `download-staging-ack-v2`；只声明旧 v1 或缺少该 capability 的同协议 helper 在 App 发送 `startDownload` 前失败关闭，不能静默回到“先写后存”或 device+inode-only。现役 helper 发布 `allocated` 后必须等待 App 已校验并原子保存 path/manifest/device/inode/birth seconds/birth nanoseconds，再由 `acknowledgeDownloadStaging` 以相同 account epoch、job identity 与完整创建身份解除写入门；错误、重复、迟到或超时回执都不能创建内容节点，超时以 typed integrity terminal 使 App 清空已失效 recovery identity。新分配且仍为空的未确认 lease 只在私有 0700 staging 根内按已打开 identity 检查，并在 unlink 前再次 reopen/复核；已观察到的同名 replacement、同 device/inode 但 birth 不同的 replacement 与恢复中的旧 lease 不删。POSIX pathname unlink 不是原子 compare-delete，当前证据只覆盖最终复核前的确定性空 replacement swap，不把它表述成对同用户恶意纳秒级替换的绝对原子保证。显式 retry 在发请求前重新打开并核对持久 lease；缺失或任一 identity 字段失配时先原子清空 recovery 字段，同一次点击直接创建 fresh lease，不先制造一次必败 resume。以目录描述符逐层 openat/O_NOFOLLOW 创建或收养 manifest 已声明节点，新文件 O_EXCL/0600；记录设备、inode 和创建时间，写入/终验拒绝替换节点、多硬链接及非普通文件。已有文件长度一致后逐 chunk 校验，只有有效块计入恢复进度，其余块重新下载。helper 在新文件预分配/写入前按缺失 chunk 预留物理空间，App 在版本复制前按完整 receipt 预留；两者都减去同 owner 其他作业预留并保留 256MiB 安全余量。App 串行执行版本复制，避免已写入字节又被完整 reservation 重复扣减；staging 与 library 同卷时，还按另一个尚未进入复制阶段的活动作业预留最多 8GiB，且复制预留存在期间不启动新 helper 作业，避免两个进程互不可见的预留发生超卖。`diskFull` 不覆盖旧 ready，并保留当前 manifest-bound 暂存供释放空间后显式重试。成功前再次核对回执路径的完整根目录身份。释放 helper 租约只关闭描述符；App 等到物理 terminal 后，以同样的直接 lease/name/no-follow/device/inode/birth 边界精确清理成功、取消或不可恢复 manifest 失配的暂存，不枚举或删除未知兄弟目录。
3. **校验：**写盘前整份 manifest 纯校验：无符号总量先与剩余预算比较，再安全转为文件长度；chunk 按 offset 验证无重叠、无空洞、完整覆盖文件。清单内路径统一检查目录/文件及大小写、Unicode 规范化冲突。首期另设 262144 chunk、单路径 4096 字符/64 层、路径索引 8Mi 字符预算；这些是资源拒绝上限，不是兼容性声明。根目录必须有非空 `project.json`。终验核对实际长度与 checksum，在文件/chunk/每次至多 64KiB 读取间响应取消。manifest/chunk 完整性和最终内容/类型校验分层；只有 metadata/零字节/部分文件不算完成。CDN 失败有 backoff 与上限，权限拒绝先判断会话/许可，不无限换服务器。进度区分网络字节、已验证字节与阶段总量，避免压缩字节分母混用。
4. **取消：**取消队列立即完成；活动作业请求取消后停止新 chunk，排空写入，回 `cancelled` 才释放 job；UI 可先“正在取消…”。helper 崩溃/管道 EOF 不得显示完成。需要强杀时只杀本任务 helper，并使其所有活动作业进入可恢复/失败，不能杀用户 Steam 客户端。
5. **原子入库：**Swift 校验 staged receipt（job/account/version/path/manifest）→复制或移动至库内临时版本→验证→原子发布记录；持久化提交阶段/receipt，覆盖文件提交与记录更新之间的崩溃恢复，不假设二者天然是同一原子操作。跨卷不能假定 rename 原子。磁盘满/取消/重复完成不覆盖旧 ready。更新使用版本目录或等价安全替换，正在播放的旧版本保留到消费端释放；属性/依赖/预览映射继续按稳定 workshopID 关联。
   下载完成凭证采用显式 `receiptVersion=2`，必须包含并核对 `jobId/workshopId/accountSteamId/accountEpoch/manifestId`、`stagedComplete/projectJsonPresent`、相等且有界的 `verifiedBytes/totalBytes`，以及本次 base 下的独占 `job-<GUID>` 直接子目录。`contentDigest` 是按 NFC UTF-8 路径字节序排序的所有普通文件的 SHA-256：每行依次写入路径 UTF-8 长度（UInt32 little-endian）、路径、文件长度（UInt64 little-endian）、文件 SHA-256 二进制；再对这些行串联求 SHA-256。空目录保留但不参与摘要。App 复制时再次计算同一摘要，拒绝 helper 完成后发生的内容变化。Swift 查询 API 返回完整 typed receipt，不丢弃为 Void，不以协议成功直接发布 ready。路径字段校验只确认归属和格式，不替代消费端的文件身份、链接、项目内容重验；入库提交前再次核对当前账号及作业 attempt。
   当前发布 owner 仍为现有 `.mywallpaperx-steam-metadata/<workshopId>.json`：新 v2 完整内容先进入 `.mywallpaperx-steam-incoming/<UUID>/content`，验收后原子 rename 到 `Video|Web|Scene/<WorkshopID>-<generationUUID>`；公开目录的强 marker 必须与 commit 完全一致，但 marker 或目录本身都不代表 ready。`<WorkshopID>-<UUID>` 是保留命名空间，marker 缺失／损坏时 legacy scanner 也必须 fail-closed，不能仅凭 `project.json` 产生第二 ready。文件复制/摘要和 project 验收在 utility task；最后账号与 attempt 检查到元数据 rename 之间不挂起。任务状态为 `running → staged(receipt) → committing(commit) → completed`，receipt/commit 先持久化再推进状态；重启只以身份完全一致且内容路径可用的已发布记录对账，未发布事务保留失败现场并等待用户重试。旧 v1 commit 只读，启动迁移复制到新 generation，发布前重读 exact 旧 metadata；失败在同进程内有界退避，后续 reload 仍可重试，不移动旧播放路径。
   更新保留旧版本原路径；移除受管下载写 tombstone，避免旧目录被扫描复活。版本回收只处理超过 24 小时的 v1 直接 UUID、incoming 直接 UUID 与 marker-backed v2 generation；保留集由当前 ready、JobStore 未决 commit、Scene/Web 活跃消费 token、Video 库持久路径及 daemon 当前／pending intent 共同组成，依赖型 Web 的同一个 token 同时租住壳与依赖宿主的具体版本。删除过程基于目录描述符、不跟随链接；跨 actor admission 后按最初 device/inode 和 exact marker 复核，同名普通目录替换只释放 retiring reservation并跳过。公开未知目录、链接和失效 marker 均不被回收 owner 收养。JobStore v5 给 receipt-bound staging 持久化 device/inode/birth；成功、取消或不可恢复 manifest 失配只在 helper 物理排空后清理同一完整 identity lease，同名替换、同 device/inode 不同 birth 与旧版不完整 identity 记录均失败关闭。新复制前把 v1、incoming 与所有保留命名空间 v2 generation 连同本次新增字节计入 16GiB retained cap；普通下载与 v1 迁移共用一个串行 copy-capacity owner、跨作业 reservation 与 256MiB 安全余量，不以独立 free-space 快照超卖。
   项目准入要求有界有效 JSON、scene/web/video 类型、受限相对入口及预览/依赖路径；scene允许入口封装于scene.pkg，web允许合法依赖项目。该准入不等于视频解码、HTML效果或Scene视觉兼容验收。配置根路径可用原生 realpath 解析物理路径，receipt路径本身不得借此绕过nofollow；Foundation路径规范化会缩写系统别名，不用于安全路径比较。

6. **恢复：**Swift 持久化最小 job intent/目标版本/暂存租约，不保存密码/token 到任务文件。App 重启后先校验 manifest 与本地块，显示“可继续”或“需重新下载”，不能伪装自动无损续传。网络断开可有界自动重试；账号切换后不自动恢复前账号任务，提示原账号恢复或移除任务。更新 manifest 改变时丢弃不匹配块，只清精确 job 暂存。
7. **自动进入已下载：**入库事务成功后一次性发布 ready 记录、更新浏览卡片/队列面板/已下载列表；即使已下载页未打开也必须更新数据源。历史条目引用同一 recordID，不复制一套已下载状态。失败/取消留在任务历史，不冒充已下载；更新成功合并同一 workshopID，不新增重复卡片。不自动切换页面、选中其他卡片或打断当前播放。
8. **播放：**现有“下载”不产生播放 intent。未来若增加“下载并设为壁纸”，必须另存用户操作的播放 epoch/display/选择，成功时重新确认仍为最新意图；不是本次默认行为。

## 6. IPC 与状态合同

有界 UTF-8 NDJSON，stdout 仅协议、stderr 脱敏诊断；支持半包/多包/Unicode 分段。初始每帧 1 MiB、有限 pending 命令与超时，SK0/SK1 冻结真实边界；禁止无限 ReadLineAsync 分配。SteamID/workshopID/manifestID 用十进制字符串。

Envelope：`v/type/requestId/processEpoch/accountEpoch`；认证另有 authAttemptId，查询有 queryGeneration/cursor，作业有 jobId/attempt/sequence。ready 返回版本/capabilities；下载必须包含 `download-staging-ack-v2`，不能只因同为协议 v1 或仅有旧 ack-v1 就假定具备完整创建身份写入门。accepted 不等于完成；每 request 最多一个 terminal。进度可合并，terminal 不得被节流丢失。helper callback pump 不阻塞 stdin；关闭/取消能终止正在等 Guard 或 QR 的异步等待。

| 命令族 | 请求与结果 |
|---|---|
| loginPassword / loginQR / cancelAuthentication / submitChallenge | 只接受 App 的显式登录或受保护操作用户手势创建的 attempt；QR 更新/Guard 挑战/取消/成功关联该 attempt，不自行打开 UI |
| restoreSession / logout | 仅显式记住偏好允许无交互恢复；敏感 token/GuardData 独立 private payload，不进普通 snapshot/日志；失败只改状态 |
| queryBrowse / queryDetails / queryAuthor / listSubscriptions / listFavorites | queryGeneration、筛选/排序、cursor/pageSize → 结构化 page/partial/error、真实 hasMore；无网页登录 |
| querySubscriptionStates / setSubscription | 主账号、itemIDs 或 desiredState/operationId；不确定结果查询确认；不得改其他账号 |
| startDownload / acknowledgeDownloadStaging / cancelDownload / queryJobs | job lease、目标版本、受控 staging；allocated 只公布精确 lease，App 持久化后才回执解锁写入，随后才允许 progress/stagedComplete/cancelled/failed。pause/resume 只有 manifest 对账能力实际成立才开放 |
| ping / snapshot / shutdown | 版本握手、进程/远端状态、作业对账；pong 不证明登录。无业务时低频/退出，不能每帧心跳 |

旧 Cookie/ensureWebSession 协议不进入最终产品合同。所有认证请求源必须可审计；UI 自动打开的唯一许可是当前有效 toolbar attempt 的下一步 Guard，且面板必须仍打开。进程重启先 snapshot 对账，只读可重试，订阅写先查状态，作业凭 receipt 恢复。错误区分 network/rateLimited/authExpired/invalidChallenge/accessDenied/unsupportedQuery/unsupportedContent/diskFull/integrity/cancelled/protocolMismatch/helperUnavailable；给有效动作，不泄露底层整段日志。

## 7. 迁移、退役与数据兼容

- 旧 SteamCMD 与社区登录不作为长期或运行时 fallback。新后端未达标时不能切成默认；回退是整个有界产品版本/路由撤回，不在同一任务里临时调用旧密码/旧 PTY/HTML。有副作用的操作禁止双发。
- 首先新增 SteamServiceClient/AccountSession/BrowseStore/JobStore 合同，再替换现有 service 的生产者；可以复用无副作用的模型、库和 UI，不保留旧状态布尔量作为第二真值。
- 退役清单：SteamCMD 包资源/启动脚本/PTY/输出解析/自动安装与凭据登录；`presentLoginGate` 的所有自动调用；`SteamCommunitySessionController` 的认证/个人抓取调用；社区账号菜单、Cookie 状态、旧 personal HTML 分页/解析；下载全局 staging 清理与 pending 自动登录任务。逐项扫描产品引用，源码存在但无调用不等于包体退役。
- 原 `Steam 已订阅/我的收藏` 列表组件保留，但数据适配、分页、错误态重写；旧缓存加 schema 标记后失效/迁移，不把 HTML 缓存误认新 API 结果。旧私人列表不作为新账号已认证证据。
- 本地已下载文件/ID/元数据/用户属性/预览与依赖保留，schema 升级有回滚路径；不要为了迁移重新下载全部内容。新历史/JobStore 不改变库 ready 权威。
- 专用社区 Cookie store 无需读取导出或转 token；产品撤权后不再使用。清理其数据与旧 runtime 必须在实施批列精确清单，按工作区规则处理，不能动用户系统浏览器/Steam 客户端数据。退出/升级不会意外删除本地壁纸。
- 登录、查询、订阅、下载合并到同一 SteamKit 服务，但 AppKit/播放器与库管理仍独立。新增 C# 只在[限定技术边界](../architecture/technology-stack-boundaries.md)内使用，不引入通用后台框架。

<a id="work-cards"></a>
## 8. 可逐张实施的工作卡

**当前续接：SK4.3 的剩余工作 → SK4.4 → SK5 → SK6 → SK7。** SK0–SK3 的真实账号/可见门仍未完成，合并进入 SK7 的最终当前构建验收，不重新搭建已存在的 owner。 默认按下表从上到下执行，一张卡一个可验证结果和一个职责提交。阶段 SK0–SK7 只用于分组，阶段完成必须包括其所有子卡；前文设计合同不因卡片摘要省略而失效。当前卡及完成证据链接只在下表更新，不为每张卡创建新计划文件。

| 顺序 | 卡 | 交付物 | 状态 |
|---|---|---|---|
| 01 | SK0.1 | 依赖/平台与能力验证表 | §10.1 是早期探针基线；当前构建 QR/账号/下载实测仍待 SK7，不能仅凭旧探针关闭 |
| 02 | SK1.1 | 双端协议与离线协议测试 | 实现及离线门完成：有界分帧/256业务+8控制准入/接收登记与terminal去重/脱敏；维护入口见本节下方 |
| 03 | SK1.2 | helper 生命周期 | 实现及离线门完成：transport generation、握手超时拆旧、有界重启、取消/陈旧回包反例；真实崩溃/发行 apphost 门仍待验 |
| 04 | SK2.1 | 密码/QR/Guard 后端 | attempt/账号/连接身份与取消已离线验证；真实四路账号门使用修复后的 steam-auth-gate.sh，需明确账号授权 |
| 05 | SK2.2 | 工具栏唯一登录入口与面板 | 代码已接入；共用记住偏好、QR刷新/关闭生命周期已修。真实 App 面板/焦点/布局/不自动弹窗门尚待验，不记为 UI 完成 |
| 06 | SK2.3 | Keychain、恢复、换号与退出 | epoch贯穿helper私有请求与回包；断线撤在线能力，取消抑制令牌采纳，退出先撤自动恢复授权并报告删除失败。离线门通过，真实Keychain/账号门待验 |
| 07 | SK3.1 | 统一结构化查询 | 检查所有统一消息Result，严格解码、partial错误ID、完整tags、有界并发；离线反例通过，真实分页/权限与限流待验 |
| 08 | SK3.2 | 浏览分页、过滤与详情 | 结构化 route 保留同 key 原始已加载集合，整集合投影排序、失败保留页。2026-09-16 实测后 `updated`（query_type 21）与分级筛选经 `taggroups` 开放：分面筛选（类型/分级/分辨率/分类）面内 OR、跨面 AND，discovery 服务端执行，author/personal 客户端后筛，分面组合参与 QueryKey。2026-09-21 纠正趋势时间窗：默认 featured/week 的 7 日值由 App→client→helper 作为 `days` 交给远端排名，移除会把热门旧作品裁空的 `timeCreated` 后过滤；新 App 只有在 helper 声明 `query-trend-days-v1` 后发送该字段，旧 helper 明确不兼容而不静默退化。SK6.2 后 discovery/ID/作者/个人列表只有同一 store，作者页返回还原 store 原始页、nextPage、hasMore 与 partial errors；详情 children 映射为严格十进制 dependency IDs，不再从 HTML 补依赖。真实普通 App 可见页与多页权限仍不能称完整验收 |
| 09 | SK3.3 | 已订阅/收藏与订阅写入 | dev route + 共享SubscriptionStore，unknown不得写、写超时先对账、无自动重写、账号隔离；个人排序/筛选仅限已加载集合，明确标注。Cookie不再是可用fallback。真账号/可见门待验 |
| 10 | SK4.1 | JobStore、队列与持久化 | 先在线准入；staged/committing 非终态；cancelAll 一次保存、失败不假推进并提示。任务 envelope 在 SK5.3 升至 v3、device/inode 升至 v4；完整 device/inode/birth identity 是不兼容恢复边界，因此当前 owner 只写 `jobs-v5.json`。v5 缺席时依次检查 v4/v3/jobs.json，只导入最新存在且可读的前代并保持其原字节；current／选中前代只接受 `O_NOFOLLOW` 打开的单链接普通文件，损坏、symlink／特殊项或 schema 超前均保持目录项、停止回退并永久关闭该 store 实例的写门。compiled fixture 覆盖原字节、dangling current/selected-predecessor、无 quarantine/sidecar、无内存 job、无 helper start；缺 birth 的 v4 partial 清空 path/manifest/receipt/cleanup authority：running 回 queued，staged 变 retryable failed，failed 保留原失败意图，completed/cancelled 不再持有 staging 清理权；committing 保留 preparedCommit，使已发布 metadata 仍可结算。损坏恢复／人工修复 UX 与完整 App 操作仍待 SK7，不把 fail-closed 等同恢复完成 |
| 11 | SK4.2 | 下载与完整receipt | 描述符staging、清单预算、v2跨语言摘要、串行进度发布/统一分母、typed磁盘错误、取消与成功共用决策点均有离线门。真实Steam下载与SDK物理排空仍待验 |
| 12 | SK4.3 | 原子入库与已下载 | 已接通版本准备/摘要与项目准入/元数据 rename/列表刷新；每个 v2 commit 按作者类型进入公开 `Video/Web/Scene/<WorkshopID>-<generationUUID>`，物理路径和 `v2:<type>:<name>` identity 永不复用。强 marker 与 metadata 共同校验 ready；整个保留命名空间即使 marker 损坏也从 legacy scanner 排除，库根经过符号链接时仍以物理父目录判定。v1 隐藏 commit 仅只读，启动迁移先进入普通 copy capacity/reservation，再重读核对旧指针发布；临时失败同进程有界退避，后续 reload 可重试，不移动旧播放路径。播放 token 以 `v1:`/`v2:` storage identity 贯穿 Scene/Web/Video 及依赖宿主；回收跨等待复核原 inode/marker，只删除超过龄期且不在完整 ready/事务/消费保留集中的受管 generation。隔离事务 26 项、服务级迁移成功/容量等待/CAS/瞬态重试及全部 Steam 维护测试 101 项与 Developer ID Debug build 通过；剩余真实已授权下载、真实库启动迁移、跨卷/断电实机与完整项目播放验收并入 SK7 |
| 13 | SK4.4 | 取消、恢复、有限并发与重试 | 工程切片已闭合：每个取消都等待原 startDownload terminal 后释放本地槽，账号 epoch 改变不丢弃物理排空 waiter。下载前 helper ready 必须只按现役合同声明 `download-staging-ack-v2`；随后只允许 `allocated(path/manifest/device/inode/birth seconds/birth nanoseconds) → App 校验 account/job/同一完整 descriptor identity 并原子保存 → exact acknowledge → create/write`。identity 在 helper 的同一锁内一次发布；wrong/missing epoch、保存失败、错误／重复／迟到 ack、旧 v1 capability 及 30 秒超时均不放行。超时删除新空 lease并返回 typed integrity，App 清空 recovery；显式 retry 先重开持久 lease，缺失／任一字段失配时同次持久清空并 fresh start。未确认空 lease 在私有 staging 根内 unlink 前再次 reopen/复核；确定性空 replacement swap 与同 device/inode、不同 birth replacement 均保留 replacement，但不把 POSIX name unlink 表述成原子 compare-delete。terminal receipt 只能复核已持久身份；恢复成组携带 path/manifest/device/inode/birth，helper 在任何内容操作前打开并核对根 descriptor；旧不完整 identity partial 走 fresh。App/helper 各至多 2 个活动作业、每 job 4 worker、跨 job 共享 4 个 chunk 槽；下载、入库复制与 v1 迁移共用容量 owner、256MiB 余量与同卷保守预留。fake-wire 覆盖 v2 mandatory capability、save-before-ack、保存失败、wrong/missing epoch、wrong birth、timeout invalidation、missing-lease same-retry fresh、A/B 隔离、同名替换与 v4 partial；helper 自检覆盖同锁 publication、错误 identity/epoch/birth、重复 ack、取消／超时等待及两次 removal identity check。helper-only 改动现由 checkpoint 强制触发产品 build。真实双下载／续传／崩溃／disk-full 与可见 UI 仍并入 SK7，不以离线绿色代替 |
| 14 | SK5.1 | 卡片 bar 真实进度填充 | 工程切片已闭合：helper 的 `sequence/stage/totalBytes/verifiedBytes` 由非 `ObservableObject` 的 item+jobKey+attempt store 严格吸收，拒绝旧 attempt、乱序、回退、超分母及超 8GiB 投影，不再把 helper 进度写入 service-wide `statusMessage`。浏览/已下载卡片只观察同 ID，reuse 显式解绑且弱 owner 自动清退；详情页在字节增量时只原位改 label/indicator，仅阶段/结构变化重建。`SteamWorkshopGlassBarView` 保留中性底轨并用独立 clip layer 按真实比例填充；未知分母才用不定态，已排队/下载/等待/失败语义色集中为 blue/green/orange/red，校验/保存/失败保留已验证比例，保存阶段禁用取消。标题/操作层在 fill 之上，窄卡只显示百分比，减少动态效果时不跑不定填充/走马灯，VoiceOver 只按阶段或 10% 桶通知。独立测试覆盖 0/1/50/100%、未知分母、等待/保存/失败保留、旧 attempt 与 A/B 观察隔离；9 个 Steam 离线模块及 arm64 无签名 Debug build 通过。真实 Steam 传输、深浅色/小宽度/点击/辅助功能的可见实机验收仍并入 SK7，未生产的 pause capability 仍不展示 |
| 15 | SK5.2 | 工具栏任务面板与队列交互 | 工程切片已闭合：浏览、作者和已下载工具栏共享同一 `steamDownloadTasks` 项；浏览与已下载页均保留账号入口，badge 只按当前 SteamID 计算非完成/非取消任务（含失败待重试），VoiceOver 与 overflow menu 同步数量。每个窗口的 toolbar controller 只惰性持有一个 transient `NSPopover`；普通按钮锚定工具栏，系统溢出时改锚窗口顶缘，外部点击/Esc 走系统关闭语义。面板打开才订阅 JobStore 的低频结构变化，逐行再按 item/jobKey/attempt 订阅 SK5.1 progress store；关闭清空 Combine/逐项 observer/缩略图请求，不停止任务。行内展示缩略图、长标题截断、阶段、真实大小/速度与稳定后 ETA、进度、取消/重试/详情；已有行在面板打开期间原位更新且不因状态变化重排，新任务追加，重新打开才恢复活动→失败待重试→排队/FIFO 排序。“全部取消”一次列数量确认且不删已下载文件，“查看已下载”和详情都走现有 Shell/Inspector 路由，完成路径不主动导航或打开面板。独立执行测试覆盖账号过滤、终态排除、排序/count/attempt identity，静态合同覆盖单 popover、溢出锚点、关闭解绑与无 Timer/NSMenu 第二刷新源；10 个 Steam 离线模块及 arm64 无签名 Debug build 通过。真实多任务按钮命中、键盘/Esc、深浅色和辅助功能的可见实机验收仍并入 SK7 |
| 16 | SK5.3 | 任务历史、保留策略与跨视图一致性 | 工程切片已闭合：JobStore 持久 envelope 在历史切片升级为 v3、device/inode 升为 v4，现因 birth identity 升为 v5；v5 只写新 sidecar，并可只读导入 v4/v3/v1-v2 兼容 envelope。jobs 与 terminal history 同一次原子写入，完成/失败/取消按 `jobID-attempt` 幂等记录，retry 沿用逻辑 job 并由面板汇总 attempts。保留配置冻结为最近 100 条且最长 30 天，每次写入/加载及打开历史面板时裁剪；历史按 SteamID 隔离，清空仅删当前账号终结记录，保存失败不假清除且不改变队列/失败重试意图/本地库。完成历史只保存既有库 recordID 引用；点击时重新通过当前 managed metadata/文件可用性判定，存在则导航已下载并定位/打开 inspector，不存在则明确提示并可转作品详情。popover 顶部已接“进行中｜历史”，切换/关闭解绑当前行高频 observer，历史只消费 JobStore 低频发布，无第二累计源。可执行测试覆盖旧 envelope/history 迁移、v4 各状态的 recovery authority 降权、prepared commit 结算、rollback bytes 保留、完成重启不重复、两次失败 attempt 汇总、账号隔离、100/30 天裁剪、清理原子失败与任务保留；AppKit arm64 无签名 Debug build 通过。真实 20 次跨页下载/取消/重试、可见定位、observer/task 计数及键盘/辅助功能仍归 SK7，未以离线门宣称交互验收完成 |
| 17 | SK6.1 | 老用户数据迁移与新路切换 | 工程切片已闭合：该批 Release 固定由 SteamKit route 接管、DEBUG 曾保留一次整版本回退参数；discovery、严格 ID、作者作品、在线个人列表与离线登录指引均先由同一 `SteamKitBrowseStore` 路由，creator SteamID 支持作者查询。App 启动和浏览入口不再读取旧密码、runtime 状态或私人 HTML cache，只允许此前授权的新 token 静默恢复。当前任务 owner 写 `jobs-v5.json`；只有 v5 缺席才按 v4→v3→jobs.json 顺序选择最新存在的前代，读取成功后复制到 v5，前代原字节不回写，最新存在者损坏时不回退更旧意图。既有 Video/Web/Scene 目录、managed/legacy metadata、属性与选择 owner 未改，启动仍先 reload 本地库。该批的 DEBUG 回退与保持原字节旧状态已在 SK6.2 按精确清单退役；SK6.1 的隔离 fixture 与构建证据不替代 SK7 真实升级、账号和播放门 |
| 18 | SK6.2 | SteamCMD/自动社区登录产品引用与资源退役 | 工程切片已闭合：删除 `Authentication`/交互状态、`CommunitySessionController`、社区适配、HTML parsing/stub/hydration queue 及旧 SwiftUI 登录层共 8 个纯旧源码文件，并把其余混合文件收敛为单一结构化查询、现有 AppKit 网格/详情/下载库/播放入口和用户主动公开外链。移除 DEBUG 路由开关、PTY/输出解析/旧状态布尔量、自动社区登录与个人 HTML producer；产品模块扫描无旧类型或调用。删除 `SteamCMDRuntime.bundle` 全部 91 个 tracked paths、82,807,675 bytes（78.97 MiB）；隔离 Debug `.app` 扫描旧 runtime 路径为 0，Web runtime 源码仍参与成功构建。升级启动以四个独立 marker 精确清除旧密码 Keychain（service/account）、旧用户名/认证时间 defaults、专用 WebKit store UUID、`Caches/MyWallpaperX/SteamWorkshop` 与 `Application Support/MyWallpaperX/SteamWorkshopRuntime`；失败仅重试本组件，不触及系统浏览器、Steam 客户端、`SteamJobs` 或 Video/Web/Scene 壁纸库。专用 WebKit store 清理会先初始化 WebKit store owner、枚举当前标识，仅在旧 UUID 确实存在时删除；不存在也写入完成 marker，避免 App 构造早期直接调用 class-level store API 的 `WTF::RunLoop::dispatch` 崩溃。隔离 DEBUG runtime gate 的私有 defaults suite 不执行真实退休清理，避免新 marker 命名空间误删用户 Keychain、WebKit store、cache 或 runtime；注入系统边界的可执行 Swift harness 已证明成功幂等、失败组件独立重试、精确目标删除且 sibling sentinel 保留。隔离 staged arm64 Debug App 启动命中 skip 诊断，启动前后的真实旧 Keychain 条目仍存在、生产 marker 仍未写入。删除 HTML producer 前补齐结构化 children→dependency IDs 严格映射，并使作者页往返恢复 store 分页快照。12 个 Steam 离线模块、helper protocol/auth/manifest/staging/download/query 自检和 arm64 无签名 Debug build 通过。开发 helper 下公开列表已在隔离 App 可见，但尚未实测生产启动的真实旧数据清理、账号、下载、播放与完整 UI／性能矩阵；该批隔离包当时未内嵌 SteamService；后续打包修复见 SK7.2，不能以环境注入或编译绿色冒充发布可用 |
| 19 | SK7.1 | 全链路 UI、异常与性能验收 | 进行中：隔离 staged arm64 Debug App 已执行匿名公开列表和未登录个人来源入口。`Steam 已订阅` 中央空态现在直接从唯一 `source`/`steamAuth` 权威派生登录引导，并订阅账号身份变化；不保存第二个登录布尔量、不创建 helper 请求、不自动打开认证窗口，工具栏账号项仍是唯一用户动作。未登录点击公开卡片下载时继续由同步 admission 在 JobStore／瞬态投影／执行器之前拒绝；既有单一 `statusMessage` 现在驱动浏览区就地横幅与账号按钮橙色提示，来源切换后由后续状态覆盖，不累计 toast 或回放被拒绝点击。App 初始化不再 eager fetch 公开 feed；浏览视图已有的 `prepareForBrowserEntry()` 成为按需查询入口，已授权 token 恢复仍是允许的启动例外。公开 helper readiness 与 auth intent 已分离：signed-out 的公共查询启动／协议失败不会再伪装成登录失败；客户端 typed error 实现 `LocalizedError`，缺失组件给出可操作中文文案。可见运行确认本地库启动停留期间零 helper，进入 Steam 浏览后才出现一个 helper 并由 skeleton 收口到可滚动列表；缺失 helper 时同一主窗口显示可重试错误，重复重试仍有界，账号按钮保持“登录 Steam”且无认证面板。同时确认中央空态、下载提示横幅、账号按钮 Help 切换、来源切换清除提示，以及未登录下载隔离目录没有生成任务 sidecar。可执行 lifecycle fault injection 证明 ready helper 崩溃会使 pending 公共请求 typed `connectionLost` 收口、未登录账号投影保持 signed-out、只创建一个新 session generation，连续 ready/crash 在预算耗尽后进入 terminated 而不无限拉起；§9.1 的两个当前开发 helper gate 又以精确 child `SIGKILL` 分别复验 idle 与 pending 查询崩溃，确认 generation 1→2、单 replacement、pending typed failure、显式重试成功与有界 shutdown。下载任务 popover 中原本仅有视觉 fill 的进度条现已补齐 progress-indicator role、逐任务 label 和实时 value；通知只在阶段或 10% bucket 变化时发送，取消／重试的即时状态也走同一有界出口。popover 打开后一次性把焦点放到“进行中／历史”，每行取消、重试、详情和历史查看的辅助名称都包含作品标题，不新增观察或刷新 owner。账号工具栏按钮不再只有固定“Steam 账号”图标描述，其动态辅助名称与同一 display state/登录提示文案同步，未引入第二个状态源。浏览网格现由容器持有瞬时键盘焦点，方向键按当前列数移动并滚入可见区域，Return／小键盘 Enter 复用唯一详情回调，Esc 仍关闭现有 inspector；它与已下载网格共享纯导航 owner，移动不写业务选择或任务状态，卡片异步刷新也保留焦点字段。追加页失败现在由同一分页 owner 发布底部“加载失败 · 重试”状态，显式按钮只解除短暂冷却并复用当前 route、QueryKey、generation 和单请求 guard；既有可执行查询反例确认失败不推进 nextPage、不清空旧页，来源往返快照也保留该失败展示，不创建 UI 第二缓存。主窗口的 Space／Esc 分发也在 Steam 浏览页停止，不再回落到此前本地壁纸选择的通用 Quick Look；Steam 已下载页仅在自身 Quick Look 确实可见时吞掉 Esc，否则由网格退出多选或关闭现有 inspector。登录面板的密码与 Guard 表单现有 Return 默认动作和明确首次焦点，二维码放大成为可 Tab 的系统按钮；二维码／状态文本补齐辅助语义，状态只在真实文本变化时发出有限通知。§9.1 已记录当前 M4 的开发 helper 启动、空闲 RSS、三页探针与产品 IPC 观测，所有测量进程均正常退出且无残留。15 个 Steam 模块（含键盘移动、分页失败 footer 与旧页保持可执行反例）和 arm64 Debug build 通过。当前仅证明开发 helper、离线 fault injection、辅助属性代码路径、键盘导航与分页失败展示合同，以及这些未登录／缺失组件交互切片；底部重试仍未做真实断网触发与点击实测，真实账号／Guard、订阅写入、已授权下载／取消／重试、播放、网络／磁盘、20 次交互、低配／完整 App 性能、深浅色、键盘实按／VoiceOver 实际朗读和正式签名包仍未验收，不能称 SK7.1 完成 |
| 20 | SK7.2 | arm64 发布、许可与升级验收 | 已接入固定 SDK、自包含 .NET 8.0.31/osx-arm64、Xcode 内嵌、逐项 native 签名脚本及许可随包；真实签名、公证、最低支持机和账号/下载链仍待验收 |

本轮审查维护门（全部无真实账号/外部网络，不能替代 §9）：

```bash
python3.12 script/run_scene_tests.py --scope all -k test_steam_ -j 1
/bin/bash script/run_checkpoint_build.sh
```

`script/tests/test_steam_helper_offline.py` 将当前 helper 源码和锁文件复制到隔离目录，仅使用本地空 feed 与已有包缓存 restore，运行 protocol/auth/manifest/staging/download/query 六套真实 C# 自检；缺 SDK/包缓存应失败，不跳过假绿。其余 maintained Swift harness 使用真实 client/query/JobStore/事务/执行器/订阅与分页源码及假 wire，磁盘测试只写隔离目录。账号门脚本只在显式真人验收时运行：`script/steam-auth-gate.sh --help`，支持 password/qr/wrong-password/restore；有整体 deadline、attempt/epoch、Guard ack与终态断言，禁止输出原始帧或令牌。二维码模式仅显示用户需要的临时挑战链接，不落盘登录凭据。

当前偏差的 owner/退役门：SK4.3 的新最终 owner 已是公开类型目录，隐藏 v1 只保留迁移读取与 playback-safe 回收；正常 incoming 和 job staging 均精确清理，但真下载、迁移后播放、跨卷／断电仍需可见验收。SK4.4 接管 helper 暂存失败现场、物理下载排空与恢复，当前有界保留不是永久暂存 GC 策略；SK5.1–SK5.3 已接数字进度、统一任务面板和 JobStore 有界历史，但真实可见/多任务/observer 压力证据仍归 SK7；SK6 撤公共HTML/旧PTY/旧凭据与资源并完成默认路由切换；SK7 继续真实签名发行与 UI/账号/性能验收。禁止用离线绿色把这些剩余门直接勾完。

### 8.1 每卡开工和完成的统一规则

- **开工：**检查工作区及本卡依赖，展开精确 owned paths；只读当前卡、关联的 §3–§7 合同和直接源码。下列“拟新增”类型/测试名不是已有实现，不得以文件名存在冒充完成。
- **落代码：**先复现对应行为/缺陷并建立最小正反例，再迁移 producer→consumer→UI；保留一个产品权威。网络能力未证明不能用 fake success、旧 Cookie/HTML 或 SteamCMD 兜底关闭工作卡。
- **隔离：**中间实现以开发注入/明确测试 route 验证，不让未完成能力接管发行默认；不建立用户可长期选择两种后端的设置。SK2.2 起新 route 的所有 UI 禁止自动登录。正式切换前旧作业必须排空或取消，不能双发订阅/双写下载。
- **验证：**新增测试放 `script/tests/`，建议协议、auth、browse、jobs、UI projection 分模块；实际建好后再用 `python3.12 -B -m unittest script.tests.<实际模块名>`。Swift 改动完成相称 checkpoint Debug build；C# 改动完成当前固定 SDK 构建及自有 fixture。真实登录/查询/下载需获授权的测试账号与隔离输出；订阅写入另取得该测试行为授权。发布前才跑正式签名/公证，不把它们作为每卡前置。
- **完成：**给出 frozen source/build/protocol、实际结果、正反例、取消/迟到处理、删除的旧职责、跳过边界与证据位置；结构/fixture/真网络/实际 UI/发行分别标明。只完成后端时不能称 UI 卡完成，只跑 mock 不能关闭真网络门。
- **提交：**冻结 owned diff、检查暂存清单；提交说明包含本卡编号、问题/结果/验证。失败回退本卡的完整职责，不在运行时偷偷切旧后端；失败现场不随意删除。需要删除历史材料或生成资源时先列精确清单并遵守工作区规则。

### SK0.1 — 固定依赖、验证能力和输入形状

- **依赖：**无；复核 `SteamService/Program.cs`、`SteamService/SteamService.csproj` 与 §10 来源。
- **改造：**固定 SDK/NuGet 版本与锁定方式、osx-arm64、许可资料；用有界独立探针验证匿名公开列表、类型/年龄/排序过滤、分页、主账号订阅/收藏、密码/QR/Guard/token、一个实际内容下载。探针不依赖尚未完成的 App IPC/UI，不建立第二产品服务。
- **交付：**“操作→实际公开调用→身份/权限→输入输出→分页/失败/限流→证据”表，以及可脱敏复用的最小响应 fixture；查询/传输并发、页大小、超时和内存预算的初始值。
- **验收：**QR 和密码均能到同一 SteamID；至少三页数据去重后可核对；拿到实际文件并验完整性，元数据成功不算下载。无账号/授权时该门明确待验，不能把 probe 编译当通过。
- **退役/停止：**撤销“库提供某类就等于接口可用”的假设；必需能力受阻先记录能力差距，不能进入假实现。探针的可用调用后续迁入 helper，临时调度不进入产品。

### SK1.1 — 双端协议和确定性协议测试

- **依赖：**SK0.1 的字段/失败合同；产品联网仍不必接入。
- **入口：**`SteamService/Program.cs`；拟新增 `SteamService/Protocol.cs` 与 SteamWorkshop/Core 下的 Swift 消息类型。
- **改造：**实现 §6 envelope、字符串 ID、最大帧/队列限制、request correlation、terminal 去重、私密 payload 脱敏；统一 ready/pong/error 形状。命令解码与业务 dispatch 分离。
- **交付/验收：**C# 与 Swift 共用脱敏 golden 消息；半包、多包、Unicode、超长、未知版本/命令、重复 terminal、乱序进度、UInt64 最大值、日志泄密反例通过；任何失败有界结束，不锁死读取循环。
- **撤旧：**替代现有无 requestId 回显与不一致 envelope；不保留两个协议 writer。

### SK1.2 — helper 生命周期与 Swift 客户端

- **依赖：**SK1.1。
- **入口：**拟新增 `Modules/SteamWorkshop/Core/SteamServiceClient.swift`；现有 service composition、Xcode copy/sign 构建输入及 helper publish 配置。
- **改造：**只孵化受控 App 内 helper，双管道读写、握手、processEpoch、超时/取消/EOF、有限重启；让模块统一持有客户端，不接 playback multiplexer。创建可离线注入的 fake transport。
- **验收：**App 能请求当前 helper 并确认 binary/protocol identity；错版本、helper 缺失、崩溃、重启后旧 reply、shutdown 超时均进入 typed state；无 orphan、无 UI 主线程阻塞。只关闭 IPC 门，不宣称登录完成。
- **撤旧：**替换散落的测试孵化路径；不引入联网/认证自动触发，未登录启动只能建立必要的匿名查询/进程能力。

### SK2.1 — 密码、二维码和 Guard 认证后端

- **依赖：**SK1.2、SK0.1 的真实认证证据。
- **入口：**拟新增 `SteamService/SteamSession.cs`、认证回调适配；Swift AccountSession 消费点。
- **改造：**独立 callback pump；密码/QR 共用会话和 authAttempt；Guard 分型；切方式取消旧轮询；LoggedOn 核验 SteamID；只由显式 attempt 或已授权的 token 恢复驱动。
- **验收：**正确/错误密码、手机确认/拒绝、邮箱/令牌错误、QR 到期/刷新、取消后扫码成功、并发旧 challenge、断网恢复均有确定终态；旧 attempt 不写 token、不触发新 UI。实际服务与 fixture 结果分列。
- **撤旧：**新 route 不再使用 PTY 输出识别或 console authenticator；秘密不经 argv、日志或普通快照。

### SK2.2 — 工具栏唯一入口与登录面板

- **依赖：**SK2.1。
- **入口：**`Toolbar/SteamWorkshopToolbarController+Actions.swift`、`+Layouts.swift`；`UI/SteamWorkshopBrowserView.swift`、`AppKitSteamWorkshopBrowserView.swift`、下载页与详情的受保护动作入口。
- **改造：**账号状态按钮；二维码/密码分段、Guard、QR 放大与统一取消；面板归模块窗口，移除页面切换导致的错误销毁。拦截所有下载/订阅/个人列表自动 presentLoginGate：只就地引导、不创建 pending 副作用。
- **验收：**按 §9 未登录路径逐项操作，纯浏览不弹面板，主动订阅/下载打开登录；重复点击只有一面板；切页/关闭/迟到回调不自动回来。密码粘贴、QR 清晰、Esc/焦点返回、窄窗口不裁切；登录成功不执行之前被拒绝的点击。
- **撤旧：**撤销新 route 的“下载失败→登录弹窗”和独立社区账号入口，不保留第二 UI 认证 owner。

### SK2.3 — 会话持久化、换号与退出

- **依赖：**SK2.2。
- **入口：**现有 Authentication/credential store、service 初始化/退出；拟新增的 Keychain token 适配和 AccountSession。
- **改造：**按 §3.3 实现记住偏好、token/GuardData 原子更新、无 UI 恢复、过期/重连分类；用户主动登录后迁移旧密码，换号递增 epoch 并失效私人请求。
- **验收：**记住/不记住、Keychain 拒绝/写失败、token 拒绝/网络失败、A→B 换号且 A 迟到成功、退出后 helper 重连；都不自动弹窗或存错账号。旧本地壁纸可继续播放。
- **撤旧：**在成功迁移条件下撤旧密码条目；保存失败不伪报“已保存”，不拿 UserDefaults 用户名充当 online。

### SK3.1 — 统一结构化查询后端

- **依赖：**SK2.3、SK0.1 查询能力表。
- **入口：**拟新增 `SteamService/WorkshopQueries.cs`；Swift browse 消息适配；当前 BrowseStubFetching/Parsing/Hydration 的 producer 调用点。
- **改造：**公开/作者/ID/详情/订阅/收藏统一 query 合同，内部 SteamKit/经验证的公开 API 适配；consumerAppID、分页 cursor、partial/error、未知 total、限流与取消明确化。不在这里创建 UI 第二缓存。
- **验收：**匿名允许/拒绝、非目标 app、缺字段/私有/删除、空页、重复页、无下一 cursor、rate limit、取消后旧页；fixture 与真实三页查询一致，无 HTML/Cookie 请求。
- **撤旧：**新 browse producer 撤掉 DOM 提取；响应适配不继续调用旧个人登录控制器。

### SK3.2 — 浏览分页、过滤与详情补全 UI

- **依赖：**SK3.1。
- **入口：**Core 下 BrowseFetching/PageLoading/Navigation/HydrationQueue/BrowseStateRecovery、BrowseFilters；AppKit 浏览网格与 footer。
- **改造：**BrowseStore 的 QueryKey/generation/cursor；首次/追加/刷新状态分离；恢复各来源 scroll anchor，批量补详情/预览；完整列表/已加载过滤范围真实显示。
- **验收：**快速搜索/筛选 A→B 逆序响应、滚动 loadMore 重入、追加页失败重试、来源返回、三页以上去重、缺图/缺详情；已有页不清空、焦点不丢、主线程不等待。未登录个人来源只显示引导。
- **撤旧：**替换旧 page-number/HTML 结果来源及重复加载状态；不残留两套 generation 判断。

### SK3.3 — 已订阅/收藏重接与订阅写入

- **依赖：**SK3.2。
- **入口：**personal source、详情次级按钮、统一 subscription state；拟新增 helper 的订阅请求适配。
- **改造：**保留现有列表入口，使用主 SteamID 结构化分页；按 desiredState 写订阅、操作序号、超时查询对账；当前列表/详情/卡片一起更新，收藏读取不回网页。
- **验收：**同账号读写、写后读延迟、写超时且服务端已成功、连续点击、换号时旧响应；取消订阅保留本地和播放；未登录点击不排写操作。真账号写入仅在明确授权下执行，恢复测试前状态也属于授权范围。
- **撤旧：**取消“已订阅依赖网页登录”的调用链，未知状态不投射为 false；接口失败不清空旧列表。

### SK4.1 — 单一 JobStore 与持久任务意图

- **依赖：**SK3.3；该卡只用 fake transfer 验证，不冒充真下载。
- **入口：**Downloads、DownloadAccessors/Filtering/Selection、现有下载模型；拟新增 JobStore/任务持久化具体类型。
- **改造：**定义 job/attempt/queue ordinal/state/receipt；去重、优先级、每 job staging 租约、状态 reducer、入队/取消；仅认证有效时接受新下载。持久记录写入版本化、可原子替换的单一任务文件，不含凭据。
- **验收：**同项连续点击/跨来源点击只一任务；未登录 job 数不变；持久化损坏/写失败/重启、重复 terminal、账号隔离、旧 attempt 进度；UI 各入口读同一投影。
- **撤旧：**移走旧 service 多份 queue/active/pending 真值；旧作业先排空，不能迁移中双调度。

### SK4.2 — 一个真实下载作业

- **依赖：**SK4.1、SK0.1 内容获取证据。
- **入口：**拟新增 `SteamService/WorkshopDownloader.cs`；客户端 startDownload/progress/stagedComplete 消费点。
- **改造：**先单 job 闭合授权→manifest→有界 chunk→解压/校验→receipt；总量/已验证字节/阶段分别上报。路径、文件数/展开字节/磁盘预算落实；不写最终库。
- **验收：**实际文件与 manifest 完整；坏块/短读/服务器失败/权限拒绝/解压越界/路径逃逸、取消后写入终止；进度分母不混压缩字节。只验证 staged 内容，不把 network 100% 当 ready。
- **撤旧：**新作业不调用 workshop_download_item，不清共享 staging；临时 probe 调度不留产品路径。

### SK4.3 — 原子入库与自动进入已下载

- **依赖：**SK4.2。
- **入口：**DownloadLibrarySync/LibraryRecords/元数据保存、现有 ready 模型、JobStore terminal 消费点。
- **改造：**校验 receipt→`.mywallpaperx-steam-incoming/<UUID>`→验证→按类型原子 rename 到 `Video/Web/Scene/<WorkshopID>-<generationUUID>`→metadata ready；公开版本必须带可核对 commit 的强 marker，generation 路径永不复用，目录/marker 本身不算 ready，marker 失效的保留命名空间也不由 legacy scanner 接管。记录 commit receipt/阶段，使“文件已发布、metadata 未提交”崩溃后可对账恢复；正常路径精确删除本次 incoming 与 receipt-bound staging。v1 隐藏版本只读迁移并复用普通下载 copy-capacity owner，metadata 指针变化时不覆盖；旧版本消费 lease 已贯穿 Scene/Web/Video，回收跨等待复核 inode/marker，只删除超过龄期且不在 ready/事务/消费保留集中的受管 storage identity。
- **验收：**Video/Web/Scene 入库、未知类型/缺依赖、磁盘满、跨卷、崩溃注入、重复 stagedComplete；不重复记录、不覆盖旧 ready、不误播放。已下载页未打开也能在打开时看到新项；已有选择和当前桌面不变。
- **撤旧：**替代 stdout success/目录存在即成功判断；helper 不直接发布本地 ready；`.mywallpaperx-steam-versions` 不再接收新最终版本，待现存 v1 metadata 全部迁移并经播放引用回收后退役该根。

### SK4.4 — 取消、恢复、并发与重试

- **依赖：**SK4.3；单作业正确后才提高活动作业数。
- **入口：**JobStore、Downloader、staging lease、重连/取消协议。
- **改造：**两活动作业与共享 chunk 上限、单项取消/有限重试、登录过期后的已提交任务等待、manifest-aware 恢复。pause 能力未经证明则保持隐藏，不添加空按钮。
- **验收：**A 取消不破坏 B；总并发不超预算；helper 崩溃、App 重启、manifest 更新、同账号重登与换号、disk-full 重试；没有重复网络作业/最终提交、无共享目录互删。原子提交点后不能伪报取消成功。
- **撤旧：**删除全局 staging 清理、取消一个任务就清全队列/杀用户 Steam 的路径；恢复只靠实际 receipt。

### SK5.1 — 卡片 bar 的真实进度

- **依赖：**SK4.4；§4.3 的状态与颜色合同。
- **入口：**AppKitSteamWorkshopBrowserItem、SteamWorkshopGlassBarView、详情下载状态投影；拟新增共享 DownloadProgressPalette。
- **改造：**中性 track+裁剪 fill+文字/操作层，宽度按进度；状态色、未知总量、阶段、retry attempt；可见卡片增量订阅、复用解除观察、≤4Hz 与减少动态效果。
- **验收：**0/1/50/100%、未知总量、错误/等待/校验/保存、小宽度与深浅色；A 卡片复用为 B 不串进度；标题对比度/取消命中区/VoiceOver 正确；无全网格 reload 或自动跳页。
- **撤旧：**退役整条填色冒充进度与恒定扫描；只有未知总量状态可用不定指示。

### SK5.2 — 工具栏下载队列面板

- **依赖：**SK5.1。
- **入口：**ToolbarIdentifiers/Layouts/Configuration/Actions、拟新增 AppKit 任务 popover/行视图。
- **改造：**浏览与已下载工具栏的任务按钮+badge，唯一非模态 popover；进行中队列、状态/进度/取消/重试/详情、查看已下载。消费 JobStore，无第二轮询源或登录入口。
- **验收：**空态/多作业/长标题/溢出菜单/键盘/Esc/关闭再开；鼠标下按钮位置稳定；popover 关闭不停止下载且不持续布局；任务数与卡片一致。完成不会自动打开面板。
- **撤旧：**清理为新任务面板添加的临时状态副本；不把高频刷新塞进 NSMenu。

### SK5.3 — 历史与跨视图一致性

- **依赖：**SK5.2。
- **入口：**JobStore terminal/persistence、popover 历史列表、已下载导航定位。
- **改造：**历史成功/失败/取消、attempt 汇总、100 条/30 天保留上限、清历史范围；recordID 引用库；明确账号隔离、文件已删后的跳转处理。
- **验收：**清历史不删库/不取消任务；删库不取消订阅；任务终结与崩溃重启不重复历史；已下载/卡片/详情/popover 同步。20 次跨页面下载/取消/重试后 observer/任务计数有界。
- **撤旧：**去除由各视图自行累计的历史/已下载副本；历史不能成为文件存在或 ready 的权威。

### SK6.1 — 老用户迁移与默认路由切换

- **依赖：**SK5.3；此前只在明确开发 route 验证。
- **入口：**SteamWorkshopService 初始化、库/账号/查询缓存 schema、helper 装配、旧 route 选择点。
- **改造：**迁移现有文件/元数据/属性/选择；旧私人 HTML 缓存失效但不删本地壁纸；旧活动作业排空/确认取消后切新路。冻结版本回退方案，明确新 schema 在旧版本中的保护行为。
- **验收：**带旧库/旧密码/旧 Cookie/未完成旧作业/损坏缓存的升级 fixture；第一次启动无认证窗、无重复下载、已有壁纸仍可播放；回退不双写或破坏新记录。
- **撤旧：**新后端取得默认执行权，旧后端失去运行时接管能力；真实库只用隔离副本验证。

当前实现冻结的升级／回退边界如下：

1. SK6.2 后产品与 DEBUG 构建都只有 SteamKit route，不再接受运行时旧后端参数。回退只能撤回整个有界版本／提交，不能在当前进程切回旧下载；切换或回退前必须退出 App，让原进程内作业收口。新版本只恢复 JobStore 中可证明的 intent，不接管未知旧子进程或共享 staging。
2. 当前版本只写 `Application Support/MyWallpaperX/SteamJobs/jobs-v5.json`。首次没有该 sidecar 时，按 `jobs-v4.json`、`jobs-v3.json`、`jobs.json` 顺序选取最新存在的前代：有效则只读导入，损坏则保留原位并停止更旧回退，不得重放旧任务。导入成功、失败、后续执行都不改名、不删除、不隔离旧文件。已有 v5 sidecar 时不再次合并旧文件；缺 birth 的 v4 recovery 只保留相称任务／commit 意图，不保留 resume/cleanup 权。
3. 回退前先停止新版活动任务。上一版本仍只读取保留的 `jobs-v4.json`，再旧版本分别读取 `jobs-v3.json` 或 `jobs.json`；它们都看不到也不会破坏 `jobs-v5.json`。回退版本不得创建需要再向前合并的新任务；再次升级以既有 v5 sidecar 为准。可执行 fixture 冻结 v4/v3/jobs.json 原始字节，证明 v5 导入、保存和重启均不回写回滚源，并覆盖 v4 running/staged/committing/failed/completed/cancelled 的权限降级。本地库 ready/legacy 目录继续由原库 owner 读取，不随任务 schema 回退。
4. 旧密码、专用 Cookie 和 HTML cache 不转换成 token。SK6.2 在任何恢复／查询前以独立 marker 删除精确旧 Keychain service/account、用户名／认证时间 defaults、专用 WebKit store、SteamWorkshop cache 与旧 runtime 根；WebKit store 先建立 store owner 并枚举标识，旧 UUID 不存在时直接完成，存在时才调用删除；单项失败不阻塞其他清理也不扩大删除范围。新 token、SteamJobs、系统浏览器／Steam 客户端数据和壁纸库不在清理清单。
5. Steam 获取层没有独立持久筛选／选择 schema；Scene/Web 属性仍以原 record ID 与各自 defaults owner 保存。本批不搬迁、不重写这些键，只维持库 reload 与播放入口。真实升级 App 的首次播放和回退仍是 SK7 外部门。

### SK6.2 — 删除旧获取职责与打包资源

- **依赖：**SK6.1。
- **入口：**§7 精确退役清单、Xcode/CI 打包引用、Authentication/CommunitySessionController/HTML producer/SteamCMD 资源。
- **改造：**先列删除文件/符号/调用/包资源/专用缓存清单，依工作区规则处理；删除已被替代职责，保留公开外链、下载库与播放入口。移除开发迁移开关和无调用的备用协议。
- **验收：**当前产品构建/调用/包内容扫描旧 SteamCMD、自动社区登录、个人 HTML 获取均清零；行为回归仍通过；没有误删 UI 列表、壁纸 Web runtime 或用户浏览器数据。
- **停止：**唯一失败证据、归属不明文件/真实数据不得顺手删除；未获所需清理确认时记录剩余项，不能宣称旧路径已全部退役。

当前 Release workflow 已撤销对不存在的 `SteamCMDRuntime.bundle`、`steamcmd`、`libsteaminput.dylib` 与旧 Breakpad Inspector 的条件签名探针；门禁同时扫描源码资源和发布配置，防止已退役 runtime 以静默 `-e` 分支重新成为包职责。

### 登录与详情的视觉约束

登录面板采用与详情卡相同的 `InspectorGlassPalette`、22 点圆角与玻璃层；固定 **420×480 pt**，二维码、密码及 Guard 切换只更新中部内容，不移动或缩放窗口。账号、密码、验证码使用有标签的 40 点输入容器；二维码有独立白底、四模块静区与无插值呈现，失效/刷新会清除原图及放大窗。认证状态仍由既有 Route/Controller 控制，展示 View 不启动请求、不保存账号凭据。

详情只有一条阅读顺序：156 点高横向封面 → 居中标题 → **等宽作者/订阅双按钮** → 单行标签 → 默认展开的作品数据 → 完整作品描述。封面采用本地视频详情的高度，不以顶部羽化覆盖。作者昵称只在详情查询时补全：登录后通过 SteamKit Player 公开资料，匿名时通过 Steam 官方公开 profile XML（无 Cookie、无重定向、不触发登录），按钮显示真实昵称，点击仅进入作者工坊；资料暂不可用时明确提示，不把 ID 或“作者工坊”冒充昵称。名称请求绑定连接身份，最多等待 6 秒；公开请求并发上限 2、响应上限 128 KiB，禁用 DTD 并核对作者 SteamID，成功缓存最多 512 项且有效期 30 分钟，缺失昵称不得丢弃其余详情。订阅状态来自唯一账号 owner，未登录主动点击订阅则打开唯一登录面板，已订阅通过菜单取消。数据使用两列键值网格，统计、类型、大小、分级、时间只在数据区出现，标签独立置于其上方；未知字段不补零，浏览数不当评分。类型、分辨率等已展示字段从标签去重。标签不另设小标题，仅占一行，胶囊保留完整自然宽度，内容过多在面板裁切范围内横向滚动，不省略、不换行、不扩大面板，隐藏滚动条，支持触控板双轴手势和普通鼠标滚轮横向浏览。作者操作区、标签、作品数据与描述之间用淡分隔线分层。类目标题和订阅提示居中；长作品标题最多两行且完整文本可访问。

底部固定**一行三个按钮**：可伸展的主任务 + 38 点网页图标 + 38 点属性齿轮，相邻间距 8 点。主任务按当前作品显示“下载壁纸 / 设为壁纸 / 停止播放”；异步阶段另外显示排队/下载进度、正在保存/正在切换、失败重试与缺少依赖的明确状态。停止前重新匹配实际活动作品，不能按全局“有引擎正在播放”误停别的作品；暂停中的当前壁纸仍可停止。网页按钮仅打开作品页；图标有 tooltip、辅助功能名称和键盘焦点。

属性从正文移入同款玻璃面板，宽度使用详情的同一 360 点常量，首次打开高度与当前详情面板一致，默认在其左侧间隔 12 点并排显示，禁止用户调整尺寸；标题居中、左侧名称、右侧控件，按作者定义顺序排列，只滚动内容，不重复封面。右上关闭，Escape 关闭；现有属性持久化/预览 owner 不变。Web 仅显示作者声明且当前可见的受支持控件，按原默认值恢复；Scene 仅在点击齿轮后异步准备作者属性，关闭或切换属性面板后迟到结果不得重开。Video 没有作者属性时明确说明，不伪造参数，也不把全局播放设置写成单作品设置。未下载齿轮禁用并说明原因；缺依赖或没有属性给出明确空态，不弹登录。不同类型的作品数据以当前实际字段为准，不对 Scene 打开详情就扫描/生成诊断。

登录、详情及属性面板的玻璃层、背景图层与最外层均按 22 点圆角裁切，不允许矩形底色漏出。登录窗口以 normal level 作为主窗口的 child window，仅高于主程序；属性窗口为可自由拖动、normal level 的独立窗口，关闭详情或切换作品不关闭已打开属性窗口。

登录公共区域位置固定，记住登录位于提交按钮之前；右上角关闭与 Escape/Cmd-W 取消本次认证。密码可显隐且关闭清空两份编辑缓冲；二维码失效就地显示提示与重新生成。登录成功但保存失败展示“完成”，不再暗示登录未完成。

浏览卡片右键、Shift-F10 与辅助功能动作提供同一作品菜单；详情订阅动作复用该命令投影。菜单绑定作品 ID，并在写操作前重验账号 epoch、订阅状态或下载 job/attempt，不按易变 indexPath 执行。未知订阅只查询，保存中不取消，不提供未实现的暂停/收藏写操作。布局门覆盖深浅色、固定尺寸、显隐密码、长标题/窄宽度；发布前仍需真实账号与下载验收。

### 审查修复后的执行边界

- **版本回收：**删除前必须完整读取并校验 managed metadata；缺失、读失败、解码失败或身份不匹配使本轮回收停止。展示列表可跳过坏条目，回收不得把它们视为空。每个版本删除前通过同一主 actor lease registry 预约；先获得的播放 lease 阻止回收，预约后的迟到播放拒绝并提示刷新。删除失败退回预约。
- **物理排空与空间：**CDN timeout/cancel 先终止 transport，再等待原始任务完成；共享 chunk slot 包含解密 buffer 和本地写入。磁盘 reservation 随已成功写入字节递减，只保留未完成分配量，空间不足仍保留可恢复暂存。
- **入库与清理：**prepare → 持久 committing → 发布 metadata → 持久 completed → 清理暂存。发布失败保留 manifest-bound staging；发布后的清理失败不回滚 ready。completed/cancelled 的未释放资源责任持久化，重载及物理任务退出后继续清理；失败删除不无限自旋。
- **重试与放弃：**忙碌重试复用同账号逻辑 job，以新 FIFO ordinal 排队，实际启动时递增 attempt，携带原 staging/manifest。失败行提供“重试／放弃”；放弃及删除失败记录先取消同账号同项目失败意图，再精确清理其 staging，其他账号与未知兄弟路径不受影响。
- **分页：**已加载页被本地过滤为空且 hasMore 时保留网格 footer，提供“继续加载”；失败可重试。空页不自动连续拉空后续页。

这些边界须由生产 owner 的可执行反例覆盖；离线 fixture、构建与无账号 helper 启动不替代以下真实链路门。

### SK7.1 当前复核队列（2026-09-21）

本轮跨专题执行顺序不另建平行计划：App/helper 定位回归和 ready 公开类型目录发布均已闭合实现批。用户再次报告远程数据为空、无法登录和找不到壁纸后，基线 `d4d4d5bf` 的 fresh 签名候选已重新执行 `App -> SteamServiceClient -> bundled helper -> SteamKit`：直接协议与普通 UI 均未复现列表／搜索缺失，主动登录到达二维码 challenge 后由取证取消。随后基线 `2eacca1b` 的真实库只读 census 证明隐藏版本根没有受管 generation，隔离产品 App 启动把真实形状 v1 复制并发布为公开 `Scene/<WorkshopID>-<UUID>`，incoming/staging 无残留。音频条件 consumer 批提交为 `22e6835f` 后，又用该 current-HEAD 签名候选的 bundled helper 复核匿名首屏与 QR challenge 发起／取消；结果仍正常，且本机 `/Applications` 旧 2.0.8 包继续缺 helper。三类证据分别只覆盖当前候选公开读取／认证发起、Scene 启动迁移与安装身份分歧；账号终态、已授权真下载、迁移后播放及到龄回收仍开放。current-HEAD 无账号审计已依次闭合复制中取消遗留 incoming UUID、App 持久化前 helper 提前写内容、device+inode 未覆盖 inode 复用、current/selected-predecessor JobStore 损坏后隔离并空状态续写，以及删除 ready 时 active update 仍在 helper 写入五个窗口；完整 birth identity 现贯穿 allocated/ack/receipt/resume/JobStore/cleanup，旧 ack-v1、缺 birth 的 v4 partial 与不可读／超前 schema 权威状态均失败关闭。删除现在先精确读取该 item 的 ready metadata、持久取消同一 JobStore attempt、调用唯一 helper 取消 owner，再发布 managed 或 legacy tombstone；身份未知或持久取消失败均保持内容与 ready 指针，不降级成路径扫描删除。fresh 基线 `65ee316b` 的直接 helper 与普通 App 仍分别通过匿名列表／搜索、远程卡片投影和二维码 challenge；随后 `3b8daa7a` 闭合公共 helper 崩溃预算耗尽后的显式匿名读取恢复。当前批又把默认 featured/week 空页定位到 Swift 对首个远端页做发布时间后过滤：官方合同与当前 SteamKit 探针均证明 `days` 是 1...365 日的趋势排名区间，collection total 保持相同而排序首项变化，因此删除该本地裁剪并让现有 QueryKey/唯一 helper query owner 端到端传递 `trendDays`；非法范围／非趋势排序拒绝，旧 helper 缺 `query-trend-days-v1` 时在发送前拒绝。真账号门不足时保留外部门而不重复已闭合发布审计。下一批回到[音频剩余 no-demand 集合](scene-open-breakpoint-queue-2026-09-09.md#q14-音频频谱与采集生命周期2026-09-20-当前态)，随后继续丁达尔射线、鼠标点击及粒子／轨迹／X-Ray。每项先核对公共 owner 与首断点，旧分支、重复 owner 或错误版本目录不能因已有测试而保留。

1. **App/helper 定位回归（已闭合）：**唯一发行位置是 `Contents/Resources/SteamService/SteamService`；产品定位器与行为门命中同一路径，环境变量只保留为显式开发覆盖，空覆盖、缺失及不可执行 helper 均失败关闭。Developer ID Debug build、签名验证、普通 App 匿名列表、搜索和主动二维码 challenge 已完成；没有账号 terminal，因此不写“登录成功”。
2. **物理入库与暂存回收（实现批已闭合，当前产品启动迁移复验通过，真实下载门保留）：**新 v2 内容经受管 incoming 验证后原子进入 `创意工坊/Video|Web|Scene/<WorkshopID>-<generationUUID>`，marker 只声明 ownership，metadata rename 仍是唯一 ready 点；legacy scanner 对整个保留命名空间 fail-closed，避免 marker 损坏后产生第二 ready owner，库根使用符号链接时也按物理父目录识别。v1 隐藏内容只读复制，复制前进入下载共用的容量队列/预留，发布前重核旧 metadata，旧播放路径不移动；失败有界退避且后续 reload 可重试。lease 与回收使用永不复用、含布局/类型/generation 的 storage identity，跨 actor admission 后重验原 inode 与 marker。正常成功、验证失败和取消不遗留本次 incoming UUID；helper descriptor identity 在首个进度事件以 device/inode/birth seconds/birth nanoseconds 落入独立 `jobs-v5.json`，terminal 不得首次绑定。恢复时完整 identity 随请求进入 helper，并在任何内容操作前对已打开根 descriptor 校验；缺 birth 的 v4 partial 清空 lexical recovery/cleanup authority并按状态保留任务或 prepared commit，同名或同 device/inode、不同 birth 的替换不会被写入或删除。v5 缺席时只读选择最新存在的 v4/v3/jobs.json 前代，前代损坏时不回退更旧意图。v1/incoming/v2 retained bytes 与本次新增共同受 16GiB 门约束。2026-09-21 真实库只读 census 中，`.mywallpaperx-steam-versions` 只有 `.DS_Store`、没有 UUID generation，`.mywallpaperx-steam-incoming` 缺席；116 个 metadata 中九个 v2 受管提交都指向带 marker 的公开 Scene 目录，另外 107 个无 managed commit，v1/other/parse-failure 均为零。真实 Application Support staging 由两次紧邻的运行后只读快照确认当前为空，不把它抬成 App before/after 证据。fresh App 两次把隔离的真实形状 v1 发布到 `Scene/3801984224-<UUID>`，metadata/marker 相等且隔离 incoming/staging 为零；第二次逐文件真实 Workshop 快照 before/after 相等。旧 v1 仍按 previous-current 与至少 24 小时回收门保留，不把它误称下载缓存。当前 birth 批的定向 helper/protocol 26 项、download 130 项、staging 49 项、fake execution 27 场景、library transaction 30 项及 JobStore v4→v5 状态矩阵均通过；未运行真实账号 helper 下载、Video/Web 产品迁移、迁移后播放、到龄回收、跨卷／断电，故 SK7.1 仍开放。
3. **最新报告复验（current HEAD 读取／认证入口通过；公共恢复断点已修，登录终态仍开放）：**基线 `22e6835f` 的 2.0.9 (277) Developer ID Debug 候选 `CDHash=08fc8db98ce5dbb124a89569f47a16844e944c44`，launcher/debug dylib/helper SHA-256=`b4495f2c0383e9b06af889a710f165cf014123b388d085734c9084c447133a94 / e03989f2144b478202fc4dd5eb39e257f0a71a704b0ba8d1184ff3c378faa638 / ff380595e2446bd4e7559b21ed0c305e50d2fc98054ca491d4a102771e5dc672`，deep/strict 验签通过。helper 直接匿名 `queryBrowse` 观察到 30 项、远端总量 3,210,563、wrong-app 0。首个 `loginQR` 负向探针沿用 account epoch 0，被 typed `cancelled / stale account epoch` 正确失败关闭；产品 `SteamAuthRoute.beginAccountIntent()` 的真实合同会先把 epoch 从 0 递增为 1。按该合同发出的第二个登录请求绑定 process epoch 1、account epoch 1 与唯一 attempt，到达有序 `connecting -> qrChallenge`，随后用同一 attempt 主动取消；原登录 request 只收到 1 个 cancelled terminal，未保留临时 challenge URL。本轮又以 `65ee316b` fresh 候选重跑直接 helper 与普通 App：直接 `queryBrowse`／`Night vibe` 搜索均接纳 30 项，远端总量分别 3,210,821／43,930，二维码 challenge 生成后按同一 attempt 取消；普通 App 首屏可见远程卡片，搜索出现 `Night vibe / music / Assetto Corsa`，账号面板显示二维码及“等待扫码确认…”。因此当前成功路线仍未复现远程不可达；独立代码审计找到 `.terminated` 上显式匿名读取永久 `notReady`，编译行为红证据复现匿名 disconnect 污染认证态／epoch，现均由既有 client/auth owner 关闭。修复后行为还冻结 anonymous-only 恢复边界、两个并发读取共用一个 helper generation，以及 reset 后仍有界的自动重启；未增加 fallback、第二 client 或宽松错误处理。本机 `/Applications/MyWallpaperX.app` 仍是 2.0.8 (269)、`CDHash=fcf5ead265d79bcc551379a560234023a50c8087`，缺 helper且仍含已退役 SteamCMD runtime，若从该包启动足以解释三项现象，但报告时身份未冻结，不能据此精确归因。真实扫码／密码／Guard terminal、token 恢复与已授权真下载继续留在 SK7.1。
4. **current-HEAD 无账号下载链审计（`11c3bd34` 后续批，按职责逐项关闭）：**公开发布目录与 `<WorkshopID>-<UUID>` 自动命名本身保持单一 owner；当前真实库再查仍为隐藏 versions 仅 `.DS_Store`、公开 `Scene` 9 个受管 generation、incoming/staging 各 0，20 个 Steam 维护模块曾 ALL OK，但这不替代真下载。第一批复现并修正“复制中取消”窗口：旧实现已在 `.mywallpaperx-steam-incoming/<UUID>/content` 复制时收到 cancellation，defer 又调用会读取 sticky cancellation 的 `removeOwnedTree`，因此 rollback 在第一个子项前再次取消并静默留下 UUID；新反例在 64 MiB 受控副本出现受管 incoming 后取消，修复只让该 descriptor-bound rollback 忽略 task cancellation，普通 staging/reclamation 仍可取消，并把非取消型 rollback 失败写入诊断。第二批关闭 staging durable acknowledgement：旧 helper 在 `downloadProgress` 公布 lease 后立即预分配／写 chunk，App 的 JobStore 保存不是写入前置；现役链改为 `mandatory ready capability -> allocated -> App 校验 account/job/descriptor 并原子保存 identity -> exact acknowledge -> helper create/write`，错误、重复、迟到、30 秒超时或保存失败均不放行。第三批关闭 inode 复用窗口：helper 已从同一 fstat 取得的 birth seconds/nanoseconds 现与 device/inode 一起贯穿 active context、allocated event、ack、terminal receipt、resume、Swift JobStore、prepare/cleanup/reclaim；Swift 公共 incoming/版本回收也统一拒绝无效 birth identity，并在普通文件 unlink 前重开 descriptor、在其他叶子 unlink 前再次按完整 identity 复核。Swift incoming container 与 helper staging base 先验证卷的 birth capability，再创建 attempt-owned UUID/job 子项；子项创建后仍二次验证。已打开同一 FD 的 metadata/marker 纯只读快照继续按 device/inode/size/mtime 验证，不因卷缺 birth 隐藏既有 ready。任一缺失、范围错误或不一致均在内容收养／写入／删除前失败关闭，旧 `download-staging-ack-v1` 不与新 App/helper 半兼容。持久 owner 因此从 `jobs-v4.json` 升为 `jobs-v5.json`，v4 只读导入保留原字节；缺 birth 的 running/staged/failed/committing/completed/cancelled 状态矩阵还覆盖 job identity 与 receipt identity 整体缺席，证明 lexical recovery 权被移除而任务意图和 matching prepared commit 按各自 owner 保留。fake-wire 另覆盖 wrong birth 的 allocated/terminal、旧 capability、保存后 ack 与 fresh fallback；helper 自检覆盖 wrong birth seconds/nanoseconds 的 resume/ack、base capability preflight 与 replacement/full-identity removal；Swift library fixture 单独覆盖同 device/inode、wrong birth cleanup。第四批撤销 current v5 损坏时的 quarantine+empty-state fail-open：当前 v5 或选中的最新前代只允许 `O_NOFOLLOW` 打开的单链接普通文件；unreadable、symlink／特殊项、decode 失败或 schema 超前时该目录项仍是唯一权威，JobStore 保持原位，停止更旧回退，关闭该实例的全部 save/apply/enqueue，普通下载入口显示“任务无法保存”且不会产生 transient job、helper start 或 sidecar。compiled fixture 另冻结 dangling current 不回放有效 v4、dangling v4 不回放有效 v3，服务点击保持 symlink 且不创建 target。损坏恢复／人工修复 UX 尚未实现，不把拒绝写入冒充修复数据。第五批闭合 ready+active update 删除：删除 owner 以 exact item filter fail-closed 读取 metadata，先持久化同一 active JobStore attempt 的 cancelled 状态，再由既有 `cancelDownloadImmediately` 发送 exact helper job 取消并等待 terminal cleanup；managed commit 写 `removed`，旧直达记录写 `legacyRemoved`，二者都让 scanner 不再投影 ready，但内容继续由未来 playback-aware 回收 owner 处理。元数据缺失／损坏／身份不一致、取消持久化失败均不物理删除内容；已持久取消后的 staging cleanup 失败保留 cancelled 与 tombstone，不制造 orphan failed transient；静默取消不会覆盖外层“已移除”反馈。剩余 finding 只有全部 v1 generation 退役后隐藏根及 `.DS_Store` 的最终退役门，仍为 P3，不与音频批捆绑。

   该 acknowledgement 批以 `c54d84172d3f0066a4d4eee52665cdcaff7d4d23` 为基线；独立审查前的 17 路径冻结 diff SHA-256=`4458d92cd4843b7521de41678a49ab0e0250815b03583b86479a1b0dc7ca807a`。初审提出 2 项 P1、4 项 P2，并另保留 1 项 P3（最终批次身份与审查结论尚未写回）：缺 mandatory capability、timeout 后首个 retry 仍引用 helper 已删除 lease、allocated 事件未核对 frame epoch、helper publication/ack 未同锁、pathname replacement 与文档原子性过称、helper-only C# 改动未选中产品构建，以及审查 trace 缺席。全部代码问题修正后，20 路径实现候选 SHA-256=`1e2be5b6da7ebd675980cbdb048273abc4e3426d013fd6b7ccfae123820c41a1` 经同一独立只读审查者复审，P0–P2 无遗留 finding；首轮纯追溯候选 full diff SHA-256=`473b50423d9c43ae6f9c22e63fa6a57f3d499461cb79c52f2164fb91669ec4d9` 的最终只读复审指出该 P3 尚未完整记录，本句修正交由同一审查者只核对追溯内容与路径集合，其 APPROVE 是本批 P0–P3 无遗留的关闭条件。当前验证为：Steam 定向 20 个模块 ALL OK；ack fake-wire 24 项、helper/protocol/selector 68 项、组合 39 项、client lifecycle 2 项均通过；文档 role/governance/semantics 3 门通过；checkpoint 的 11 个定向模块通过，随后被当前分支既有 code-health ratchet 债务截断，未把该失败写成通过；独立执行的标准 Debug checkpoint build 成功并实际 restore/publish/embed SteamService。最初 all-Steam 运行中 lifecycle fixture 因 fake helper 未声明新 mandatory capability 两次 15 秒超时，修正 fixture 后全量重跑通过，不隐藏该中间失败。审查与离线门未执行真实账号／网络／真下载／UI／发行，也不证明 POSIX pathname unlink 最后窗口为原子 compare-delete；birth identity、current-v4 损坏、ready+active update 取消与隐藏根最终退役继续保持开放，不能从分母移除。

   该 birth identity 批以 `39d2d4ccdf01bc786f9507f5aa1c7a6e9d5259f4` 为基线，owned paths 为同一组 20 个 Swift/C#/fixture/测试/本文路径。首轮冻结 full diff SHA-256=`ccf93c107e12229083fe35399e73865381848db44438951a54cc62493519b905`，独立只读审查以 2 项 P2 阻断：旧 receipt 整个 identity 缺席未撤销 recovery authority，且 Swift public incoming/reclaim 只比较 birth 而未拒绝非法范围。修正候选 `9ac47a8dbb3908e4cb70f15af4af40059ce65ab24f4d00fcc7383e41520701b6` 的二轮审查再以 2 项 P2 阻断：mutation comparator 扩大到 pinned-FD metadata read 而可能隐藏既有 ready，以及 Swift/C# 在验证卷的 birth capability 前已创建 attempt-owned child。第三实现候选 full diff SHA-256=`e73db3665e874bd71a8e131e5eafa73f41983f5dc2b4cf16c82ecc4f69a260c2` 已分别以 identityless receipt 状态矩阵、统一 mutation admission、pinned-read comparator、container-before-child preflight 及 wrong seconds/nanoseconds 反例关闭四项 P2；同一审查者复审 **APPROVE（P0–P2 无遗留 finding）**，P3 只剩本段追溯写回。最终验证为 Steam 定向 20 模块 ALL OK、helper selftest protocol/auth 26/26、manifest 32/32、staging 49/49、download 130/130、query 21/21、library transaction 30 项、fake execution 27 场景、JobStore v4→v5 状态矩阵、文档 13/12/7 与 checkpoint focused 10 模块均通过；标准隔离 Debug build `BUILD SUCCEEDED` 并实际 restore/publish/embed helper。checkpoint aggregate 在这些测试通过后只因当前分支既有 code-health ratchet／超限债务截断，未自动构建且未冒充通过；独立标准构建另行补足。中间失败如实保留：最早 allocated fixture 一次超时后中断、history harness autoclosure 编译错误、三次旧 docs module 名、首轮过严 special-leaf 清理导致 staging symlink 用例失败，均修正后重跑。没有执行真实账号／网络／真下载／重启恢复／UI／播放／跨卷／断电／Release 或真实 invalid-birth 卷；synthetic stat 与父容器 preflight 不能升级为 per-node 异常后零残留证明，POSIX 最后 pathname unlink 仍非原子 compare-delete。current `jobs-v5.json` 损坏、ready+active delete cancellation 与 hidden-v1 root 退役继续开放。本文新增段作为最终纯追溯候选交同一审查者核对；其对新 full diff 的 APPROVE 是本批 P3 与 P0–P3 全关闭条件。

   该 JobStore 权威损坏 fail-closed 批以 `796e7e5bb864f6231bd93a593e34407782f17cf6` 为基线，owned paths 为 JobStore、history/execution/backend 三组测试、execution fixture 与本文六个路径。首轮实现候选 full diff SHA-256=`d15c11fb55c4bb7bc8424d702e7add81528af098dfc2a4be3852f7e299058118` 删除 quarantine+empty-state 续写，冻结普通坏字节、future schema、选中前代和服务 no-start；独立只读初审以 1 项 P1 阻断：`fileExists(atPath:)` 跟随最终 symlink，使 dangling current 被误作 absent 并可回放旧任务，指向外部的 link 也会越过路径身份。修正后 current 与前代统一由 `open(O_NOFOLLOW|O_NONBLOCK)` 的三态 owner 读取，只有 `ENOENT` 是 absent；symlink、特殊项、权限／`fstat` 失败、多硬链接、decode 失败与超前 schema 均保持目录项并拒写，同一 FD 负责 type check 与读取。新增 dangling current→有效 v4、dangling v4→有效 v3 以及普通产品点击三组 compiled 反例，修正候选 full diff SHA-256=`4be614d2967f90fe0995c742739f942227343dcc52cbd52f073eb358d01c8e8d` 经同一审查者复审 **APPROVE（P0–P3 无遗留 finding）**。最终验证为 Steam 定向 20 模块 ALL OK、history+fake execution+backend 36 项、文档 13/12/7 与标准隔离 Debug build通过，构建实际 restore/publish/embed SteamService；touched JobStore 697 行、共享 execution harness 保持基线 799 行，code-health 对两者只有既有 review-limit warning，aggregate 仍被未触达路径的现存 ratchet／超限债务截断。中间失败如实保留：最初 Swift fixture 把 throwing read 放入 `precondition` autoclosure 导致编译失败；首轮 all-Steam 被已退役 `quarantineOnFailure: false` 源码形状断言阻断，改由 compiled 行为 fixture 承担；shared harness 曾被推到 824 行，随后在不删反例的前提下压回 799 行。没有执行真实账号／网络／真下载／重启恢复／人工修复／App UI／Release／跨卷／断电；fail-closed 不等于恢复损坏数据。本文追溯写回产生新的 docs-only diff 身份，交同一审查者纯追溯复核；其批准是本批最终关闭与提交条件。

   该 ready+active update 删除批以 `65e079f1e125c3fb557dd5dc10f96841b75cb380` 为基线，owned paths 为六个 Steam Swift owner、validation mapping、两个 execution fixture、execution test 与本文十一条路径。首轮五路径实现候选 SHA-256=`8d81f049718155fed2462ae7cab80cebcee9d5e086e9b62f53cf6711d48adb58` 的新增 compiled 反例先以 process `-5`／`delete must cancel the exact helper task` 复现旧失效，再通过；独立只读初审仍以 3 项 P1、2 项 P2 阻断：两次 fail-open metadata 读取会把 managed 删除降级成 legacy unlink；durable cancelled 后 cleanup 失败会尝试非法 `cancelled -> failed` 并投影孤儿失败卡；legacy direct ready 仍立即 unlink；silent cancellation 的 terminal 会覆盖“已移除”；新增生产 owner 未映射到 `steam-download-control`。修正后的首轮实现候选 SHA-256=`2f4bc8f733cda0feaecfc2d7429eec3036565dc67e4f5a2e9b046d4d8e4f9bb0` 以 exact metadata admission、managed/legacy tombstone、单一 helper cancel owner、同一 cancellation registry 携带反馈策略及扩充现有 validation group 关闭五项。后续复审先以一项 P1、一项 P2 阻断：历史 direct Video metadata 按导出文件 basename 而非 Workshop ID 命名，故 canonical exact reader 会漏掉常见旧视频；cancellation registry 的实际 owner `SteamWorkshopService.swift` 也未映射到 Steam execution 门。实现候选 SHA-256=`957c7c31c77e5c2aed934409e694cab3378f2f63f4240ee943255557cc48a1b1` 保持 canonical `<WorkshopID>.json` 优先且损坏失败关闭，只在 canonical 缺席时按当前 record 的视频 URL 推导唯一 alias，以同一 transaction owner 的 `O_NOFOLLOW`/单链接/有界 descriptor 读取；随后同时校验 snapshot item ID 与导出 URL，再把 tombstone 发布到 canonical。validation mapping 现覆盖 registry owner；另补 tombstone 发布失败反例，冻结“取消已持久化并发送 exact helper cancel、旧 pointer/content 保留、失败反馈不被 silent terminal 覆盖”的顺序。再次复审又以两项 identity finding 阻断：数字标题的普通 legacy Video alias 会被全局 managed loader 误认成 Workshop ID 并阻断回收／迁移，且带非空 managed commit 的 alias 会跳过 legacy 校验、又未经过 managed commit 身份校验。当前实现候选 SHA-256=`3d61956b7ea44a866156511d9b42ba5d48655a45415af04fad297e7f574e4cd2` 让全局 managed loader 忽略普通 commit-nil alias、只在显式 legacy/tombstone 查询时按 canonical identity 接纳，并让 basename alias fallback 只接纳 `commit == nil` 的旧版 direct Video 快照；数字 alias 与 commit-bearing alias 两个 compiled 反例分别冻结“不污染全局 managed 索引”和“在 JobStore 取消、helper cancel、canonical tombstone 之前失败关闭”。九个删除场景和完整 execution 37 项通过；中间曾有 cleanup-failure 断言过度绑定诊断措辞、legacy Video fixture 缺 metadata helper shim，以及 publish-failure 首版在读取前制造 canonical directory 而错误触发 fail-closed，均修正后重跑。identity 收紧后的当前候选重新通过 Steam 定向 20 模块与 checkpoint 的 15 个定向模块（含三项文档门）ALL OK；checkpoint aggregate 随后只被当前分支既有 code-health ratchet／超限债务截断，未自动构建且未冒充通过；独立标准 Debug checkpoint build `BUILD SUCCEEDED` 并实际 restore/publish/embed SteamService。transaction/shared harness 继续保持基线 1033/799 行。没有执行真实账号／网络／真下载／App UI／重启／播放中删除／跨卷／断电／Release；legacy alias metadata 与物理内容刻意保留，不能表述为缓存已清除，待未来 playback-aware 退役 owner 回收。十一路径冻结 full diff SHA-256=`b5740575b9798b900e66948770968e4504208ff43c67c6314cbf36b419d56940` 经同一独立只读审查者复审为 **APPROVE／P0–P3 无遗留 finding**；本句只写回审查身份与结论，不改变已批准实现、证据上限或开放边界，并交原审查者做纯追溯核对后提交。

### SK7.1 — 全链路交互与性能验收

- **依赖：**SK6.2；前卡证据绑定当前构建。
- **入口：**§9 所有路径、当前 AppKit/JobStore/helper 诊断与代表性自有 fixture。
- **实施：**低配 arm64 真机，匿名/密码/QR/Guard/记住/过期/换号、三页以上浏览、各种内容下载、取消/恢复/历史/自动入库；叠加快速操作与网络/磁盘故障。
- **验收：**无用户手势认证窗为 0、无被拒绝点击自动下载、交互 pending ≤100 ms、progress ≤4Hz、终态及时；至少 20 次跨页任务操作和一轮重启。滚动不被网络/校验阻塞，主线程/常驻内存/并发与日志有界；截图、键盘、VoiceOver 实测，不只做源码断言。
- **停止：**不通过就回对应卡修正并重跑相称影响面；不能通过降低内容/隐藏错误、换高配机器或恢复旧登录兜底关闭。

### SK7.2 — arm64 发行与最终交接

- **依赖：**SK7.1。
- **入口：**固定 .NET publish/Xcode 打包/CI、许可与发布签名文档、helper 协议版本。
- **实施：**self-contained osx-arm64、对应源码/依赖锁/NOTICE、所有嵌套 native 依赖、hardened runtime 最小权限、签名/公证与升级/不兼容处理；核对实际产物，不只看设置。
- **验收：**无 SDK/runtime 的最低支持 Mac 启动当前 helper 并完成账号/列表/下载纵向链；不带 osx-x64 自有产物/开发机路径/秘密；包体、冷启动、常驻内存满足 SK0/SK7.1 冻结预算。发布未验证时只报本地构建完成。
- **交接：**工作卡全部有对应真实证据与退役结果，稳定合同接管终态；归档计划前保留导航。生成物按精确清单清理，不把包体或日志提交进知识文档。

## 9. 用户路径与量化验收

| 场景 | 期望 |
|---|---|
| 首次打开/未登录浏览 | 不弹任何认证窗；公开浏览或明确登录指引。进入已订阅显示账号空态，主动点击下载打开登录；任务数不增长 |
| 主动密码登录 | 点击工具栏→面板→密码/Guard→成功；焦点回原位置、账号状态更新、当前个人列表加载。登录前点过下载也不能自行启动 |
| 主动二维码登录 | toolbar→QR→扫码确认→同一主会话；二维码过期/刷新/切密码/关窗/迟到扫码都有终态；任何分支不会另起社区登录 |
| 持久化 | 勾选记住后重启无 UI 恢复；不记住重启匿名；token 过期只显工具栏重登；Keychain 写失败明确“本次已登录，未保存”，不虚报保存成功 |
| 浏览到下载 | 下载 A→A 卡片真实 bar 填色→继续翻页搜 B→popover 看 A→校验入库→已下载自动有 A；浏览仍在 B、桌面不变 |
| 同项跨视图 | A 同时在公开/已订阅/详情/任务面板出现，取消/重试只发一次，各处状态一致；卡片复用不能显示 A 的进度到 B |
| 分页与筛选 | 快速更改条件、返回来源、loadMore 失败/重复回包不丢滚动与旧数据；总量/过滤范围真实；私人缓存不跨账号 |
| 重启/断网/换号 | 真实 receipt 决定可恢复性，不假 ready；已提交任务需要认证时等待用户工具栏操作；换账号不能继续前账号授权任务 |
| 任务历史与本地库 | 清历史不删文件；删本地不取消订阅；取消订阅不删本地；失败/取消不进入 ready 列表；更新合并旧记录 |
| 易用性 | 窄窗口/长标题/深浅色/减少动态效果、Tab/Return/Esc/VoiceOver、二维码放大/粘贴验证码、toolbar 溢出菜单逐项实测 |

项目初始验收目标：本地点击 pending 反馈 ≤100 ms；progress ≤4Hz、terminal 立即；主线程不做网络/解压/校验，连续滚动不被下载阻塞。数值为实施前需冻结的产品门，不是当前实测。记住登录后的恢复不额外弹窗；未登录或已取消时任何非用户主动登录/订阅/下载事件引起认证 UI，均为阻断缺陷。最少执行 20 次跨页面下载/取消/重试及一轮 App 重启恢复，记录任务/进程/资源是否有界；不得把有限测试称为永不丢数据。

### 9.1 当前 helper 与产品接缝观测（2026-09-21）

2026-09-15 的开发 helper 行和 2026-09-20 的候选行均是历史基线。首行是本轮基线 `65ee316b` 新建的 Developer ID Debug 候选及其直接 helper／普通 UI 复核；`22e6835f`、`d4d4d5bf` 与 `2eacca1b` 行分别继续承载此前 current-HEAD helper、普通 UI 和公开迁移 sentinel。这里都不是低配机、发行公证包或完整账号/下载性能门。

| 路径 | 次数 | 当前观测 | 证据边界 |
|---|---:|---|---|
| 2026-09-21 `3b8daa7a` 基线 → 趋势时间窗修正后的 fresh helper | 1 轮产品 NDJSON + 4 轮三页 probe | ready 声明 `query-trend-days-v1`；Video 趋势 1/7/30/365 日的远端 total 均为 1,399,699，但首项分别为 `3805188470`、`3803559783`、`3792056955`、`3737237256`，每轮 28–30 项且 hasMore=true；无 Video tag 的三页 probe 同样保持 total=3,210,859 而各窗口首项不同。0、366 及 newest+7 均返回 typed `unsupportedQuery`，负数和字符串返回 `protocolMismatch`；shutdown ok、exit 0 | 支持当前 fresh helper 的远端排名窗口、输入拒绝、能力声明和收口；不包含普通 App 网格截图、多页滚动、账号、下载、发行签名或性能。网络结果会随 Steam 内容变化；核心判定是同次 total 稳定且窗口间顺序发生变化。raw probe／fresh helper summary 与 build/selftest log 保存在 ignored evidence `2026-09-21-steam-trend-window-ranking` |
| 2026-09-21 `65ee316b` fresh 2.0.9 (277) Developer ID Debug 候选 → bundled helper 直接列表／搜索／QR + 普通 App UI | 1+1 | App `CDHash=33c491b5a3422f4f4e7f7941f378e0572841a6db`，launcher/debug dylib/helper SHA-256=`9d37e29071b7aabc48ba43e17ec91afdcf5b485d9bd03e592289f1219304d1c9 / 23183da109cc8643282f7eee757f01a60b976a0f26b824b9ce42bb87814a1ec7 / db76977f1c7ac722d32be79df18c983df063fdf9cb77a30656e52002266485dc`，deep/strict 验签通过。direct helper 的 trend 首屏与 `Night vibe` 搜索均 `ok=true`／30项／wrong-app 0，远端总量分别 3,210,821／43,930；account epoch 1 的 QR 依序 `connecting -> qrChallenge`，同 attempt 取消后 login 唯一 terminal=`cancelled`，shutdown exit 0。普通 App 首屏可见远程卡片；搜索出现 `Night vibe / music / Assetto Corsa`；账号面板生成二维码并显示“等待扫码确认…”，随后主动关窗取消；App/helper 均无残留 | 这是修复前成功路线的 current-source 基线，用来排除“当前 helper 普遍不能联网／不能发 challenge”，不是两个异常恢复分支的产品实机复现。没有扫码、账号 terminal/token、订阅、下载、安装覆盖或发行包证明；direct summary 与 build log 已保留，UI 为本轮辅助树观察，不冒充截图。首轮取证脚本在 cancel/login 并发 terminal 分流上丢弃先到的 login terminal并超时，修正 requestId demux 后才得到本行结果；该编排失败不冒充产品失败 |
| 2026-09-21 current-HEAD 2.0.9 (277) Developer ID Debug 候选 → bundled helper 直接首屏／QR challenge | 1+1 | 基线 `22e6835f`；App `CDHash=08fc8db98ce5dbb124a89569f47a16844e944c44`，launcher/debug dylib/helper SHA-256=`b4495f2c0383e9b06af889a710f165cf014123b388d085734c9084c447133a94 / e03989f2144b478202fc4dd5eb39e257f0a71a704b0ba8d1184ff3c378faa638 / ff380595e2446bd4e7559b21ed0c305e50d2fc98054ca491d4a102771e5dc672`，deep/strict 验签通过。`queryBrowse` 接纳 30 项、远端总量 3,210,563、wrong-app 0；account epoch 0 的首个 QR 负向探针被 typed stale rejection 正确关闭，随后 process/account epoch 1 的唯一 attempt 依序到达 connecting/challenge；定向取消使用同一 attempt，原登录 request 恰 1 个 cancelled terminal，helper shutdown 后无残留 | 只支持 current HEAD 的直接 helper 公开读取、认证发起、attempt/epoch 取消与进程收口；stale-epoch 负例不是登录故障。未重跑普通 App UI，未扫码、未提交凭据、未取得账号终态／token、未订阅或下载。expiring challenge URL 与 raw helper 输出未留存；summary manifest SHA-256=`a05670d7162a25df100ad820f184e4e6eef27ac75e8869521cf45bd5e1704bea` |
| 2026-09-21 fresh 2.0.9 (277) Developer ID Debug 候选 → 产品启动 v1 公开迁移 | 2 | 基线 `2eacca1b`；App `CDHash=77c4aab841a2c87a1293af1ac1d4161b64cb1d0f`，launcher/debug dylib/helper SHA-256 `f57a7f7ef5db8bdccd52293aac853c366f2618679e68d4918b1e434afd85d3ca / 163f5cefcafa5c2f4bb4f6962c43b930fe281e1424cbda0ca537cf3a54cb7098 / 4eb326259589e9e9fd3dc3654ae8c96574d55e141ba3b62a76edce3e5b66eae6`。隔离真实形状 `3801984224` v1 两次经普通 service 初始化发布为不同的 `Scene/3801984224-<UUID>`，首次 metadata 与 marker canonical hash 都为 `0afc3ffc4f38f8923762c51f8fc1608825f56548a0f867c63a04a8e87c197a38`，两次隔离 incoming/staging 各 0；第二次冻结的真实 Workshop 逐文件快照只差 before/after 标签，归一化后两端 SHA-256 均为 `54eaa1ca282005719172f6855a214a21bdb52754d1eda71083fbddbfb157daf2`。真实 Application Support staging 只由两次相邻的运行后只读快照记录 `EMPTY`。fresh build/strict-deep 签名通过，三模块 50 个测试方法 ALL OK | 支持当前产品启动 owner 的 Scene v1→v2 公开类型目录、ready pointer 和零 transient residue，并证明复验未写真实 Workshop。真实 Workshop 隐藏根没有受管 generation，九个 v2 均在公开 Scene。未登录、未真下载、未播放，也未运行 Video/Web 产品迁移、24 小时回收、跨卷／断电或发行门；隔离旧 v1 是 previous-current 保护，不是未清缓存 |
| 2026-09-21 fresh 2.0.9 (277) Developer ID Debug 候选 → bundled helper 直接查询／普通 App UI | 1+1 | 基线 `d4d4d5bf`；App `CDHash=e6ab49628b88573bc3a3f259c093a30b9465c025`，launcher/debug dylib SHA-256 `41138245615ed8cf7ef2ad7dcf67d44f45334895d7534dbb40fd965c5403b136 / a0d3748edfc32099bb05f0da023d64949ad02b7de4d863324b7a5a034ae5ab0c`，helper SHA-256 `9d7ad02317ec172a0333a64f3985f7e6355ecf076ffde6a6c92b2c3f3df9a272`。helper 首屏 `queryBrowse` 观察到 30 项、`total=3,210,234`、wrong-app 0；搜索 `Night vibe` 观察到 30 项、`total=43,918`。同一普通 App 首屏辅助树观察到远程卡片，搜索出现 `Night vibe / music / Assetto Corsa` 与 `Couple vibe / sound`；账号入口生成二维码并显示“等待扫码确认…”，随后主动关窗取消 | 支持当前候选未复现 helper spawn、匿名读取、列表／搜索投影和认证 challenge 发起故障；未扫码、未提交凭据，不能称登录成功。隔离 Workshop 没有下载任务或内容，真实壁纸库未写入；取证结束后 App/helper 无残留进程。缓存只有 summary manifest，raw helper/test/build 与脱敏 AX 输出未留存，不能独立重放这些运行观察 |
| 本机可启动 App identity 盘点 | 2 | 当前隔离候选见上；`/Applications/MyWallpaperX.app` 为 2.0.8 (269)、`CDHash=fcf5ead265d79bcc551379a560234023a50c8087`、helper 缺失。取证中按同名 App 选择曾启动旧安装包，使它与当前候选同时存在；随后按候选绝对路径重新连接才取得上述产品证据 | 只证明本机存在会导致结果分歧的旧 bundle 和同名选择歧义；用户报告时的 bundle identity 未冻结，故不能精确归因。未覆盖、删除或移动任何 App；安装当前候选不在本批授权内 |
| 候选 Debug App → bundle helper → 公开列表／搜索／主动登录 | 1 | App `CDHash=629798bfa90214b6fca17b1b9bb5e47d8e8f63db`；helper 进程实际路径为 `Contents/Resources/SteamService/SteamService`。创意工坊首屏显示远程卡片；搜索 `Night vibe` 返回 `Night vibe / music / Assetto Corsa` 与 `Couple vibe / sound`；账号入口生成二维码并显示“等待扫码确认…”，随后由取证主动取消 | 证明普通 App 已恢复 helper spawn、匿名列表/搜索和 QR challenge 发起；没有扫码、账号 terminal、token 保存、订阅、下载或发行包证明。隔离库根为 `/private/tmp/mwx-steam-app.XLmlOd/Workshop`，取证后已删除，未写真实壁纸库 |
| 产品服务冷／暖启动→ready→shutdown | 5 | 首次 585.3 ms，随后 35.2–37.9 ms；ready 后 RSS 最大 47.3 MiB；5/5 exit 0 | 只量 helper handshake 与空闲驻留，不含 App、查询、图片或下载 |
| 匿名统一消息 `uquery` 三页 | 3 | 每次 3×30；去重 90；总时延中位 8.03 s、最大 10.61 s；峰值 RSS 110.9 MiB；3/3 exit 0 | 开发探针路线，用于确认当前 SteamKit 匿名查询形状，不代替产品解码/UI |
| 产品 NDJSON `queryBrowse` 三页 | 1 | ready 36.3 ms；三页 terminal 5.32/1.31/1.29 s，总计 7.92 s；84 个接纳项全部跨页唯一，6 个 `result != OK` 条目进入 partial，wrong-app 0；峰值 RSS 112.7 MiB；shutdown exit 0 | `hasMore` 依据原始满页响应保持 true；安全 partial 丢弃不是缺页证明。单轮且当前网络可变，不构成性能完成 |
| ready 后真实 helper 崩溃→自动替换→产品查询 | 1 | 精确 `SIGKILL` generation 1 的唯一 child；43.0 ms 后 generation 2 ready，仍只有一个 helper；随后 `queryBrowse` 接纳 29 项、1 个 partial、wrong-app 0、`hasMore=true`；有界 stop 后 gate/helper 均 exit 0／无残留 | 一次性 gate 位于隔离临时目录并已移入废纸篓；只证明当前 framework-dependent 开发 helper 的进程换代，不含 UI、账号、下载或长期 crash loop |
| pending 产品查询中 helper 崩溃→显式重试 | 1 | 查询发出 100 ms 后精确 `SIGKILL` generation 1 的唯一 child；pending 以 typed `connectionLost` 失败，43.1 ms 后 generation 2 ready 且仍只有一个 helper；显式重试接纳 29 项、1 个 partial、wrong-app 0、`hasMore=true`；有界 stop 后 gate/helper 均 exit 0／无残留 | 一次性 gate 位于隔离临时目录并已移入废纸篓；未证明 App 错误页、自动重试、账号、下载物理排空或断网恢复 |

上述开发 helper 与 gate 结束后 `pgrep -x SteamService` 均为空；这里只建立当前 helper 的量级与残留反例门。SK7.1 仍需低配机上的完整 App 主线程、滚动、图片、20 次任务交互、下载并发和长驻内存实测。

## 10. 来源与能力边界

- [SteamKit2 3.4.0 项目](https://github.com/SteamRE/SteamKit/blob/3.4.0/SteamKit2/SteamKit2/SteamKit2.csproj)声明 net8.0/net10.0 与 LGPL-2.1-only；[许可证](https://github.com/SteamRE/SteamKit/blob/3.4.0/SteamKit2/SteamKit2/license.txt)及对应依赖分发义务必须落实。独立进程不自动免除义务；固定源码、NOTICE、重建/修改说明随发行策略验收。
- [Authentication API](https://github.com/SteamRE/SteamKit/blob/3.4.0/SteamKit2/SteamKit2/Steam/Authentication/SteamAuthentication.cs)有 credentials/QR 认证入口；[认证样例](https://github.com/SteamRE/SteamKit/blob/3.4.0/Samples/000_Authentication/Program.cs)区分 poll、GuardData 与 LogOn。样例的 argv/打印 token 不能照搬；实际二维码刷新与平台认证权限由 SK0 验证。
- [Valve ISteamRemoteStorage](https://partner.steamgames.com/doc/webapi/ISteamRemoteStorage)中 publisher-key 订阅接口不能用于本客户端；普通用户协议的查询/写入权限与公开匿名查询逐项验证。类名存在不等于可用，不能绕过内容授权。
- [Valve ISteamUGC](https://partner.steamgames.com/doc/api/isteamugc) 将 `SetRankedByTrendDays` 定义为 1–365 日的趋势排名窗口；它不是作品发布时间 cutoff，远端 `total` 不变不能用来推断该字段失效。
- MirageWallpaper 仅为 third-party-reference-pattern；已核对的本机参考项目 README（非仓库材料）说明长驻会话、token 恢复、订阅/收藏与下载集中在服务中。不复制 GPL 实现、Cookie 拼装或 UI。最终本项目不再依赖网页 Cookie 自动登录。
- SDK 路径、78 MB、构建成功不是当前功能证明；发行前核对 .NET 支持期、self-contained native 依赖、arm64 最低系统与签名。AOT/trim/single-file 仅在反射与 native codec 等兼容实证后开启。

<a id="sk01-能力验证-2026-09-15"></a>
### 10.1 SK0.1 能力验证（2026-09-15 匿名链实测）

以下保留早期探针记录；属于该探针当时的能力证据，不是本轮修复后产品构建的复验结果。

工程：`dotnet 8.0.401`、`SteamKit2 3.4.0`（NuGet lock `LockModeFilePathAndContent`）、`RuntimeIdentifier osx-arm64`、[NOTICE](../../SteamService/NOTICE.md)。探针源码 `SteamService/Probe/`（仅开发验证，不进入产品 IPC 路径）；命令 `dotnet SteamService.dll probe <help|query|details|uquery|auth-password|auth-qr|restore|subscriptions|download|matrix>`。

| 操作 | 实际调用 | 匿名 | 实测结果 |
|---|---|---|---|
| 公开浏览/排序 | 统一消息 `CPublishedFile.QueryFiles`（匿名 SteamKit 会话） | ✅ | query_type 1(最新)/3(趋势)/9(订阅)/11(点赞) 均可；每页 30，3 页去重 90；total≈320 万 |
| 分页 | 请求 `page` 字段 | ✅ | 响应无 `next_cursor`；hasMore=`received==pageSize`；分页 token 由页码+排序+筛选摘要构成，不是游标 |
| 标签筛选 | `requiredtags` | ✅ | `Video` 生效（total→139.8 万），与现有内容模式 tag 同形 |
| 搜索 | `search_text` | ✅ | 生效 |
| 趋势时间窗 | `days` 字段 | ✅（2026-09-21 纠正） | 早期因 `total` 不变而判断“被忽略”是错误推论。Valve 将该字段定义为 RankedByTrend 的排名区间；当前匿名 SteamKit 对 1/7/30/365 日返回相同 collection total、不同首项和顺序，证明字段生效。产品现只在趋势排序传 1...365，并移除错误的 `timeCreated` 本地裁剪 |
| 匿名详情 | `CPublishedFile.GetDetails` | ✅ | result=1，含 `hcontent_file`/`file_size`/preview |
| 匿名详情对照 | Web API `ISteamRemoteStorage/GetPublishedFileDetails/v1`（POST） | ✅ | HTTP 200；仅作对照路由，不作主链 |
| Web API 列表查询 | `ISteamRemoteStorage/QueryFiles` | ❌ | 接口不存在（404）；`IPublishedFileService/QueryFiles` 需 Web API key → **该路由禁用**，公开浏览只走匿名统一消息 |
| 匿名下载链 | `GetDepotDecryptionKey` | ❌ | AccessDenied：匿名取不到 depot key；**下载必须登录**（且需 WE 所有权），这是 SK0.1 账号门的硬依据 |
| 密码+Guard 登录 | Authentication 凭据流 + 邮箱验证码 | 账号已验 ✅ | 测试账号登录到 steamId `765611989968***62`，返回新 GuardData；令牌落隔离 state（0600） |
| 静默令牌恢复 | 保存 refresh token + `SteamUser.LogOn` | 账号已验 ✅ | `sameSteamId:true`，无 UI 无密码 |
| 二维码登录 | `BeginAuthSessionViaQRAsync` | **部分** | 挑战生成与 `ChallengeURLChanged` 刷新事件实测出现；**扫码确认闭环未完成**（用户中断），SK2.1 全流程重测 |
| 订阅/收藏列表 | `GetUserFiles(mysubscriptions/myfavorites)` + `AreFilesInSubscriptionList` | 账号已验 ✅ | 58 订阅 3 页（50+8+0）与 total 精确对上；727 收藏 3 页 150 条；状态核对 50/50 inList |
| 真实下载+完整性 | depot key→manifest→chunk adler→`project.json` | 账号已验 ✅ | 项目 1300076567：depot 431960，manifest 2218307088438485379，4 chunks，已验证字节 1646197 == manifest 总量，project.json 在，9.7 s；首连延迟约 3 s 记为观测 |

**冻结预算**（`SteamService/Probe/Budgets.cs`，改动需新证据）：query 页大小 30；HTTP 并发共享上限 2；超时 query 15s / details 20s / manifest 30s / chunk 60s / connect 12s / logon 30s；chunk worker 每 job 4；探针输出上限 2 GB / 10 万文件；进度合并 ≤4Hz（SK5 冻结 250 ms）。SDK `net8.0` + `osx-arm64` 单 RID；NuGet lock 双模式（路径+内容哈希）。

脱敏 fixture（SK1.1 协议 golden 输入）：`script/tests/fixtures/steam-probe/{unified-queryfiles-page1,unified-getdetails-anonymous,publishedfiledetails-anonymous}.json`。账号门验证命令与隔离输出目录（`--state /private/tmp/mwx-sk01-probe`）在探针 help 中；令牌只落 state 目录（0600），stdout 脱敏。

<a id="sk01-能力验证-2026-09-16"></a>
### 10.2 SK0.1 能力补充验证（2026-09-16 匿名链实测，`probe uquery` + `--match-any/--exclude-tag/--taggroup`）

为解禁「最后更新」排序与分面筛选而做的增量实测；命令与 tag 命中统计已并入探针（`ProbeHost.TagStats`）。

| 操作 | 实际调用 | 匿名 | 实测结果 |
|---|---|---|---|
| 最后更新排序 | `query_type 21`（RankedByLastUpdatedDate） | ✅ | 3 页 × 30 无重复；total≈320 万；与 `taggroups` 组合可用 |
| 标签 OR | `requiredtags` + `match_all_tags=false` | ✅ | `Anime+Landscape` anyHit 30/30，total 88.5 万（AND 对照组 total=0） |
| 分面分组 | `taggroups`（每组 `TagGroup.tags`） | ✅ | `{Anime}+{3840 x 2160}`：两组 anyHit 均 30/30，total 15.8 万 → **组内任一命中（OR）、组间全部命中（AND）**；单组 `{Anime+Landscape+Cute}` anyHit 30/30、allHit 0 → 组内 OR 确认 |

据此：`updated` 排序与分面筛选解禁（卡 08），分级（Everyone/Questionable/Mature）作为普通 tag 参与同一 `taggroups` 机制。

用户交互补充约束：卡片心形及详情标签不显示悬停 tooltip；订阅与下载的主动操作可打开登录，纯浏览与后台流程不得弹出登录。浏览默认趋势排名范围为一周；显式时间窗改变远端趋势排名区间，不对已加载作品按发布时间做二次删除。分面结果采用服务端过滤及客户端一致性校验，局部筛空不能将远端 hasMore 置否；自动续载暂停后保留手动继续入口。

分类（Video/Web/Scene）支持多选，同组 OR、跨主题/分级/分辨率组 AND。全部或清空最后一个选项恢复不限分类；类别全选归一化为全部。分类集合按固定顺序进入 QueryKey，变更时重置分页并拒绝旧 generation 回复。公开浏览单类别用 requiredtags，多类别用一个 taggroups 组；个人与作者列表使用同一客户端判定。结果按作品 ID 去重后保持服务端顺序，在同一网格混排，不按类别分别拉取并拼接。Steam 返回总量是远端查询总量，不应冒充本地复核后的精确匹配数。
