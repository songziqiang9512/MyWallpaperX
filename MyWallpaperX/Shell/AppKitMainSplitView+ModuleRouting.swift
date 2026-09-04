import Foundation

extension AppKitMainSplitViewController {
    func moduleIdentifier(for item: SelectedItem) -> ModuleIdentifier {
        switch item {
        case .staticImageLibrary, .silTag:
            return .staticImageLibrary
        case .onlineLibrary, .onlineDownloads:
            return .onlineLibrary
        case .steamWorkshop, .steamSubscribed, .steamDownloads:
            return .steamWorkshop
        default:
            return .videoLibrary
        }
    }
}
