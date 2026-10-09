import Foundation

struct ResolvedWebHostCapabilitySnapshot: Codable, Equatable {
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

struct ResolvedWebStaticContentSummary: Codable, Equatable {
    let usesApplyGeneralProperties: Bool
    let usesGeneralFPS: Bool
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

    enum CodingKeys: String, CodingKey {
        case usesApplyGeneralProperties
        case usesGeneralFPS
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
        usesApplyGeneralProperties: Bool,
        usesGeneralFPS: Bool,
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
        self.usesApplyGeneralProperties = usesApplyGeneralProperties
        self.usesGeneralFPS = usesGeneralFPS
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
            usesApplyGeneralProperties: try container.decode(Bool.self, forKey: .usesApplyGeneralProperties),
            usesGeneralFPS: try container.decode(Bool.self, forKey: .usesGeneralFPS),
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
    let presetResourceBindingsByKey: [String: ResolvedWebResourceBinding]
    let baselineVisiblePropertyKeys: [String]
    let baselineVisibleOptionsByKey: [String: [SteamWorkshopWebPropertyOption]]
    let baselinePreconditionStates: [ResolvedWebRuntimePrecondition]
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
            return "高负载结构"
        case .externalServiceDependency:
            return "外部服务依赖"
        case .localhostDependency:
            return "本地服务依赖"
        case .webMHeavyMedia:
            return "WebM 媒体风险"
        case .hoverOnlyInteraction:
            return "Hover 交互风险"
        case .persistentBrowserStorageUsage:
            return "持久化存储依赖"
        case .pluginBridgeApproximation:
            return "Plugin/RGB 占位兼容"
        case .unsupportedDisplayConditionFallback:
            return "Display Condition 回退"
        case .incompleteLocalizationTokens:
            return "Localization 不完整"
        case .implicitFractionalSliderPrecision:
            return "Fractional Slider 默认精度"
        case .knownSafariBaselineIncompatibility:
            return "Safari 基线可疑"
        case .missingAccessibleFileBinding:
            return "缺少可访问文件"
        case .missingAccessibleDirectoryBinding:
            return "缺少可访问目录"
        case .serviceWorkerRegistration:
            return "Service Worker 依赖"
        case .esModuleDependency:
            return "ES Module 依赖"
        case .dynamicImportUsage:
            return "动态 import 依赖"
        case .wasmUsage:
            return "WASM 依赖"
        case .wasmStreamingUsage:
            return "WASM Streaming 依赖"
        case .customSchemeSensitiveWebGL:
            return "WebGL/纹理 Origin 敏感"
        case .iframeCrossFrameAccess:
            return "iframe 跨 frame DOM 访问"
        case .truncatedStaticAnalysis:
            return "大型脚本静态分析截断"
        }
    }
}

struct ResolvedWebRuntimeDiagnosticsSnapshot: Equatable {
    let recordID: String
    let entryRelativePath: String
    let entryPath: String
    let rootPath: String
    let propertySource: String
    let sourceKind: String
    let entrySource: String
    let sampleStructure: String
    let presetOverrideCount: Int
    let visiblePropertyCount: Int
    let validationIssueCount: Int
    let propertyPayloadSize: Int
    let unmetPreconditionMessages: [String]
    let runtimeRiskFlags: [ResolvedWebRuntimeRiskFlag]
    let lastPlaybackFailureMessage: String?
    let isActivePlayback: Bool
}

/// 纯数据值：由运行时缓存的后台解析段构造并跨执行器返回，不随
/// default-MainActor 隔离。
nonisolated struct ResolvedWebPlaybackContext: Equatable {
    let recordID: String
    let effectiveEntryURL: URL
    let effectiveRootURL: URL
    let propertyPayloadJSON: String?
    let language: String
}

struct ResolvedWebRuntimePrecondition: Codable, Equatable, Hashable {
    enum Kind: String, Codable, Equatable, Hashable {
        case file
        case directory
    }

    enum Status: String, Codable, Equatable, Hashable {
        case satisfied
        case unmet
    }

    let key: String
    let kind: Kind
    let status: Status
    let message: String
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

struct ResolvedWebRuntimeModel: Equatable {
    let recordID: String
    let descriptor: ResolvedWebProjectDescriptor
    let resolvedLanguage: String
    let effectiveEntryURL: URL
    let effectiveRootURL: URL
    let defaultValues: [String: SteamWorkshopWebPropertyValue]
    let presetOverrides: [String: SteamWorkshopWebPropertyValue]
    let userOverrides: [String: SteamWorkshopWebPropertyValue]
    let resolvedRuntimeValues: [String: SteamWorkshopWebPropertyValue]
    let resourceBindings: [String: ResolvedWebResourceBinding]
    let fallbackResourceKeys: [String]
    let visiblePropertyKeys: [String]
    let visibleOptionsByKey: [String: [SteamWorkshopWebPropertyOption]]
    let propertyPayloadJSON: String?
    let validationReport: SteamWorkshopWebValidationReport?
    let preconditionStates: [ResolvedWebRuntimePrecondition]
    let runtimeRiskFlags: [ResolvedWebRuntimeRiskFlag]
    let lastPlaybackFailureMessage: String?
    let lastPlaybackFailureIssue: SteamWorkshopWebValidationIssue?
    let diagnosticsSnapshot: ResolvedWebRuntimeDiagnosticsSnapshot
}
