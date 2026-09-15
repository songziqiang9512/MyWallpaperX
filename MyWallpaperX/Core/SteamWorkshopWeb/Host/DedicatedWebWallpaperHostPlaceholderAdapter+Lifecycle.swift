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
            guard reloadTrackedSurfaces(for: request, localEntryURL: entryURL) else {
                failCurrentLaunch(message: "dedicated_web_host_navigation_unavailable")
                return
            }
            return
        }

        let createdAllSurfaces = targetScreens.allSatisfy { screen in
            createAndLoadSurface(
                for: screen,
                request: request,
                localEntryURL: entryURL
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
                    localEntryURL: entryURL
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
        switch message.name {
        case "wallpaperHostInteractiveRegions":
            guard let webView = self.webView(for: userContentController),
                  let screenID = screenID(for: webView),
                  let regions = parseInteractiveRegions(from: message.body) else {
                return
            }
            let source = ((message.body as? [String: Any])?["source"] as? String) ?? "page-script"
            updateInteractiveRegions(regions, source: source, screenID: screenID)
        case "wallpaperHostLog":
            guard let webView = self.webView(for: userContentController) else { return }
            let screenID = screenID(for: webView)
            let body = message.body as? [String: Any]
            let type = body?["type"] as? String ?? "js.log"
            let rawMessage = body?["message"] as? String ?? String(describing: message.body)
            recordDiagnostic(
                type: type,
                severity: diagnosticSeverity(for: type),
                message: rawMessage,
                screenID: screenID,
                url: webView.url?.absoluteString
            )
            if type == "dom.ready", let screenID,
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
            let resolvedPath = resolveRandomFilePath(forPropertyNamed: propertyName) ?? ""
            let escapedRequestID = WebWallpaperHostSupport.javaScriptQuotedString(requestID)
            let escapedPath = WebWallpaperHostSupport.javaScriptQuotedString(resolvedPath)
            webView.evaluateJavaScript(
                "window.__myWallpaperResolveRandomFile(\(escapedRequestID), \(escapedPath));",
                completionHandler: nil
            )
        case "wallpaperHostNetworkRequest":
            guard let body = message.body as? [String: Any],
                  let webView = self.webView(for: userContentController) else {
                return
            }
            handleNetworkRequestMessage(body, webView: webView)
        default:
            return
        }
    }

    func runtimeEntryURL(
        for request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL,
        surface: HostSurface
    ) -> URL {
        guard request.runtimeProfile.originMode == .httpLoopback else {
            return localEntryURL
        }
        do {
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
            let baseURL = try server.start()
            let path = localEntryURL.path
            let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            recordDiagnostic(type: "runtime.origin", severity: .info, message: "httpLoopback \(url.absoluteString)", screenID: surface.screenID, url: url.absoluteString)
            return url
        } catch {
            recordDiagnostic(type: "runtime.origin.error", severity: .error, message: error.localizedDescription, screenID: surface.screenID, url: localEntryURL.absoluteString)
            return localEntryURL
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
