import Foundation

struct SteamWorkshopWebAnalysisCacheManifest: Codable, Equatable {
    static let currentVersion = 15

    let version: Int
    let recordID: String
    let generatedAt: Date
    // 属性标题、选项 label 与 precondition 文案都在解析期按系统语言烘焙，
    // 语言变化必须让分析缓存整体失效。
    let language: String
    let projectModifiedAt: Date?
    let propertySourceRecordID: String?
    let propertySourceProjectModifiedAt: Date?
    let resolvedEntryModifiedAt: Date?
    let resourceSignature: SteamWorkshopWebRuntimeResourceSignature?
    let analysis: CachedResolvedWebProjectDescriptor
}

struct SteamWorkshopWebRuntimeCacheManifest: Codable, Equatable {
    static let currentVersion = 18

    let version: Int
    let recordID: String
    let generatedAt: Date
    // 运行缓存里的属性 payload 同样按解析期语言烘焙。
    let language: String
    let projectModifiedAt: Date?
    let propertySourceRecordID: String?
    let propertySourceProjectModifiedAt: Date?
    let resolvedEntryModifiedAt: Date?
    let resourceSignature: SteamWorkshopWebRuntimeResourceSignature?
    let overridesSignature: Data?
    let execution: CachedResolvedWebExecutionManifest
}

struct SteamWorkshopWebRuntimeResourceSignature: Codable, Equatable {
    let scannedFileCount: Int
    let truncated: Bool
    let entries: [Entry]

    struct Entry: Codable, Equatable {
        let relativePath: String
        let modifiedAt: Date?
        let size: Int64?
    }
}

struct CachedResolvedWebExecutionManifest: Codable, Equatable {
    let resolvedEntryPath: String
    let effectiveRootPath: String
    let propertyPayloadJSON: String?
}

struct CachedResolvedWebProjectDescriptor: Codable, Equatable {
    let sourceKind: ResolvedWebProjectDescriptor.SourceKind
    let declaredEntryRelativePath: String?
    let resolvedEntryRelativePath: String
    let resolvedEntryPath: String
    let effectiveRootPath: String
    let entrySource: ResolvedWebProjectDescriptor.EntrySource
    let sampleStructure: SteamWorkshopWebSampleStructure
    let propertySource: SteamWorkshopWebPropertySource
    let propertyDefinitions: [SteamWorkshopWebPropertyDefinition]
    let defaultValueMap: [String: SteamWorkshopWebPropertyValue]
    let presetOverrideMap: [String: SteamWorkshopWebPropertyValue]
    let presetResourceBindingsByKey: [String: ResolvedWebResourceBinding]
    let baselineVisiblePropertyKeys: [String]
    let baselineVisibleOptionsByKey: [String: [SteamWorkshopWebPropertyOption]]
    let baselinePreconditionStates: [ResolvedWebRuntimePrecondition]
    let resolvedLocalizationMap: [String: String]
    let hostCapabilitySnapshot: ResolvedWebHostCapabilitySnapshot
    let staticContentSummary: ResolvedWebStaticContentSummary
    let runtimeRiskFlags: [ResolvedWebRuntimeRiskFlag]
}

extension SteamWorkshopService {
    nonisolated static func webRuntimeCacheDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
            .appendingPathComponent("WebRuntime", isDirectory: true)
    }

    nonisolated static func webRuntimeCacheFileStem(for recordID: String) -> String {
        Data(recordID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func webAnalysisCacheFileURL(for record: SteamWorkshopDownloadRecord) -> URL {
        Self.webRuntimeCacheDirectoryURL()
            .appendingPathComponent("\(Self.webRuntimeCacheFileStem(for: record.id))-analysis.json")
    }

    func webRuntimeCacheFileURL(for record: SteamWorkshopDownloadRecord) -> URL {
        Self.webRuntimeCacheDirectoryURL()
            .appendingPathComponent("\(Self.webRuntimeCacheFileStem(for: record.id))-runtime.json")
    }

    func preloadWebRuntimeCaches(for records: [SteamWorkshopDownloadRecord]) {
        let webRecords = records.filter { $0.contentType == .web }
        guard !webRecords.isEmpty else { return }
        webRuntimePreloadTask?.cancel()
        webRuntimePreloadTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            for record in webRecords {
                guard !Task.isCancelled else { break }
                let requiresLiveResolution = self.webRuntimeRequiresLiveResourceResolution(for: record)
                guard !requiresLiveResolution else { continue }
                if self.loadCachedWebPlaybackContext(
                    for: record,
                    liveResourceResolutionRequired: requiresLiveResolution
                ) == nil {
                    _ = self.resolvedWebPlaybackContext(for: record)
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
            self.webRuntimePreloadTask = nil
        }
    }

    func loadCachedWebPlaybackContext(
        for record: SteamWorkshopDownloadRecord,
        liveResourceResolutionRequired: Bool? = nil
    ) -> ResolvedWebPlaybackContext? {
        let requiresLiveResolution = liveResourceResolutionRequired
            ?? webRuntimeRequiresLiveResourceResolution(for: record)
        guard !requiresLiveResolution else {
            NSLog("MWX WEB RUNTIME CACHE: live resource resolution record=%@", record.id)
            return nil
        }
        let fileURL = webRuntimeCacheFileURL(for: record)
        guard let data = try? Data(contentsOf: fileURL),
              let manifest = try? JSONDecoder().decode(SteamWorkshopWebRuntimeCacheManifest.self, from: data),
              manifest.version == SteamWorkshopWebRuntimeCacheManifest.currentVersion,
              manifest.recordID == record.id,
              isWebRuntimeCacheManifestValid(manifest, for: record) else {
            return nil
        }

        let resolvedEntryURL = URL(fileURLWithPath: manifest.execution.resolvedEntryPath).resolvingSymlinksInPath().standardizedFileURL
        let effectiveRootURL = URL(fileURLWithPath: manifest.execution.effectiveRootPath).resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolvedEntryURL.path),
              FileManager.default.fileExists(atPath: effectiveRootURL.path) else {
            return nil
        }

        return ResolvedWebPlaybackContext(
            recordID: record.id,
            effectiveEntryURL: resolvedEntryURL,
            effectiveRootURL: effectiveRootURL,
            propertyPayloadJSON: manifest.execution.propertyPayloadJSON,
            language: Self.resolvedWebWallpaperLanguage()
        )
    }

    func loadCachedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> ResolvedWebProjectDescriptor? {
        let fileURL = webAnalysisCacheFileURL(for: record)
        guard let data = try? Data(contentsOf: fileURL),
              let manifest = try? JSONDecoder().decode(SteamWorkshopWebAnalysisCacheManifest.self, from: data),
              manifest.version == SteamWorkshopWebAnalysisCacheManifest.currentVersion,
              manifest.recordID == record.id,
              isWebAnalysisCacheManifestValid(manifest, for: record) else {
            return nil
        }

        let cached = manifest.analysis
        let resolvedEntryURL = URL(fileURLWithPath: cached.resolvedEntryPath).resolvingSymlinksInPath().standardizedFileURL
        let effectiveRootURL = URL(fileURLWithPath: cached.effectiveRootPath).resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolvedEntryURL.path),
              FileManager.default.fileExists(atPath: effectiveRootURL.path) else {
            return nil
        }

        return ResolvedWebProjectDescriptor(
            recordID: record.id,
            sourceKind: cached.sourceKind,
            declaredEntryRelativePath: cached.declaredEntryRelativePath,
            resolvedEntryRelativePath: cached.resolvedEntryRelativePath,
            resolvedEntryURL: resolvedEntryURL,
            effectiveRootURL: effectiveRootURL,
            entrySource: cached.entrySource,
            sampleStructure: cached.sampleStructure,
            propertySource: cached.propertySource,
            propertyDefinitions: cached.propertyDefinitions,
            defaultValueMap: cached.defaultValueMap,
            presetOverrideMap: cached.presetOverrideMap,
            presetResourceBindingsByKey: cached.presetResourceBindingsByKey,
            baselineVisiblePropertyKeys: cached.baselineVisiblePropertyKeys,
            baselineVisibleOptionsByKey: cached.baselineVisibleOptionsByKey,
            baselinePreconditionStates: cached.baselinePreconditionStates,
            resolvedLocalizationMap: cached.resolvedLocalizationMap,
            hostCapabilitySnapshot: cached.hostCapabilitySnapshot,
            staticContentSummary: cached.staticContentSummary,
            runtimeRiskFlags: cached.runtimeRiskFlags
        )
    }

    func saveWebAnalysisCache(
        descriptor: ResolvedWebProjectDescriptor,
        for record: SteamWorkshopDownloadRecord,
        resourceSignature: SteamWorkshopWebRuntimeResourceSignature? = nil
    ) {
        let manifest = SteamWorkshopWebAnalysisCacheManifest(
            version: SteamWorkshopWebAnalysisCacheManifest.currentVersion,
            recordID: record.id,
            generatedAt: Date(),
            language: Self.resolvedWebWallpaperLanguage(),
            projectModifiedAt: webRuntimeCacheProjectModifiedAt(for: record),
            propertySourceRecordID: webPropertyDefinitionSourceRecord(for: record)?.id,
            propertySourceProjectModifiedAt: webRuntimeCachePropertySourceProjectModifiedAt(for: record),
            resolvedEntryModifiedAt: webRuntimeCacheResolvedEntryModifiedAt(for: record),
            resourceSignature: resourceSignature ?? webRuntimeResourceSignature(for: record),
            analysis: CachedResolvedWebProjectDescriptor(
                sourceKind: descriptor.sourceKind,
                declaredEntryRelativePath: descriptor.declaredEntryRelativePath,
                resolvedEntryRelativePath: descriptor.resolvedEntryRelativePath,
                resolvedEntryPath: descriptor.resolvedEntryURL.path,
                effectiveRootPath: descriptor.effectiveRootURL.path,
                entrySource: descriptor.entrySource,
                sampleStructure: descriptor.sampleStructure,
                propertySource: descriptor.propertySource,
                propertyDefinitions: descriptor.propertyDefinitions,
                defaultValueMap: descriptor.defaultValueMap,
                presetOverrideMap: descriptor.presetOverrideMap,
                presetResourceBindingsByKey: descriptor.presetResourceBindingsByKey,
                baselineVisiblePropertyKeys: descriptor.baselineVisiblePropertyKeys,
                baselineVisibleOptionsByKey: descriptor.baselineVisibleOptionsByKey,
                baselinePreconditionStates: descriptor.baselinePreconditionStates,
                resolvedLocalizationMap: descriptor.resolvedLocalizationMap,
                hostCapabilitySnapshot: descriptor.hostCapabilitySnapshot,
                staticContentSummary: descriptor.staticContentSummary,
                runtimeRiskFlags: descriptor.runtimeRiskFlags
            )
        )

        guard let data = try? JSONEncoder().encode(manifest) else { return }
        let fileURL = webAnalysisCacheFileURL(for: record)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    func saveWebRuntimeCache(
        descriptor: ResolvedWebProjectDescriptor,
        propertyPayloadJSON: String?,
        for record: SteamWorkshopDownloadRecord
    ) {
        let fileURL = webRuntimeCacheFileURL(for: record)
        guard !webRuntimeRequiresLiveResourceResolution(for: record) else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let resourceSignature = webRuntimeResourceSignature(for: record)
        saveWebAnalysisCache(
            descriptor: descriptor,
            for: record,
            resourceSignature: resourceSignature
        )

        let manifest = SteamWorkshopWebRuntimeCacheManifest(
            version: SteamWorkshopWebRuntimeCacheManifest.currentVersion,
            recordID: record.id,
            generatedAt: Date(),
            language: Self.resolvedWebWallpaperLanguage(),
            projectModifiedAt: webRuntimeCacheProjectModifiedAt(for: record),
            propertySourceRecordID: webPropertyDefinitionSourceRecord(for: record)?.id,
            propertySourceProjectModifiedAt: webRuntimeCachePropertySourceProjectModifiedAt(for: record),
            resolvedEntryModifiedAt: webRuntimeCacheResolvedEntryModifiedAt(for: record),
            resourceSignature: resourceSignature,
            overridesSignature: webRuntimeCacheOverridesSignature(for: record),
            execution: CachedResolvedWebExecutionManifest(
                resolvedEntryPath: descriptor.resolvedEntryURL.path,
                effectiveRootPath: descriptor.effectiveRootURL.path,
                propertyPayloadJSON: propertyPayloadJSON
            )
        )

        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    func webRuntimeResourceSignature(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopWebRuntimeResourceSignature? {
        guard let entryURL = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL else {
            return nil
        }
        let rootURL = effectiveWebRootURL(for: record, entryURL: entryURL)
        let maxScannedFiles = 120
        let deadline = Date().addingTimeInterval(0.20)
        var scannedFiles = Set<URL>()
        var pendingFiles = [entryURL]
        var entries: [SteamWorkshopWebRuntimeResourceSignature.Entry] = []
        var truncated = false

        while let fileURL = pendingFiles.first {
            if scannedFiles.count >= maxScannedFiles || Date() >= deadline {
                truncated = true
                break
            }
            pendingFiles.removeFirst()
            let normalizedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
            guard scannedFiles.insert(normalizedURL).inserted else { continue }

            let resourceValues = try? normalizedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            entries.append(
                SteamWorkshopWebRuntimeResourceSignature.Entry(
                    relativePath: webRelativePath(for: normalizedURL, under: rootURL),
                    modifiedAt: resourceValues?.contentModificationDate,
                    size: resourceValues?.fileSize.map(Int64.init)
                )
            )

            guard Self.shouldScanWebDependencyFile(named: normalizedURL.lastPathComponent),
                  let content = try? String(contentsOf: normalizedURL, encoding: .utf8) else {
                continue
            }
            for reference in Self.extractLocalWebResourceReferences(from: content, fileExtension: normalizedURL.pathExtension) {
                guard case let .local(path) = reference,
                      let resolvedURL = Self.resolveWebResourceURL(path, relativeTo: normalizedURL, rootURL: rootURL),
                      FileManager.default.fileExists(atPath: resolvedURL.path),
                      Self.shouldScanWebDependencyFile(named: resolvedURL.lastPathComponent) else {
                    continue
                }
                pendingFiles.append(resolvedURL)
            }
        }

        return SteamWorkshopWebRuntimeResourceSignature(
            scannedFileCount: scannedFiles.count,
            truncated: truncated,
            entries: entries.sorted { $0.relativePath < $1.relativePath }
        )
    }

}
