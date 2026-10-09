//
//  SteamWorkshopService.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import Combine
@MainActor
final class SteamWorkshopService: ObservableObject {
    static let shared = SteamWorkshopService()

    // MARK: - Browser feed state

    @Published var browserItems: [SteamWorkshopBrowserItem] = [] {
        didSet { updateDisplayedBrowserItems() }
    }
    @Published var displayedBrowserItems: [SteamWorkshopBrowserItem] = []
    @Published var pendingBrowserScrollRestoreOffset: CGFloat?
    var browserState: SteamWorkshopBrowserLoadState = .idle
    /// SK-helper-idle-reap：浏览面板窗口挂载计数——「浏览 UI 活跃」的唯一 owner。
    /// AppKitSteamWorkshopBrowserView 进/出窗口（viewDidMoveToWindow）时经
    /// noteBrowsePanelAttached/Detached 增减；> 0 即面板对用户可见，空闲回收绝不
    /// 触发。加载态 browserState 只反映取页进度（.loaded/.failed 停留在最后值，
    /// 仅 clearAllCachedState 回置 .idle），不得用作面板可见性代理。
    private(set) var browsePanelAttachmentCount = 0

    /// 浏览面板当前是否对用户可见（挂载于任一窗口）。
    var isBrowsePanelOpen: Bool { browsePanelAttachmentCount > 0 }

    /// 浏览面板进窗（AppKitSteamWorkshopBrowserView.viewDidMoveToWindow 唯一产生者）。
    func noteBrowsePanelAttached() {
        browsePanelAttachmentCount += 1
    }

    /// 浏览面板出窗（同上唯一产生者）。无配对出窗（视图被装入未挂窗层级后
    /// 移除时，viewDidMoveToWindow 以 nil→nil 触发）不得把计数推负——负数会让
    /// 下一次真实进窗停在 0，面板可见却被判休眠（fail-deadly 方向）。
    func noteBrowsePanelDetached() {
        browsePanelAttachmentCount = max(0, browsePanelAttachmentCount - 1)
    }
    @Published var isRefreshingBrowserFeed = false
    @Published var previewReloadToken: Int = 0
    @Published var isLoadingMoreBrowserItems = false
    @Published var hasMoreBrowserItems = true
    /// 追加页失败只发布展示状态；已加载页、页码与查询 generation 仍由
    /// `SteamKitBrowseStore` 唯一持有。非 nil 时网格底部提供显式重试。
    @Published var browserLoadMoreFailureMessage: String?
    @Published var downloads: [SteamWorkshopDownloadRecord] = [] {
        didSet { refreshDisplayedDownloads() }
    }
    var removingDownloadIDs: Set<String> = []
    @Published private(set) var displayedDownloads: [SteamWorkshopDownloadRecord] = []
    /// M0.5：最近一次"设为壁纸/播放"pending 的记录 ID。点击立即置位
    /// （≤1 runloop turn 渲染加载态）；Scene launch 终态或 runtime 切换
    /// 通知清除；video/web 发送后另有 1.5s 兜底清除。
    @Published private(set) var launchPendingRecordID: String?
    /// setAsWallpaper 的点击代际：每次进入递增。web 分支的异步解析完成
    /// 回到主线程后必须仍是最新代际才发布启动通知或走失败出口——窗口内
    /// 出现更新的点击（web/scene/video 任意分支）时本请求整体退役，避免
    /// 旧请求的迟到通知覆盖用户的最后选择（完成序倒置）。
    private(set) var webLaunchIntentGeneration: UInt64 = 0

    /// 递增点击代际并返回新值（仅 setAsWallpaper 入口调用；跨文件扩展
    /// 不能直接写 private(set) 字段）。
    @discardableResult
    func advanceWebLaunchIntentGeneration() -> UInt64 {
        webLaunchIntentGeneration &+= 1
        return webLaunchIntentGeneration
    }

    func isLaunchPending(_ recordID: String) -> Bool {
        launchPendingRecordID == recordID
    }

    func markLaunchPending(recordID: String) {
        launchPendingRecordID = recordID
    }

    func clearLaunchPending(matching recordID: String? = nil) {
        if let recordID, launchPendingRecordID != recordID { return }
        launchPendingRecordID = nil
    }
    @Published var browserContentMode: SteamWorkshopBrowserContentMode = .video {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var source: SteamWorkshopSource = .featured {
        didSet {
            if !browseContext.isAuthorWorkshop {
                currentPageTitle = source.pageTitle
                browserSectionTitle = source.pageTitle
            }
            NotificationCenter.default.post(
                name: .steamWorkshopBrowseContextDidChange,
                object: nil,
                userInfo: ["isAuthorWorkshop": browseContext.isAuthorWorkshop, "title": source.pageTitle]
            )
            if !suppressAutomaticBrowseNavigation { navigateToBrowse() }
        }
    }
    @Published var personalSort: SteamWorkshopPersonalSort = .subscriptionDate {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var browserQuery: String = "" {
        didSet {
            guard !isUpdatingBrowserQueryProgrammatically else { return }
            handleBrowserQueryChanged()
        }
    }
    @Published var trendingWindow: SteamWorkshopTrendingWindow = .week {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    /// 浏览分面筛选唯一 Owner（类型/分级/分辨率/分类）。空值 = 不筛选；
    /// 任一变化重置浏览键并重取第一页。
    @Published var facetFilters: SteamWorkshopBrowseFacetFilters = .none {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var downloadsQuery: String = "" {
        didSet { refreshDisplayedDownloads() }
    }
    @Published var downloadsDisplayMode: SteamWorkshopDownloadsDisplayMode = .all {
        didSet { refreshDisplayedDownloads() }
    }
    @Published var downloadsSortMode: SteamWorkshopDownloadsSortMode = .updatedAt {
        didSet { refreshDisplayedDownloads() }
    }
    @Published var downloadsSortAscending: Bool = false {
        didSet { refreshDisplayedDownloads() }
    }
    @Published var zoomOffset: Int = 0
    @Published var statusMessage: String = "浏览页使用 SteamKit 结构化数据展示 Wallpaper Engine 创意工坊内容。"
    @Published var currentWorkshopItemID: String?
    @Published var currentPageTitle: String = "Steam 创意工坊"
    @Published var browserSectionTitle: String = "Steam 创意工坊"
    @Published var isBrowsingAuthorWorkshop = false
    @Published var activeAuthorWorkshopName: String?
    @Published var navigationVersion: Int = 0

    /// SK1.2：Steam helper 生命周期客户端。模块统一持有；spawn 由首次结构化
    /// 公开查询、用户登录动作或已授权恢复触发。本地库启动不预取、不产生
    /// helper 进程；不接 playback multiplexer，不承担播放控制。
    private(set) var steamServiceClient = SteamServiceClient()

    /// SK2.2：新登录路线（SteamKit）权威。登录面板与工具栏账号状态的数据源。
    private(set) lazy var steamAuth = SteamAuthRoute(client: steamServiceClient)

    /// SK3.2：新浏览 route 的键控取页状态（QueryKey/generation）。
    private(set) lazy var steamKitBrowseStore = SteamKitBrowseStore(
        queryClient: steamWorkshopQueryClient
    )

    /// SK3.3：统一查询消费入口（个人列表、订阅状态与写入、详情批）。
    private(set) lazy var steamWorkshopQueryClient = SteamWorkshopQueryClient(
        client: steamServiceClient
    )

    private(set) lazy var steamSubscriptions: SteamWorkshopSubscriptionStore = {
        let store = SteamWorkshopSubscriptionStore(
            identity: { [weak self] in
                guard let self, self.steamAuth.isOnline else { return nil }
                return self.steamServiceClient.accountEpoch
            },
            read: { [weak self] id in
                guard let self else { throw CancellationError() }
                let states = try await self.steamWorkshopQueryClient.subscriptionStates(ids: [id])
                guard let value = states[id] else { throw SteamServiceClient.RequestError.helperError(code: "protocolMismatch", message: "订阅状态缺失。") }
                return value
            },
            write: { [weak self] id, desired in
                guard let self else { throw CancellationError() }
                try await self.steamWorkshopQueryClient.setSubscription(workshopId: id, subscribe: desired)
            }
        )

        store.didReconcileWrite = { [weak self] _, _ in
            guard let self, self.source == .mySubscriptions, self.shouldUseSteamKitPersonal else { return }
            self.fetchBrowserItems(forceRefresh: true)
        }
        return store
    }()

    /// SK4.1：下载任务单一权威（队列/去重/状态机/持久化）。旧 queued/
    /// pending 数组真值已移除，各入口读同一投影。
    private(set) lazy var downloadJobStore = SteamDownloadJobStore()

    /// SK-helper-idle-reap：空闲回收策略。internal setter 供同模块唯一装配方
    /// （SteamWorkshopService+HelperIdleReaping.swift）写入。
    var helperIdleReaper: SteamHelperIdleReaper?

    /// SK4.1：出队重建执行请求所需的内存载荷映射（不入任务文件）。
    var steamJobItemPayloads: [String: SteamWorkshopBrowserItem] = [:]

    /// SK2.3：唯一登录面板入口。重复调用聚焦同一面板，不产生第二个认证流。
    func showLoginPanel() {
        SteamLoginPanelController.shared.show(auth: steamAuth)
    }

    /// SK2.3：记住登录偏好开启时的启动静默恢复（有界、无 UI、无弹窗）。
    /// 恢复到不同账号立即登出（不存错账号）；明确拒绝才标过期并删令牌；
    /// 网络失败保留令牌下次再试。
    func restoreSavedSteamSessionIfAuthorized() {
        guard UserDefaults.standard.bool(forKey: SteamWorkshopTokenStore.rememberPreferenceKey),
              SteamWorkshopTokenStore.isRestoreAuthorized,
              let saved = SteamWorkshopTokenStore.load() else { return }
        let scheduledEpoch = steamAuth.client.accountEpoch
        Task { @MainActor [weak self] in
            guard let self, self.steamAuth.client.accountEpoch == scheduledEpoch else { return }
            let restoreEpoch = scheduledEpoch + 1
            do {
                let steamId = try await self.steamAuth.restore(
                    refreshToken: saved.refreshToken,
                    accountName: saved.accountName,
                    expectedSteamId: saved.steamId
                )
                guard self.steamAuth.client.accountEpoch == restoreEpoch else { return }
                if saved.accountName.isEmpty == false {
                    self.statusMessage = "已恢复 Steam 登录（\(saved.accountName)）。"
                }
                _ = steamId
            } catch is CancellationError {
                return
            } catch {
                guard self.steamAuth.client.accountEpoch == restoreEpoch ||
                    (self.steamAuth.client.accountEpoch == restoreEpoch + 1 && self.steamAuth.expired) else { return }
                // 账号不一致与过期都删令牌+标过期，但文案区分（不能匹配
                // localizedDescription——Swift 枚举错误默认不含关联 message）。
                var mismatch = false
                if case let .helperError(_, message) = error as? SteamServiceClient.RequestError,
                   message.contains("不一致") {
                    mismatch = true
                }
                switch SteamAuthRoute.disposition(for: error) {
                case .deleteToken:
                    self.statusMessage = mismatch
                        ? "保存的登录与实际账号不一致，已停止恢复。请重新登录。"
                        : "保存的 Steam 登录已过期。请使用工具栏的「登录 Steam」重新登录。"
                    if self.steamAuth.tokenDeletionFailed {
                        self.statusMessage += " 已禁止自动恢复，但 Keychain 清理失败。"
                    }
                case .keepToken:
                    self.statusMessage = "已保存的 Steam 登录暂无法恢复（网络原因），保留登录信息，下次启动再试。"
                }
            }
        }
    }

    /// SK2.3：退出登录 = 新路线登出（epoch 递增+令牌清理）。
    /// 有活动/排队任务时先说明一次；本地文件与当前壁纸不受影响。
    func signOutEverywhere() {
        let hasActiveDownloads = !activeDownloadTasks.isEmpty || downloadJobStore.queuedCount > 0
        if hasActiveDownloads {
            let alert = NSAlert()
            alert.messageText = "退出 Steam 登录？"
            alert.informativeText = "进行中和排队中的下载任务将被停止；已下载的文件和当前壁纸不受影响。"
            alert.addButton(withTitle: "退出登录")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cancelDownloadImmediately(showFeedback: false)
            // SK4.1：队列真值在 JobStore——取消全部任务并清理对应投影。
            self.pausedDownloadItemIDs.removeAll()
            for workshopID in self.downloadJobStore.cancelAll() {
                self.removeTransientRecord(id: workshopID)
                self.steamJobItemPayloads.removeValue(forKey: workshopID)
            }
            if !self.downloadJobStore.lastSaveSucceeded {
                self.downloadError = "取消队列未能保存；任务执行已停止，请检查磁盘后重试。"
            }
            let cleared = await self.steamAuth.signOut()
            guard self.steamAuth.phase == .idle else { return }
            self.statusMessage = cleared ? "已退出 Steam 登录。"
                : "已退出并禁止自动恢复，但 Keychain 中的旧令牌清理失败。"
        }
    }

    /// Only explicit protected actions open login; browsing/refresh never do.
    /// The original action is not replayed after authentication.
    func presentSteamLoginForUserAction(context: String) {
        statusMessage = ""
        showLoginPanel()
    }

    // MARK: - Download selection state

    @Published var activeDownloadItemIDs: Set<String> = []
    @Published var isDownloadsMultiSelectMode = false
    @Published var selectedDownloadID: String?
    @Published var selectedDownloadIDs: Set<String> = []
    /// F15 残留修复：失败提示以代数而非文本区分——并发同根因的两条同文
    /// 失败也会各自推进 revision，弹窗完成回调按 revision 判定续播/清空，
    /// 不再依赖「文本不同 = 新失败」。
    @Published var downloadError: String? {
        didSet { downloadErrorRevision += 1 }
    }
    private(set) var downloadErrorRevision = 0
    @Published var selectedDownloadInspectorItem: SteamWorkshopBrowserItem?
    @Published var selectedDownloadDetailItem: SteamWorkshopBrowserItem?
    @Published var selectedBrowserItem: SteamWorkshopBrowserItem?
    @Published var isRefreshingSelectedDownloadDetailItem = false
    @Published var isRefreshingSelectedBrowserItem = false
    @Published var selectedDownloadDetailError: String?
    @Published var selectedBrowserItemError: String?

    // MARK: - Web runtime state

    @Published var lastWebPlaybackFailureRecordID: String?
    @Published var lastWebPlaybackFailurePath: String?
    @Published var lastWebPlaybackFailureMessage: String?

    var webValidationReportCache: [String: CachedWebValidationReport] = [:]
    var webRuntimeModelCache: [String: CachedWebRuntimeModel] = [:]
    var webProjectDescriptorCache: [String: CachedWebProjectDescriptor] = [:]
    var activeWebPropertySecurityScopedURLs: [String: URL] = [:]
    /// 会话新鲜清单快速路径的起点：本实例存续期间由保存路径写入的分析
    /// 清单（写时刚完成同源签名扫描）在 `isAnalysisManifestValid` 里会话内
    /// 免再扫。运行时清单校验（isRuntimeManifestValid）不适用——其调用方
    /// 在后台段恒做实时扫描。壁钟前跳后回拨或并行第二实例写出的清单可能
    /// 被误判新鲜，暴露面与 mtime 键内存缓存的既有盲区同级。
    let webRuntimeCacheSessionStartDate = Date()
    var scenePropertyRenderTask: Task<Void, Never>?
    var scenePropertyCommandRevision: UInt64 = 0
    var scenePropertyEditRevisions: [String: UInt64] = [:]
    var pendingSceneTextureProperties: [String: SceneTexturePropertyPending] = [:]

    // MARK: - Runtime tasks and processes

    var browserFetchTask: Task<Void, Never>?
    var webRuntimePreloadTask: Task<Void, Never>?
    /// preload 任务代际：被抢占的旧任务收尾时据此判断句柄是否已归属新
    /// 任务，避免把新任务的 cancel 句柄清成 nil（重复 IO 有界但脏）。
    /// 唯一写方是 preloadWebRuntimeCaches。
    var webRuntimePreloadGeneration: UInt64 = 0
    var lastPreviewPrefetchIDSet = Set<String>()
    var browserLoadMoreRetryAfter: Date = .distantPast
    /// 稀疏筛选下连续无新增可见项的自动续载页数（见 maxConsecutiveEmptyLoadMorePages）。
    var consecutiveEmptyLoadMorePages = 0

    // MARK: - Shared infrastructure

    var cancellables = Set<AnyCancellable>()
    /// Shared preference owner for Scene property values and security-scoped
    /// texture bookmarks. This is independent of the retired acquisition
    /// backend and preserves the isolated defaults suite used by runtime gates.
    let defaults: UserDefaults = {
#if DEBUG
        if let suiteName = SteamWorkshopService.isolatedDebugDefaultsSuiteName() {
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to create Debug defaults suite")
            }
            NSLog("MWX DEBUG DEFAULTS: suite=%@", suiteName)
            return defaults
        }
#endif
        return .standard
    }()
    let maximumConcurrentDownloads = 2
    var activeDownloadJobKeysByItemID: [String: String] = [:]
    var activeDownloadTasks: [String: Task<Void, Never>] = [:]
    var cancellationFeedbackByDownloadJobKey: [String: Bool] = [:]
    /// steam-ux-0：用户暂停中的下载 itemID（会话内，不持久化、不新增状态枚举）。
    /// 暂停任务以 queued 状态保留完整 staging 恢复身份；出队跳过本集合，
    /// 恢复即移出并复用既有出队路径。重启后按普通 queued 任务自然续跑。
    var pausedDownloadItemIDs: Set<String> = []
    var reservedLibraryCopyBytesByJobKey: [String: Int64] = [:]
    let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    let steamLibraryVersionLeaseRegistry = SteamWorkshopLibraryVersionLeaseRegistry()
    var libraryVersionReclamationTask: Task<Void, Never>?
    var legacyLibraryPublicationMigrationTask: Task<Void, Never>?
    var terminalDownloadCleanupTask: Task<Void, Never>?
    /// Coalesces overlapping installed-library scans: only the newest
    /// scan's result is published (see reloadInstalledItems).
    var installedLibraryScanGeneration = 0
    var selectedItemDetailTask: Task<Void, Never>?
    /// Item ID of the in-flight `selectedItemDetailTask`. A live refresh for
    /// the same item is reused instead of cancelled and re-issued (rapid
    /// detail-panel re-opens re-fetched the same SteamKit details each time).
    var inFlightDetailItemID: String?
    var discoveryBrowseSnapshot: SteamWorkshopDiscoveryBrowseSnapshot?
    var currentBrowserScrollOffsetY: CGFloat = 0
    var savedDiscoveryQueryBeforeAuthorBrowse: String?
    var isUpdatingBrowserQueryProgrammatically = false
    var suppressAutomaticBrowseNavigation = false
    var browseContext: SteamWorkshopBrowseContext = .discovery {
        didSet {
            browserSectionTitle = browseContext.isAuthorWorkshop ? browseContext.title : source.pageTitle
            isBrowsingAuthorWorkshop = browseContext.isAuthorWorkshop
            if case let .authorWorkshop(authorName, _) = browseContext {
                activeAuthorWorkshopName = authorName
            } else {
                activeAuthorWorkshopName = nil
            }
            updateDisplayedBrowserItems()
            NotificationCenter.default.post(
                name: .steamWorkshopBrowseContextDidChange,
                object: nil,
                userInfo: [
                    "isAuthorWorkshop": browseContext.isAuthorWorkshop,
                    "title": browseContext.title
                ]
            )
        }
    }

    // MARK: - Lifecycle

    private init() {
        if Self.isolatedDebugDefaultsSuiteName() == nil {
            SteamWorkshopLegacyAcquisitionRetirement.run(defaults: defaults)
        } else {
            // Runtime gates intentionally use a private defaults suite. Never
            // let that fresh marker namespace trigger deletion in the user's
            // real login Keychain, WebKit store, caches or runtime directory.
            NSLog("MWX DEBUG RETIREMENT: skipped for isolated defaults suite")
        }
#if DEBUG
        let isIsolatedWebSampleRun = ProcessInfo.processInfo.arguments.contains("--mwx-debug-run-web-workshop-id")
#else
        let isIsolatedWebSampleRun = false
#endif
        if !isIsolatedWebSampleRun {
            restoreSavedSteamSessionIfAuthorized()
        }
        // 整库扫描（recoverPublications + 三库枚举 + 每条 project.json 读取）
        // 不再在 init 同步执行：启动重放只需要单条记录（走
        // installedRecordForLaunchReplay 快路径），完整扫描由装配层在主窗口
        // 激活后经 performStartupLibraryReloadIfNeeded 补跑。
        refreshDisplayedDownloads()
        // Public discovery is demand-loaded by prepareForBrowserEntry(). Keep
        // local-library startup free of helper/network work; an authorized
        // saved-session restore above remains the sole intentional exception.
        observeWebPlaybackFailures()
        installLaunchPendingObservers()
        observeSteamAccountIdentityForPersonalSources()
        observeDownloadJobStoreForProjection()
        installHelperIdleReaping()
    }

    /// D7：JobStore 是失败意图的持久 owner（弹窗清除、删除移除意图、重试推进
    /// attempt 都只改 JobStore），这些变化不经过 `downloads` didSet，必须单独
    /// 订阅以维持下载页失败投影同源刷新。
    private func observeDownloadJobStoreForProjection() {
        downloadJobStore.$jobs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshDisplayedDownloads()
            }
            .store(in: &cancellables)
    }

    /// 启动重放单记录快路径：按 itemID 定向读取已发布元数据
    /// （publishedMetadata(matchingItemID:) 只读索引里那一条 JSON），复用与
    /// 整库扫描相同的 buildInstalledRecord 构造该条安装记录。命中时把记录
    /// 并入 downloads 投影，重放窗口内 latestDownloadRecord 等既有消费方
    /// （web 网络桥解析、跨引擎轮换）照常工作；miss（未发布/不可用/未安装）
    /// 返回 nil，由调用方走既有降级路径。带依赖项的记录经既有目录回退解析，
    /// 不要求整库快照。
    func installedRecordForLaunchReplay(itemID: String) -> SteamWorkshopDownloadRecord? {
        let snapshots = (try? loadManagedDownloadSnapshots(
            requireComplete: false,
            matchingItemID: itemID
        )) ?? [:]
        guard let snapshot = snapshots[itemID],
              let commit = snapshot.commit,
              SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: steamDownloadLibraryRootURL),
              let record = buildInstalledRecord(from: snapshot, legacyDirectory: snapshot.legacyFolderURL,
                  fallbackProject: nil, fallbackIdentifier: snapshot.item.id,
                  managedSnapshots: [itemID: snapshot]) else {
            return nil
        }
        if latestDownloadRecord(for: itemID) == nil {
            downloads = (downloads + [record]).sorted { $0.updatedAt > $1.updatedAt }
        }
        return record
    }

    /// 完整整库扫描补跑开关：init 已不再同步扫描，装配层在主窗口激活让出
    /// 首帧后调用本方法补跑一次；先到者赢，重复调用为 no-op。工坊下载页
    /// viewDidMoveToWindow 的 downloadsCount==0 自愈重载走 reloadInstalledItems
    /// 原入口、不经本开关，极端竞态下最多多跑一次整库扫描，无正确性影响。
    private var isStartupLibraryReloadPending = true

    func performStartupLibraryReloadIfNeeded() {
        guard isStartupLibraryReloadPending else { return }
        isStartupLibraryReloadPending = false
        reloadInstalledItems()
    }

    private static func isolatedDebugDefaultsSuiteName() -> String? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--mwx-debug-user-defaults-suite"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        let suiteName = arguments[index + 1]
        precondition(
            suiteName.hasPrefix("com.songziqiang.MyWallpaperX.Debug."),
            "Debug defaults suite must use the MyWallpaperX Debug namespace"
        )
        return suiteName
#else
        return nil
#endif
    }

    /// SK3.3（§3.3/§3.2）：账号身份变化（登录成功/登出/在线换号）即失效当前
    /// 个人来源视图——旧账号的私有列表与空态不得展示给新账号；登录后当前
    /// 个人来源立即同账号重读。navigateToBrowse 递增 navigationVersion，
    /// 在飞的旧账号取页/追加页按 navigationVersion+generation 双守卫判废。
    private func observeSteamAccountIdentityForPersonalSources() {
        steamAuth.$steamId
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // 账号身份变化即刷新下载页失败投影：合成与历史判定都按现役账号
                // 隔离，旧账号的失败意图不得展示给新账号（D7 跨账号不接管）。
                self.refreshDisplayedDownloads()
                guard self.source.isPersonal else { return }
                self.navigateToBrowse()
            }
            .store(in: &cancellables)
    }

    private func refreshDisplayedDownloads() {
        // D7 单一投影：先把现役账号的失败意图合成进 downloads（选中/删除/详情
        // 因此走同一条 record 路径），再做过滤排序。值相等守卫防止
        // downloads didSet → refresh 自激：写回触发的重入趟在此处发现无差异
        // 即收敛，深度恒为 2。
        let merged = downloadsWithFailedIntents(from: downloads)
        if merged != downloads {
            downloads = merged
            return
        }
        displayedDownloads = filteredAndSortedDownloads(from: downloads)
        sanitizeDownloadSelectionAgainstDisplayedDownloads()
    }
}
