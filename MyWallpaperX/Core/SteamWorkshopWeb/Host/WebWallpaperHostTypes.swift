//
//  WebWallpaperHostTypes.swift
//  MyWallpaperX
//
//  Web 壁纸播放边界类型。
//  当前 daemon + WKWebView 方案已经被验证为诊断 harness，
//  不应继续被默认理解为最终 Web 壁纸宿主。
//

import Foundation
import AppKit
import WebKit
import CoreGraphics
import Darwin

extension WallpaperEngine {
    enum WebWallpaperLaunchSource: String {
        case steamWorkshop
    }

    enum WebRuntimeOriginMode: String, Equatable {
        case customScheme
        case httpLoopback
    }

    struct WebRuntimeProfile: Equatable {
        enum DataStorePolicy: String {
            case sharedPersistent
            case workshopPersistent
            case scopedPersistent
            case ephemeral
        }

        let id: String
        let originMode: WebRuntimeOriginMode
        let dataStorePolicy: DataStorePolicy
        let strictLocalResourcePolicy: Bool
        let diagnosticsEnabled: Bool

        static let standard = WebRuntimeProfile(
            id: "standard",
            originMode: .customScheme,
            dataStorePolicy: .workshopPersistent,
            strictLocalResourcePolicy: false,
            diagnosticsEnabled: true
        )

        static let highCompatibility = WebRuntimeProfile(
            id: "highCompatibility",
            originMode: .httpLoopback,
            dataStorePolicy: .scopedPersistent,
            strictLocalResourcePolicy: false,
            diagnosticsEnabled: true
        )

        static let strictLocal = WebRuntimeProfile(
            id: "strictLocal",
            originMode: .customScheme,
            dataStorePolicy: .ephemeral,
            strictLocalResourcePolicy: true,
            diagnosticsEnabled: true
        )

        static let diagnostic = WebRuntimeProfile(
            id: "diagnostic",
            originMode: .httpLoopback,
            dataStorePolicy: .ephemeral,
            strictLocalResourcePolicy: false,
            diagnosticsEnabled: true
        )
    }

    struct WebWallpaperLaunchRequest {
        let id: UUID
        let entryURL: URL
        let rootURL: URL
        let propertiesJSON: String?
        let source: WebWallpaperLaunchSource
        let recordID: String?
        let language: String
        let runtimeProfile: WebRuntimeProfile
        let multiDisplayEnabled: Bool
        let resourceLifetime: PlaybackResourceLifetime?

        init(
            id: UUID = UUID(),
            entryURL: URL,
            rootURL: URL,
            propertiesJSON: String?,
            source: WebWallpaperLaunchSource,
            recordID: String?,
            language: String,
            runtimeProfile: WebRuntimeProfile,
            multiDisplayEnabled: Bool,
            resourceLifetime: PlaybackResourceLifetime? = nil
        ) {
            self.id = id
            self.entryURL = entryURL
            self.rootURL = rootURL
            self.propertiesJSON = propertiesJSON
            self.source = source
            self.recordID = recordID
            self.language = language
            self.runtimeProfile = runtimeProfile
            self.multiDisplayEnabled = multiDisplayEnabled
            self.resourceLifetime = resourceLifetime
        }
    }

    struct WebWallpaperRuntimeState {
        let paused: Bool
        let volume: Float
        let playbackRate: Float
        let spectrumLevels: [Float]?
    }

    enum WebWallpaperRuntimeCommand {
        case pause
        case resume(playbackRate: Float)
        case stop
        case setVolume(Float)
        case setPlaybackRate(Float)
        case applyProperties(String)
        case pushAudioSpectrum([Float])
    }

    enum WebWallpaperHostEvent {
        case accepted(requestID: UUID)
        case ready(requestID: UUID)
        case audioSpectrumDemandChanged(Bool, requestID: UUID)
        case failed(message: String, requestID: UUID)
        case stopped(requestID: UUID)
    }

    protocol WebWallpaperHostAdapter: AnyObject {
        var eventHandler: ((WebWallpaperHostEvent) -> Void)? { get set }
        func launch(_ request: WebWallpaperLaunchRequest, runtimeState: WebWallpaperRuntimeState)
        func updateDisplayConfiguration(multiDisplayEnabled: Bool)
        func handle(_ command: WebWallpaperRuntimeCommand)
    }
}

/// D5（Web 跨源 frame 定向回包与宿主推送）每 webView 的 frame endpoint 登记。
/// - frame 的持久主键是宿主生成的 endpoint token：WKFrameInfo 是瞬时对象
///   （Apple 明确不保证跨 delegate 调用唯一），URL/origin/frameInfo 相等性
///   一律不作主键。
/// - nonce/token 只做 hello 相关性与 challenge 续约路由，不是任何资源、网络
///   或主 frame 特权的凭据；页面伪造 token 只会让自己错过推送/续约失败。
/// - 生命周期：每个文档注入期 hello 注册；主导航/web content 进程终止/surface
///   teardown 撤销全部；子导航产生新 hello，旧 endpoint 由失效 challenge 或
///   租约到期撤销。
@MainActor
final class WebWallpaperFrameEndpointRegistry {
    /// 初始预算（D5：接受压力门后冻结）：每 webView 128 个 endpoint。
    static let endpointCapacityPerWebView = 128
    /// 租约初值 60s；存活文档每 20s 由宿主 challenge 续约（宿主调度，
    /// 不依赖可能被冻结的页面 RAF）。
    static let leaseDuration: TimeInterval = 60
    static let leaseRenewalInterval: TimeInterval = 20

    final class Endpoint {
        let token: String
        let documentNonce: String
        var frameInfo: WKFrameInfo
        var leaseExpiresAt: TimeInterval
        /// 逐 endpoint 单调推送序号：属性/暂停等推送按此有序，接收端丢弃乱序。
        private(set) var pushSequence: Int64 = 0
        /// 频谱每 endpoint 同时至多一个在途定向调用；期间只保留最新一份。
        private(set) var isSpectrumDeliveryInFlight = false
        var pendingSpectrumLevels: [Float]?

        init(token: String, documentNonce: String, frameInfo: WKFrameInfo, now: TimeInterval) {
            self.token = token
            self.documentNonce = documentNonce
            self.frameInfo = frameInfo
            self.leaseExpiresAt = now + WebWallpaperFrameEndpointRegistry.leaseDuration
        }

        func advancePushSequence() -> Int64 {
            pushSequence += 1
            return pushSequence
        }

        func beginSpectrumDelivery() { isSpectrumDeliveryInFlight = true }
        func endSpectrumDelivery() { isSpectrumDeliveryInFlight = false }

        func isLeaseValid(now: TimeInterval) -> Bool {
            leaseExpiresAt > now
        }

        func renewLease(now: TimeInterval) {
            leaseExpiresAt = now + WebWallpaperFrameEndpointRegistry.leaseDuration
        }
    }

    private var endpointsByWebView: [ObjectIdentifier: [String: Endpoint]] = [:]

    func endpoints(in webView: WKWebView) -> [Endpoint] {
        Array(endpointsByWebView[ObjectIdentifier(webView)]?.values ?? [:].values)
    }

    func hasEndpoints(in webView: WKWebView) -> Bool {
        endpointsByWebView[ObjectIdentifier(webView)]?.isEmpty == false
    }

    var hasAnyEndpoints: Bool {
        endpointsByWebView.contains { $0.value.isEmpty == false }
    }

    /// hello 注册：同一文档（同 nonce）重复 hello 只续租不新增；容量满时拒绝
    /// 新 endpoint（洪泛注册不扩大内存，既有 endpoint 不受影响）。
    func register(
        documentNonce: String,
        frameInfo: WKFrameInfo,
        in webView: WKWebView
    ) -> Endpoint? {
        let key = ObjectIdentifier(webView)
        var endpoints = endpointsByWebView[key] ?? [:]
        if let existing = endpoints.first(where: { $0.value.documentNonce == documentNonce }) {
            existing.value.frameInfo = frameInfo
            existing.value.renewLease(now: ProcessInfo.processInfo.systemUptime)
            return existing.value
        }
        guard endpoints.count < Self.endpointCapacityPerWebView else { return nil }
        let endpoint = Endpoint(
            token: UUID().uuidString,
            documentNonce: documentNonce,
            frameInfo: frameInfo,
            now: ProcessInfo.processInfo.systemUptime
        )
        endpoints[endpoint.token] = endpoint
        endpointsByWebView[key] = endpoints
        return endpoint
    }

    func renewLease(token: String, in webView: WKWebView) {
        endpointsByWebView[ObjectIdentifier(webView)]?[token]?
            .renewLease(now: ProcessInfo.processInfo.systemUptime)
    }

    func revoke(token: String, in webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        guard var endpoints = endpointsByWebView[key], endpoints.removeValue(forKey: token) != nil else {
            return
        }
        if endpoints.isEmpty {
            endpointsByWebView.removeValue(forKey: key)
        } else {
            endpointsByWebView[key] = endpoints
        }
    }

    func revokeAll(in webView: WKWebView) {
        endpointsByWebView.removeValue(forKey: ObjectIdentifier(webView))
    }
}

final class DedicatedWebWallpaperHostPlaceholderAdapter: NSObject, WallpaperEngine.WebWallpaperHostAdapter, WKNavigationDelegate, WKScriptMessageHandler {
    enum Phase: String {
        case idle
        case launching
        case ready
        case failed
    }

    /// E2c 站点 3: App 装配注入的下载记录解析器（返回外部依赖 host 白
    /// 名单）——Host 层不再直呼 Modules 的 SteamWorkshopService 单例。
    /// 注入前维持空名单（保守拒绝网络桥接）。
    var allowedNetworkBridgeHostsResolver: ((_ recordID: String) -> Set<String>)?

    final class HostWindow: NSWindow {
        override var canBecomeKey: Bool {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--mwx-debug-web-evidence-dir") {
                return true
            }
            #endif
            return false
        }
        override var canBecomeMain: Bool { false }
    }

    final class HostContentView: NSView {
        var blocksUnderlyingMouseInput = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard blocksUnderlyingMouseInput else { return nil }
            return super.hitTest(point)
        }
    }

    struct HostSurface {
        let screenID: CGDirectDisplayID
        let window: NSWindow
        let contentView: HostContentView
        let webView: WKWebView
        let audioDemandMessageHandler: WebAudioDemandMessageHandler
        let schemeHandler: WebWallpaperLocalSchemeHandler
        let originMode: WallpaperEngine.WebRuntimeOriginMode
        /// 本 surface 实际使用的持久化 store 标识（default/nonPersistent 为 nil）。
        let persistentDataStoreIdentifier: UUID?
    }

    struct NavigationOwnership {
        let requestID: UUID
        let navigation: WKNavigation
    }

    struct DirectorySnapshot {
        let filesByPath: [String: TimeInterval]
    }

    struct DirectorySyncStatus {
        let snapshot: DirectorySnapshot
        let isAccessible: Bool
        let errorMessage: String?
    }

    struct FetchAllDirectoryProperty {
        let name: String
        let path: String
    }

    struct FetchAllDirectoryNotification {
        let propertyName: String
        let addedOrChangedFiles: [String]
        let removedFiles: [String]
    }

    struct FetchAllDirectoryAccessNotification {
        let propertyName: String
        let errorMessage: String?
    }

    /// 目录访问错误去重键：属性名 + 屏幕标识，逐屏独立记录状态迁移。
    struct DirectoryAccessErrorKey: Hashable {
        let propertyName: String
        let screenID: CGDirectDisplayID?
    }

    struct FetchAllDirectorySyncResult {
        let seenPropertyNames: Set<String>
        let watchedDirectoriesByProperty: [String: String]
        let snapshotsByProperty: [String: DirectorySnapshot]
        let accessNotifications: [FetchAllDirectoryAccessNotification]
        let changeNotifications: [FetchAllDirectoryNotification]
        let hasFetchAllDirectory: Bool
    }

    struct InteractiveRegion {
        let id: String
        let normalizedRect: CGRect
        let allowsClick: Bool
        let allowsDrag: Bool
    }

    struct InteractiveRegionRegistration {
        let regions: [InteractiveRegion]
        let source: String
    }

    final class DirectoryWatcher {
        let path: String
        let fileDescriptor: Int32
        let source: DispatchSourceFileSystemObject

        init(path: String, fileDescriptor: Int32, source: DispatchSourceFileSystemObject) {
            self.path = path
            self.fileDescriptor = fileDescriptor
            self.source = source
        }
    }

    var eventHandler: ((WallpaperEngine.WebWallpaperHostEvent) -> Void)?

    /// D5：frame endpoint 登记与推送投递的唯一状态（per webView）。
    var frameEndpointRegistry = WebWallpaperFrameEndpointRegistry()
    /// 租约续约心跳（宿主调度）：首 endpoint 注册时启动，teardown 停止。
    var frameEndpointLeaseRenewalTimer: DispatchSourceTimer?
    /// 网络桥授权阶段（DNS 解析等，无应用层超时）在飞的 requestID：授权
    /// 看门狗据此在窗口到期时释放配额并回包；授权完成方与看门狗先到先得，
    /// 迟到方整体退役（防止双重 release/双重回包）。只在主线程访问。
    var pendingNetworkBridgeAuthorizationIDs: Set<String> = []

    var phase: Phase = .idle
    var currentRequest: WallpaperEngine.WebWallpaperLaunchRequest? {
        didSet {
            // 请求切换（新壁纸 / 停止 / 失败）时作废旧目录快照，并在后台预枚举
            // 新请求的 directory 属性；主线程的随机文件请求只做取值。
            guard oldValue?.id != currentRequest?.id else { return }
            resetRandomFileSnapshots()
            refreshRandomFileSnapshots(using: currentRequest?.propertiesJSON)
        }
    }
    var currentVolume: Float = 0.5
    var currentPlaybackRate: Float = 1.0
    var currentSpectrumLevels: [Float]?
    var paused = false
    var hostActivityToken: NSObjectProtocol?
    var lifecycleObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    var screenReconciliationWorkItem: DispatchWorkItem?
    var webContentRecoveryAttemptsByScreen: [CGDirectDisplayID: Int] = [:]
    /// 每屏最近一次 WebContent 终止时刻（systemUptime）：恢复成功不清除，
    /// 用作冷却窗判定的唯一记录。
    var lastWebContentTerminationAtByScreen: [CGDirectDisplayID: TimeInterval] = [:]
    var recoveringWebContentScreenIDs = Set<CGDirectDisplayID>()
    var webContentRecoveryReloadStartedScreenIDs = Set<CGDirectDisplayID>()
    var webContentRecoveryWorkItems: [CGDirectDisplayID: DispatchWorkItem] = [:]
    var readyScreenIDs = Set<CGDirectDisplayID>()
    /// 当前 request 是否已向引擎发过 `.ready`（markScreenReady 或 reconcile
    /// 补位）：多屏初始启动在途闪断（一屏 ready、另一屏 pre-ready 被拔）时，
    /// 补位转 .ready 后引擎的 .ready 事件也须补发一次（video 退场/暂停补发
    /// 还悬置着）；增屏闪断（增前已 ready）则不重发。launch 时复位。
    var didEmitReadyEventForCurrentRequest = false
    var audioSpectrumDemandScreenIDs = Set<CGDirectDisplayID>()
    var surfaces: [CGDirectDisplayID: HostSurface] = [:]
    var navigationOwnershipByScreen: [CGDirectDisplayID: NavigationOwnership] = [:]
    var loopbackServers: [CGDirectDisplayID: WebWallpaperLoopbackServer] = [:]
    var directorySnapshotsByProperty: [String: DirectorySnapshot] = [:]
    // 键含屏幕维度：目录访问错误通知按屏去重，多显示器各自收到状态迁移。
    var directoryAccessErrorsByProperty: [DirectoryAccessErrorKey: String] = [:]
    var randomFileSnapshotsByDirectoryPath: [String: DirectorySnapshot] = [:]
    var randomFileSnapshotRefreshedAtByDirectoryPath: [String: TimeInterval] = [:]
    var randomFileEnumeratingDirectoryPaths = Set<String>()
    var directoryWatchersByProperty: [String: DirectoryWatcher] = [:]
    var directoryWatchTimer: DispatchSourceTimer?
    let directorySyncQueue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.web-directory-sync", qos: .utility)
    var directorySyncRequestID: UInt64 = 0
    var deferredDirectorySyncWorkItem: DispatchWorkItem?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var pointerPollingTimer: Timer?
    var lastPolledMouseLocation: NSPoint?
    var lastHoveredScreenID: CGDirectDisplayID?
    var lastPointerMoveForwardedAt: TimeInterval = 0
    var activeInputForwardingStartedAt: TimeInterval?
    var cachedDesktopInputWindowNumber: Int?
    var cachedDesktopInputWindowAllowsForwarding = false
    var admittedDesktopGestureScreenByButton: [Int: CGDirectDisplayID] = [:]
    var interactiveRegionsByScreen: [CGDirectDisplayID: [InteractiveRegion]] = [:]
    var interactiveRegionRegistrationByScreen: [CGDirectDisplayID: InteractiveRegionRegistration] = [:]
    var transientCaptureReleaseWorkItems: [CGDirectDisplayID: DispatchWorkItem] = [:]
    var transientCaptureActiveScreenID: CGDirectDisplayID?
    var lastPreheatedRegionIDByScreen: [CGDirectDisplayID: String] = [:]
    #if DEBUG
    var debugSnapshotLumaSamplesByScreen: [CGDirectDisplayID: [String: [Double]]] = [:]
    #endif

    static let pointerMoveThrottleInterval: TimeInterval = 1.0 / 30.0
    static let activeClickWarmupDuration: TimeInterval = 0.45
    static let transientCaptureDuration: TimeInterval = 0.03
    static let dragCaptureDuration: TimeInterval = 0.12
    static let hoverPreheatInset: CGFloat = 0.03
    /// WebContent 恢复预算冷却窗：同一屏在窗内的第二次终止直接 fail-fast
    /// （拒绝崩溃循环），窗外的终止视为独立事件并重新武装一次恢复预算。
    static let webContentRecoveryCoolingWindow: TimeInterval = 5 * 60
    /// 随机文件目录快照的最小重枚举间隔，与 fetchall 目录轮询节奏一致。
    static let randomFileSnapshotRefreshInterval: TimeInterval = 10
    /// fetchall 目录事件（DispatchSource + 10s 定时器）触发全树重枚举前的
    /// trailing 去抖窗；churn 目录在一个窗内的所有事件合并为一次枚举。
    static let directorySyncDebounceInterval: TimeInterval = 0.5

    /// 兼容脚本主体（7 段顶层常量的一次性拼接）。旧实现按 surface 重新拼接，
    /// 每个新 surface 都在主线程重复分配约 187KB；per-screen 只有 seedScript
    /// 前缀参与每次拼接。缓存刻意留在函数体内：本函数是既有 DEBUG harness
    /// 按文本抽取的独立编译单元（test_web_playback_pause），不能依赖类上
    /// 未随抽取一起搬运的成员。
    static func webCompatibilityScript(
        for request: WallpaperEngine.WebWallpaperLaunchRequest?,
        generalPropertiesJSON: String,
        volume: Float,
        playbackRate: Float,
        paused: Bool
    ) -> String {
        enum ScriptBodyCache {
            static let body: String =
                webCompatibilityScriptBootstrap
                + webCompatibilityScriptMediaDiscovery
                + webCompatibilityScriptMediaState
                + webCompatibilityScriptInteractionAndRuntime
                + webCompatibilityScriptMediaObservers
                + webCompatibilityScriptDOMLifecycle
                + webCompatibilityScriptHostBridge
        }
        let propertiesJSON = request?.propertiesJSON ?? "{}"
        let escapedProperties = WebWallpaperHostSupport.javaScriptQuotedString(propertiesJSON)
        let escapedGeneralProperties = WebWallpaperHostSupport.javaScriptQuotedString(generalPropertiesJSON)
        let volumeLiteral = String(format: "%.6f", volume)
        let playbackRateLiteral = String(format: "%.6f", playbackRate)
        let pausedLiteral = paused ? "true" : "false"
        let seedScript = """
        (() => {
          try { window.__myWallpaperInitialUserProperties = JSON.parse(\(escapedProperties)); } catch (_) { window.__myWallpaperInitialUserProperties = {}; }
          try { window.__myWallpaperInitialGeneralProperties = JSON.parse(\(escapedGeneralProperties)); } catch (_) { window.__myWallpaperInitialGeneralProperties = {}; }
          window.__myWallpaperInitialVolume = \(volumeLiteral);
          window.__myWallpaperInitialPlaybackRate = \(playbackRateLiteral);
          window.__myWallpaperInitialPaused = \(pausedLiteral);
        })();
        """
        return seedScript + ScriptBodyCache.body
    }

    /// 播放脚本的暂停/恢复两份变体：`__MWX_INITIAL_PAUSED__` 替换在进程内各做
    /// 一次，避免每个新 surface 重新替换整段播放脚本。裸名会被下面同基名的
    /// `webWallpaperPlaybackScript(paused:)` 成员遮蔽，故显式限定模块名。
    private static let webWallpaperPlaybackScriptByPausedState: [Bool: String] = [
        true: MyWallpaperX.webWallpaperPlaybackScript.replacingOccurrences(of: "__MWX_INITIAL_PAUSED__", with: "true"),
        false: MyWallpaperX.webWallpaperPlaybackScript.replacingOccurrences(of: "__MWX_INITIAL_PAUSED__", with: "false")
    ]

    static func webWallpaperPlaybackScript(paused: Bool) -> String {
        webWallpaperPlaybackScriptByPausedState[paused] ?? MyWallpaperX.webWallpaperPlaybackScript
    }

    /// navigation.blocked 的 WebView 侧只读状态。宿主每次取消主框架导航后经
    /// `__mwxNavigationBlocked` 累加；页面与 DEBUG 探针可查询
    /// `window.__mwxNavigationState`，无需依赖宿主诊断存储。
    static let webNavigationStateScript = #"""
    (() => {
      try {
        if (window.__mwxNavigationState) { return; }
        const state = {
          blockedCount: 0,
          lastBlockedURL: null,
          lastBlockedReason: null,
          updatedAt: 0
        };
        Object.defineProperty(window, '__mwxNavigationState', {
          value: state,
          enumerable: false,
          configurable: false,
          writable: false
        });
        window.__mwxNavigationBlocked = function(payload) {
          try {
            state.blockedCount += 1;
            state.lastBlockedURL = payload && payload.url ? payload.url : null;
            state.lastBlockedReason = payload && payload.reason ? payload.reason : null;
            state.updatedAt = Date.now();
            window.dispatchEvent(new CustomEvent('mwx-navigation-blocked', {
              detail: { url: state.lastBlockedURL, reason: state.lastBlockedReason }
            }));
          } catch (_) {}
        };
      } catch (_) {}
    })();
    """#
}

/// 工坊 web 记录的持久化 WKWebsiteDataStore 回收。触发面只有装配层注入的事实
/// （Host 层不直呼 Modules 单例）：
/// - 删除钩子：装配层投递 downloads 投影 + 模块自身的删除意图
///   （SteamWorkshopService.removingDownloadIDs），只有"上一条投影里有、新投影里
///   没有、且带删除意图"的记录才算删除；宽限期复核后按统一派生标识调
///   `WKWebsiteDataStore.remove(forIdentifier:)`；
/// - 历史孤儿一次性退役：首次确认删除时，在同一次标识枚举里清掉既不属于在用记录、
///   也不属于在播 surface、也不属于任何可派生 scoped 档的 store（旧线性散列派生的
///   scoped store 与已删记录的 store 都在此列）。
/// 绝不从投影差集推断删除：「清除缓存」（SteamWorkshopService+BrowseStateRecovery.swift
/// 的 `downloads = []`）与启动早期只含重放单条记录的投影都不携带删除意图，既不触发
/// 记录回收也不触发孤儿退役。孤儿退役另要求在播记录仍在投影内（投影完整才敢全量清）。
/// 交付后果（与派生变更同批，必须对外写明）：scoped 档派生从模 256 线性散列改为
/// SHA256，highCompatibility 用户既有 scoped store 不会被新算法再次命中，其
/// localStorage 等于重置；旧 store 由本回收器按孤儿退役清理。
/// 已知边界（有意保留）：当前未接入显示器所创建的 scoped store 不在可派生集合里，
/// 会被判为孤儿回收；该屏重连后 store 重建，localStorage 随之重置。
@MainActor
final class WebWallpaperDataStoreReclaimer {
    static let shared = WebWallpaperDataStoreReclaimer()

    /// 「仍在用」事实（在播记录与在播 surface 实际持有的 store 标识）。
    struct LiveUsage {
        let activeRecordIDs: Set<String>
        let inUsePersistentDataStoreIdentifiers: Set<UUID>
    }

    /// 在用事实的实时读取（装配层注入，只在主线程调用）。删除判定落在宽限期末的
    /// work item 上，必须读那一刻的事实：投影回调时刻的快照无法反映 30s 内新建的
    /// surface 或新起播的记录，而 WebKit 的 "WKWebView 仍在使用该 store 时不得删除"
    /// 契约要求按删除时刻校验。未注入时退回 `updateLiveRecords` 传入的快照。
    var liveUsageProvider: (@MainActor () -> LiveUsage)?

    /// 删除复核宽限期：工坊库重扫 / 版本发布可能让记录短暂缺席。
    static let removalGracePeriod: TimeInterval = 30
    /// 仍在用（surface 未释放）时的有界重试次数：arm 阶段不丢弃删除，只推迟；
    /// 用尽后显式记录放弃原因，让"没回收"始终可在日志里追到。
    static let maxRemovalAttempts = 3

    private(set) var liveRecordIDs = Set<String>()
    private var identifiersByRecordID: [String: Set<UUID>] = [:]
    private var pendingRemovalWorkItems: [String: DispatchWorkItem] = [:]
    private var removalAttemptsByRecordID: [String: Int] = [:]
    private var activeRecordIDs = Set<String>()
    private var inUsePersistentDataStoreIdentifiers = Set<UUID>()
    private var didRetireOrphanStores = false

    /// 删除事件的唯一判定（纯函数）：意图集合为空（清空 / 重扫 / 早期投影）一律
    /// 不构成删除；只有同时满足"曾见过、新投影缺席、模块声明了删除意图"才成立。
    static func confirmedDeletedRecordIDs(
        previouslyKnown: Set<String>,
        currentProjection: Set<String>,
        removalIntent: Set<String>
    ) -> Set<String> {
        guard !removalIntent.isEmpty else { return [] }
        return previouslyKnown
            .subtracting(currentProjection)
            .intersection(removalIntent)
    }

    /// 装配层每次收到 downloads 投影时调用。`removalIntent` 是模块自身的删除意图
    /// 快照（装配层必须同步投递，避免意图在宽限期内被撤下）；`activeRecordIDs` 与
    /// `inUsePersistentDataStoreIdentifiers` 是在播记录 / 在播 surface 实际持有的
    /// store 标识：有 `liveUsageProvider` 时它们只是投影时刻的兜底快照，删除复核
    /// 按 provider 的实时事实执行。
    func updateLiveRecords(
        _ records: [DedicatedWebWallpaperHostPlaceholderAdapter.WebPersistentDataStoreRecord],
        screenIDs: [CGDirectDisplayID],
        removalIntent: Set<String>,
        activeRecordIDs: Set<String>,
        inUsePersistentDataStoreIdentifiers: Set<UUID>
    ) {
        var nextIdentifiersByRecordID: [String: Set<UUID>] = [:]
        for record in records {
            nextIdentifiersByRecordID[record.recordID] = DedicatedWebWallpaperHostPlaceholderAdapter.persistentDataStoreIdentifiers(
                for: record,
                screenIDs: screenIDs
            )
        }
        let deletedRecordIDs = Self.confirmedDeletedRecordIDs(
            previouslyKnown: liveRecordIDs,
            currentProjection: Set(nextIdentifiersByRecordID.keys),
            removalIntent: removalIntent
        ).sorted()
        let previousIdentifiersByRecordID = identifiersByRecordID
        liveRecordIDs = Set(nextIdentifiersByRecordID.keys)
        identifiersByRecordID = nextIdentifiersByRecordID
        self.activeRecordIDs = activeRecordIDs
        self.inUsePersistentDataStoreIdentifiers = inUsePersistentDataStoreIdentifiers

        for recordID in nextIdentifiersByRecordID.keys {
            // 记录在宽限期内回归（库重扫 / 版本发布）：撤销待执行删除。
            pendingRemovalWorkItems.removeValue(forKey: recordID)?.cancel()
            removalAttemptsByRecordID.removeValue(forKey: recordID)
        }
        for recordID in deletedRecordIDs {
            guard let identifiers = previousIdentifiersByRecordID[recordID],
                  !identifiers.isEmpty else { continue }
            // arm 阶段不做 still_in_use 丢弃：此刻记录已被移出 liveRecordIDs，
            // 任何后续发射都不会再判它一次删除；WebKit 契约校验统一交给宽限期末
            // 复核（且仍在用则按 maxRemovalAttempts 有界重试，不静默放弃）。
            schedulePersistentDataStoreRemoval(recordID: recordID, identifiers: identifiers)
        }
    }

    /// 删除回收的唯一调度：宽限期末复核在用状态——仍被在播记录 / 在播 surface 持有
    /// 时重挂一次（同一宽限期），次数用尽后显式记录放弃原因。复核读 `liveUsageProvider`
    /// 的实时事实（未注入时才用投影快照）。
    private func schedulePersistentDataStoreRemoval(recordID: String, identifiers: Set<UUID>) {
        let attempt = removalAttemptsByRecordID[recordID, default: 0] + 1
        removalAttemptsByRecordID[recordID] = attempt
        pendingRemovalWorkItems.removeValue(forKey: recordID)?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRemovalWorkItems.removeValue(forKey: recordID)
            guard !self.liveRecordIDs.contains(recordID) else {
                self.removalAttemptsByRecordID.removeValue(forKey: recordID)
                return
            }
            let liveUsage = self.currentLiveUsage()
            let stillInUse = liveUsage.activeRecordIDs.contains(recordID)
                || !identifiers.isDisjoint(with: liveUsage.inUsePersistentDataStoreIdentifiers)
            if stillInUse {
                guard attempt < Self.maxRemovalAttempts else {
                    self.removalAttemptsByRecordID.removeValue(forKey: recordID)
                    NSLog(
                        "MWX WEB DATASTORE REMOVAL: skipped record=%@ reason=still_in_use attempts=%d",
                        recordID,
                        attempt
                    )
                    return
                }
                self.schedulePersistentDataStoreRemoval(recordID: recordID, identifiers: identifiers)
                return
            }
            self.removalAttemptsByRecordID.removeValue(forKey: recordID)
            self.reclaimPersistentDataStores(removing: identifiers, recordID: recordID, liveUsage: liveUsage)
        }
        pendingRemovalWorkItems[recordID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.removalGracePeriod, execute: workItem)
    }

    /// work item 执行时刻的在用事实：优先现读，未注入 provider 时退回投影快照。
    private func currentLiveUsage() -> LiveUsage {
        liveUsageProvider?() ?? LiveUsage(
            activeRecordIDs: activeRecordIDs,
            inUsePersistentDataStoreIdentifiers: inUsePersistentDataStoreIdentifiers
        )
    }

    private func reclaimPersistentDataStores(
        removing removedIdentifiers: Set<UUID>,
        recordID: String,
        liveUsage: LiveUsage
    ) {
        guard #available(macOS 14.0, *) else { return }
        // 在播记录 / 在播 surface 持有的 store 一律排除：WKWebsiteDataStore 的
        // "WKWebView using the data store must be released before removal" 契约。
        // 集合来自复核时刻的实时事实（含宽限期内新建的 surface）。
        let protectedIdentifiers = liveUsage.activeRecordIDs
            .union(liveRecordIDs)
            .reduce(into: Set<UUID>()) { $0.formUnion(identifiersByRecordID[$1] ?? []) }
            .union(liveUsage.inUsePersistentDataStoreIdentifiers)
        let liveIdentifiers = identifiersByRecordID.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        let retiresOrphanStores = !didRetireOrphanStores && liveUsage.activeRecordIDs.isSubset(of: liveRecordIDs)
        // 与 SteamWorkshopLegacyAcquisitionRetirement 的 web store 退役同法：WebKit
        // 的类级 store API 会分发回自己的 run loop，先初始化该 owner 再枚举标识。
        _ = WKWebsiteDataStore.default()
        WKWebsiteDataStore.fetchAllDataStoreIdentifiers { [weak self] identifiers in
            guard let self else { return }
            var targets = removedIdentifiers.subtracting(protectedIdentifiers)
            if retiresOrphanStores {
                self.didRetireOrphanStores = true
                // default / nonPersistent store 没有标识，不在枚举结果里。
                targets.formUnion(identifiers.filter {
                    !liveIdentifiers.contains($0) && !protectedIdentifiers.contains($0)
                })
            }
            guard !targets.isEmpty else { return }
            for identifier in targets.sorted(by: { $0.uuidString < $1.uuidString }) {
                WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
                    if let error {
                        NSLog(
                            "MWX WEB DATASTORE REMOVAL: failed record=%@ identifier=%@ error=%@",
                            recordID,
                            identifier.uuidString,
                            error.localizedDescription
                        )
                    } else {
                        NSLog(
                            "MWX WEB DATASTORE REMOVAL: removed record=%@ identifier=%@",
                            recordID,
                            identifier.uuidString
                        )
                    }
                }
            }
        }
    }
}
