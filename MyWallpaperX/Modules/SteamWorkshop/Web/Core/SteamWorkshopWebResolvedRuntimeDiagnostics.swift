import Foundation

extension SteamWorkshopService {
    nonisolated func resolvedWebHostCapabilitySnapshot() -> ResolvedWebHostCapabilitySnapshot {
        ResolvedWebHostCapabilitySnapshot(
            userPropertiesLevel: .basic,
            generalProperties: .init(
                applyListenerLevel: .basic,
                fpsLevel: .basic
            ),
            directoryNotificationsLevel: .placeholder,
            audioListenerLevel: .basic,
            audioStreamLevel: .basic,
            media: .init(
                statusLevel: .basic,
                propertiesLevel: .basic,
                thumbnailLevel: .basic,
                timelineLevel: .basic,
                playbackLevel: .basic
            ),
            pluginBridgeLevel: .placeholder,
            rgbBridgeLevel: .placeholder,
            pauseBridgeLevel: .basic,
            volumeBridgeLevel: .basic
        )
    }

    func resolvedWebStaticContentSummary(
        for record: SteamWorkshopDownloadRecord,
        entryURL: URL,
        rootURL: URL
    ) -> ResolvedWebStaticContentSummary {
        resolvedWebStaticContentSummary(
            for: record,
            entryURL: entryURL,
            rootURL: rootURL,
            propertyDefinitions: webPropertyDefinitions(for: record)
        )
    }

    /// 解析核：definitions 由调用方解析后传入（后台段不回读记录存储），
    /// BFS 文件扫描可在任意线程执行。
    nonisolated func resolvedWebStaticContentSummary(
        for record: SteamWorkshopDownloadRecord,
        entryURL: URL,
        rootURL: URL,
        propertyDefinitions: [SteamWorkshopWebPropertyDefinition],
        read: ((URL) -> WebAuthorFileReader.Observation?)? = nil,
        exists: ((URL) -> Bool)? = nil,
        observeReference: ((String, URL, URL?) -> Void)? = nil
    ) -> ResolvedWebStaticContentSummary {
        var scannedFiles = Set<URL>()
        var pendingFiles: ArraySlice<URL> = [entryURL]
        var externalDependencyURLs = Set<String>()
        var usesWebMResource = false
        var usesHoverOnlyInteraction = false
        var usesPluginBridge = false
        var usesPersistentBrowserStorage = false
        var usesServiceWorkerRegistration = false
        var usesESModuleDependency = false
        var usesDynamicImport = false
        var usesWASMResource = false
        var usesWASMStreaming = false
        var usesCustomSchemeSensitiveWebGL = false
        var usesIframeCrossFrameAccess = false
        var referencesSchemeColorUserProperty = false
        var hasUncertainUserPropertyUsage = false
        var hasTruncatedStaticAnalysis = false
        let hasFetchAllDirectoryProperty = propertyDefinitions.contains {
            $0.kind == .directory && $0.directoryMode?.lowercased() == "fetchall"
        }
        let hasOnDemandDirectoryProperty = propertyDefinitions.contains {
            $0.kind == .directory && $0.directoryMode?.lowercased() == "ondemand"
        }

        while let fileURL = pendingFiles.popFirst() {
            guard scannedFiles.insert(fileURL).inserted else { continue }
            guard !Task.isCancelled else { break }
            let observation: WebAuthorFileReader.Observation?
            if let read { observation = read(fileURL) }
            else { observation = Self.webStaticAnalysisContent(from: fileURL).map {
                WebAuthorFileReader.Observation(content: $0.content, isTruncated: $0.isTruncated,
                    containsServiceWorker: $0.isTruncated && Self.webFileContainsServiceWorkerRegistration(fileURL))
            } }
            guard let scan = observation else {
                hasUncertainUserPropertyUsage = true
                continue
            }
            let content = scan.content
            if scan.isTruncated {
                hasTruncatedStaticAnalysis = true
                hasUncertainUserPropertyUsage = true
            }

            if Self.webContentUsesWebMResource(content) {
                usesWebMResource = true
            }
            if fileURL.pathExtension.localizedLowercase == "css",
               Self.webContentUsesHoverOnlyInteraction(content) {
                usesHoverOnlyInteraction = true
            }
            if Self.webContentUsesPluginBridge(content) {
                usesPluginBridge = true
            }
            if Self.webContentUsesPersistentBrowserStorage(content) {
                usesPersistentBrowserStorage = true
            }
            if !usesServiceWorkerRegistration,
               Self.webContentUsesServiceWorkerRegistration(content)
                || (scan.isTruncated && scan.containsServiceWorker) {
                usesServiceWorkerRegistration = true
            }
            if Self.webContentUsesESModuleDependency(content) {
                usesESModuleDependency = true
            }
            if Self.webContentUsesDynamicImport(content) {
                usesDynamicImport = true
            }
            if Self.webContentUsesWASMResource(content) {
                usesWASMResource = true
            }
            if Self.webContentUsesWASMStreaming(content) {
                usesWASMStreaming = true
            }
            if Self.webContentUsesCustomSchemeSensitiveWebGL(content) {
                usesCustomSchemeSensitiveWebGL = true
            }
            if Self.webContentUsesIframeCrossFrameAccess(content) {
                usesIframeCrossFrameAccess = true
            }
            if Self.webContentReferencesSchemeColorUserProperty(content) {
                referencesSchemeColorUserProperty = true
            }
            if Self.webContentHasUncertainUserPropertyUsage(content) {
                hasUncertainUserPropertyUsage = true
            }

            for reference in Self.extractLocalWebResourceReferences(from: content, fileExtension: fileURL.pathExtension) {
                switch reference {
                case let .local(path):
                    let resolved = Self.resolveWebResourceURL(path, relativeTo: fileURL, rootURL: rootURL)
                    let dependencyName = path.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? path
                    if Self.shouldScanWebDependencyFile(named: dependencyName) { observeReference?(path, fileURL, resolved) }
                    guard let resolvedURL = resolved else {
                        let normalizedPath = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
                        if Self.shouldScanWebDependencyFile(named: normalizedPath) {
                            hasUncertainUserPropertyUsage = true
                        }
                        continue
                    }
                    let ext = resolvedURL.pathExtension.localizedLowercase
                    if ext == "webm" {
                        usesWebMResource = true
                    }
                    if ext == "wasm" {
                        usesWASMResource = true
                    }
                    if ["html", "htm", "css", "js", "json"].contains(ext),
                       Self.shouldScanWebDependencyFile(named: resolvedURL.lastPathComponent) {
                        if exists?(resolvedURL) ?? FileManager.default.fileExists(atPath: resolvedURL.path) {
                            pendingFiles.append(resolvedURL)
                        } else {
                            hasUncertainUserPropertyUsage = true
                        }
                    }
                case let .external(urlString):
                    externalDependencyURLs.insert(urlString)
                }
            }
        }

        let parsedURLs = externalDependencyURLs.compactMap { URL(string: $0) }
        let hosts = Set(parsedURLs.compactMap { $0.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let localhostHosts = hosts.filter { $0 == "localhost" || $0 == "127.0.0.1" || $0 == "::1" }
        let remoteScriptHosts = Set(
            parsedURLs.compactMap { url -> String? in
                guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                    return nil
                }
                let path = url.path.lowercased()
                if path.hasSuffix(".js") || path.hasSuffix(".mjs") {
                    return host
                }
                return nil
            }
        )
        if usesDynamicImport || remoteScriptHosts.isEmpty == false {
            hasUncertainUserPropertyUsage = true
        }

        return ResolvedWebStaticContentSummary(
            usesPluginBridge: usesPluginBridge,
            usesPersistentBrowserStorage: usesPersistentBrowserStorage,
            usesServiceWorkerRegistration: usesServiceWorkerRegistration,
            usesESModuleDependency: usesESModuleDependency,
            usesDynamicImport: usesDynamicImport,
            usesWASMResource: usesWASMResource,
            usesWASMStreaming: usesWASMStreaming,
            usesCustomSchemeSensitiveWebGL: usesCustomSchemeSensitiveWebGL,
            usesIframeCrossFrameAccess: usesIframeCrossFrameAccess,
            usesWebMResource: usesWebMResource,
            usesHoverOnlyInteraction: usesHoverOnlyInteraction,
            referencesSchemeColorUserProperty: referencesSchemeColorUserProperty,
            hasUncertainUserPropertyUsage: hasUncertainUserPropertyUsage,
            hasTruncatedStaticAnalysis: hasTruncatedStaticAnalysis,
            hasFetchAllDirectoryProperty: hasFetchAllDirectoryProperty,
            hasOnDemandDirectoryProperty: hasOnDemandDirectoryProperty,
            externalDependencyHosts: hosts.sorted(),
            localhostDependencyHosts: localhostHosts.sorted(),
            remoteScriptDependencyHosts: remoteScriptHosts.sorted()
        )
    }
}
