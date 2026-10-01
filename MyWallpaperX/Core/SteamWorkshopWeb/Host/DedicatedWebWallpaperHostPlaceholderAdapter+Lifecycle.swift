//
//  DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func beginHostActivity() {
        guard hostActivityToken == nil else { return }
        hostActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "MyWallpaperX Web wallpaper active playback"
        )
    }

    func endHostActivity() {
        guard let hostActivityToken else { return }
        ProcessInfo.processInfo.endActivity(hostActivityToken)
        self.hostActivityToken = nil
    }

    func launch(
        _ request: WallpaperEngine.WebWallpaperLaunchRequest,
        runtimeState: WallpaperEngine.WebWallpaperRuntimeState
    ) {
        let shouldRebuildSurfaces = currentRequest?.id != request.id
            || currentRequest?.entryURL.resolvingSymlinksInPath().standardizedFileURL != request.entryURL.resolvingSymlinksInPath().standardizedFileURL
            || currentRequest?.rootURL.resolvingSymlinksInPath().standardizedFileURL != request.rootURL.resolvingSymlinksInPath().standardizedFileURL
            || currentRequest?.runtimeProfile != request.runtimeProfile
            || currentRequest?.recordID != request.recordID
            || currentRequest?.multiDisplayEnabled != request.multiDisplayEnabled

        if shouldRebuildSurfaces {
            teardownHostSurfaces()
        } else {
            resetWebContentRecoveryState()
        }
        installLifecycleObservers()
        beginHostActivity()
        currentRequest = request
        currentVolume = runtimeState.volume
        currentPlaybackRate = runtimeState.playbackRate
        currentSpectrumLevels = runtimeState.spectrumLevels
        phase = .launching
        paused = runtimeState.paused
        resetInteractiveRegions()
        resetTransientMouseCaptureState()
        readyScreenIDs.removeAll()
        directorySnapshotsByProperty.removeAll()
        directoryAccessErrorsByProperty.removeAll()
        deferredDirectorySyncWorkItem?.cancel()
        deferredDirectorySyncWorkItem = nil
        stopAllDirectoryWatchers()
        stopDirectoryWatchTimer()
        eventHandler?(.accepted(requestID: request.id))

        let targetScreens = targetScreens(for: request)
        guard !targetScreens.isEmpty else {
            failCurrentLaunch(message: "dedicated_web_host_no_screens")
            return
        }

        let entryURL = WebWallpaperHostSupport.makeLocalSchemeEntryURL(
            entryURL: request.entryURL,
            rootURL: request.rootURL
        )
        recordDiagnostic(
            type: "runtime.profile",
            severity: .info,
            message: "profile=\(request.runtimeProfile.id) origin=\(request.runtimeProfile.originMode.rawValue) dataStore=\(request.runtimeProfile.dataStorePolicy.rawValue)",
            screenID: nil,
            url: entryURL.absoluteString
        )

        if !shouldRebuildSurfaces, !surfaces.isEmpty {
            installDefaultInteractiveRegionsIfNeeded()
            // 装载失败在异步完成回调里以同一 message failCurrentLaunch。
            reloadTrackedSurfaces(for: request, localEntryURL: entryURL)
            return
        }

        let createdAllSurfaces = targetScreens.allSatisfy { screen in
            createAndLoadSurface(
                for: screen,
                request: request,
                localEntryURL: entryURL,
                loadFailureMessage: "dedicated_web_host_no_surface"
            )
        }

        guard createdAllSurfaces, surfaces.count == targetScreens.count else {
            failCurrentLaunch(message: "dedicated_web_host_no_surface")
            return
        }
    }

    func updateDisplayConfiguration(multiDisplayEnabled: Bool) {
        guard let request = currentRequest,
              request.multiDisplayEnabled != multiDisplayEnabled else {
            return
        }
        let updatedRequest = WallpaperEngine.WebWallpaperLaunchRequest(
            id: request.id,
            entryURL: request.entryURL,
            rootURL: request.rootURL,
            propertiesJSON: request.propertiesJSON,
            source: request.source,
            recordID: request.recordID,
            language: request.language,
            runtimeProfile: request.runtimeProfile,
            multiDisplayEnabled: multiDisplayEnabled,
            resourceLifetime: request.resourceLifetime
        )
        currentRequest = updatedRequest
        reconcileDisplaySurfaces(for: updatedRequest)
    }

    func targetScreens(for request: WallpaperEngine.WebWallpaperLaunchRequest) -> [NSScreen] {
        let availableScreens = NSScreen.screens
        return request.multiDisplayEnabled ? availableScreens : Array(availableScreens.prefix(1))
    }

    func reconcileDisplaySurfaces(for request: WallpaperEngine.WebWallpaperLaunchRequest) {
        let screens = targetScreens(for: request)
        guard !screens.isEmpty else {
            failCurrentLaunch(message: "dedicated_web_host_no_screens")
            return
        }

        let screensByID = Dictionary(
            uniqueKeysWithValues: screens.compactMap { screen in
                Self.screenID(for: screen).map { ($0, screen) }
            }
        )
        guard !screensByID.isEmpty, screensByID.count == screens.count else {
            failCurrentLaunch(message: "dedicated_web_host_no_surface")
            return
        }

        let targetScreenIDs = Set(screensByID.keys)
        for screenID in Set(surfaces.keys).subtracting(targetScreenIDs) {
            removeSurface(for: screenID)
        }

        let entryURL = WebWallpaperHostSupport.makeLocalSchemeEntryURL(
            entryURL: request.entryURL,
            rootURL: request.rootURL
        )
        let newScreenIDs = targetScreenIDs.subtracting(Set(surfaces.keys))
        if !newScreenIDs.isEmpty {
            phase = .launching
        }

        for screen in screens {
            guard let screenID = Self.screenID(for: screen) else { continue }
            if let surface = surfaces[screenID] {
                updateSurface(surface, for: screen, request: request)
            } else {
                guard createAndLoadSurface(
                    for: screen,
                    request: request,
                    localEntryURL: entryURL,
                    loadFailureMessage: "dedicated_web_host_navigation_unavailable"
                ) else {
                    failCurrentLaunch(message: "dedicated_web_host_navigation_unavailable")
                    return
                }
            }
        }

        guard Set(surfaces.keys) == targetScreenIDs else {
            failCurrentLaunch(message: "dedicated_web_host_no_surface")
            return
        }
        installDefaultInteractiveRegionsIfNeeded()
    }

    func updateSurface(
        _ surface: HostSurface,
        for screen: NSScreen,
        request: WallpaperEngine.WebWallpaperLaunchRequest
    ) {
        setTransientMouseCaptureEnabled(false, for: surface)
        surface.schemeHandler.updateAdditionalReadableRoots(accessibleResourceURLs(from: request.propertiesJSON))
        surface.window.setFrame(screen.frame, display: true)
        surface.window.collectionBehavior = Self.webWindowCollectionBehavior
        surface.window.level = Self.webWindowLevel
        surface.window.orderFrontRegardless()
        applyGeneralProperties(to: surface.webView)
    }

    func handle(_ command: WallpaperEngine.WebWallpaperRuntimeCommand) {
        switch command {
        case let .pushAudioSpectrum(levels):
            currentSpectrumLevels = levels
            forEachWebView { self.pushAudioSpectrum(levels, to: $0) }
        default:
            switch command {
            case .pause:
                paused = true
                forEachWebView { self.applyPausedState(true, to: $0) }
            case let .resume(playbackRate):
                paused = false
                currentPlaybackRate = playbackRate
                forEachWebView {
                    self.applyPausedState(false, to: $0)
                    self.applyPlaybackRate(playbackRate, to: $0)
                }
            case let .setVolume(volume):
                currentVolume = volume
                forEachWebView { self.applyVolume(volume, to: $0) }
            case let .setPlaybackRate(playbackRate):
                currentPlaybackRate = playbackRate
                forEachWebView { self.applyPlaybackRate(playbackRate, to: $0) }
            case let .applyProperties(propertiesJSON):
                let effectivePropertiesJSON = mergedWebPropertiesJSON(
                    baseJSON: currentRequest?.propertiesJSON,
                    deltaJSON: propertiesJSON
                )
                if let request = currentRequest {
                    currentRequest = WallpaperEngine.WebWallpaperLaunchRequest(
                        id: request.id,
                        entryURL: request.entryURL,
                        rootURL: request.rootURL,
                        propertiesJSON: effectivePropertiesJSON,
                        source: request.source,
                        recordID: request.recordID,
                        language: request.language,
                        runtimeProfile: request.runtimeProfile,
                        multiDisplayEnabled: request.multiDisplayEnabled,
                        resourceLifetime: request.resourceLifetime
                    )
                }
                refreshReadableResourceRoots(using: effectivePropertiesJSON)
                syncFetchAllDirectoryProperties(using: effectivePropertiesJSON)
                forEachWebView { self.applyProperties(propertiesJSON, to: $0) }
            case .stop:
                let requestID = currentRequest?.id
                teardownHostSurfaces()
                removeLifecycleObservers()
                phase = .idle
                endHostActivity()
                recordDiagnostic(
                    type: "lifecycle.stop",
                    severity: .info,
                    message: "phase=\(phase.rawValue) surfaces=\(surfaces.count) loopbacks=\(loopbackServers.count) observers=\(lifecycleObservers.count)",
                    screenID: nil,
                    url: nil
                )
                currentRequest = nil
                if let requestID {
                    eventHandler?(.stopped(requestID: requestID))
                }
            case .pushAudioSpectrum:
                break
            }
        }
    }

    private func mergedWebPropertiesJSON(baseJSON: String?, deltaJSON: String) -> String {
        guard let deltaData = deltaJSON.data(using: .utf8),
              let delta = try? JSONSerialization.jsonObject(with: deltaData) as? [String: Any] else {
            return baseJSON ?? deltaJSON
        }

        var merged: [String: Any] = [:]
        if let baseJSON,
           let baseData = baseJSON.data(using: .utf8),
           let base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any] {
            merged = base
        }
        for (key, value) in delta {
            merged[key] = value
        }

        guard JSONSerialization.isValidJSONObject(merged),
              let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let mergedJSON = String(data: mergedData, encoding: .utf8) else {
            return baseJSON ?? deltaJSON
        }
        return mergedJSON
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // 注入脚本按 frame 下发且 只由顶层 frame 发出屏幕级信号，但任何 frame 都能
        // 直接向 `window.webkit.messageHandlers.*` 投递：因此 frame 敏感的消息在宿主
        // 侧再判一次 `frameInfo.isMainFrame`（注入 JS 的门是第一层，这是第二层）。
        let isMainFrame = message.frameInfo.isMainFrame
        switch message.name {
        case "wallpaperHostInteractiveRegions":
            guard let webView = self.webView(for: userContentController),
                  let screenID = screenID(for: webView) else {
                return
            }
            guard isMainFrame else {
                recordDiagnostic(
                    type: "interactive-regions.subframe-rejected",
                    severity: .warning,
                    message: "subframe registration ignored sender=\(message.frameInfo.request.url?.absoluteString ?? "unknown")",
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                return
            }
            guard let regions = parseInteractiveRegions(from: message.body) else { return }
            let source = ((message.body as? [String: Any])?["source"] as? String) ?? "page-script"
            updateInteractiveRegions(regions, source: source, screenID: screenID)
        case "wallpaperHostLog":
            guard let webView = self.webView(for: userContentController) else { return }
            let screenID = screenID(for: webView)
            let body = message.body as? [String: Any]
            let type = body?["type"] as? String ?? "js.log"
            let rawMessage = body?["message"] as? String ?? String(describing: message.body)
            // 非主 frame 的日志按其自身文档 URL 标记来源，避免与顶层诊断/评测计数混淆。
            let frameScopedMessage = isMainFrame
                ? rawMessage
                : "[frame:\(message.frameInfo.request.url?.absoluteString ?? "subframe")] \(rawMessage)"
            recordDiagnostic(
                type: type,
                severity: diagnosticSeverity(for: type),
                message: frameScopedMessage,
                screenID: screenID,
                url: webView.url?.absoluteString
            )
            // dom.ready 是屏幕级就绪：只认主 frame 发来的那一条（子 frame 可绕过
            // 注入 JS 的门直接 postMessage）。
            if type == "dom.ready", isMainFrame, let screenID,
               !recoveringWebContentScreenIDs.contains(screenID) {
                installDefaultInteractiveRegionsIfNeeded()
                applyCompatibilityState(to: webView, deferDirectorySync: false)
                startSyntheticInputForwardingIfNeeded()
                markScreenReady(screenID)
            }
        case "wallpaperHostRandomFile":
            guard let body = message.body as? [String: Any],
                  let requestID = body["requestID"] as? String,
                  let propertyName = body["propertyName"] as? String,
                  let webView = self.webView(for: userContentController) else {
                return
            }
            // D5：回包按发送 frame 定向送达，子 frame（含跨源）的请求同样有
            // 回包目标。随机文件仍走既有可读资源根解析（frame 定向只修回包，
            // 不授予任意文件或主 frame 特权）；解析缺失回显空路径（页面侧按
            // 「明确不可用」消费，不悬挂）。
            let resolvedPath = resolveRandomFilePath(forPropertyNamed: propertyName) ?? ""
            let escapedRequestID = WebWallpaperHostSupport.javaScriptQuotedString(requestID)
            let escapedPath = WebWallpaperHostSupport.javaScriptQuotedString(resolvedPath)
            webView.evaluateJavaScript(
                "window.__myWallpaperResolveRandomFile(\(escapedRequestID), \(escapedPath));",
                in: message.frameInfo,
                in: .page
            ) { [weak self] result in
                guard let self, case let .failure(error) = result else { return }
                // 无效 frame 的回包就地取消，不改发主 frame（迟到回包不得到达
                // 替代文档）。
                self.recordDiagnostic(
                    type: "frame.reply.invalid",
                    severity: .info,
                    message: "random-file reply dropped: \(error.localizedDescription)",
                    screenID: self.screenID(for: webView),
                    url: webView.url?.absoluteString
                )
            }
        case "wallpaperHostNetworkRequest":
            guard let body = message.body as? [String: Any],
                  let webView = self.webView(for: userContentController) else {
                return
            }
            // 在飞配额按 frame 分桶：子 frame（含跨源）不得消耗主 frame 的代理配额
            // 而令顶层请求得到 too_many_requests。
            handleNetworkRequestMessage(
                body,
                webView: webView,
                frameKey: networkBridgeFrameKey(for: message.frameInfo),
                frameInfo: message.frameInfo
            )
        case "wallpaperHostFrameEndpoint":
            // D5：每个注入文档的 hello 登记。校验真实 webView（按
            // userContentController 反查）与文档 nonce；frame 身份由 WebKit 的
            // frameInfo 提供，页面自称的任何 ID 都不参与路由。
            guard let body = message.body as? [String: Any],
                  let nonce = body["nonce"] as? String,
                  nonce.isEmpty == false,
                  let webView = self.webView(for: userContentController) else {
                return
            }
            handleFrameEndpointHello(nonce: nonce, frameInfo: message.frameInfo, webView: webView)
        default:
            return
        }
    }

    /// D5 hello 登记 + ack + 全量快照重放。ack/frame 快照都按发送 frame 定向
    /// evaluateJavaScript（.page world，与注入面同 world）；主 frame 的初始
    /// 快照仍走 dom.ready / didFinish 的 applyCompatibilityState（避免同帧重复
    /// 推送），子 frame 在 ack 时即刻拿到最新快照。
    func handleFrameEndpointHello(nonce: String, frameInfo: WKFrameInfo, webView: WKWebView) {
        guard let endpoint = frameEndpointRegistry.register(
            documentNonce: nonce,
            frameInfo: frameInfo,
            in: webView
        ) else {
            recordDiagnostic(
                type: "frame.endpoint.capacity",
                severity: .warning,
                message: "frame endpoint registration refused (capacity)",
                screenID: screenID(for: webView),
                url: webView.url?.absoluteString
            )
            return
        }
        ensureFrameEndpointLeaseRenewalTimer()
        let tokenLiteral = WebWallpaperHostSupport.javaScriptQuotedString(endpoint.token)
        webView.evaluateJavaScript(
            """
            (() => {
              window.__myWallpaperHostFrameEndpointToken = \(tokenLiteral);
              window.__myWallpaperHostFrameEndpointAck = true;
            })();
            """,
            in: frameInfo,
            in: .page
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case .failure = result {
                    // ack 都到不了的 frame 不会产生有效 endpoint。
                    self.frameEndpointRegistry.revoke(token: endpoint.token, in: webView)
                }
            }
        }
        guard frameInfo.isMainFrame == false else { return }
        applyCompatibilitySnapshot(to: endpoint, webView: webView)
    }

    func runtimeEntryURL(
        for request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL,
        surface: HostSurface,
        completion: @escaping (URL) -> Void
    ) {
        guard request.runtimeProfile.originMode == .httpLoopback else {
            completion(localEntryURL)
            return
        }
        let server: WebWallpaperLoopbackServer
        if let existing = loopbackServers[surface.screenID] {
            server = existing
        } else {
            server = WebWallpaperLoopbackServer(schemeHandler: surface.schemeHandler)
            server.diagnosticHandler = { [weak self] type, severity, message, url in
                Task { @MainActor in
                    self?.recordDiagnostic(type: type, severity: severity, message: message, screenID: surface.screenID, url: url?.absoluteString)
                }
            }
            loopbackServers[surface.screenID] = server
        }
        server.start { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(baseURL):
                let path = localEntryURL.path
                let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                self.recordDiagnostic(type: "runtime.origin", severity: .info, message: "httpLoopback \(url.absoluteString)", screenID: surface.screenID, url: url.absoluteString)
                completion(url)
            case let .failure(error):
                // 保持旧语义：端口就绪超时/失败回退 localEntryURL，不判启动失败。
                self.recordDiagnostic(type: "runtime.origin.error", severity: .error, message: error.localizedDescription, screenID: surface.screenID, url: localEntryURL.absoluteString)
                completion(localEntryURL)
            }
        }
    }

    func recordDiagnostic(
        type: String,
        severity: WebRuntimeDiagnosticEvent.Severity,
        message: String,
        screenID: CGDirectDisplayID?,
        url: String?
    ) {
        let adjustedSeverity = adjustedDiagnosticSeverity(type: type, severity: severity, message: message)
        WebRuntimeDiagnosticsStore.shared.record(
            type: type,
            severity: adjustedSeverity,
            message: message,
            recordID: currentRequest?.recordID,
            screenID: screenID,
            url: url
        )
    }

    func markScreenReady(_ screenID: CGDirectDisplayID) {
        let inserted = readyScreenIDs.insert(screenID).inserted
        guard inserted,
              readyScreenIDs.count == surfaces.count,
              phase != .ready else {
            return
        }
        recordDiagnostic(type: "host.ready", severity: .info, message: "ready", screenID: screenID, url: nil)
        phase = .ready
        if let requestID = currentRequest?.id {
            eventHandler?(.ready(requestID: requestID))
        }
        scheduleDebugEvidenceIfNeeded()
        scheduleWebNavigationProbeIfNeeded()
    }

    func diagnosticSeverity(for type: String) -> WebRuntimeDiagnosticEvent.Severity {
        let lowered = type.lowercased()
        if lowered.contains("error") || lowered.contains("rejection") {
            return .error
        }
        if ["warn", "stalled", "waiting", "degraded", "failed"].contains(where: lowered.contains) {
            return .warning
        }
        return .info
    }

    func adjustedDiagnosticSeverity(
        type: String,
        severity: WebRuntimeDiagnosticEvent.Severity,
        message: String
    ) -> WebRuntimeDiagnosticEvent.Severity {
        guard severity == .error else { return severity }

        let loweredType = type.lowercased()
        let loweredMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if loweredType == "resource.error",
           loweredMessage.hasPrefix("audio ") {
            if isOptionalLocalAudioDiagnosticMessage(loweredMessage) {
                return .info
            }
            return .warning
        }
        if loweredType == "media.error",
           loweredMessage.contains("tag=audio") {
            if isOptionalLocalAudioDiagnosticMessage(loweredMessage) {
                return .info
            }
            return .warning
        }
        return severity
    }

    private func isOptionalLocalAudioDiagnosticMessage(_ loweredMessage: String) -> Bool {
        let isLocalSource = loweredMessage.contains("mwx-local://wallpaper/") ||
            loweredMessage.contains("http://127.0.0.1:") ||
            loweredMessage.contains("http://localhost:")
        guard isLocalSource else { return false }
        if loweredMessage.contains("/null") {
            return true
        }
        let hasAudioExtension = loweredMessage.contains(".ogg") ||
            loweredMessage.contains(".mp3") ||
            loweredMessage.contains(".wav") ||
            loweredMessage.contains(".m4a") ||
            loweredMessage.contains(".aac") ||
            loweredMessage.contains(".flac")
        guard hasAudioExtension else { return false }
        if loweredMessage.contains("/sound/") || loweredMessage.contains("/sounds/") {
            return true
        }
        return loweredMessage.contains("/audio/0-") ||
            loweredMessage.contains("/audio/00-")
    }

}
