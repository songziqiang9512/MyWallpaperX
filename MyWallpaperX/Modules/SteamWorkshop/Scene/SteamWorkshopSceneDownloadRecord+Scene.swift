import Foundation

extension SteamWorkshopDownloadRecord {
    var scenePackageURL: URL? {
        if let project = try? SceneProjectLoader().load(from: folderURL) {
            return project.packageURL
        }
        return SceneProjectLoader.scenePackageURL(in: folderURL, entryPath: "scene.json")
    }

    var isSceneLaunchable: Bool {
        status == .ready && contentType == .scene && scenePackageURL != nil
    }
}
