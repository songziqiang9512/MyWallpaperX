import Foundation

#if DEBUG
nonisolated enum SteamWorkshopWebValidationSeverity: String, Codable, Equatable, Hashable {
    case error
    case warning
    case info

    var displayName: String {
        switch self {
        case .error:
            return "错误"
        case .warning:
            return "警告"
        case .info:
            return "信息"
        }
    }
}

#endif

enum SteamWorkshopWebSampleStructure: String, Codable, Equatable, Hashable {
    case dependencyBackedShell
    case spineWebCharacter
    case shaderOrCanvasWeb
    case multimediaDashboardWeb
    case megaConfigDashboardWeb
    case propertyDrivenHTMLWeb
    case basicHTMLWeb

    var displayName: String {
        switch self {
        case .dependencyBackedShell:
            return "依赖壳样本"
        case .spineWebCharacter:
            return "Spine 角色壁纸"
        case .shaderOrCanvasWeb:
            return "Shader / Canvas 壁纸"
        case .multimediaDashboardWeb:
            return "多媒体面板壁纸"
        case .megaConfigDashboardWeb:
            return "大型配置面板壁纸"
        case .propertyDrivenHTMLWeb:
            return "属性驱动 HTML 壁纸"
        case .basicHTMLWeb:
            return "基础 HTML 壁纸"
        }
    }
}

#if DEBUG
nonisolated enum SteamWorkshopWebValidationLevel: String, Codable, Equatable, Hashable {
    case fatal
    case runtimeBlocking
    case warning
    case preconditionUnmet
    case info

    var displayName: String {
        switch self {
        case .fatal:
            return "致命问题"
        case .runtimeBlocking:
            return "运行阻断"
        case .warning:
            return "警告"
        case .preconditionUnmet:
            return "前置条件未满足"
        case .info:
            return "信息"
        }
    }

    var severity: SteamWorkshopWebValidationSeverity {
        switch self {
        case .fatal:
            return .error
        case .runtimeBlocking, .warning, .preconditionUnmet:
            return .warning
        case .info:
            return .info
        }
    }
}

struct SteamWorkshopWebValidationIssue: Identifiable, Codable, Equatable, Hashable {
    let severity: SteamWorkshopWebValidationSeverity
    let level: SteamWorkshopWebValidationLevel
    let message: String

    var id: String { "\(level.rawValue):\(severity.rawValue):\(message)" }
}

struct SteamWorkshopWebValidationReport: Codable, Equatable, Hashable {
    let sampleStructure: SteamWorkshopWebSampleStructure
    let entryRelativePath: String
    let scannedFileCount: Int
    let issueCount: Int
    let issues: [SteamWorkshopWebValidationIssue]
    let propertySource: SteamWorkshopWebPropertySource
    let presetOverrideCount: Int

    var fatalIssue: SteamWorkshopWebValidationIssue? {
        issues.first(where: { $0.level == .fatal })
    }

    var blockingIssue: SteamWorkshopWebValidationIssue? {
        issues.first(where: { $0.level == .fatal || $0.level == .runtimeBlocking })
    }
}

#endif

nonisolated enum SteamWorkshopWebDependencyStatus: Equatable {
    case none
    case available(itemID: String)
    case missing(itemID: String)
}
