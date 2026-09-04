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

    // MARK: - Download selection state

    @Published var activeDownloadItemID: String?
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
    var pendingDownloadRequest: SteamWorkshopPendingDownloadRequest?
    var queuedDownloadRequests: [SteamWorkshopPendingDownloadRequest] = []
    var lastSuccessfulSessionValidationAt: Date?
    var activeDownloadProcess: Process?
    var activeDownloadTask: Task<Void, Never>?
    var activeDownloadWasCancelled = false
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
            loadAuthenticationState()
            refreshSteamRuntimeStatus()
            loadCachedBrowserItemsIfPossible()
        }
        reloadInstalledItems()
        refreshDisplayedDownloads()
        if !isIsolatedWebSampleRun {
            fetchBrowserItems()
        }
        observeWebPlaybackFailures()
    }

    private func refreshDisplayedDownloads() {
        displayedDownloads = filteredAndSortedDownloads(from: downloads)
        sanitizeDownloadSelectionAgainstDisplayedDownloads()
    }
}
