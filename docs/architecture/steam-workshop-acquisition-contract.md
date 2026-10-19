# Steam 创意工坊获取合同

<!-- document-role: stable-contract -->

> 状态：现役长期合同。2026-10-16 从已完成的 SteamKit 迁移计划接管获取职责；本次按源码核对所有权与数据边界，没有重新执行账号、下载或发行验收。

本文适用于浏览、认证、订阅、下载及本地入库。 当前源码落点查[仓库地图](repository-map.md)。技术准入归[技术栈边界](technology-stack-boundaries.md)，SDK、内嵌、许可与签名归[发布流程](../release/release-signing.md#steamservice-build-and-signing-boundary)；迁移过程与既有验证上限归[完成记录](../history/cross-topic/steamkit-migration-completed-2026-10-16.md)。

## 1. 唯一职责与用户意图

产品获取链为 `AppKit → SteamWorkshopService → SteamServiceClient → SteamService/SteamKit → staged receipt → Swift 入库事务 → ready metadata`。Swift 持有用户意图、账号投影、分页、任务、库记录与播放选择；C# helper 执行 Steam 认证、结构化查询、订阅请求及 CDN 传输，不接管 UI、库 ready 或 Video/Web/Scene 播放。预览图片可以沿现有 Swift 网络与缓存服务加载，但只消费结构化结果中的 URL，不成为列表/账号第二权威。

| 职责 | 现役 owner |
|---|---|
| helper 进程、协议准入、request/terminal 与换代 | [SteamServiceClient](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceClient.swift)、[Protocol](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceProtocol.swift) |
| 主账号、认证尝试与令牌恢复 | [SteamAuthRoute](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamAuthRoute.swift)、[SteamAccountSession](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamAccountSession.swift)、[TokenStore](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopTokenStore.swift) |
| 结构化列表与分页 | [SteamKitBrowseStore](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+SteamKitBrowse.swift)、[QueryClient](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopQueryClient.swift) |
| 同账号订阅状态及写后对账 | [SubscriptionStore](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopSubscriptionStore.swift) |
| 任务意图、FIFO、attempt、历史与执行 | [JobStore](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopJobStore.swift)、[Downloads](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift) |
| staging 校验、发布、消费租约与回收 | [LibraryTransaction](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryTransaction.swift)、[Publication](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryPublication.swift)、[DownloadLibrarySync](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadLibrarySync.swift)、[VersionLeaseRegistry](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryVersionLease.swift) |

订阅、下载、设为壁纸是独立动作。取消订阅不删本地，删除本地不取消订阅，下载成功只更新同一 ready 数据源与相关视图，不跳页、不隐式订阅或播放。未知订阅状态先查询；写入结果不确定时先对账，不自动重复写入。 任务面板“全部清除”只放弃当前账号的failed jobs并清terminal history；queued/running/staged/committing均不取消，清历史本身不改活动任务或队列。

## 2. 认证、身份与 IPC

认证面板只由用户主动登录或受保护操作打开，密码、QR、Guard 共用同一 attempt 与账号 owner。启动、进入个人列表、网络失败、token 失效或 helper 重启不自动弹认证 UI。未登录下载在创建 JobStore/瞬态任务之前同步拒绝并打开唯一登录入口；登录成功不重放被拒绝的旧点击。已经持久化的任务按原账号、恢复偏好与对账结果处理，不能转交新账号。

每次认证绑定 `authAttemptId/accountEpoch`，请求还绑定进程/连接 generation；取消、关闭面板、切方式与换号及时撤原尝试。迟到事件不得采纳 token、恢复旧在线状态或影响后继账号。helper ready、网络连接、已保存 token 与账号 online 分域，pong 不证明登录。显式重连与有界自动重启复用同一进程 owner；只读重试、订阅对账与下载恢复各走其原意图，不把崩溃恢复变成写操作重放。

只有记住偏好及恢复授权允许时才进行有界、无 UI 的 token 恢复。refresh token/GuardData 由 Keychain 单主账号槽位原子更新；UserDefaults 仅保显示信息、偏好和恢复授权。退出/换号先撤旧恢复授权，再处理凭据，清理失败须可见；网络失败不凭异常文字删除令牌。密码、验证码、token 不进日志、argv、环境变量、浏览快照或任务历史。

双端使用有界 UTF-8 NDJSON，stdout 仅协议，stderr 为脱敏诊断；SteamID、Workshop ID、manifest ID 使用十进制字符串。协议当前限制单帧 1 MiB、256 个业务 pending 及 8 个保留控制准入；接收登记、超时、取消与唯一 terminal 共同防止重复完成和无限等待。progress 可合并，terminal 不得因节流丢失。

ready 必须校验版本与命令所需 capability。下载要求 `download-staging-ack-v2`、`download-cdn-auth-retry-v1`；趋势时间窗要求 `query-trend-days-v1`，缺失时在发命令前明确拒绝，不能以协议大版本相同静默降级。helper 标准位置为 `Contents/Resources/SteamService/SteamService`；开发覆盖仍须显式、可追踪，空值、缺失或不可执行项不回退旧获取器。

## 3. 浏览、缓存与 UI 投影

公开读取沿唯一匿名/账号结构化查询，个人列表绑定当前账号。QueryKey 纳入来源、账号、搜索、排序、趋势区间与分面筛选，generation 拒绝旧回包；成功采纳当前页后才推进页码，失败保留已加载页与重试入口。当前列表页大小为 30；按实际原始响应判 hasMore，partial 失败保留可诊断的条目身份，不能把一页本地过滤冒充全量结果。

趋势 `days` 是远端 1…365 日排名区间，不是本地发布时间 cutoff。服务端可执行的筛选交给服务端；个人列表筛选和作者页搜索标明仅针对已加载集合。来源往返使用原 store 快照，不由视图重建第二分页缓存。

页面往返由 Service 至多保留公开、个人两个内存快照，包含原查询条件、原 store 分页、条目与滚动位置；store 仍是唯一取页和 generation owner。进入页面时才检查成功首刷的单调时间：个人列表 120 秒、公开列表 300 秒；新鲜快照直接恢复，过期沿原请求刷新，手动刷新绕过期限，不添加后台轮询或磁盘缓存。失败保留已显示内容，不延长成功期限；退出或换号丢弃个人快照及当前个人原始分页；订阅写入只使个人数据过期，保留搜索、筛选和排序，作者返回也执行同一新鲜度检查。自动续页暂停与失败冷却随快照恢复，清缓存移除全部快照。刷新首批身份和总数均未变化、且无部分失败时可保留已加载尾页与游标；这不等于重新验证了远端每一尾页。

网格尺寸和快照提交由同一视图串行协调：以实际 clip viewport 计算卡片及页脚宽度，挂窗且尺寸有效后才提交；原生快照进行中不修改几何，结束后应用最新尺寸与待处理列表。相同身份顺序只更新可见内容，原位移除保留递补效果。Video、Steam 已下载和 Pixabay Flow 网格也以真实可视区域为尺寸依据，缩窄时先安装可容纳的尺寸；工具栏按同一网格可用宽度和最小卡宽限制计算列数，命令从当前有效列数增减，图片瀑布流保持独立策略。验收覆盖往返新鲜度、分页/筛选/滚动恢复、手动刷新、账号与订阅失效、迟到回包，以及原生网格重新挂载、缩放、重排和页脚变化；离线测试不冒充真实 Steam 账号结果。

作品详情按 Workshop ID 使用唯一查询与转换路径，不套用列表类型筛选；列表摘要在打开在线或已下载详情时按需补齐，完整响应允许分辨率、预览、作者名称等可选字段缺失，不能据此反复补查。切换作品、在线/下载面板或浏览导航时统一结束旧请求与刷新状态；仅同一消费者、同一作品复用活请求，取消后的回包不得再发布。成功更新同步已下载 metadata，保留 storage identity 与首次下载时间；已下载记录在打开面板时检查 72 小时新鲜度，完整旧详情立即显示，过期刷新静默进行，成功后原位替换，失败保留缓存；首次补全和手动重试保留加载与错误反馈，无后台轮询。新鲜详情磁盘缓存优先补齐较旧本地记录，沿用原获取时间；成功结果立即更新内存记录及原 metadata，不等待全库扫描才能复用。预览读取独立于详情查询，不以额外图片探测阻塞作者信息。作者工坊不继承主浏览页类型或分面筛选，显示全部可访问类型；搜索只匹配已加载作品，非空搜索禁止网格自动续页，保留页脚手动加载。同一作者重复进入保留分页、搜索与滚动位置；作者页统一归属侧栏创意工坊，不随上次浏览来源选中订阅；作者导航只保存首次进入的返回来源，作者间跳转不覆盖；返回公开或订阅页恢复原条件和已加载页，返回已下载则恢复原列表及滚动位置，不触发浏览页刷新。显式侧栏导航清除作者上下文后服从侧栏目标。清除作者页续页暂停，中断的首载在重新进入浏览页时请求。

私人缓存与订阅投影按账号隔离；退出或换号不得展示旧账号数据。预览 URL/条目 identity 改变时原图片请求与复用视图不得发布陈旧内容。卡片、详情、任务面板共用 JobStore 与按 item/job/attempt 键控的进度投影；视图关闭解绑 observer，不停止后台任务，也不自行累计任务历史或轮询任务状态。进度区分已验证字节、网络字节及真实阶段总量；未知分母不显示伪百分比，staged/committing 不显示 ready。

## 4. 持久任务、staging 与取消

JobStore 只写 `jobs-v5.json`。当前文件缺席时按 v4→v3→jobs.json 选择最新存在的前代，只读导入、保留原字节；当前或选中前代损坏、超前 schema、symlink/特殊项等不安全输入使该 store 实例停止写入，不能隔离后当空库继续，也不能回退更旧意图。缺完整 birth identity 的旧 partial 不获得恢复/清理权，已持久化的 prepared commit 仍沿原对账处理。历史按账号隔离，现有限额为 100 条且最长 30 天；清历史不删内容或活动任务。

Swift JobStore 决定排队、去重、attempt 与取消，helper 仅执行活动网络作业。当前双方最多 2 个活动下载，helper 每作业最多 4 个 worker、全作业共享 4 个物理 chunk 槽；槽位包含网络、解密和写入，等原作业物理 terminal 后才释放。活动取消先停止新工作并排空，worker 永久失败只取消同作业 sibling，以原错误收口；helper EOF/崩溃不产生成功。账号换代撤旧授权，但不能丢弃等待旧物理排空的 waiter。

App 分配私有 staging 根，helper 只在其受控直接子目录创建/恢复租约。顺序为 `allocated → App 校验并原子持久化 → exact acknowledge → 创建/写内容`；path、manifest、device、inode、birth seconds/nanoseconds 及账号/job identity 必须一致。错误、迟到、重复 ack 或 30 秒超时不解除写门。显式 retry 重新核对持久 lease；失配先持久清空 recovery 再 fresh start，不对同名 replacement 操作。

manifest 在写盘前整体校验路径、大小/文件数/chunk 预算、覆盖与 checksum；拒绝绝对路径、逃逸链接、多硬链接、大小写/Unicode 冲突及非普通文件。helper 当前每 job 上限 8 GiB/200,000 文件，并保有界 chunk、路径、重试及磁盘余量；App 复制另由现有串行 copy-capacity/reservation owner 计入旧内容、staging、在途发布及其他作业，不以独立 free-space 快照超卖。写入与清理沿目录描述符、nofollow、完整创建身份复核；只清原 lease，不枚举删除未知兄弟目录。pathname unlink 不升级为对同用户任意时序替换的绝对原子保证。

CDN 候选与 token 只属于当前账号 lease 的单个作业。manifest/chunk 使用原有有界循环、节点切换和同节点 403 鉴权回放，鉴权重试不冒充内容节点切换，刷新不重置暂态预算；永久拒绝、完整性失败不盲重试。typed 错误保阶段/HTTP 类别与有限尝试上下文，不泄露 token、完整 URL 或原始异常。具体实现与预算见 [WorkshopDownloader](../../SteamService/WorkshopDownloader.cs)、[WorkshopCdnTransfer](../../SteamService/WorkshopCdnTransfer.cs)、[WorkshopStagingLease](../../SteamService/WorkshopStagingLease.cs)。

## 5. receipt、v3 发布与消费生命周期

helper 仅产出 staged 内容与 typed receipt，不决定 ready。receipt v2 核对 job/account/epoch/Workshop/manifest、完成状态、非空 project.json、相等且有界的 verified/total bytes 及独占 lease。App 复制时重算完整摘要：NFC UTF-8 路径排序，逐文件编码 UInt32-LE 路径长度、路径、UInt64-LE 文件长度及文件 SHA-256，再对串联求 SHA-256；路径格式校验不替代消费端身份及内容重验。

v3 使用 `Video|Web|Scene/<WorkshopID>`；generation 在 commit/ownership marker，兼容 v2 UUID 目录。incoming 校验后保存 publication intent，经 rename/exchange 安装并原子发布 `.mywallpaperx-steam-metadata/<WorkshopID>.json`。**metadata 是唯一 ready 点**；目录、marker、stagedComplete 不代表 ready。失败经同一 journal 回滚/恢复，未知目录勿覆盖；复制/摘要在后台，账号/attempt 复核至发布不挂起。`firstDownloadedAt` 保存首次入库时间，刷新和版本替换不重置；旧记录沿用 commit/本地创建时间。排序与详情共用后台目录统计的原始字节数。

任务沿 `running → staged → committing → completed` 持久化推进，receipt/commit 先落盘再推进。失败、取消、空间不足或重复 terminal 不破坏旧 ready；成功后的 staging 清理失败不回滚已发布 ready，未释放清理责任保留并有界重试。

旧 v1 隐藏内容只读兼容，迁移复用同一容量/发布 owner；旧 v2 只有在无消费引用时迁至纯 ID。迁移先重核旧 metadata，正在播放/导入的路径不移动，不因专项计划退役删除兼容代码。保留命名空间即使 marker 损坏也从 legacy discovery 排除，避免第二 ready。旧 generation 先改名为同类型隐藏退役目录，再交既有回收器，不在主线程递归清理。

播放/导入消费持有具体 storage identity 的租约，依赖 Web 同时保壳与宿主；新 ready 不能代替旧消费者的身份。删除先阻止该项目的新播放/入库并取消精确作业，Scene 消费等当次 daemon generations 的真实退出后释放，再按身份发布 tombstone/删除；后继进程不能拖住旧代际回调。普通回收要求完整可读索引、超过 24 小时、未在 ready/未决事务/播放与视频库引用保留集，并经原 lease registry 预约及目录身份/marker 复核。未知、损坏或替换目录不被收养；同代际 tombstone 不得被崩溃恢复复活。入口为 [LibraryReclamation](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryReclamation.swift)。

## 6. 旧路退出与后续维护

SteamCMD、PTY/输出解析、自动社区登录、Cookie/个人 HTML 抓取和旧密码读取都不再是产品获取 fallback；公开网页只保用户主动外链。遗留状态只由[精确退役器](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLegacyAcquisitionRetirement.swift)按独立组件 marker 清理，不读 Cookie 转 token，不触系统浏览器、Steam 客户端或用户壁纸库。退役失败保原项并可重试，不借迁移清理未知目录。

后续修复按当前 owner 的普通维护处理。协议/进程最近门为 [protocol golden](../../script/tests/test_steam_protocol_golden.py)、[client lifecycle](../../script/tests/test_steam_client_lifecycle.py)；任务/文件最近门为 [download execution](../../script/tests/test_steam_download_execution.py)、[library transaction](../../script/tests/test_steam_library_transaction.py)、[publication](../../script/tests/test_steam_library_publication.py)、[legacy retirement](../../script/tests/test_steam_legacy_retirement.py)。账号取证入口为 [steam_auth_gate.py](../../script/steam_auth_gate.py)，按当次授权、隔离状态与脱敏输出执行。

离线 fixture、Debug 构建、匿名查询或 QR challenge 都有各自证明范围，不能替代账号终态、真实下载、播放、完整交互/VoiceOver、长期恢复、跨卷/断电或 Release 验收。发行门继续归发布流程；当前故障须绑定实际 App/helper identity 和输入，历史成功与旧 HTTP 403 观察不能自动归因到新构建。本合同不创建新迁移阶段、通用平台或第二运行权威。
