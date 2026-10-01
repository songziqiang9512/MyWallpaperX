import Foundation

extension SteamWorkshopService {
    nonisolated static func resolveSceneContentType(
        project: SteamWorkshopProject?,
        directory: URL?,
        browserItem: SteamWorkshopBrowserItem?
    ) -> SteamWorkshopDownloadContentType? {
        let projectType = project?.type?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        if projectType == "scene" {
            return .scene
        }

        let declaredEntry = project?.file?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .localizedLowercase
        if declaredEntry == "scene.json" {
            return .scene
        }

        if let directory,
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("scene.pkg").path) {
            return .scene
        }

        if browserItem?.workshopTypeText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Scene") == .orderedSame {
            return .scene
        }

        return nil
    }
}
