import Foundation

extension SteamWorkshopService {
    func resolvedWebStructuralRiskFlags(
        for record: SteamWorkshopDownloadRecord,
        sampleStructure: SteamWorkshopWebSampleStructure? = nil
    ) -> [ResolvedWebRuntimeRiskFlag] {
        var flags = Set<ResolvedWebRuntimeRiskFlag>()
        let resolvedSampleStructure = sampleStructure ?? webSampleStructure(for: record)
        if resolvedSampleStructure == .shaderOrCanvasWeb
            || resolvedSampleStructure == .spineWebCharacter
            || resolvedSampleStructure == .megaConfigDashboardWeb
            || resolvedSampleStructure == .multimediaDashboardWeb {
            flags.insert(.highLoadStructure)
        }

        let propertyDefinitions = webPropertyDefinitions(for: record)
        if propertyDefinitions.contains(where: { ($0.displayCondition?.isEmpty == false) && SteamWorkshopService.webDisplayConditionRequiresFallback($0.displayCondition) }) {
            flags.insert(.unsupportedDisplayConditionFallback)
        }
        if propertyDefinitions.contains(where: { $0.title.lowercased().hasPrefix("ui_") || $0.options.contains(where: { $0.label.lowercased().hasPrefix("ui_") }) }) {
            flags.insert(.incompleteLocalizationTokens)
        }
        if propertyDefinitions.contains(where: { $0.kind == .slider && $0.allowsFractionalValues && $0.fractionalPrecision == nil }) {
            flags.insert(.implicitFractionalSliderPrecision)
        }
        if webHasKnownSafariIncompatibility(for: record) {
            flags.insert(.knownSafariBaselineIncompatibility)
        }
        return Array(flags)
    }

    func webHasKnownSafariIncompatibility(for _: SteamWorkshopDownloadRecord) -> Bool {
        false
    }

    /// 运行风险旗标只由结构化信号装配。`staticContentSummary` 是静态扫描的唯一结构化结果，
    /// 校验文案只用于展示，不作为旗标来源：文案措辞变化不得改变运行档位。
    func resolvedWebStaticContentRiskFlags(
        from summary: ResolvedWebStaticContentSummary
    ) -> [ResolvedWebRuntimeRiskFlag] {
        var flags = Set<ResolvedWebRuntimeRiskFlag>()
        if summary.usesWebMResource {
            flags.insert(.webMHeavyMedia)
        }
        if summary.usesHoverOnlyInteraction {
            flags.insert(.hoverOnlyInteraction)
        }
        if summary.usesPluginBridge {
            flags.insert(.pluginBridgeApproximation)
        }
        if summary.usesPersistentBrowserStorage {
            flags.insert(.persistentBrowserStorageUsage)
        }
        if summary.usesServiceWorkerRegistration {
            flags.insert(.serviceWorkerRegistration)
        }
        if summary.usesESModuleDependency {
            flags.insert(.esModuleDependency)
        }
        if summary.usesDynamicImport {
            flags.insert(.dynamicImportUsage)
        }
        if summary.usesWASMResource {
            flags.insert(.wasmUsage)
        }
        if summary.usesWASMStreaming {
            flags.insert(.wasmStreamingUsage)
        }
        if summary.usesCustomSchemeSensitiveWebGL {
            flags.insert(.customSchemeSensitiveWebGL)
        }
        if summary.usesIframeCrossFrameAccess {
            flags.insert(.iframeCrossFrameAccess)
        }
        if summary.hasTruncatedStaticAnalysis {
            flags.insert(.truncatedStaticAnalysis)
        }
        if summary.localhostDependencyHosts.isEmpty == false {
            flags.insert(.localhostDependency)
        }
        let remoteExternalHosts = summary.externalDependencyHosts.filter {
            !summary.localhostDependencyHosts.contains($0)
        }
        if remoteExternalHosts.isEmpty == false {
            flags.insert(.externalServiceDependency)
        }
        return Array(flags)
    }
}
