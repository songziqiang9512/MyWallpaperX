//
//  DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit
import CoreGraphics
import CryptoKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func makeSurface(for screen: NSScreen, screenID: CGDirectDisplayID) -> HostSurface {
        let request = currentRequest
        let window = HostWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        // 默认保持桌面透传；只在命中热点时做短时接管。
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.level = Self.webWindowLevel
        window.collectionBehavior = Self.webWindowCollectionBehavior
        let contentView = HostContentView(frame: window.frame)
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = contentView

        let controller = WKUserContentController()
        let audioDemandMessageHandler = WebAudioDemandMessageHandler(adapter: self, screenID: screenID)
        controller.add(self, name: "wallpaperHostLog")
        controller.add(audioDemandMessageHandler, name: "wallpaperHostAudioDemand")
        controller.add(self, name: "wallpaperHostRandomFile")
        controller.add(self, name: "wallpaperHostInteractiveRegions")
        controller.add(self, name: "wallpaperHostNetworkRequest")
        controller.addUserScript(WKUserScript(
            source: Self.webWallpaperPlaybackScript(paused: paused),
            injectionTime: .atDocumentStart, forMainFrameOnly: false
        ))
        // navigation.blocked 的 WebView 侧通道：主框架导航被取消后页面可查询
        // 阻断计数与末次目标（宿主经 evaluateJavaScript 累加，见 NavigationDelegate）。
        controller.addUserScript(WKUserScript(
            source: Self.webNavigationStateScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        // 兼容 API 面与种子按 frame 各自建立（种子只是本 frame 的初始值，
        // 属性/媒体/指针状态都存储在 window 上），因此与暂停门、远程样式表
        // 脚本保持同一注入面：iframe 壁纸同样拿到完整 API。
        controller.addUserScript(
            WKUserScript(
                source: Self.webCompatibilityScript(
                    for: request,
                    generalPropertiesJSON: currentGeneralPropertiesJSON(for: screen, screenID: screenID),
                    volume: currentVolume,
                    playbackRate: currentPlaybackRate,
                    paused: paused
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mwx-debug-web-stall-animation-frame") {
            controller.addUserScript(
                WKUserScript(
                    source: """
                    window.requestAnimationFrame = function() { return 1; };
                    window.__myWallpaperDebugAnimationFrameStalled = true;
                    try {
                      window.webkit.messageHandlers.wallpaperHostLog.postMessage({
                        type: 'debug.animation-frame.suppressed',
                        message: 'active'
                      });
                    } catch (_) {}
                    """,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
        #endif
        controller.addUserScript(
            WKUserScript(
                source: webRemoteStylesheetCompatibilityScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        let schemeHandler = WebWallpaperLocalSchemeHandler(
            rootURL: request?.rootURL ?? URL(fileURLWithPath: "/"),
            strictSymlinkPolicy: request?.runtimeProfile.strictLocalResourcePolicy ?? false
        )
        schemeHandler.updateAdditionalReadableRoots(accessibleResourceURLs(from: request?.propertiesJSON))
        schemeHandler.diagnosticHandler = { [weak self] type, severity, message, url in
            Task { @MainActor in
                self?.recordDiagnostic(type: type, severity: severity, message: message, screenID: screenID, url: url?.absoluteString)
            }
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.websiteDataStore = websiteDataStore(for: request, screenID: screenID)
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: WebWallpaperHostSupport.localScheme)
        let webView = WKWebView(frame: contentView.bounds, configuration: configuration)
        webView.setAllMediaPlaybackSuspended(paused, completionHandler: nil)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        if #available(macOS 13.0, *) {
            webView.isInspectable = request?.runtimeProfile.diagnosticsEnabled ?? true
        }
        contentView.addSubview(webView)
        return HostSurface(
            screenID: screenID,
            window: window,
            contentView: contentView,
            webView: webView,
            audioDemandMessageHandler: audioDemandMessageHandler,
            schemeHandler: schemeHandler,
            originMode: request?.runtimeProfile.originMode ?? .customScheme,
            persistentDataStoreIdentifier: persistentDataStoreIdentifier(for: request, screenID: screenID)
        )
    }

    func teardownHostSurfaces() {
        resetWebContentRecoveryState()
        resetTransientMouseCaptureState()
        stopGlobalMouseForwarding()
        endHostActivity()
        deferredDirectorySyncWorkItem?.cancel()
        deferredDirectorySyncWorkItem = nil
        stopAllDirectoryWatchers()
        stopDirectoryWatchTimer()
        directoryAccessErrorsByProperty.removeAll()
        #if DEBUG
        debugSnapshotLumaSamplesByScreen.removeAll()
        #endif
        for screenID in Array(surfaces.keys) {
            removeSurface(for: screenID)
        }
        navigationOwnershipByScreen.removeAll()
        clearAudioSpectrumDemand()
        for server in loopbackServers.values {
            server.stop()
        }
        loopbackServers.removeAll()
        let activeMonitorCount = (localMouseMonitor == nil ? 0 : 1) + (globalMouseMonitor == nil ? 0 : 1)
        recordDiagnostic(
            type: "lifecycle.teardown",
            severity: .info,
            message: "surfaces=\(surfaces.count) loopbacks=\(loopbackServers.count) watchers=\(directoryWatchersByProperty.count) monitors=\(activeMonitorCount) pointerTimer=\(pointerPollingTimer == nil ? 0 : 1)",
            screenID: nil,
            url: nil
        )
    }

    func removeSurface(for screenID: CGDirectDisplayID) {
        navigationOwnershipByScreen.removeValue(forKey: screenID)
        setAudioSpectrumDemand(false, for: screenID)
        guard let surface = surfaces[screenID] else { return }
        resetWebContentRecoveryState(for: screenID)
        resetInteractionState(for: screenID)
        #if DEBUG
        debugSnapshotLumaSamplesByScreen.removeValue(forKey: screenID)
        #endif
        surfaces.removeValue(forKey: screenID)
        if let loopbackServer = loopbackServers.removeValue(forKey: screenID) {
            recordDiagnostic(
                type: "loopback.stopped",
                severity: .info,
                message: "screen=\(screenID)",
                screenID: screenID,
                url: nil
            )
            loopbackServer.stop()
        }
        readyScreenIDs.remove(screenID)
        surface.webView.navigationDelegate = nil
        surface.webView.stopLoading()
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostLog")
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostAudioDemand")
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostRandomFile")
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostInteractiveRegions")
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostNetworkRequest")
        surface.webView.loadHTMLString("", baseURL: nil)
        surface.webView.removeFromSuperview()
        surface.window.orderOut(nil)
        surface.window.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak webView = surface.webView] in
            guard let self else { return }
            self.recordDiagnostic(
                type: webView == nil ? "lifecycle.surface.released" : "lifecycle.surface.retained",
                severity: webView == nil ? .info : .warning,
                message: "screen=\(screenID)",
                screenID: screenID,
                url: nil
            )
        }
    }

    func resetInteractionState(for screenID: CGDirectDisplayID) {
        cancelAdmittedDesktopGestures(for: screenID)
        interactiveRegionsByScreen.removeValue(forKey: screenID)
        interactiveRegionRegistrationByScreen.removeValue(forKey: screenID)
        lastPreheatedRegionIDByScreen.removeValue(forKey: screenID)
        transientCaptureReleaseWorkItems.removeValue(forKey: screenID)?.cancel()
        if transientCaptureActiveScreenID == screenID {
            transientCaptureActiveScreenID = nil
        }
        if lastHoveredScreenID == screenID {
            lastHoveredScreenID = nil
        }
        if let surface = surfaces[screenID] {
            setTransientMouseCaptureEnabled(false, for: surface)
        }
    }

    func forEachWebView(_ body: (WKWebView) -> Void) {
        for surface in surfaces.values {
            body(surface.webView)
        }
    }

    /// 当前所有 surface 实际持有的持久化 store 标识。回收侧用它显式排除仍被
    /// WKWebView 使用的 store（释放前删除会被 WebKit 拒绝）。
    var inUsePersistentDataStoreIdentifiers: Set<UUID> {
        Set(surfaces.values.compactMap(\.persistentDataStoreIdentifier))
    }

    func screenID(for webView: WKWebView) -> CGDirectDisplayID? {
        surfaces.first(where: { $0.value.webView === webView })?.key
    }

    func webView(for userContentController: WKUserContentController) -> WKWebView? {
        surfaces.values.first(where: {
            $0.webView.configuration.userContentController === userContentController
        })?.webView
    }

    func setTransientMouseCaptureEnabled(_ enabled: Bool, for surface: HostSurface) {
        surface.window.ignoresMouseEvents = !enabled
        surface.contentView.blocksUnderlyingMouseInput = enabled
    }

    func beginTransientMouseCapture(for surface: HostSurface) {
        transientCaptureActiveScreenID = surface.screenID
        transientCaptureReleaseWorkItems[surface.screenID]?.cancel()
        transientCaptureReleaseWorkItems[surface.screenID] = nil
        setTransientMouseCaptureEnabled(true, for: surface)
    }

    func scheduleTransientMouseCaptureRelease(for screenID: CGDirectDisplayID, delay: TimeInterval? = nil) {
        let effectiveDelay = delay ?? Self.transientCaptureDuration
        transientCaptureReleaseWorkItems[screenID]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let surface = self.surfaces[screenID] else { return }
            self.setTransientMouseCaptureEnabled(false, for: surface)
            if self.transientCaptureActiveScreenID == screenID {
                self.transientCaptureActiveScreenID = nil
            }
            self.transientCaptureReleaseWorkItems[screenID] = nil
        }
        transientCaptureReleaseWorkItems[screenID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: workItem)
    }

    func resetTransientMouseCaptureState() {
        transientCaptureActiveScreenID = nil
        for workItem in transientCaptureReleaseWorkItems.values {
            workItem.cancel()
        }
        transientCaptureReleaseWorkItems.removeAll()
        for surface in surfaces.values {
            setTransientMouseCaptureEnabled(false, for: surface)
        }
    }

    static func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static var webWindowLevel: NSWindow.Level {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mwx-debug-web-evidence-dir") {
            return .floating
        }
        #endif
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }

    static var webWindowCollectionBehavior: NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mwx-debug-web-evidence-dir") {
            behavior.remove(.canJoinAllSpaces)
            behavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        }
        #endif
        return behavior
    }

    func websiteDataStore(for request: WallpaperEngine.WebWallpaperLaunchRequest?, screenID: CGDirectDisplayID) -> WKWebsiteDataStore {
        switch request?.runtimeProfile.dataStorePolicy ?? .sharedPersistent {
        case .sharedPersistent:
            return .default()
        case .ephemeral:
            return .nonPersistent()
        case .workshopPersistent, .scopedPersistent:
            if #available(macOS 14.0, *),
               let identifier = persistentDataStoreIdentifier(for: request, screenID: screenID) {
                return WKWebsiteDataStore(forIdentifier: identifier)
            }
            return .nonPersistent()
        }
    }

    /// 该 request/screen 实际使用的持久化 store 标识（default/nonPersistent 没有
    /// 标识，返回 nil）。创建路径与回收路径共用它，surface 也持有同一标识，
    /// 使「WKWebView 仍在用该 store 时不得删除」可被显式校验。
    func persistentDataStoreIdentifier(
        for request: WallpaperEngine.WebWallpaperLaunchRequest?,
        screenID: CGDirectDisplayID
    ) -> UUID? {
        switch request?.runtimeProfile.dataStorePolicy ?? .sharedPersistent {
        case .workshopPersistent:
            return workshopDataStoreUUID(for: request)
        case .scopedPersistent:
            return Self.persistentDataStoreIdentifier(
                for: dataStoreIdentity(for: request, screenID: screenID)
            )
        case .sharedPersistent, .ephemeral:
            return nil
        }
    }

    func workshopDataStoreUUID(for request: WallpaperEngine.WebWallpaperLaunchRequest?) -> UUID {
        Self.persistentDataStoreIdentifier(
            for: Self.workshopDataStoreIdentity(
                recordID: request?.recordID ?? "workshop",
                rootPath: Self.resolvedRootPath(request?.rootURL),
                profileID: request?.runtimeProfile.id ?? "standard"
            )
        )
    }

    func dataStoreIdentity(for request: WallpaperEngine.WebWallpaperLaunchRequest?, screenID: CGDirectDisplayID) -> String {
        Self.scopedDataStoreIdentity(
            recordID: request?.recordID ?? "diagnostic",
            screenID: screenID,
            rootPath: Self.resolvedRootPath(request?.rootURL),
            profileID: request?.runtimeProfile.id ?? "standard"
        )
    }

    /// 持久化 WebKit store 标识（UUID）的唯一派生：SHA256 前 16 字节 + RFC 4122
    /// version/variant 位。工坊档与 scoped 档共用它；旧 scoped 档的模 256 线性
    /// 散列（可按身份构造碰撞）已退役，其遗留 store 由 `WebWallpaperDataStoreReclaimer`
    /// 的历史孤儿退役回收。
    static func persistentDataStoreIdentifier(for identity: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid)
    }

    /// 工坊档（profile 级持久化）身份串：`recordID|rootPath|profileID`。
    static func workshopDataStoreIdentity(recordID: String, rootPath: String, profileID: String) -> String {
        "\(recordID)|\(rootPath)|\(profileID)"
    }

    /// scoped 档（逐屏持久化）身份串：`recordID|screenID|rootPath|profileID`。
    static func scopedDataStoreIdentity(recordID: String, screenID: CGDirectDisplayID, rootPath: String, profileID: String) -> String {
        "\(recordID)|\(screenID)|\(rootPath)|\(profileID)"
    }

    static func resolvedRootPath(_ rootURL: URL?) -> String {
        rootURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? "root"
    }

    /// 装配层注入的工坊 web 记录身份（Host 只按自身派生规则展开，不认识
    /// Modules 的记录类型）。`rootPaths` 是候选资源根的宽集合：descriptor 的
    /// 有效根、记录解析根、依赖宿主目录与记录目录。宽集合只让在用 store 更不
    /// 可能被误判为孤儿，不参与创建侧派生。
    struct WebPersistentDataStoreRecord {
        let recordID: String
        let rootPaths: [String]
    }

    /// 持久化策略的 runtime profile：创建侧按记录选一个，回收侧需要全量候选
    /// （同一记录可能先后以不同 profile 播放过）。
    static let persistableWebRuntimeProfiles: [WallpaperEngine.WebRuntimeProfile] = [
        .standard,
        .highCompatibility
    ]

    /// 记录身份 → 该记录可能创建的持久化 store 标识全量（工坊档 + 逐屏 scoped 档）。
    static func persistentDataStoreIdentifiers(
        for record: WebPersistentDataStoreRecord,
        profiles: [WallpaperEngine.WebRuntimeProfile] = persistableWebRuntimeProfiles,
        screenIDs: [CGDirectDisplayID]
    ) -> Set<UUID> {
        var identifiers = Set<UUID>()
        for profile in profiles {
            switch profile.dataStorePolicy {
            case .workshopPersistent:
                for rootPath in record.rootPaths {
                    identifiers.insert(persistentDataStoreIdentifier(
                        for: workshopDataStoreIdentity(
                            recordID: record.recordID,
                            rootPath: rootPath,
                            profileID: profile.id
                        )
                    ))
                }
            case .scopedPersistent:
                for rootPath in record.rootPaths {
                    for screenID in screenIDs {
                        identifiers.insert(persistentDataStoreIdentifier(
                            for: scopedDataStoreIdentity(
                                recordID: record.recordID,
                                screenID: screenID,
                                rootPath: rootPath,
                                profileID: profile.id
                            )
                        ))
                    }
                }
            case .sharedPersistent, .ephemeral:
                // 默认 store 没有标识（WKWebsiteDataStore.identifier 对 default /
                // nonPersistent 返回 nil），ephemeral 不落盘：都不属于回收面。
                continue
            }
        }
        return identifiers
    }
}
