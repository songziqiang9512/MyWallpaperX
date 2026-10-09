import Foundation

extension SteamWorkshopService {
    func resolvedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> ResolvedWebProjectDescriptor? {
        guard record.contentType == .web else {
            return nil
        }

        // mtime 键记忆缓存（与 webValidationReportCache / webRuntimeModelCache
        // 同一纪律）：属性面板 rebuild、详情页、宿主桥解析闭包等高频同步
        // 调用面在 mtime 态未变时零 IO 返回，只有首个未命中才走读盘校验
        // 或冷解析。
        let memoSignature = webProjectDescriptorSignature(for: record)
        if let cached = webProjectDescriptorCache[record.id], cached.signature == memoSignature {
            return cached.descriptor
        }

        guard let resolvedDescriptor = computeResolvedWebProjectDescriptor(for: record) else {
            return nil
        }
        webProjectDescriptorCache[record.id] = CachedWebProjectDescriptor(
            signature: memoSignature,
            descriptor: resolvedDescriptor
        )
        return resolvedDescriptor
    }

    /// 冷解析产物：除书签相邻段（presetBindings/preconditions——经
    /// resolvedWebResourceBinding 触 security scope 与陈旧书签回写，必须
    /// 主线程）外的全部字段；由 nonisolated 解析核产出，主线程收尾装配。
    struct WebProjectDescriptorParseProduct {
        let standardizedEntryURL: URL
        let effectiveRootURL: URL
        let propertySource: SteamWorkshopWebPropertySource
        let sourceKind: ResolvedWebProjectDescriptor.SourceKind
        let declaredEntryRelativePath: String?
        let entrySource: ResolvedWebProjectDescriptor.EntrySource
        let propertyDefinitions: [SteamWorkshopWebPropertyDefinition]
        let localization: [String: String]
        let baselineValues: [String: SteamWorkshopWebPropertyValue]
        let presetOverrides: [String: SteamWorkshopWebPropertyValue]
        let hostCapabilitySnapshot: ResolvedWebHostCapabilitySnapshot
        let staticContentSummary: ResolvedWebStaticContentSummary
        let sampleStructure: SteamWorkshopWebSampleStructure
        let runtimeRiskFlags: [ResolvedWebRuntimeRiskFlag]
    }

    private func computeResolvedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> ResolvedWebProjectDescriptor? {
        if let cachedDescriptor = loadCachedWebProjectDescriptor(for: record) {
            return cachedDescriptor
        }

        guard let resolvedDescriptor = assembleResolvedWebProjectDescriptor(
            record: record,
            propertySourceRecord: webPropertyDefinitionSourceRecord(for: record),
            parseProduct: nil
        ) else {
            return nil
        }
        saveWebAnalysisCache(descriptor: resolvedDescriptor, for: record)
        return resolvedDescriptor
    }

    /// 启动冷路径入口：memo（主线程零 IO 命中）→ 后台段（分析缓存读盘
    /// 校验/解析核全量构造）→ 主线程收尾（书签相邻段 + 装配 + memo）。
    /// 与同步版共享 memo、解析核与装配，只是执行位置不同。
    func resolvedWebProjectDescriptorForLaunch(for record: SteamWorkshopDownloadRecord) async -> ResolvedWebProjectDescriptor? {
        guard record.contentType == .web else {
            return nil
        }
        let memoSignature = webProjectDescriptorSignature(for: record)
        if let cached = webProjectDescriptorCache[record.id], cached.signature == memoSignature {
            return cached.descriptor
        }
        // 主线程快照：actor 输入一次收集，后台段不回读。
        let propertySourceRecord = webPropertyDefinitionSourceRecord(for: record)
        let inputs = webRuntimeCacheManifestInputs(for: record)
        let entryURL = inputs.entryURL
        let rootURL = inputs.rootURL
        enum LaunchOutcome {
            case cached(ResolvedWebProjectDescriptor)
            case parsed(WebProjectDescriptorParseProduct)
            case none
        }
        let outcome: LaunchOutcome = await Task.detached(priority: .userInitiated) { [weak self] () -> LaunchOutcome in
            if let cachedDescriptor = Self.loadCachedAnalysisDescriptor(inputs: inputs, scanner: self) {
                return .cached(cachedDescriptor)
            }
            guard let self, let entryURL, let rootURL else {
                return .none
            }
            guard let product = self.parseWebProjectDescriptorCore(
                record: record,
                propertySourceRecord: propertySourceRecord,
                standardizedEntryURL: entryURL,
                effectiveRootURL: rootURL
            ) else {
                return .none
            }
            return .parsed(product)
        }.value
        let resolvedDescriptor: ResolvedWebProjectDescriptor?
        switch outcome {
        case let .cached(cachedDescriptor):
            resolvedDescriptor = cachedDescriptor
        case let .parsed(product):
            resolvedDescriptor = assembleResolvedWebProjectDescriptor(
                record: record,
                propertySourceRecord: propertySourceRecord,
                parseProduct: product
            )
        case .none:
            resolvedDescriptor = nil
        }
        guard let resolvedDescriptor else { return nil }
        webProjectDescriptorCache[record.id] = CachedWebProjectDescriptor(
            signature: memoSignature,
            descriptor: resolvedDescriptor
        )
        return resolvedDescriptor
    }

    /// 解析核：project root/入口 HTML BFS/目录 listing 等全部文件 IO 在
    /// 调用线程执行；propertySourceRecord 由主线程快照传入。
    nonisolated private func parseWebProjectDescriptorCore(
        record: SteamWorkshopDownloadRecord,
        propertySourceRecord: SteamWorkshopDownloadRecord?,
        standardizedEntryURL: URL,
        effectiveRootURL: URL
    ) -> WebProjectDescriptorParseProduct? {
        let propertySource: SteamWorkshopWebPropertySource = if let propertySourceRecord, propertySourceRecord.id != record.id {
            .dependencyHost(itemID: propertySourceRecord.id)
        } else {
            .ownProject
        }
        let sourceKind: ResolvedWebProjectDescriptor.SourceKind = if record.isDependencyBackedWeb {
            .dependencyBackedShell
        } else if record.projectFileURL == nil {
            .inferredProject
        } else {
            .ownProject
        }

        let declaredEntryRelativePath = declaredWebEntryRelativePath(for: record)

        let entrySource: ResolvedWebProjectDescriptor.EntrySource
        if let declaredEntryRelativePath,
           standardizedEntryURL.path == record.folderURL.appendingPathComponent(declaredEntryRelativePath).resolvingSymlinksInPath().standardizedFileURL.path {
            entrySource = .declaredProjectEntry
        } else if record.isDependencyBackedWeb,
                  let dependencyEntryURL = record.webDependencyHostEntryURL,
                  dependencyEntryURL.resolvingSymlinksInPath().standardizedFileURL.path == standardizedEntryURL.path {
            entrySource = .dependencyHostEntry
        } else {
            entrySource = .inferredFallbackEntry
        }

        let sourceRoot = propertySourceRecord.flatMap { Self.loadWebProjectRootStatic(for: $0) }
        let localizationRoot = sourceRoot ?? Self.loadWebProjectRootStatic(for: record) ?? [:]
        let propertyDefinitions = sourceRoot.map { Self.webPropertyDefinitions(projectRoot: $0) } ?? []
        let localization = Self.webProjectLocalization(from: localizationRoot)
        let baselineValues = webPropertyBaselineValues(for: record, definitions: propertyDefinitions)
        let presetOverrides = Self.webPresetValues(for: record)
        let hostCapabilitySnapshot = resolvedWebHostCapabilitySnapshot()
        let staticContentSummary = resolvedWebStaticContentSummary(
            for: record,
            entryURL: standardizedEntryURL,
            rootURL: effectiveRootURL,
            propertyDefinitions: propertyDefinitions
        )
        let sampleStructure = Self.webSampleStructure(
            record: record,
            sourceRecord: propertySourceRecord ?? record
        )
        var runtimeRiskFlags = Self.resolvedWebStructuralRiskFlags(
            record: record,
            sampleStructure: sampleStructure,
            propertyDefinitions: propertyDefinitions
        )
        runtimeRiskFlags = runtimeRiskFlags.union(with: resolvedWebStaticContentRiskFlags(from: staticContentSummary))
        return WebProjectDescriptorParseProduct(
            standardizedEntryURL: standardizedEntryURL,
            effectiveRootURL: effectiveRootURL,
            propertySource: propertySource,
            sourceKind: sourceKind,
            declaredEntryRelativePath: declaredEntryRelativePath,
            entrySource: entrySource,
            propertyDefinitions: propertyDefinitions,
            localization: localization,
            baselineValues: baselineValues,
            presetOverrides: presetOverrides,
            hostCapabilitySnapshot: hostCapabilitySnapshot,
            staticContentSummary: staticContentSummary,
            sampleStructure: sampleStructure,
            runtimeRiskFlags: runtimeRiskFlags
        )
    }

    /// 主线程装配：书签相邻段（presetBindings/preconditions）+ 最终
    /// descriptor 构造。`parseProduct == nil` 时在调用线程（同步路径=主
    /// 线程）先执行解析核——两条编排共享同一实现。
    private func assembleResolvedWebProjectDescriptor(
        record: SteamWorkshopDownloadRecord,
        propertySourceRecord: SteamWorkshopDownloadRecord?,
        parseProduct: WebProjectDescriptorParseProduct?
    ) -> ResolvedWebProjectDescriptor? {
        let product: WebProjectDescriptorParseProduct
        if let parseProduct {
            product = parseProduct
        } else {
            guard let resolvedEntryURL = record.webEntryURL else {
                return nil
            }
            let standardizedEntryURL = resolvedEntryURL.resolvingSymlinksInPath().standardizedFileURL
            guard let parsed = parseWebProjectDescriptorCore(
                record: record,
                propertySourceRecord: propertySourceRecord,
                standardizedEntryURL: standardizedEntryURL,
                effectiveRootURL: effectiveWebRootURL(for: record, entryURL: standardizedEntryURL)
            ) else {
                return nil
            }
            product = parsed
        }
        let propertyDefinitions = product.propertyDefinitions
        let baselineValues = product.baselineValues
        let baselineVisiblePropertyKeys = propertyDefinitions
            .filter {
                shouldDisplayWebProperty(
                    $0,
                    values: baselineValues,
                    definitions: propertyDefinitions
                )
            }
            .map(\.key)
        let baselineVisibleOptionsByKey = Dictionary(uniqueKeysWithValues: propertyDefinitions.map { definition in
            (
                definition.key,
                visibleWebPropertyOptions(
                    for: definition,
                    values: baselineValues,
                    definitions: propertyDefinitions
                )
            )
        })
        let presetResourceBindingsByKey = resolvedWebPresetResourceBindings(for: record)
        let baselinePreconditionStates = resolvedWebRuntimePreconditions(
            for: record,
            definitions: propertyDefinitions,
            effectiveValues: baselineValues
        )

        return ResolvedWebProjectDescriptor(
            recordID: record.id,
            sourceKind: product.sourceKind,
            declaredEntryRelativePath: product.declaredEntryRelativePath,
            resolvedEntryRelativePath: webRelativePath(for: product.standardizedEntryURL, under: product.effectiveRootURL),
            resolvedEntryURL: product.standardizedEntryURL,
            effectiveRootURL: product.effectiveRootURL,
            entrySource: product.entrySource,
            sampleStructure: product.sampleStructure,
            propertySource: product.propertySource,
            propertyDefinitions: propertyDefinitions,
            defaultValueMap: baselineValues,
            presetOverrideMap: product.presetOverrides,
            presetResourceBindingsByKey: presetResourceBindingsByKey,
            baselineVisiblePropertyKeys: baselineVisiblePropertyKeys,
            baselineVisibleOptionsByKey: baselineVisibleOptionsByKey,
            baselinePreconditionStates: baselinePreconditionStates,
            resolvedLocalizationMap: product.localization,
            hostCapabilitySnapshot: product.hostCapabilitySnapshot,
            staticContentSummary: product.staticContentSummary,
            runtimeRiskFlags: product.runtimeRiskFlags
        )
    }

    func resolvedWebPresetResourceBindings(for record: SteamWorkshopDownloadRecord) -> [String: ResolvedWebResourceBinding] {
        Dictionary(
            uniqueKeysWithValues: webShellResourcePathLikePresetValues(for: record).compactMap { key, rawValue in
                guard let binding = resolvedWebResourceBinding(
                    forKey: key,
                    definition: nil,
                    rawValue: rawValue,
                    record: record
                ) else {
                    return nil
                }
                return (key, binding)
            }
        )
    }

    /// 缓存命中的读盘/校验扫描与冷路径的解析/写盘都在内部后台段执行；
    /// 冷路径解析核与同步表面共享同一 nonisolated 实现（见
    /// resolvedWebProjectDescriptorForLaunch）。
    func resolvedWebPlaybackContext(for record: SteamWorkshopDownloadRecord) async -> ResolvedWebPlaybackContext? {
        if let cachedPlaybackContext = await loadCachedWebPlaybackContext(for: record) {
            // 磁盘命中路径同时预热 descriptor memo：否则回主线程后
            // recommendedWebRuntimeProfile → resolvedWebRuntimeModel 的两级
            // memo 全冷，analysis 清单读盘+解码（跨会话清单还有 BFS 签名
            // 扫描）落回主线程，违反「点击热路径不做文件 IO」契约。预热在
            // 后台段完成后返回；model 构造自此是纯计算。
            _ = await resolvedWebProjectDescriptorForLaunch(for: record)
            return cachedPlaybackContext
        }

        guard let descriptor = await resolvedWebProjectDescriptorForLaunch(for: record) else {
            return nil
        }
        let effectiveValues = effectiveWebPropertyValues(for: record, descriptor: descriptor)
        let propertyPayloadJSON = effectiveWebPropertiesJSONString(
            for: record,
            definitions: descriptor.propertyDefinitions,
            valuesOverride: effectiveValues
        )
        await saveWebRuntimeCache(descriptor: descriptor, propertyPayloadJSON: propertyPayloadJSON, for: record)
        return ResolvedWebPlaybackContext(
            recordID: record.id,
            effectiveEntryURL: descriptor.resolvedEntryURL,
            effectiveRootURL: descriptor.effectiveRootURL,
            propertyPayloadJSON: propertyPayloadJSON,
            language: Self.resolvedWebWallpaperLanguage()
        )
    }

    func resolvedWebRuntimeModel(for record: SteamWorkshopDownloadRecord) -> ResolvedWebRuntimeModel? {
        let signature = webRuntimeComputationSignature(for: record)
        if let cached = webRuntimeModelCache[record.id], cached.signature == signature {
            return cached.model
        }
        guard let descriptor = resolvedWebProjectDescriptor(for: record) else {
            return nil
        }

        let userOverrides = webPropertyOverrides(for: record)
        let effectiveValues = effectiveWebPropertyValues(for: record, descriptor: descriptor)
        let visiblePropertyKeys = descriptor.propertyDefinitions
            .filter {
                shouldDisplayWebProperty(
                    $0,
                    values: effectiveValues,
                    definitions: descriptor.propertyDefinitions
                )
            }
            .map(\.key)

        let visibleOptionsByKey = Dictionary(uniqueKeysWithValues: descriptor.propertyDefinitions.map { definition in
            (
                definition.key,
                visibleWebPropertyOptions(
                    for: definition,
                    values: effectiveValues,
                    definitions: descriptor.propertyDefinitions
                )
            )
        })

        let resolvedRuntimeValues = Dictionary(uniqueKeysWithValues: descriptor.propertyDefinitions.map { definition in
            let rawValue = effectiveValues[definition.key] ?? definition.defaultValue
            return (
                definition.key,
                resolvedWebRuntimeValue(
                    forKey: definition.key,
                    definition: definition,
                    rawValue: rawValue,
                    record: record
                )
            )
        })

        var resourceBindings = descriptor.presetResourceBindingsByKey

        let definitionBindings = descriptor.propertyDefinitions.compactMap { definition -> (String, ResolvedWebResourceBinding)? in
            let rawValue = effectiveValues[definition.key] ?? definition.defaultValue
            guard let binding = resolvedWebResourceBinding(
                forKey: definition.key,
                definition: definition,
                rawValue: rawValue,
                record: record
            ) else {
                return nil
            }
            return (definition.key, binding)
        }

        for (key, binding) in definitionBindings {
            resourceBindings[key] = binding
        }

        let fallbackResourceKeys = resourceBindings.values
            .filter { $0.origin == .presetFallback }
            .map(\.key)
            .sorted()

        let propertyPayloadJSON = effectiveWebPropertiesJSONString(
            for: record,
            definitions: descriptor.propertyDefinitions,
            valuesOverride: effectiveValues
        )

        let preconditionStates = if userOverrides.isEmpty {
            descriptor.baselinePreconditionStates
        } else {
            resolvedWebRuntimePreconditions(
                for: record,
                definitions: descriptor.propertyDefinitions,
                effectiveValues: effectiveValues
            )
        }

        let validationReport = webValidationReport(for: record)
        let lastPlaybackFailureMessage = webPlaybackFailureMessage(for: record)
        let lastPlaybackFailureIssue = lastPlaybackFailureMessage.map(webPlaybackFailureIssue(for:))
        let runtimeRiskFlags = descriptor.runtimeRiskFlags
            .union(with: preconditionStates.compactMap { precondition in
                guard precondition.status == .unmet else { return nil }
                switch precondition.kind {
                case .file:
                    return .missingAccessibleFileBinding
                case .directory:
                    return .missingAccessibleDirectoryBinding
                }
            })

        let diagnosticsSnapshot = ResolvedWebRuntimeDiagnosticsSnapshot(
            recordID: record.id,
            entryRelativePath: descriptor.resolvedEntryRelativePath,
            entryPath: descriptor.resolvedEntryURL.path,
            rootPath: descriptor.effectiveRootURL.path,
            propertySource: descriptor.propertySource.displayName,
            sourceKind: descriptor.sourceKind.displayName,
            entrySource: descriptor.entrySource.displayName,
            sampleStructure: descriptor.sampleStructure.displayName,
            presetOverrideCount: descriptor.presetOverrideMap.count,
            visiblePropertyCount: visiblePropertyKeys.count,
            validationIssueCount: validationReport?.issueCount ?? 0,
            propertyPayloadSize: propertyPayloadJSON?.utf8.count ?? 0,
            unmetPreconditionMessages: preconditionStates
                .filter { $0.status == .unmet }
                .map(\.message),
            runtimeRiskFlags: runtimeRiskFlags,
            lastPlaybackFailureMessage: lastPlaybackFailureMessage,
            isActivePlayback: isActiveWebRecord(record)
        )

        let runtimeModel = ResolvedWebRuntimeModel(
            recordID: record.id,
            descriptor: descriptor,
            resolvedLanguage: Self.resolvedWebWallpaperLanguage(),
            effectiveEntryURL: descriptor.resolvedEntryURL,
            effectiveRootURL: descriptor.effectiveRootURL,
            defaultValues: descriptor.defaultValueMap,
            presetOverrides: descriptor.presetOverrideMap,
            userOverrides: userOverrides,
            resolvedRuntimeValues: resolvedRuntimeValues,
            resourceBindings: resourceBindings,
            fallbackResourceKeys: fallbackResourceKeys,
            visiblePropertyKeys: visiblePropertyKeys,
            visibleOptionsByKey: visibleOptionsByKey,
            propertyPayloadJSON: propertyPayloadJSON,
            validationReport: validationReport,
            preconditionStates: preconditionStates,
            runtimeRiskFlags: runtimeRiskFlags,
            lastPlaybackFailureMessage: lastPlaybackFailureMessage,
            lastPlaybackFailureIssue: lastPlaybackFailureIssue,
            diagnosticsSnapshot: diagnosticsSnapshot
        )
        webRuntimeModelCache[record.id] = CachedWebRuntimeModel(signature: signature, model: runtimeModel)
        return runtimeModel
    }

}

private extension ResolvedWebProjectDescriptor.SourceKind {
    var displayName: String {
        switch self {
        case .ownProject:
            return "独立项目"
        case .dependencyBackedShell:
            return "依赖补丁壳"
        case .inferredProject:
            return "推断项目"
        }
    }
}

private extension ResolvedWebProjectDescriptor.EntrySource {
    var displayName: String {
        switch self {
        case .declaredProjectEntry:
            return "project.json 声明入口"
        case .dependencyHostEntry:
            return "依赖宿主入口"
        case .inferredFallbackEntry:
            return "推断回退入口"
        }
    }
}

private extension Array where Element == ResolvedWebRuntimeRiskFlag {
    nonisolated func union(with other: [ResolvedWebRuntimeRiskFlag]) -> [ResolvedWebRuntimeRiskFlag] {
        Array(Set(self).union(other))
    }
}

private extension SteamWorkshopService {
}
