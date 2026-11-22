import Foundation

nonisolated struct ResolvedWebHostCapabilitySnapshot: Codable, Equatable {
    enum SupportLevel: String, Codable, Equatable {
        case none
        case placeholder
        case basic
    }

    struct GeneralPropertiesCapabilitySnapshot: Codable, Equatable {
        let applyListenerLevel: SupportLevel
        let fpsLevel: SupportLevel
    }

    struct MediaCapabilitySnapshot: Codable, Equatable {
        let statusLevel: SupportLevel
        let propertiesLevel: SupportLevel
        let thumbnailLevel: SupportLevel
        let timelineLevel: SupportLevel
        let playbackLevel: SupportLevel
    }

    let userPropertiesLevel: SupportLevel
    let generalProperties: GeneralPropertiesCapabilitySnapshot
    let directoryNotificationsLevel: SupportLevel
    let audioListenerLevel: SupportLevel
    let audioStreamLevel: SupportLevel
    let media: MediaCapabilitySnapshot
    let pluginBridgeLevel: SupportLevel
    let rgbBridgeLevel: SupportLevel
    let pauseBridgeLevel: SupportLevel
    let volumeBridgeLevel: SupportLevel
}

nonisolated struct ResolvedWebStaticContentSummary: Codable, Equatable {
    let usesPluginBridge: Bool
    let usesPersistentBrowserStorage: Bool
    let usesServiceWorkerRegistration: Bool
    let usesESModuleDependency: Bool
    let usesDynamicImport: Bool
    let usesWASMResource: Bool
    let usesWASMStreaming: Bool
    let usesCustomSchemeSensitiveWebGL: Bool
    let usesIframeCrossFrameAccess: Bool
    let usesWebMResource: Bool
    let usesHoverOnlyInteraction: Bool
    let referencesSchemeColorUserProperty: Bool
    let hasUncertainUserPropertyUsage: Bool
    let hasTruncatedStaticAnalysis: Bool
    let hasFetchAllDirectoryProperty: Bool
    let hasOnDemandDirectoryProperty: Bool
    let externalDependencyHosts: [String]
    let localhostDependencyHosts: [String]
    let remoteScriptDependencyHosts: [String]

    func withDirectoryModes(definitions: [SteamWorkshopWebPropertyDefinition]) -> Self {
        Self(
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
            hasFetchAllDirectoryProperty: definitions.contains { $0.kind == .directory && $0.directoryMode?.lowercased() == "fetchall" },
            hasOnDemandDirectoryProperty: definitions.contains { $0.kind == .directory && $0.directoryMode?.lowercased() == "ondemand" },
            externalDependencyHosts: externalDependencyHosts,
            localhostDependencyHosts: localhostDependencyHosts,
            remoteScriptDependencyHosts: remoteScriptDependencyHosts
        )
    }

    enum CodingKeys: String, CodingKey {
        case usesPluginBridge
        case usesPersistentBrowserStorage
        case usesServiceWorkerRegistration
        case usesESModuleDependency
        case usesDynamicImport
        case usesWASMResource
        case usesWASMStreaming
        case usesCustomSchemeSensitiveWebGL
        case usesIframeCrossFrameAccess
        case usesWebMResource
        case usesHoverOnlyInteraction
        case referencesSchemeColorUserProperty
        case hasUncertainUserPropertyUsage
        case hasTruncatedStaticAnalysis
        case hasFetchAllDirectoryProperty
        case hasOnDemandDirectoryProperty
        case externalDependencyHosts
        case localhostDependencyHosts
        case remoteScriptDependencyHosts
    }

    init(
        usesPluginBridge: Bool,
        usesPersistentBrowserStorage: Bool,
        usesServiceWorkerRegistration: Bool,
        usesESModuleDependency: Bool,
        usesDynamicImport: Bool,
        usesWASMResource: Bool,
        usesWASMStreaming: Bool,
        usesCustomSchemeSensitiveWebGL: Bool,
        usesIframeCrossFrameAccess: Bool,
        usesWebMResource: Bool,
        usesHoverOnlyInteraction: Bool,
        referencesSchemeColorUserProperty: Bool,
        hasUncertainUserPropertyUsage: Bool,
        hasTruncatedStaticAnalysis: Bool,
        hasFetchAllDirectoryProperty: Bool,
        hasOnDemandDirectoryProperty: Bool,
        externalDependencyHosts: [String],
        localhostDependencyHosts: [String],
        remoteScriptDependencyHosts: [String]
    ) {
        self.usesPluginBridge = usesPluginBridge
        self.usesPersistentBrowserStorage = usesPersistentBrowserStorage
        self.usesServiceWorkerRegistration = usesServiceWorkerRegistration
        self.usesESModuleDependency = usesESModuleDependency
        self.usesDynamicImport = usesDynamicImport
        self.usesWASMResource = usesWASMResource
        self.usesWASMStreaming = usesWASMStreaming
        self.usesCustomSchemeSensitiveWebGL = usesCustomSchemeSensitiveWebGL
        self.usesIframeCrossFrameAccess = usesIframeCrossFrameAccess
        self.usesWebMResource = usesWebMResource
        self.usesHoverOnlyInteraction = usesHoverOnlyInteraction
        self.referencesSchemeColorUserProperty = referencesSchemeColorUserProperty
        self.hasUncertainUserPropertyUsage = hasUncertainUserPropertyUsage
        self.hasTruncatedStaticAnalysis = hasTruncatedStaticAnalysis
        self.hasFetchAllDirectoryProperty = hasFetchAllDirectoryProperty
        self.hasOnDemandDirectoryProperty = hasOnDemandDirectoryProperty
        self.externalDependencyHosts = externalDependencyHosts
        self.localhostDependencyHosts = localhostDependencyHosts
        self.remoteScriptDependencyHosts = remoteScriptDependencyHosts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            usesPluginBridge: try container.decode(Bool.self, forKey: .usesPluginBridge),
            usesPersistentBrowserStorage: try container.decode(Bool.self, forKey: .usesPersistentBrowserStorage),
            usesServiceWorkerRegistration: try container.decode(Bool.self, forKey: .usesServiceWorkerRegistration),
            usesESModuleDependency: try container.decode(Bool.self, forKey: .usesESModuleDependency),
            usesDynamicImport: try container.decode(Bool.self, forKey: .usesDynamicImport),
            usesWASMResource: try container.decode(Bool.self, forKey: .usesWASMResource),
            usesWASMStreaming: try container.decode(Bool.self, forKey: .usesWASMStreaming),
            usesCustomSchemeSensitiveWebGL: try container.decodeIfPresent(Bool.self, forKey: .usesCustomSchemeSensitiveWebGL) ?? false,
            usesIframeCrossFrameAccess: try container.decodeIfPresent(Bool.self, forKey: .usesIframeCrossFrameAccess) ?? false,
            usesWebMResource: try container.decode(Bool.self, forKey: .usesWebMResource),
            usesHoverOnlyInteraction: try container.decode(Bool.self, forKey: .usesHoverOnlyInteraction),
            referencesSchemeColorUserProperty: try container.decodeIfPresent(Bool.self, forKey: .referencesSchemeColorUserProperty) ?? false,
            hasUncertainUserPropertyUsage: try container.decodeIfPresent(Bool.self, forKey: .hasUncertainUserPropertyUsage) ?? true,
            hasTruncatedStaticAnalysis: try container.decodeIfPresent(Bool.self, forKey: .hasTruncatedStaticAnalysis) ?? false,
            hasFetchAllDirectoryProperty: try container.decode(Bool.self, forKey: .hasFetchAllDirectoryProperty),
            hasOnDemandDirectoryProperty: try container.decode(Bool.self, forKey: .hasOnDemandDirectoryProperty),
            externalDependencyHosts: try container.decode([String].self, forKey: .externalDependencyHosts),
            localhostDependencyHosts: try container.decode([String].self, forKey: .localhostDependencyHosts),
            remoteScriptDependencyHosts: try container.decode([String].self, forKey: .remoteScriptDependencyHosts)
        )
    }
}

struct ResolvedWebProjectDescriptor: Equatable {
    enum SourceKind: String, Codable, Equatable, Hashable {
        case ownProject
        case dependencyBackedShell
        case inferredProject
    }

    enum EntrySource: String, Codable, Equatable, Hashable {
        case declaredProjectEntry
        case dependencyHostEntry
        case inferredFallbackEntry
    }

    let recordID: String
    let sourceKind: SourceKind
    let declaredEntryRelativePath: String?
    let resolvedEntryRelativePath: String
    let resolvedEntryURL: URL
    let effectiveRootURL: URL
    let entrySource: EntrySource
    let sampleStructure: SteamWorkshopWebSampleStructure
    let propertySource: SteamWorkshopWebPropertySource
    let propertyDefinitions: [SteamWorkshopWebPropertyDefinition]
    let defaultValueMap: [String: SteamWorkshopWebPropertyValue]
    let presetOverrideMap: [String: SteamWorkshopWebPropertyValue]
    let resolvedLocalizationMap: [String: String]
    let hostCapabilitySnapshot: ResolvedWebHostCapabilitySnapshot
    let staticContentSummary: ResolvedWebStaticContentSummary
    let runtimeRiskFlags: [ResolvedWebRuntimeRiskFlag]
}

enum ResolvedWebRuntimeRiskFlag: String, Codable, Equatable, Hashable {
    case highLoadStructure
    case externalServiceDependency
    case localhostDependency
    case webMHeavyMedia
    case hoverOnlyInteraction
    case persistentBrowserStorageUsage
    case pluginBridgeApproximation
    case unsupportedDisplayConditionFallback
    case incompleteLocalizationTokens
    case implicitFractionalSliderPrecision
    case knownSafariBaselineIncompatibility
    case missingAccessibleFileBinding
    case missingAccessibleDirectoryBinding
    case serviceWorkerRegistration
    case esModuleDependency
    case dynamicImportUsage
    case wasmUsage
    case wasmStreamingUsage
    case customSchemeSensitiveWebGL
    case iframeCrossFrameAccess
    case truncatedStaticAnalysis

    var displayName: String {
        switch self {
        case .highLoadStructure:
            return String(localized: "High-Load Structure")
        case .externalServiceDependency:
            return String(localized: "External Service Dependencies")
        case .localhostDependency:
            return String(localized: "Local Service Dependency")
        case .webMHeavyMedia:
            return String(localized: "WebM Media Risk")
        case .hoverOnlyInteraction:
            return String(localized: "Hover Interaction Risk")
        case .persistentBrowserStorageUsage:
            return String(localized: "Persistent Storage Dependency")
        case .pluginBridgeApproximation:
            return String(localized: "Plugin/RGB Placeholder Compatibility")
        case .unsupportedDisplayConditionFallback:
            return String(localized: "Display Condition Fallback")
        case .incompleteLocalizationTokens:
            return String(localized: "Incomplete Localization")
        case .implicitFractionalSliderPrecision:
            return String(localized: "Fractional Slider Default Precision")
        case .knownSafariBaselineIncompatibility:
            return String(localized: "Suspicious Safari Baseline")
        case .missingAccessibleFileBinding:
            return String(localized: "No accessible file")
        case .missingAccessibleDirectoryBinding:
            return String(localized: "No accessible folder")
        case .serviceWorkerRegistration:
            return String(localized: "Service Worker Dependency")
        case .esModuleDependency:
            return String(localized: "ES Module Dependency")
        case .dynamicImportUsage:
            return String(localized: "Dynamic Import Dependency")
        case .wasmUsage:
            return String(localized: "WASM Dependency")
        case .wasmStreamingUsage:
            return String(localized: "WASM Streaming Dependency")
        case .customSchemeSensitiveWebGL:
            return String(localized: "WebGL/Texture Origin Sensitivity")
        case .iframeCrossFrameAccess:
            return String(localized: "Cross-Frame DOM Access via iframe")
        case .truncatedStaticAnalysis:
            return String(localized: "Large Script Static Analysis Truncated")
        }
    }
}

/// 纯数据值：由运行时缓存的后台解析段构造并跨执行器返回，不随
/// default-MainActor 隔离。
nonisolated struct ResolvedWebPlaybackContext: Equatable {
    let recordID: String
    let effectiveEntryURL: URL
    let effectiveRootURL: URL
    let propertyPayloadJSON: String?
    let language: String
    let resourceGrants: [WebWallpaperResourceGrant]
    let allowedNetworkHosts: Set<String>

    init(recordID: String, effectiveEntryURL: URL, effectiveRootURL: URL,
         propertyPayloadJSON: String?, language: String, resourceGrants: [WebWallpaperResourceGrant] = [],
         allowedNetworkHosts: Set<String> = []) {
        self.recordID = recordID
        self.effectiveEntryURL = effectiveEntryURL
        self.effectiveRootURL = effectiveRootURL
        self.propertyPayloadJSON = propertyPayloadJSON
        self.language = language
        self.resourceGrants = resourceGrants
        self.allowedNetworkHosts = allowedNetworkHosts
    }
}

/// Playback and profile selection consume the same prepared descriptor.
@MainActor struct ResolvedWebPlaybackPreparation {
    let context: ResolvedWebPlaybackContext
    let descriptor: ResolvedWebProjectDescriptor
    let resourceLifetime: PlaybackResourceLifetime?
}

enum ResolvedWebResourceBindingKind: String, Codable, Equatable, Hashable {
    case file
    case directory
    case pathlikePreset
}

enum ResolvedWebResourceBindingSource: String, Codable, Equatable, Hashable {
    case bookmarkedOverride
    case absolutePath
    case shellRoot
    case hostRoot
    case recordFolder
    case unresolved
}

enum ResolvedWebResourceBindingOrigin: String, Codable, Equatable, Hashable {
    case propertyDefinition
    case presetFallback
}

struct ResolvedWebResourceBinding: Codable, Equatable, Hashable {
    let key: String
    let rawValue: String
    let kind: ResolvedWebResourceBindingKind
    let fileType: String?
    let resolvedURL: URL?
    let source: ResolvedWebResourceBindingSource
    let origin: ResolvedWebResourceBindingOrigin

    var resolvedPath: String? {
        resolvedURL?.path
    }
}
