import Foundation


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


nonisolated enum SteamWorkshopWebDependencyStatus: Equatable {
    case none
    case available(itemID: String)
    case missing(itemID: String)
}
