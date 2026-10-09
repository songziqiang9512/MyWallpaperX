import Foundation

// 纯数据值类型：清单在后台线程解码/编码（detached 段），不随服务类的
// default-MainActor 隔离。
nonisolated struct SteamWorkshopWebAnalysisCacheManifest: Codable, Equatable {
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

nonisolated struct SteamWorkshopWebRuntimeCacheManifest: Codable, Equatable {
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

nonisolated struct SteamWorkshopWebRuntimeResourceSignature: Codable, Equatable {
    let scannedFileCount: Int
    let truncated: Bool
    let entries: [Entry]

    nonisolated struct Entry: Codable, Equatable {
        let relativePath: String
        let modifiedAt: Date?
        let size: Int64?
    }
}

nonisolated struct CachedResolvedWebExecutionManifest: Codable, Equatable {
    let resolvedEntryPath: String
    let effectiveRootPath: String
    let propertyPayloadJSON: String?
}

nonisolated struct CachedResolvedWebProjectDescriptor: Codable, Equatable {
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
    /// Web 运行时缓存清单字段的输入快照：主线程一次性收集（actor 状态 +
    /// 轻量 stat），签名扫描 / JSON 编码 / 写盘在后台线程消费；后台段不得
    /// 回读任何 actor 状态。
    nonisolated struct WebRuntimeCacheManifestInputs {
        let recordID: String
        let language: String
        let projectModifiedAt: Date?
        let propertySourceRecordID: String?
        let propertySourceProjectModifiedAt: Date?
        let resolvedEntryModifiedAt: Date?
        let overridesSignature: Data?
        let entryURL: URL?
        let rootURL: URL?
        let currentEntryPath: String
        let currentRootPath: String
        let analysisFileURL: URL
        let runtimeFileURL: URL
        /// 会话新鲜快速路径起点（实例初始化时刻），分析校验器消费。
        let sessionStartDate: Date
    }

    /// 主线程入口：收集清单输入快照（缓存校验与保存共用一份字段来源）。
    func webRuntimeCacheManifestInputs(for record: SteamWorkshopDownloadRecord) -> WebRuntimeCacheManifestInputs {
        let entryURL = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL
        let rootURL = entryURL.map { effectiveWebRootURL(for: record, entryURL: $0) }
        return WebRuntimeCacheManifestInputs(
            recordID: record.id,
            language: Self.resolvedWebWallpaperLanguage(),
            projectModifiedAt: webRuntimeCacheProjectModifiedAt(for: record),
            propertySourceRecordID: webPropertyDefinitionSourceRecord(for: record)?.id,
            propertySourceProjectModifiedAt: webRuntimeCachePropertySourceProjectModifiedAt(for: record),
            resolvedEntryModifiedAt: webRuntimeCacheResolvedEntryModifiedAt(for: record),
            overridesSignature: webRuntimeCacheOverridesSignature(for: record),
            entryURL: entryURL,
            rootURL: rootURL,
            currentEntryPath: entryURL?.path ?? "",
            currentRootPath: rootURL?.path ?? "",
            analysisFileURL: webAnalysisCacheFileURL(for: record),
            runtimeFileURL: webRuntimeCacheFileURL(for: record),
            sessionStartDate: webRuntimeCacheSessionStartDate
        )
    }

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
        // 主 actor 只做轻量字段收集与失效判定；签名扫描与写盘在
        // loadCached/resolved 内部的后台段执行，循环间的 await 让主线程
        // 在每条记录的重 IO 期间保持可用。
        webRuntimePreloadGeneration &+= 1
        let preloadGeneration = webRuntimePreloadGeneration
        webRuntimePreloadTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // 被抢占的旧任务只许清自己的句柄：字段已指向新任务时保持原样。
                if self.webRuntimePreloadGeneration == preloadGeneration {
                    self.webRuntimePreloadTask = nil
                }
            }
            for record in webRecords {
                guard !Task.isCancelled else { break }
                let requiresLiveResolution = self.webRuntimeRequiresLiveResourceResolution(for: record)
                guard !requiresLiveResolution else { continue }
                if await self.loadCachedWebPlaybackContext(
                    for: record,
                    liveResourceResolutionRequired: requiresLiveResolution
                ) == nil {
                    _ = await self.resolvedWebPlaybackContext(for: record)
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    /// 缓存命中路径：读盘 / 解码 / 签名扫描 / 字段比对全部在后台段完成，
    /// 主线程只产出输入快照。点击播放的热路径因此不再做任何文件 IO。
    func loadCachedWebPlaybackContext(
        for record: SteamWorkshopDownloadRecord,
        liveResourceResolutionRequired: Bool? = nil
    ) async -> ResolvedWebPlaybackContext? {
        let requiresLiveResolution = liveResourceResolutionRequired
            ?? webRuntimeRequiresLiveResourceResolution(for: record)
        guard !requiresLiveResolution else {
            NSLog("MWX WEB RUNTIME CACHE: live resource resolution record=%@", record.id)
            return nil
        }
        let inputs = webRuntimeCacheManifestInputs(for: record)
        return await Task.detached(priority: .userInitiated) { [weak self] () -> ResolvedWebPlaybackContext? in
            guard let data = try? Data(contentsOf: inputs.runtimeFileURL),
                  let manifest = try? JSONDecoder().decode(SteamWorkshopWebRuntimeCacheManifest.self, from: data),
                  manifest.version == SteamWorkshopWebRuntimeCacheManifest.currentVersion,
                  manifest.recordID == inputs.recordID else {
                return nil
            }
            guard let self else { return nil }
            let liveResourceSignature = Self.liveResourceSignature(inputs: inputs, scanner: self)
            guard Self.isRuntimeManifestValid(manifest, inputs: inputs, liveResourceSignature: liveResourceSignature) else {
                return nil
            }
            let resolvedEntryURL = URL(fileURLWithPath: manifest.execution.resolvedEntryPath).resolvingSymlinksInPath().standardizedFileURL
            let effectiveRootURL = URL(fileURLWithPath: manifest.execution.effectiveRootPath).resolvingSymlinksInPath().standardizedFileURL
            guard FileManager.default.fileExists(atPath: resolvedEntryURL.path),
                  FileManager.default.fileExists(atPath: effectiveRootURL.path) else {
                return nil
            }
            return ResolvedWebPlaybackContext(
                recordID: inputs.recordID,
                effectiveEntryURL: resolvedEntryURL,
                effectiveRootURL: effectiveRootURL,
                propertyPayloadJSON: manifest.execution.propertyPayloadJSON,
                language: inputs.language
            )
        }.value
    }

    /// 启动冷路径的分析缓存装载：读盘/解码/校验（含会话新鲜快速路径）
    /// 全部在调用线程执行，scanner 仅用于 nonisolated 签名扫描。
    nonisolated static func loadCachedAnalysisDescriptor(
        inputs: WebRuntimeCacheManifestInputs,
        scanner: SteamWorkshopService?
    ) -> ResolvedWebProjectDescriptor? {
        guard let data = try? Data(contentsOf: inputs.analysisFileURL),
              let manifest = try? JSONDecoder().decode(SteamWorkshopWebAnalysisCacheManifest.self, from: data),
              manifest.version == SteamWorkshopWebAnalysisCacheManifest.currentVersion,
              manifest.recordID == inputs.recordID else {
            return nil
        }
        // 廉价键先行短路（HEAD 同序）：已失效清单不做签名扫描——同步装载
        // 在主线程执行时不在廉价键失配上白付一次 ≤120 文件 BFS。
        guard Self.analysisManifestCheapFieldsMatch(manifest, inputs: inputs) else {
            return nil
        }
        let liveResourceSignature: SteamWorkshopWebRuntimeResourceSignature?
        if manifest.generatedAt >= inputs.sessionStartDate {
            liveResourceSignature = manifest.resourceSignature
        } else if let scanner, let entryURL = inputs.entryURL, let rootURL = inputs.rootURL {
            liveResourceSignature = scanner.webRuntimeResourceSignature(entryURL: entryURL, rootURL: rootURL)
        } else {
            liveResourceSignature = nil
        }
        guard manifest.resourceSignature == liveResourceSignature else {
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
            recordID: inputs.recordID,
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

    /// 同步表面（属性面板等）的分析缓存装载：与启动冷路径共用同一
    /// nonisolated 装载器（读盘/校验/重建单一实现），只是执行线程不同。
    func loadCachedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> ResolvedWebProjectDescriptor? {
        Self.loadCachedAnalysisDescriptor(
            inputs: webRuntimeCacheManifestInputs(for: record),
            scanner: self
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
            analysis: Self.cachedAnalysis(from: descriptor)
        )
        Self.writeManifest(manifest, to: webAnalysisCacheFileURL(for: record))
    }

    /// 冷路径保存：主线程只收集清单字段与纯映射，扫描 / 编码 / 双清单
    /// 原子写盘在后台段完成后返回（保持与同步版相同的完成时序语义）。
    func saveWebRuntimeCache(
        descriptor: ResolvedWebProjectDescriptor,
        propertyPayloadJSON: String?,
        for record: SteamWorkshopDownloadRecord
    ) async {
        let inputs = webRuntimeCacheManifestInputs(for: record)
        guard !webRuntimeRequiresLiveResourceResolution(for: record) else {
            try? FileManager.default.removeItem(at: inputs.runtimeFileURL)
            return
        }
        let cachedAnalysis = Self.cachedAnalysis(from: descriptor)
        let execution = CachedResolvedWebExecutionManifest(
            resolvedEntryPath: descriptor.resolvedEntryURL.path,
            effectiveRootPath: descriptor.effectiveRootURL.path,
            propertyPayloadJSON: propertyPayloadJSON
        )
        await Task.detached(priority: .utility) { [weak self] () -> Void in
            guard let self else { return }
            let resourceSignature = Self.liveResourceSignature(inputs: inputs, scanner: self)
            Self.writeManifest(
                SteamWorkshopWebAnalysisCacheManifest(
                    version: SteamWorkshopWebAnalysisCacheManifest.currentVersion,
                    recordID: inputs.recordID,
                    generatedAt: Date(),
                    language: inputs.language,
                    projectModifiedAt: inputs.projectModifiedAt,
                    propertySourceRecordID: inputs.propertySourceRecordID,
                    propertySourceProjectModifiedAt: inputs.propertySourceProjectModifiedAt,
                    resolvedEntryModifiedAt: inputs.resolvedEntryModifiedAt,
                    resourceSignature: resourceSignature,
                    analysis: cachedAnalysis
                ),
                to: inputs.analysisFileURL
            )
            Self.writeManifest(
                SteamWorkshopWebRuntimeCacheManifest(
                    version: SteamWorkshopWebRuntimeCacheManifest.currentVersion,
                    recordID: inputs.recordID,
                    generatedAt: Date(),
                    language: inputs.language,
                    projectModifiedAt: inputs.projectModifiedAt,
                    propertySourceRecordID: inputs.propertySourceRecordID,
                    propertySourceProjectModifiedAt: inputs.propertySourceProjectModifiedAt,
                    resolvedEntryModifiedAt: inputs.resolvedEntryModifiedAt,
                    resourceSignature: resourceSignature,
                    overridesSignature: inputs.overridesSignature,
                    execution: execution
                ),
                to: inputs.runtimeFileURL
            )
        }.value
    }

    func webRuntimeResourceSignature(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopWebRuntimeResourceSignature? {
        guard let entryURL = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL else {
            return nil
        }
        let rootURL = effectiveWebRootURL(for: record, entryURL: entryURL)
        return webRuntimeResourceSignature(entryURL: entryURL, rootURL: rootURL)
    }

    /// 签名扫描核心：≤120 文件 BFS + 文本依赖全文读取，纯 FS 无 actor 状态，
    /// 可在任意线程执行。
    nonisolated func webRuntimeResourceSignature(
        entryURL: URL,
        rootURL: URL
    ) -> SteamWorkshopWebRuntimeResourceSignature? {
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

    /// 后台段调用的签名入口：无 entry/root（记录无入口）时与同步版一致返回 nil。
    nonisolated private static func liveResourceSignature(
        inputs: WebRuntimeCacheManifestInputs,
        scanner: SteamWorkshopService
    ) -> SteamWorkshopWebRuntimeResourceSignature? {
        guard let entryURL = inputs.entryURL, let rootURL = inputs.rootURL else { return nil }
        return scanner.webRuntimeResourceSignature(entryURL: entryURL, rootURL: rootURL)
    }

    /// 纯映射：descriptor → 分析缓存负载（同步保存与后台保存共用一份构造）。
    private static func cachedAnalysis(from descriptor: ResolvedWebProjectDescriptor) -> CachedResolvedWebProjectDescriptor {
        CachedResolvedWebProjectDescriptor(
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
    }

    /// 纯编码 + 原子写盘，可在任意线程执行。
    nonisolated private static func writeManifest<T: Encodable>(_ manifest: T, to fileURL: URL) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

}
