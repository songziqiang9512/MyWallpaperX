import Foundation

extension SteamWorkshopService {
    func resolvedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> ResolvedWebProjectDescriptor? {
        guard record.contentType == .web else {
            return nil
        }

        let source = webPropertyDefinitionSource(for: record)
        let inputs = webRuntimeCacheManifestInputs(for: record, source: source)
        if let cached = webProjectDescriptorCache[record.id], cached.matches(inputs) {
            return assembleResolvedWebProjectDescriptor(record: record, product: cached.product)
        }
        if let cached = Self.loadCachedAnalysisDescriptor(inputs: inputs) {
            webProjectDescriptorCache[record.id] = cached
            return assembleResolvedWebProjectDescriptor(record: record, product: cached.product)
        }
        let reader = WebAuthorFileReader()
        guard let captured = captureWebAuthorInput(record: record, source: source, inputs: inputs, reader: reader),
              let product = parseWebProjectDescriptorCore(record: record, captured: captured) else { return nil }
        let cached = reader.cachedProduct(product, inputs: inputs)
        if cached.isReusable {
            webProjectDescriptorCache[record.id] = cached
            let publication = SteamWorkshopWebRuntimeCachePublication.shared.begin(key: inputs.analysisFileURL.path)
            Self.saveWebAnalysisCache(cached, inputs: inputs, publication: publication)
        }
        return assembleResolvedWebProjectDescriptor(record: record, product: product)
    }

    /// Author-only interpretation. Current overrides and bookmark authority are
    /// projected separately on the service actor immediately before playback.
    nonisolated struct WebProjectDescriptorParseProduct: Codable, Equatable, Sendable {
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
        let bindingContext: WebAuthorBindingContext
    }

    /// The real parser consumes captured bytes/names/signals only. No author
    /// URL may be reopened here or in the per-waiter assembly below.
    nonisolated func parseWebProjectDescriptorCore(record: SteamWorkshopDownloadRecord,
        captured: WebCapturedAuthorInput) -> WebProjectDescriptorParseProduct? {
        guard !Task.isCancelled, let entry = captured.inputs.entryURL, let root = captured.inputs.rootURL else { return nil }
        let sourceRoot = Self.loadWebProjectRootStatic(data: captured.sourceProjectData)
        let ownRoot = captured.sourceProjectData == captured.ownProjectData ? sourceRoot : Self.loadWebProjectRootStatic(data: captured.ownProjectData)
        let definitions = sourceRoot.map { Self.webPropertyDefinitions(projectRoot: $0, languageKeys: captured.inputs.authorLanguageKeys) } ?? []
        let localization = Self.webProjectLocalization(from: sourceRoot ?? ownRoot ?? [:], languageKeys: captured.inputs.authorLanguageKeys)
        let presets = Self.webPresetValues(projectRoot: ownRoot)
        var baseline = Dictionary(uniqueKeysWithValues: definitions.map { ($0.key, $0.defaultValue) })
        baseline.merge(presets) { _, preset in preset }
        let count = ((sourceRoot?["general"] as? [String: Any])?["properties"] as? [String: Any])?.count ?? 0
        let structure = Self.webSampleStructure(record: record, propertyCount: count, fileNames: captured.topLevelNames)
        let summary = captured.summary.withDirectoryModes(definitions: definitions)
        let sourceKind: ResolvedWebProjectDescriptor.SourceKind = record.isDependencyBackedWeb
            ? .dependencyBackedShell : (record.projectFileURL == nil ? .inferredProject : .ownProject)
        let propertySource: SteamWorkshopWebPropertySource = if let source = captured.source, source.id != record.id {
            .dependencyHost(itemID: source.id)
        } else { .ownProject }
        let flags = Array(Set(Self.resolvedWebStructuralRiskFlags(record: record, sampleStructure: structure,
            propertyDefinitions: definitions)).union(resolvedWebStaticContentRiskFlags(from: summary))).sorted { $0.rawValue < $1.rawValue }
        return WebProjectDescriptorParseProduct(standardizedEntryURL: entry, effectiveRootURL: root,
            propertySource: propertySource, sourceKind: sourceKind, declaredEntryRelativePath: captured.declaredEntry,
            entrySource: captured.entrySource, propertyDefinitions: definitions, localization: localization,
            baselineValues: baseline, presetOverrides: presets, hostCapabilitySnapshot: resolvedWebHostCapabilitySnapshot(),
            staticContentSummary: summary, sampleStructure: structure, runtimeRiskFlags: flags,
            bindingContext: .make(record: record, presets: presets, roots: captured.candidateRoots))
    }

    func assembleResolvedWebProjectDescriptor(record: SteamWorkshopDownloadRecord,
        product: WebProjectDescriptorParseProduct) -> ResolvedWebProjectDescriptor {
        let propertyDefinitions = product.propertyDefinitions
        let baselineValues = product.baselineValues

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
            resolvedLocalizationMap: product.localization,
            hostCapabilitySnapshot: product.hostCapabilitySnapshot,
            staticContentSummary: product.staticContentSummary,
            runtimeRiskFlags: product.runtimeRiskFlags
        )
    }

    /// Compatibility surface for callers that need only the playback payload.
    func resolvedWebPlaybackContext(for record: SteamWorkshopDownloadRecord) async -> ResolvedWebPlaybackContext? {
        await prepareWebPlaybackContext(for: record)?.context
    }

    /// Runtime profile selection consumes this same descriptor rather than
    /// reconstructing a property-panel model after preparation has finished.
    /// Optional analysis-cache writing never delays this playback projection.
    func prepareWebPlaybackContext(for record: SteamWorkshopDownloadRecord) async -> ResolvedWebPlaybackPreparation? {
        guard let admission = admitWebAuthorPreparation(for: record) else { return nil }
        defer { withExtendedLifetime(admission) {} }
        guard let product = await resolvedWebAuthorProduct(for: record, admission: admission) else { return nil }
        let bindingContext = product.bindingContext
        // No suspension after the current overrides and bookmark grants are
        // projected. The analysis cache carries no playback payload authority.
        let descriptor = assembleResolvedWebProjectDescriptor(record: record, product: product)
        let currentValues = effectiveWebPropertyValues(for: record, descriptor: descriptor)
        let currentPayload = effectiveWebPropertiesJSONString(for: record,
            definitions: product.propertyDefinitions, valuesOverride: currentValues, bindingContext: bindingContext)
        let resourceGrants = resolvedWebResourceGrants(for: record,
            definitions: product.propertyDefinitions, valuesOverride: currentValues,
            effectiveRootURL: descriptor.effectiveRootURL, bindingContext: bindingContext)
        let context = ResolvedWebPlaybackContext(
            recordID: record.id,
            effectiveEntryURL: descriptor.resolvedEntryURL,
            effectiveRootURL: descriptor.effectiveRootURL,
            propertyPayloadJSON: currentPayload,
            language: admission.inputs.language,
            resourceGrants: resourceGrants,
            allowedNetworkHosts: Set(descriptor.staticContentSummary.externalDependencyHosts
                .compactMap(DedicatedWebWallpaperHostPlaceholderAdapter.normalizedNetworkBridgeHost))
        )
        return ResolvedWebPlaybackPreparation(context: context, descriptor: descriptor, resourceLifetime: admission.lifetime)
    }
}
