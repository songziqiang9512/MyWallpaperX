# SteamKit 统一创意工坊：浏览、登录、订阅与下载改造计划

<!-- document-role: active-plan -->

> 状态：现役专项计划；SK1–SK4.2 已有实现并完成本轮离线审查修复，SK4.3 已接通原子事务及播放感知版本回收；SK4.4 工程切片已闭合物理排空、manifest-bound 恢复、精确 lease 清理、同 job 重试、两活动作业/共享 chunk 上限及跨作业磁盘预留；SK5.1 工程切片已接通 item/attempt 精确数字进度、独立裁剪 fill 与卡片/详情增量投影；SK5.2 工程切片已接通账号隔离的工具栏 badge、单一瞬态任务 popover 及当前队列交互；SK5.3 工程切片已由同一 JobStore 接通持久 terminal history、attempt 汇总、有界保留/清理与已下载定位；SK6.1 已完成默认结构化路由和 sidecar 回退边界，SK6.2 已撤旧获取源码、产品引用、专用状态与 78.97 MiB 随包 runtime。SK7.1 已开始隔离 arm64 Debug 全链路 UI 验收，个人来源登录引导、未登录下载可见反馈、本地库启动延迟查询、缺失 helper 的 typed 错误／账号隔离，以及 ready 后崩溃的有界替换生命周期已覆盖；账号、下载、播放、真实进程崩溃与性能矩阵仍待继续。当前 Debug 包尚未内嵌 SteamService helper，self-contained arm64 打包与签名仍是 SK7.2 硬门。
>
> 复核：2026-09-15。本轮依据当前 Swift/C#、隔离文件系统与无网络协议测试、App Debug 构建，以及匿名公开列表／未登录个人来源／缺失 helper 重试页的隔离可见 UI；未使用真实账号、修改真实订阅或实测下载、播放与性能。§10.1 保留早期探针证据，不能代替本轮构建的真实链路验收。
>
> 权威：本计划细化[工程路线 E2/E6/E8](engine-refactor-program.md)，覆盖 Video/Web/Scene 共用的 Steam 内容获取，不改变播放器。本文覆盖此前“双网页登录/自动弹登录/保留订阅 HTML 主路径”的方案。
>
> 退役：SK0–SK7 完成、SteamCMD 与自动社区登录/个人列表抓取产品路径撤除、交互/数据/发布门通过后，稳定合同和功能证据接管终态，本文转历史。

实施从 [§8 工作卡](#work-cards) 的当前剩余项开始；产品交互约束查 §3–§4，数据/协议边界查 §5–§7，完整验收查 §9。不要先实现整个平台再补 UI。

## 1. 确定的产品规则

1. **一个 SteamKit 服务、一个主账号、一个订阅状态源、一个下载任务源。** 完整替换 SteamCMD 与“Steam 已订阅”自动网页登录/HTML 数据获取；保留现有列表、网格和详情入口，重新接入结构化数据。
2. **登录面板只由用户主动点击工具栏账号区域的“登录 Steam/重新登录/切换账号”打开。** App 启动、进入个人列表、点击下载/订阅、网络失败、token 失效、helper 重启均不得自动弹出登录、Guard 或网页窗口。
3. 未登录的受保护动作只给就地提示“需要登录，请使用工具栏的登录 Steam”，可以强调工具栏位置，但提示本身不打开登录。**不创建待登录下载/订阅写任务，不在之后登录成功时自动执行旧点击。** 保留页面位置，用户登录后再次确认自己的下载/订阅操作。
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
| [DownloadLibrarySync](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadLibrarySync.swift)维护 ready 记录与本地库 | 保留并明确为唯一入库发布者；与 JobStore 分离职责，helper stagedComplete 不等于 ready |

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
| 未登录点击下载/订阅 | 卡片或详情显示就地提示，工具栏温和强调；不建立任务 | presentLoginGate、自动续接下载、无限提示 toast |
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

`QueryKey = source/accountEpoch/search/sort/filter/contentMode/locale`；每次查询有 queryGeneration。当前协议为页码分页、每页 30 项，收藏详情批 30 项（helper 上限 80），查询并发 2。仅在成功采纳当前 generation 页后推进 nextPage；hasMore 按实际返回页宽判断。将来若服务接口改游标，显式升级协议，不能继续假定页码。搜索 debounce 300 ms 是仍需实测的交互目标。

- 初次加载 skeleton；滚动近底部只预取下一页，最多一个 loadMore，generation 变化取消旧页；按 workshopID 去重。失败保留已经加载页，底部“加载失败 · 重试”，不能清空整个网格。
- 搜索/筛选变化从第一页重新开始，来源切换保留各自页面与滚动 anchor；刷新用旧数据上方的轻量状态，不闪回空白。新 query 的回包校验 generation，不能让慢旧页覆盖新页面。
- totalCount 未知时显示“已加载 N 项”，不能猜总数；hasMore/cursor 由真实响应决定。订阅列表没有稳定 snapshot 时采用游标/去重＋revision invalidation，不承诺远端实时分页快照。
- **过滤正确性：**远端支持的过滤交给服务端；只支持本地过滤时明确“在已加载项目中筛选”，或完成有界全量 ID 获取后提供全量过滤。不能用一页过滤结果代表整个订阅库；详情缺失的条目保留 ID 占位和重试。
- 列表基础字段先展示，详情与预览后补；元数据缓存按 schema/version/query/账号区分，私人缓存退出后不可见。预览 URL 更新使图片缓存失效，NSCollectionView 复用必须核对 ID，避免错图/错进度。
- 浏览列表不轮询下载，不把卡片 viewport 当任务生命周期；同 item 在多个来源出现时共用 JobStore/subscription state。外链返回只在 App 激活时对相关 ID 做一次合并刷新，不抓取网页按钮文字。

### 4.2 订阅、下载、播放是三个独立动作

详情保留主下载/设壁纸按钮，订阅是次级动作；窄窗口可移到第二行，不挤掉作者/网页/刷新。未知订阅状态显示“正在查询”，写入采用 desiredState＋operationId；超时表示“待确认”，先读后重试，不盲 toggle。取消订阅保留本地内容和播放；删除本地不取消订阅。未登录都只引导工具栏，不开面板。

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
2. **路径/预算：**Swift 为每 job 分配隔离 staging 与受控根，helper 不能接受任意 outputRoot 写用户目录。拒绝 `..`、绝对路径、逃逸 symlink、大小写/Unicode 冲突、非法长度；约束文件数、展开字节、并发、重试与磁盘空间，空间估计包括旧版本＋暂存＋提交空间。持久下载暂存由任务租约管理，不在真实 Scene 样本根试验。helper 只接受已存在且祖先无符号链接的 staging 基目录；新作业排他创建随机直接子目录（0700），恢复仅可重新打开 JobStore 持久化的同一 `job-<GUID>` 直接子目录，且服务端当前 manifestID 必须一致。以目录描述符逐层 openat/O_NOFOLLOW 创建或收养 manifest 已声明节点，新文件 O_EXCL/0600；记录设备、inode 和创建时间，写入/终验拒绝替换节点、多硬链接及非普通文件。已有文件长度一致后逐 chunk 校验，只有有效块计入恢复进度，其余块重新下载。helper 在新文件预分配/写入前按缺失 chunk 预留物理空间，App 在版本复制前按完整 receipt 预留；两者都减去同 owner 其他作业预留并保留 256MiB 安全余量。App 串行执行版本复制，避免已写入字节又被完整 reservation 重复扣减；staging 与 library 同卷时，还按另一个尚未进入复制阶段的活动作业预留最多 8GiB，且复制预留存在期间不启动新 helper 作业，避免两个进程互不可见的预留发生超卖。`diskFull` 不覆盖旧 ready，并保留当前 manifest-bound 暂存供释放空间后显式重试。成功前再次核对回执路径的根目录身份。释放 helper 租约只关闭描述符；App 等到物理 terminal 后，以同样的直接 lease/name/no-follow/inode 边界精确清理成功、取消或不可恢复 manifest 失配的暂存，不枚举或删除未知兄弟目录。
3. **校验：**写盘前整份 manifest 纯校验：无符号总量先与剩余预算比较，再安全转为文件长度；chunk 按 offset 验证无重叠、无空洞、完整覆盖文件。清单内路径统一检查目录/文件及大小写、Unicode 规范化冲突。首期另设 262144 chunk、单路径 4096 字符/64 层、路径索引 8Mi 字符预算；这些是资源拒绝上限，不是兼容性声明。根目录必须有非空 `project.json`。终验核对实际长度与 checksum，在文件/chunk/每次至多 64KiB 读取间响应取消。manifest/chunk 完整性和最终内容/类型校验分层；只有 metadata/零字节/部分文件不算完成。CDN 失败有 backoff 与上限，权限拒绝先判断会话/许可，不无限换服务器。进度区分网络字节、已验证字节与阶段总量，避免压缩字节分母混用。
4. **取消：**取消队列立即完成；活动作业请求取消后停止新 chunk，排空写入，回 `cancelled` 才释放 job；UI 可先“正在取消…”。helper 崩溃/管道 EOF 不得显示完成。需要强杀时只杀本任务 helper，并使其所有活动作业进入可恢复/失败，不能杀用户 Steam 客户端。
5. **原子入库：**Swift 校验 staged receipt（job/account/version/path/manifest）→复制或移动至库内临时版本→验证→原子发布记录；持久化提交阶段/receipt，覆盖文件提交与记录更新之间的崩溃恢复，不假设二者天然是同一原子操作。跨卷不能假定 rename 原子。磁盘满/取消/重复完成不覆盖旧 ready。更新使用版本目录或等价安全替换，正在播放的旧版本保留到消费端释放；属性/依赖/预览映射继续按稳定 workshopID 关联。
   下载完成凭证采用显式 `receiptVersion=2`，必须包含并核对 `jobId/workshopId/accountSteamId/accountEpoch/manifestId`、`stagedComplete/projectJsonPresent`、相等且有界的 `verifiedBytes/totalBytes`，以及本次 base 下的独占 `job-<GUID>` 直接子目录。`contentDigest` 是按 NFC UTF-8 路径字节序排序的所有普通文件的 SHA-256：每行依次写入路径 UTF-8 长度（UInt32 little-endian）、路径、文件长度（UInt64 little-endian）、文件 SHA-256 二进制；再对这些行串联求 SHA-256。空目录保留但不参与摘要。App 复制时再次计算同一摘要，拒绝 helper 完成后发生的内容变化。Swift 查询 API 返回完整 typed receipt，不丢弃为 Void，不以协议成功直接发布 ready。路径字段校验只确认归属和格式，不替代消费端的文件身份、链接、项目内容重验；入库提交前再次核对当前账号及作业 attempt。
   当前发布 owner 仍为现有 `.mywallpaperx-steam-metadata/<workshopId>.json`：完整内容放入库内 `.mywallpaperx-steam-versions/<UUID>/content`，该元数据增加 commit 指针，临时版本自身不代表 ready。文件复制/摘要和 project 验收在 utility task；最后账号与 attempt 检查到元数据 rename 之间不挂起。任务状态为 `running → staged(receipt) → committing(commit) → completed`，receipt/commit 先持久化再推进状态；重启只以身份完全一致且内容路径可用的已发布记录对账，未发布事务保留失败现场并等待用户重试。旧 v1 活动任务文件可读取，写入升为 v2；失败保存不向观察者发布虚假的状态变化。
   更新保留旧版本原路径；移除受管下载写 tombstone，避免旧目录被扫描复活。版本回收只处理 `.mywallpaperx-steam-versions` 下超过 24 小时的直接 UUID 目录，以当前 ready、JobStore 未决 commit、Scene/Web 活跃消费 token 和 Video 库持久路径组成保留集；依赖型 Web 的同一个 token 同时租住壳与依赖宿主的具体版本。删除过程基于目录描述符、不跟随链接，并在最终删除前复核 inode。未知条目与 helper 暂存树不进入版本回收；SK4.4 的下载 owner 只凭当前 job 的精确 lease identity，在 helper 物理排空后单独清理，不由普通同步枚举。每个暂存/版本根最多64个直接子项；开始新作业前已有内容不得超过16GiB，再加两个活动作业各8GiB上限，使单根逻辑上限为32GiB（同时受200k节点/8MiB路径索引预算及上述物理空间预留约束），超限明确拒绝。
   项目准入要求有界有效 JSON、scene/web/video 类型、受限相对入口及预览/依赖路径；scene允许入口封装于scene.pkg，web允许合法依赖项目。该准入不等于视频解码、HTML效果或Scene视觉兼容验收。配置根路径可用原生 realpath 解析物理路径，receipt路径本身不得借此绕过nofollow；Foundation路径规范化会缩写系统别名，不用于安全路径比较。

6. **恢复：**Swift 持久化最小 job intent/目标版本/暂存租约，不保存密码/token 到任务文件。App 重启后先校验 manifest 与本地块，显示“可继续”或“需重新下载”，不能伪装自动无损续传。网络断开可有界自动重试；账号切换后不自动恢复前账号任务，提示原账号恢复或移除任务。更新 manifest 改变时丢弃不匹配块，只清精确 job 暂存。
7. **自动进入已下载：**入库事务成功后一次性发布 ready 记录、更新浏览卡片/队列面板/已下载列表；即使已下载页未打开也必须更新数据源。历史条目引用同一 recordID，不复制一套已下载状态。失败/取消留在任务历史，不冒充已下载；更新成功合并同一 workshopID，不新增重复卡片。不自动切换页面、选中其他卡片或打断当前播放。
8. **播放：**现有“下载”不产生播放 intent。未来若增加“下载并设为壁纸”，必须另存用户操作的播放 epoch/display/选择，成功时重新确认仍为最新意图；不是本次默认行为。

## 6. IPC 与状态合同

有界 UTF-8 NDJSON，stdout 仅协议、stderr 脱敏诊断；支持半包/多包/Unicode 分段。初始每帧 1 MiB、有限 pending 命令与超时，SK0/SK1 冻结真实边界；禁止无限 ReadLineAsync 分配。SteamID/workshopID/manifestID 用十进制字符串。

Envelope：`v/type/requestId/processEpoch/accountEpoch`；认证另有 authAttemptId，查询有 queryGeneration/cursor，作业有 jobId/attempt/sequence。ready 返回版本/capabilities；accepted 不等于完成；每 request 最多一个 terminal。进度可合并，terminal 不得被节流丢失。helper callback pump 不阻塞 stdin；关闭/取消能终止正在等 Guard 或 QR 的异步等待。

| 命令族 | 请求与结果 |
|---|---|
| loginPassword / loginQR / cancelAuthentication / submitChallenge | 只接受 App 的工具栏用户手势创建的 attempt；QR 更新/Guard 挑战/取消/成功关联该 attempt，不自行打开 UI |
| restoreSession / logout | 仅显式记住偏好允许无交互恢复；敏感 token/GuardData 独立 private payload，不进普通 snapshot/日志；失败只改状态 |
| queryBrowse / queryDetails / queryAuthor / listSubscriptions / listFavorites | queryGeneration、筛选/排序、cursor/pageSize → 结构化 page/partial/error、真实 hasMore；无网页登录 |
| querySubscriptionStates / setSubscription | 主账号、itemIDs 或 desiredState/operationId；不确定结果查询确认；不得改其他账号 |
| startDownload / cancelDownload / queryJobs | job lease、目标版本、受控 staging；progress/stagedComplete/cancelled/failed。pause/resume 只有 manifest 对账能力实际成立才开放 |
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
| 08 | SK3.2 | 浏览分页、过滤与详情 | 结构化 route 保留同 key 原始已加载集合，整集合投影排序、失败保留页；updated/分级无能力明确禁用。SK6.2 后 discovery/ID/作者/个人列表只有同一 store，作者页返回还原 store 原始页、nextPage、hasMore 与 partial errors；详情 children 映射为严格十进制 dependency IDs，不再从 HTML 补依赖。真实分页/权限仍不能称完整验收 |
| 09 | SK3.3 | 已订阅/收藏与订阅写入 | dev route + 共享SubscriptionStore，unknown不得写、写超时先对账、无自动重写、账号隔离；个人排序/筛选仅限已加载集合，明确标注。Cookie不再是可用fallback。真账号/可见门待验 |
| 10 | SK4.1 | JobStore、队列与持久化 | 先在线准入；staged/committing 非终态；cancelAll 一次保存、失败不假推进并提示。任务 envelope 在 SK5.3 升至 v3；SK6.1 将默认文件改为 `jobs-v3.json`，仅在 sidecar 不存在时只读导入 `jobs.json` 的 v1/v2/v3 快照，旧文件不写不隔离，完整 App 操作仍待 SK7 |
| 11 | SK4.2 | 下载与完整receipt | 描述符staging、清单预算、v2跨语言摘要、串行进度发布/统一分母、typed磁盘错误、取消与成功共用决策点均有离线门。真实Steam下载与SDK物理排空仍待验 |
| 12 | SK4.3 | 原子入库与已下载 | 已接通版本准备/摘要与项目准入/元数据rename/列表刷新；ready 索引由事务 owner 有界 nofollow 读取且不依赖页面打开，播放 token 贯穿 Scene/Web/Video 及依赖宿主，旧版本按 ready/事务/消费引用延迟安全回收。离线事务门与 Debug build 通过；剩余真实可见、跨卷/断电实机与完整项目播放验收并入 SK7 |
| 13 | SK4.4 | 取消、恢复、有限并发与重试 | 工程切片已闭合：取消后的本地队列等待各自 helper 原 startDownload terminal（物理 I/O 排空）再推进，账号 epoch 改变不提前丢弃 waiter；helper 分配的受管 staging path+manifestID 在内容写入前落入 JobStore，崩溃重启只显示显式恢复，重试沿用同一逻辑 job 并递增 attempt、不跨账号。helper 仅重开同一直接 lease，当前 manifest 一致后逐块校验并跳过有效块；manifest 变化、取消与成功在物理 terminal 后由 App 精确清理当前 lease，未知兄弟和链接目标不受影响。App/helper 同为 2 个活动作业，各 job 最多 4 worker、跨 job 共享 4 个 CDN chunk 槽；A/B 假 wire 消融证明取消 A 不撤 B 的 task/running/ready。helper 缺失块与 App 版本复制均有跨作业磁盘预留、256MiB 安全余量及同卷跨进程保守额度，disk-full 保留可恢复暂存并给出重试动作；双成功假 wire 证明版本复制串行且两个 ready 均发布。离线事务 20 项、假 wire 执行 9 项、admission 两槽反例与 Helper protocol/auth/manifest/staging 39/download 115/query 门通过；真实双下载/续传/崩溃/disk-full 恢复及可见 UI 仍并入 SK7，不以离线绿色代替 |
| 14 | SK5.1 | 卡片 bar 真实进度填充 | 工程切片已闭合：helper 的 `sequence/stage/totalBytes/verifiedBytes` 由非 `ObservableObject` 的 item+jobKey+attempt store 严格吸收，拒绝旧 attempt、乱序、回退、超分母及超 8GiB 投影，不再把 helper 进度写入 service-wide `statusMessage`。浏览/已下载卡片只观察同 ID，reuse 显式解绑且弱 owner 自动清退；详情页在字节增量时只原位改 label/indicator，仅阶段/结构变化重建。`SteamWorkshopGlassBarView` 保留中性底轨并用独立 clip layer 按真实比例填充；未知分母才用不定态，已排队/下载/等待/失败语义色集中为 blue/green/orange/red，校验/保存/失败保留已验证比例，保存阶段禁用取消。标题/操作层在 fill 之上，窄卡只显示百分比，减少动态效果时不跑不定填充/走马灯，VoiceOver 只按阶段或 10% 桶通知。独立测试覆盖 0/1/50/100%、未知分母、等待/保存/失败保留、旧 attempt 与 A/B 观察隔离；9 个 Steam 离线模块及 arm64 无签名 Debug build 通过。真实 Steam 传输、深浅色/小宽度/点击/辅助功能的可见实机验收仍并入 SK7，未生产的 pause capability 仍不展示 |
| 15 | SK5.2 | 工具栏任务面板与队列交互 | 工程切片已闭合：浏览、作者和已下载工具栏共享同一 `steamDownloadTasks` 项；浏览与已下载页均保留账号入口，badge 只按当前 SteamID 计算非完成/非取消任务（含失败待重试），VoiceOver 与 overflow menu 同步数量。每个窗口的 toolbar controller 只惰性持有一个 transient `NSPopover`；普通按钮锚定工具栏，系统溢出时改锚窗口顶缘，外部点击/Esc 走系统关闭语义。面板打开才订阅 JobStore 的低频结构变化，逐行再按 item/jobKey/attempt 订阅 SK5.1 progress store；关闭清空 Combine/逐项 observer/缩略图请求，不停止任务。行内展示缩略图、长标题截断、阶段、真实大小/速度与稳定后 ETA、进度、取消/重试/详情；已有行在面板打开期间原位更新且不因状态变化重排，新任务追加，重新打开才恢复活动→失败待重试→排队/FIFO 排序。“全部取消”一次列数量确认且不删已下载文件，“查看已下载”和详情都走现有 Shell/Inspector 路由，完成路径不主动导航或打开面板。独立执行测试覆盖账号过滤、终态排除、排序/count/attempt identity，静态合同覆盖单 popover、溢出锚点、关闭解绑与无 Timer/NSMenu 第二刷新源；10 个 Steam 离线模块及 arm64 无签名 Debug build 通过。真实多任务按钮命中、键盘/Esc、深浅色和辅助功能的可见实机验收仍并入 SK7 |
| 16 | SK5.3 | 任务历史、保留策略与跨视图一致性 | 工程切片已闭合：JobStore 持久 envelope 升级为 v3，仍读取 v1/v2；jobs 与 terminal history 同一次原子写入，完成/失败/取消按 `jobID-attempt` 幂等记录，retry 沿用逻辑 job 并由面板汇总 attempts。保留配置冻结为最近 100 条且最长 30 天，每次写入/加载及打开历史面板时裁剪；历史按 SteamID 隔离，清空仅删当前账号终结记录，保存失败不假清除且不改变队列/失败重试意图/本地库。完成历史只保存既有库 recordID 引用；点击时重新通过当前 managed metadata/文件可用性判定，存在则导航已下载并定位/打开 inspector，不存在则明确提示并可转作品详情。popover 顶部已接“进行中｜历史”，切换/关闭解绑当前行高频 observer，历史只消费 JobStore 低频发布，无第二累计源。可执行测试覆盖 v2 无 history 迁移、完成重启不重复、两次失败 attempt 汇总、账号隔离、100/30 天裁剪、清理原子失败与任务保留；AppKit arm64 无签名 Debug build 通过。真实 20 次跨页下载/取消/重试、可见定位、observer/task 计数及键盘/辅助功能仍归 SK7，未以离线门宣称交互验收完成 |
| 17 | SK6.1 | 老用户数据迁移与新路切换 | 工程切片已闭合：该批 Release 固定由 SteamKit route 接管、DEBUG 曾保留一次整版本回退参数；discovery、严格 ID、作者作品、在线个人列表与离线登录指引均先由同一 `SteamKitBrowseStore` 路由，creator SteamID 支持作者查询。App 启动和浏览入口不再读取旧密码、runtime 状态或私人 HTML cache，只允许此前授权的新 token 静默恢复。任务默认写 `jobs-v3.json`；sidecar 不存在时只读导入旧 `jobs.json`，损坏旧文件保持原位且不生成新版状态，之后两文件互不写入。既有 Video/Web/Scene 目录、managed/legacy metadata、属性与选择 owner 未改，启动仍先 reload 本地库。该批的 DEBUG 回退与保持原字节旧状态已在 SK6.2 按精确清单退役；SK6.1 的隔离 fixture 与构建证据不替代 SK7 真实升级、账号和播放门 |
| 18 | SK6.2 | SteamCMD/自动社区登录产品引用与资源退役 | 工程切片已闭合：删除 `Authentication`/交互状态、`CommunitySessionController`、社区适配、HTML parsing/stub/hydration queue 及旧 SwiftUI 登录层共 8 个纯旧源码文件，并把其余混合文件收敛为单一结构化查询、现有 AppKit 网格/详情/下载库/播放入口和用户主动公开外链。移除 DEBUG 路由开关、PTY/输出解析/旧状态布尔量、自动社区登录与个人 HTML producer；产品模块扫描无旧类型或调用。删除 `SteamCMDRuntime.bundle` 全部 91 个 tracked paths、82,807,675 bytes（78.97 MiB）；隔离 Debug `.app` 扫描旧 runtime 路径为 0，Web runtime 源码仍参与成功构建。升级启动以四个独立 marker 精确清除旧密码 Keychain（service/account）、旧用户名/认证时间 defaults、专用 WebKit store UUID、`Caches/MyWallpaperX/SteamWorkshop` 与 `Application Support/MyWallpaperX/SteamWorkshopRuntime`；失败仅重试本组件，不触及系统浏览器、Steam 客户端、`SteamJobs` 或 Video/Web/Scene 壁纸库。隔离 DEBUG runtime gate 的私有 defaults suite 不执行真实退休清理，避免新 marker 命名空间误删用户 Keychain、WebKit store、cache 或 runtime；注入系统边界的可执行 Swift harness 已证明成功幂等、失败组件独立重试、精确目标删除且 sibling sentinel 保留。隔离 staged arm64 Debug App 启动命中 skip 诊断，启动前后的真实旧 Keychain 条目仍存在、生产 marker 仍未写入。删除 HTML producer 前补齐结构化 children→dependency IDs 严格映射，并使作者页往返恢复 store 分页快照。12 个 Steam 离线模块、helper protocol/auth/manifest/staging/download/query 自检和 arm64 无签名 Debug build 通过。开发 helper 下公开列表已在隔离 App 可见，但尚未实测生产启动的真实旧数据清理、账号、下载、播放与完整 UI／性能矩阵；隔离包同时确认当前尚无内嵌 SteamService helper，该发行阻断明确归 SK7.2，不能以环境注入或编译绿色冒充发布可用 |
| 19 | SK7.1 | 全链路 UI、异常与性能验收 | 进行中：隔离 staged arm64 Debug App 已执行匿名公开列表和未登录个人来源入口。`Steam 已订阅` 中央空态现在直接从唯一 `source`/`steamAuth` 权威派生登录引导，并订阅账号身份变化；不保存第二个登录布尔量、不创建 helper 请求、不自动打开认证窗口，工具栏账号项仍是唯一用户动作。未登录点击公开卡片下载时继续由同步 admission 在 JobStore／瞬态投影／执行器之前拒绝；既有单一 `statusMessage` 现在驱动浏览区就地横幅与账号按钮橙色提示，来源切换后由后续状态覆盖，不累计 toast 或回放被拒绝点击。App 初始化不再 eager fetch 公开 feed；浏览视图已有的 `prepareForBrowserEntry()` 成为按需查询入口，已授权 token 恢复仍是允许的启动例外。公开 helper readiness 与 auth intent 已分离：signed-out 的公共查询启动／协议失败不会再伪装成登录失败；客户端 typed error 实现 `LocalizedError`，缺失组件给出可操作中文文案。可见运行确认本地库启动停留期间零 helper，进入 Steam 浏览后才出现一个 helper 并由 skeleton 收口到可滚动列表；缺失 helper 时同一主窗口显示可重试错误，重复重试仍有界，账号按钮保持“登录 Steam”且无认证面板。同时确认中央空态、下载提示横幅、账号按钮 Help 切换、来源切换清除提示，以及未登录下载隔离目录没有生成 `jobs-v3.json`。可执行 lifecycle fault injection 进一步证明 ready helper 崩溃会使 pending 公共请求 typed `connectionLost` 收口、未登录账号投影保持 signed-out、只创建一个新 session generation，连续 ready/crash 在预算耗尽后进入 terminated 而不无限拉起。聚焦 client lifecycle／查询／下载准入测试和 arm64 Debug build 通过。当前仅证明开发 helper、离线 fault injection 与这些未登录／缺失组件交互切片；真实账号／Guard、订阅写入、已授权下载／取消／重试、播放、网络／磁盘／真实进程崩溃、20 次交互、低配性能、深浅色、键盘／VoiceOver 和正式签名包仍未验收，不能称 SK7.1 完成 |
| 20 | SK7.2 | arm64 发布、许可与升级验收 | 待实施 |

本轮审查维护门（全部无真实账号/外部网络，不能替代 §9）：

```bash
python3.12 script/run_scene_tests.py --scope all -k test_steam_ -j 1
/bin/bash script/run_checkpoint_build.sh
```

`script/tests/test_steam_helper_offline.py` 将当前 helper 源码和锁文件复制到隔离目录，仅使用本地空 feed 与已有包缓存 restore，运行 protocol/auth/manifest/staging/download/query 六套真实 C# 自检；缺 SDK/包缓存应失败，不跳过假绿。其余 maintained Swift harness 使用真实 client/query/JobStore/事务/执行器/订阅与分页源码及假 wire，磁盘测试只写隔离目录。账号门脚本只在显式真人验收时运行：`script/steam-auth-gate.sh --help`，支持 password/qr/wrong-password/restore；有整体 deadline、attempt/epoch、Guard ack与终态断言，禁止输出原始帧或令牌。二维码模式仅显示用户需要的临时挑战链接，不落盘登录凭据。

当前偏差的 owner/退役门：SK4.3 已接旧版本生命周期 token 与有龄期的安全回收，仍需可见/依赖验收；SK4.4 接管 helper 暂存失败现场、物理下载排空与恢复，当前有界保留不是永久暂存 GC 策略；SK5.1–SK5.3 已接数字进度、统一任务面板和 JobStore 有界历史，但真实可见/多任务/observer 压力证据仍归 SK7；SK6 撤公共HTML/旧PTY/旧凭据与资源并完成默认路由切换；SK7 冻结 SDK global.json、自包含发布、许可材料与真实 UI/账号/性能验收。禁止用离线绿色把这些剩余门直接勾完。

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
- **验收：**按 §9 未登录路径逐项操作，面板出现次数为 0；toolbar 重复点击只有一面板；切页/关闭/迟到回调不自动回来。密码粘贴、QR 清晰、Esc/焦点返回、窄窗口不裁切；登录成功不执行之前被拒绝的点击。
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
- **改造：**校验 receipt→库内临时版本→验证→发布 ready；记录 commit receipt/阶段，使“文件已提交、记录未提交”崩溃后可对账恢复，而不是凭目录非空当 ready。自动更新已下载、浏览卡、详情、队列；旧版本消费 lease 已贯穿 Scene/Web/Video，回收仅删除超过龄期且不在 ready/事务/消费保留集中的受管 UUID 版本。
- **验收：**Video/Web/Scene 入库、未知类型/缺依赖、磁盘满、跨卷、崩溃注入、重复 stagedComplete；不重复记录、不覆盖旧 ready、不误播放。已下载页未打开也能在打开时看到新项；已有选择和当前桌面不变。
- **撤旧：**替代 stdout success/目录存在即成功判断；helper 不直接发布本地 ready。

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
2. 新版本只写 `Application Support/MyWallpaperX/SteamJobs/jobs-v3.json`。首次没有该 sidecar 时可只读导入 `jobs.json`；导入成功、失败、后续执行都不改名、不删除、不隔离旧文件。已有 sidecar 时不再次合并旧文件，防止重放旧任务。
3. 回退前先停止新版活动任务。旧版本只会看到保留的 `jobs.json`，不能看到或破坏 `jobs-v3.json`；回退版本不得用于创建需要再向前合并的新任务。再次升级以既有 sidecar 为准。本地库 ready/legacy 目录继续由原库 owner 读取，不随任务 schema 回退。
4. 旧密码、专用 Cookie 和 HTML cache 不转换成 token。SK6.2 在任何恢复／查询前以独立 marker 删除精确旧 Keychain service/account、用户名／认证时间 defaults、专用 WebKit store、SteamWorkshop cache 与旧 runtime 根；单项失败不阻塞其他清理也不扩大删除范围。新 token、SteamJobs、系统浏览器／Steam 客户端数据和壁纸库不在清理清单。
5. Steam 获取层没有独立持久筛选／选择 schema；Scene/Web 属性仍以原 record ID 与各自 defaults owner 保存。本批不搬迁、不重写这些键，只维持库 reload 与播放入口。真实升级 App 的首次播放和回退仍是 SK7 外部门。

### SK6.2 — 删除旧获取职责与打包资源

- **依赖：**SK6.1。
- **入口：**§7 精确退役清单、Xcode/CI 打包引用、Authentication/CommunitySessionController/HTML producer/SteamCMD 资源。
- **改造：**先列删除文件/符号/调用/包资源/专用缓存清单，依工作区规则处理；删除已被替代职责，保留公开外链、下载库与播放入口。移除开发迁移开关和无调用的备用协议。
- **验收：**当前产品构建/调用/包内容扫描旧 SteamCMD、自动社区登录、个人 HTML 获取均清零；行为回归仍通过；没有误删 UI 列表、壁纸 Web runtime 或用户浏览器数据。
- **停止：**唯一失败证据、归属不明文件/真实数据不得顺手删除；未获所需清理确认时记录剩余项，不能宣称旧路径已全部退役。

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
| 首次打开/未登录浏览 | 不弹任何认证窗；公开浏览或明确登录指引。进入已订阅/点击下载只在原区域提示；任务数不增长 |
| 主动密码登录 | 点击工具栏→面板→密码/Guard→成功；焦点回原位置、账号状态更新、当前个人列表加载。登录前点过下载也不能自行启动 |
| 主动二维码登录 | toolbar→QR→扫码确认→同一主会话；二维码过期/刷新/切密码/关窗/迟到扫码都有终态；任何分支不会另起社区登录 |
| 持久化 | 勾选记住后重启无 UI 恢复；不记住重启匿名；token 过期只显工具栏重登；Keychain 写失败明确“本次已登录，未保存”，不虚报保存成功 |
| 浏览到下载 | 下载 A→A 卡片真实 bar 填色→继续翻页搜 B→popover 看 A→校验入库→已下载自动有 A；浏览仍在 B、桌面不变 |
| 同项跨视图 | A 同时在公开/已订阅/详情/任务面板出现，取消/重试只发一次，各处状态一致；卡片复用不能显示 A 的进度到 B |
| 分页与筛选 | 快速更改条件、返回来源、loadMore 失败/重复回包不丢滚动与旧数据；总量/过滤范围真实；私人缓存不跨账号 |
| 重启/断网/换号 | 真实 receipt 决定可恢复性，不假 ready；已提交任务需要认证时等待用户工具栏操作；换账号不能继续前账号授权任务 |
| 任务历史与本地库 | 清历史不删文件；删本地不取消订阅；取消订阅不删本地；失败/取消不进入 ready 列表；更新合并旧记录 |
| 易用性 | 窄窗口/长标题/深浅色/减少动态效果、Tab/Return/Esc/VoiceOver、二维码放大/粘贴验证码、toolbar 溢出菜单逐项实测 |

项目初始验收目标：本地点击 pending 反馈 ≤100 ms；progress ≤4Hz、terminal 立即；主线程不做网络/解压/校验，连续滚动不被下载阻塞。数值为实施前需冻结的产品门，不是当前实测。记住登录后的恢复不额外弹窗；未登录或已取消时任何非 toolbar 事件引起认证 UI，均为阻断缺陷。最少执行 20 次跨页面下载/取消/重试及一轮 App 重启恢复，记录任务/进程/资源是否有界；不得把有限测试称为永不丢数据。

## 10. 来源与能力边界

- [SteamKit2 3.4.0 项目](https://github.com/SteamRE/SteamKit/blob/3.4.0/SteamKit2/SteamKit2/SteamKit2.csproj)声明 net8.0/net10.0 与 LGPL-2.1-only；[许可证](https://github.com/SteamRE/SteamKit/blob/3.4.0/SteamKit2/SteamKit2/license.txt)及对应依赖分发义务必须落实。独立进程不自动免除义务；固定源码、NOTICE、重建/修改说明随发行策略验收。
- [Authentication API](https://github.com/SteamRE/SteamKit/blob/3.4.0/SteamKit2/SteamKit2/Steam/Authentication/SteamAuthentication.cs)有 credentials/QR 认证入口；[认证样例](https://github.com/SteamRE/SteamKit/blob/3.4.0/Samples/000_Authentication/Program.cs)区分 poll、GuardData 与 LogOn。样例的 argv/打印 token 不能照搬；实际二维码刷新与平台认证权限由 SK0 验证。
- [Valve ISteamRemoteStorage](https://partner.steamgames.com/doc/webapi/ISteamRemoteStorage)中 publisher-key 订阅接口不能用于本客户端；普通用户协议的查询/写入权限与公开匿名查询逐项验证。类名存在不等于可用，不能绕过内容授权。
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
| 趋势时间窗 | `days` 字段 | ❌ | 全部排序下被静默忽略（total 不变）；**能力缺口**：SK3.1 决定客户端按 `time_created` 过滤或砍掉该筛选 |
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
