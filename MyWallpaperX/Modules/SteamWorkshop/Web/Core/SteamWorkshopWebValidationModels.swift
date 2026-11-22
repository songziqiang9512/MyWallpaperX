import Foundation


nonisolated enum SteamWorkshopWebSampleStructure: String, Codable, Equatable, Hashable {
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
            return String(localized: "Dependency Shell Sample")
        case .spineWebCharacter:
            return String(localized: "Spine Character Wallpaper")
        case .shaderOrCanvasWeb:
            return String(localized: "Shader / Canvas Wallpaper")
        case .multimediaDashboardWeb:
            return String(localized: "Multimedia Dashboard Wallpaper")
        case .megaConfigDashboardWeb:
            return String(localized: "Large Config Dashboard Wallpaper")
        case .propertyDrivenHTMLWeb:
            return String(localized: "Property-Driven HTML Wallpaper")
        case .basicHTMLWeb:
            return String(localized: "Basic HTML Wallpaper")
        }
    }
}


nonisolated enum SteamWorkshopWebDependencyStatus: Equatable, Codable {
    case none
    case available(itemID: String)
    case missing(itemID: String)
}
