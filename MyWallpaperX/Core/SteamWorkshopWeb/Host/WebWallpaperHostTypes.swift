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
    enum WebWallpaperHostStrategy: String {
        case daemonDiagnosticsHarness
        case dedicatedHostPlaceholder
    }

    enum WebWallpaperLaunchSource: String {
        case steamWorkshop
        case diagnostic
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
        var strategy: WebWallpaperHostStrategy { get }
        var eventHandler: ((WebWallpaperHostEvent) -> Void)? { get set }
        func launch(_ request: WebWallpaperLaunchRequest, runtimeState: WebWallpaperRuntimeState)
        func updateDisplayConfiguration(multiDisplayEnabled: Bool)
        func handle(_ command: WebWallpaperRuntimeCommand)
    }
}

final class DedicatedWebWallpaperHostPlaceholderAdapter: NSObject, WallpaperEngine.WebWallpaperHostAdapter, WKNavigationDelegate, WKScriptMessageHandler {
    enum Phase: String {
        case idle
        case launching
        case ready
        case failed
    }

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
        let dataStoreIdentity: String
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

    var strategy: WallpaperEngine.WebWallpaperHostStrategy { .dedicatedHostPlaceholder }
    var eventHandler: ((WallpaperEngine.WebWallpaperHostEvent) -> Void)?

    var phase: Phase = .idle
    var currentRequest: WallpaperEngine.WebWallpaperLaunchRequest?
    var currentVolume: Float = 0.5
    var currentPlaybackRate: Float = 1.0
    var currentSpectrumLevels: [Float]?
    var paused = false
    var hostActivityToken: NSObjectProtocol?
    var lifecycleObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    var screenReconciliationWorkItem: DispatchWorkItem?
    var webContentRecoveryAttemptsByScreen: [CGDirectDisplayID: Int] = [:]
    var recoveringWebContentScreenIDs = Set<CGDirectDisplayID>()
    var webContentRecoveryReloadStartedScreenIDs = Set<CGDirectDisplayID>()
    var webContentRecoveryWorkItems: [CGDirectDisplayID: DispatchWorkItem] = [:]
    var readyScreenIDs = Set<CGDirectDisplayID>()
    var audioSpectrumDemandScreenIDs = Set<CGDirectDisplayID>()
    var surfaces: [CGDirectDisplayID: HostSurface] = [:]
    var navigationOwnershipByScreen: [CGDirectDisplayID: NavigationOwnership] = [:]
    var loopbackServers: [CGDirectDisplayID: WebWallpaperLoopbackServer] = [:]
    var directorySnapshotsByProperty: [String: DirectorySnapshot] = [:]
    var directoryAccessErrorsByProperty: [String: String] = [:]
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
    static func webCompatibilityScript(
        for request: WallpaperEngine.WebWallpaperLaunchRequest?,
        generalPropertiesJSON: String,
        volume: Float,
        playbackRate: Float,
        paused: Bool
    ) -> String {
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
        return seedScript
        + webCompatibilityScriptBootstrap
        + webCompatibilityScriptMediaDiscovery
        + webCompatibilityScriptMediaState
        + webCompatibilityScriptInteractionAndRuntime
        + webCompatibilityScriptMediaObservers
        + webCompatibilityScriptDOMLifecycle
        + webCompatibilityScriptHostBridge
    }
}
