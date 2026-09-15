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
    static let authorNameStore = SteamWorkshopAuthorNameStore()

    // MARK: - Browser feed state

    @Published var browserItems: [SteamWorkshopBrowserItem] = [] {
        didSet { updateDisplayedBrowserItems() }
    }
    @Published var displayedBrowserItems: [SteamWorkshopBrowserItem] = []
    @Published var pendingBrowserScrollRestoreOffset: CGFloat?
    var browserState: SteamWorkshopBrowserLoadState = .idle
    @Published var isRefreshingBrowserFeed = false
    @Published var previewReloadToken: Int = 0
    @Published var isLoadingMoreBrowserItems = false
    @Published var hasMoreBrowserItems = true
    @Published var downloads: [SteamWorkshopDownloadRecord] = [] {
        didSet { refreshDisplayedDownloads() }
    }
    @Published private(set) var displayedDownloads: [SteamWorkshopDownloadRecord] = []
    /// M0.5：最近一次"设为壁纸/播放"pending 的记录 ID。点击立即置位
    /// （≤1 runloop turn 渲染加载态）；Scene launch 终态或 runtime 切换
    /// 通知清除；video/web 发送后另有 1.5s 兜底清除。
    @Published private(set) var launchPendingRecordID: String?

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
    @Published var themeFilter: SteamWorkshopThemeFilter = .all {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var ageRatingFilter: SteamWorkshopAgeRatingFilter = .all {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var resolutionFilter: SteamWorkshopResolutionFilter = .all {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var categoryFilter: SteamWorkshopCategoryFilter = .all {
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
    @Published var statusMessage: String = "浏览页使用原生网格展示，后台抓取 Wallpaper Engine 创意工坊内容。"
    @Published var currentWorkshopItemID: String?
    @Published var currentPageTitle: String = "Steam 创意工坊"
    @Published var browserSectionTitle: String = "Steam 创意工坊"
    @Published var isBrowsingAuthorWorkshop = false
    @Published var activeAuthorWorkshopName: String?
    @Published var requestedURL: URL
    @Published var navigationVersion: Int = 0
    @Published var communityAccountID: String?
    @Published var communityAccountName: String?

    let communitySession = SteamCommunitySessionController.shared

    /// SK1.2：Steam helper 生命周期客户端。模块统一持有；spawn 由首次登录动作
    /// 触发（SteamAuthRoute.ensureHelperReady），未登录启动不产生进程。不接
    /// playback multiplexer，不承担播放控制。
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

    /// SK2.3：退出登录 = 新路线登出（epoch 递增+令牌清理）+ 旧路线会话清理。
    /// 有活动/排队任务时先说明一次；本地文件与当前壁纸不受影响。
    /// 旧 SteamCMD 密码条目的显式迁移清理仍归 SK6；下载执行器已不再消费它。
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
            // Cleanup runs before signOut suspends; its completion cannot clear a new account.
            // 旧路线清理（不含旧密码删除，理由见上）。
            self.cancelActiveLoginSession()
            self.clearCommunitySession()
            self.cancelDownloadImmediately(showFeedback: false)
            self.defaults.removeObject(forKey: Constants.defaultsLastUsername)
            self.defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
            // SK4.1：队列真值在 JobStore——取消全部任务并清理对应投影。
            for workshopID in self.downloadJobStore.cancelAll() {
                self.removeTransientRecord(id: workshopID)
                self.steamJobItemPayloads.removeValue(forKey: workshopID)
            }
            if !self.downloadJobStore.lastSaveSucceeded {
                self.downloadError = "取消队列未能保存；任务执行已停止，请检查磁盘后重试。"
            }
            self.steamUsername = ""
            self.steamPassword = ""
            self.steamGuardCode = ""
            self.requiresLogin = true
            self.isAnonymousBrowsing = false
            self.authPhase = .credentials
            self.authSessionState = .expired
            self.lastSuccessfulSessionValidationAt = nil
            self.isLoginSheetPresented = false
            self.authError = nil
            let cleared = await self.steamAuth.signOut()
            guard self.steamAuth.phase == .idle else { return }
            self.statusMessage = cleared ? "已退出 Steam 登录。"
                : "已退出并禁止自动恢复，但 Keychain 中的旧令牌清理失败。"
        }
    }

    /// SK2.2：未登录受保护动作的就地提示（§1 规则 3：提示本身不打开登录）。
    func presentSteamLoginGuidance(context: String) {
        statusMessage = "需要登录 Steam（\(context)）。请使用工具栏的「登录 Steam」。"
    }

    // MARK: - Download selection state

    @Published var activeDownloadItemIDs: Set<String> = []
    @Published var isDownloadsMultiSelectMode = false
    @Published var selectedDownloadID: String?
    @Published var selectedDownloadIDs: Set<String> = []
    @Published var downloadError: String?
    @Published var selectedDownloadInspectorItem: SteamWorkshopBrowserItem?
    @Published var selectedDownloadDetailItem: SteamWorkshopBrowserItem?
    @Published var selectedBrowserItem: SteamWorkshopBrowserItem?
    @Published var isRefreshingSelectedDownloadDetailItem = false
    @Published var isRefreshingSelectedBrowserItem = false
    @Published var selectedDownloadDetailError: String?
    @Published var selectedBrowserItemError: String?

    // MARK: - Authentication state

    @Published var requiresLogin: Bool = true
    @Published var isAnonymousBrowsing = false
    @Published var authPhase: SteamWorkshopAuthenticationPhase = .credentials
    @Published var isLoginSheetPresented = false
    @Published var isAuthenticating = false
    @Published var isPreparingRuntime = false
    @Published var authStatusMessage: String = "首次进入请登录 Steam，软件会使用随 App 打包的 SteamCMD 并保留登录态。"
    @Published var authError: String?
    @Published var authSessionState: SteamWorkshopAuthSessionState = .unknown
    @Published var steamRuntimeVersion: String = "未检测"
    @Published var steamRuntimeUpdateStatus: String = "当前使用 App 内置 SteamCMD 基线版本。"
    @Published var steamUsername: String = ""
    @Published var steamPassword: String = ""
    @Published var steamGuardCode: String = ""

    // MARK: - Web runtime state

    @Published var lastWebPlaybackFailureRecordID: String?
    @Published var lastWebPlaybackFailurePath: String?
    @Published var lastWebPlaybackFailureMessage: String?

    var webValidationReportCache: [String: CachedWebValidationReport] = [:]
    var webRuntimeModelCache: [String: CachedWebRuntimeModel] = [:]
    var activeWebPropertySecurityScopedURLs: [String: URL] = [:]
    var scenePropertyRenderTask: Task<Void, Never>?
    var scenePropertyCommandRevision: UInt64 = 0

    // MARK: - Runtime tasks and processes

    var browserFetchTask: Task<Void, Never>?
    var browserDetailHydrationTask: Task<Void, Never>?
    var webRuntimePreloadTask: Task<Void, Never>?
    var browserNextPage = 1
    var prefetchedBrowserPageKeys = Set<String>()
    var prefetchedBrowserPages: [String: SteamWorkshopBrowseStubPage] = [:]
    var pendingBrowserDetailStubs: [SteamWorkshopBrowseStub] = []
    var pendingBrowserDetailStubIDs = Set<String>()
    var browserDetailRetryCounts: [String: Int] = [:]
    var prioritizedVisibleBrowserItemIDs: [String] = []
    var lastPreviewPrefetchIDSet = Set<String>()
    var backgroundDetailDeferralUntil: Date = .distantPast
    var browserLoadMoreRetryAfter: Date = .distantPast

    // MARK: - Shared infrastructure

    var cancellables = Set<AnyCancellable>()
    let defaults: UserDefaults = {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--mwx-debug-user-defaults-suite"),
           arguments.indices.contains(index + 1) {
            let suiteName = arguments[index + 1]
            precondition(
                suiteName.hasPrefix("com.songziqiang.MyWallpaperX.Debug."),
                "Debug defaults suite must use the MyWallpaperX Debug namespace"
            )
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to create Debug defaults suite")
            }
            NSLog("MWX DEBUG DEFAULTS: suite=%@", suiteName)
            return defaults
        }
#endif
        return .standard
    }()
    var loginProcess: Process?
    var loginInputHandle: FileHandle?
    var loginOutputHandle: FileHandle?
    var loginOutputBuffer: String = ""
    var loginPasswordSent = false
    var loginSucceeded = false
    var loginSubmittedGuardCode = false
    var pendingLoginUsername: String = ""
    var pendingLoginPassword: String = ""
    var pendingLoginCommand: String?
    var startupTask: Task<Void, Never>?
    var loginBootstrapTimeoutTask: Task<Void, Never>?
    var loginSessionID: String = ""
    var lastSuccessfulSessionValidationAt: Date?
    let maximumConcurrentDownloads = 2
    var activeDownloadJobKeysByItemID: [String: String] = [:]
    var activeDownloadTasks: [String: Task<Void, Never>] = [:]
    var cancelledDownloadJobKeys: Set<String> = []
    var reservedLibraryCopyBytesByJobKey: [String: Int64] = [:]
    let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    let steamLibraryVersionLeaseRegistry = SteamWorkshopLibraryVersionLeaseRegistry()
    var libraryVersionReclamationTask: Task<Void, Never>?
    var selectedItemDetailTask: Task<Void, Never>?
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
        requestedURL = SteamWorkshopService.makeBrowseURL(
            browserContentMode: .video,
            source: .featured,
            query: "",
            trendingWindow: .week,
            themeFilter: .all,
            ageRatingFilter: .all,
            resolutionFilter: .all,
            categoryFilter: .all,
            page: 1,
            personalSort: .subscriptionDate
        )
#if DEBUG
        let isIsolatedWebSampleRun = ProcessInfo.processInfo.arguments.contains("--mwx-debug-run-web-workshop-id")
#else
        let isIsolatedWebSampleRun = false
#endif
        if !isIsolatedWebSampleRun {
#if DEBUG
            if !isSteamKitBrowseEnabled {
                // 整版本回退必须恢复旧 route 的完整启动 owner，而不是只把
                // 浏览函数切回去。该分支只由进程启动参数触发，发行构建不可达。
                loadAuthenticationState()
                refreshSteamRuntimeStatus()
                loadCachedBrowserItemsIfPossible()
            } else {
                restoreSavedSteamSessionIfAuthorized()
            }
#else
            // SK6.1：启动不再读取旧密码/SteamCMD 状态或 HTML 浏览缓存。
            // 旧凭据和缓存留待 SK6.2 按精确清单退役；本批只撤销其产品执行权。
            restoreSavedSteamSessionIfAuthorized()
#endif
        }
        reloadInstalledItems()
        refreshDisplayedDownloads()
        if !isIsolatedWebSampleRun {
            fetchBrowserItems()
        }
        observeWebPlaybackFailures()
        installLaunchPendingObservers()
        observeSteamAccountIdentityForPersonalSources()
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
                guard let self, self.source.isPersonal else { return }
                self.navigateToBrowse()
            }
            .store(in: &cancellables)
    }

    private func refreshDisplayedDownloads() {
        displayedDownloads = filteredAndSortedDownloads(from: downloads)
        sanitizeDownloadSelectionAgainstDisplayedDownloads()
    }
}
