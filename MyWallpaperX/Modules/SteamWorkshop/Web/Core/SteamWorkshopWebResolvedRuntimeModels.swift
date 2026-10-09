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

    private func computeResolvedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> ResolvedWebProjectDescriptor? {
        if let cachedDescriptor = loadCachedWebProjectDescriptor(for: record) {
            return cachedDescriptor
        }

        guard let resolvedEntryURL = record.webEntryURL else {
            return nil
        }

        let standardizedEntryURL = resolvedEntryURL.resolvingSymlinksInPath().standardizedFileURL
        let effectiveRootURL = effectiveWebRootURL(for: record, entryURL: standardizedEntryURL)
        let propertySourceRecord = webPropertyDefinitionSourceRecord(for: record)
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

        let propertyDefinitions = webPropertyDefinitions(for: record)
        let localizationRoot = propertySourceRecord.flatMap(loadWebProjectRoot(for:)) ?? loadWebProjectRoot(for: record) ?? [:]
        let localization = Self.webProjectLocalization(from: localizationRoot)
        let baselineValues = webPropertyBaselineValues(for: record, definitions: propertyDefinitions)
        let presetOverrides = webPresetValues(for: record)
        let hostCapabilitySnapshot = resolvedWebHostCapabilitySnapshot()
        let staticContentSummary = resolvedWebStaticContentSummary(
            for: record,
            entryURL: standardizedEntryURL,
            rootURL: effectiveRootURL
        )
        let presetResourceBindingsByKey = resolvedWebPresetResourceBindings(for: record)
        let sampleStructure = webSampleStructure(for: record)
        var runtimeRiskFlags = resolvedWebStructuralRiskFlags(for: record, sampleStructure: sampleStructure)
        runtimeRiskFlags = runtimeRiskFlags.union(with: resolvedWebStaticContentRiskFlags(from: staticContentSummary))
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
        let baselinePreconditionStates = resolvedWebRuntimePreconditions(
            for: record,
            definitions: propertyDefinitions,
            effectiveValues: baselineValues
        )

        let descriptor = ResolvedWebProjectDescriptor(
            recordID: record.id,
            sourceKind: sourceKind,
            declaredEntryRelativePath: declaredEntryRelativePath,
            resolvedEntryRelativePath: webRelativePath(for: standardizedEntryURL, under: effectiveRootURL),
            resolvedEntryURL: standardizedEntryURL,
            effectiveRootURL: effectiveRootURL,
            entrySource: entrySource,
            sampleStructure: sampleStructure,
            propertySource: propertySource,
            propertyDefinitions: propertyDefinitions,
            defaultValueMap: baselineValues,
            presetOverrideMap: presetOverrides,
            presetResourceBindingsByKey: presetResourceBindingsByKey,
            baselineVisiblePropertyKeys: baselineVisiblePropertyKeys,
            baselineVisibleOptionsByKey: baselineVisibleOptionsByKey,
            baselinePreconditionStates: baselinePreconditionStates,
            resolvedLocalizationMap: localization,
            hostCapabilitySnapshot: hostCapabilitySnapshot,
            staticContentSummary: staticContentSummary,
            runtimeRiskFlags: runtimeRiskFlags
        )
        saveWebAnalysisCache(descriptor: descriptor, for: record)
        return descriptor
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

    /// 缓存命中的读盘/校验扫描与冷路径的写盘都在内部后台段执行；
    /// 冷路径的 descriptor 解析仍在主线程（读取属性覆盖等 actor 状态）。
    func resolvedWebPlaybackContext(for record: SteamWorkshopDownloadRecord) async -> ResolvedWebPlaybackContext? {
        if let cachedPlaybackContext = await loadCachedWebPlaybackContext(for: record) {
            return cachedPlaybackContext
        }

        guard let descriptor = resolvedWebProjectDescriptor(for: record) else {
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
    func union(with other: [ResolvedWebRuntimeRiskFlag]) -> [ResolvedWebRuntimeRiskFlag] {
        Array(Set(self).union(other))
    }
}

private extension SteamWorkshopService {
}
