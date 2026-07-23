import Foundation

struct SceneProject {
    let rootURL: URL
    let projectFileURL: URL
    let entryPath: String
    let packageURL: URL?
    let title: String?
    let supportsAudioProcessing: Bool
    let userProperties: SceneUserPropertyCatalog

    nonisolated var entryURL: URL {
        rootURL.appendingPathComponent(entryPath)
    }
}

struct SceneProjectLoader {
    enum LoadError: LocalizedError {
        case missingProjectFile(URL)
        case invalidProjectJSON(URL)
        case notSceneProject

        var errorDescription: String? {
            switch self {
            case let .missingProjectFile(url):
                return "缺少 Scene project.json：\(url.path)"
            case let .invalidProjectJSON(url):
                return "无法解析 Scene project.json：\(url.path)"
            case .notSceneProject:
                return "project.json 未声明 scene 类型。"
            }
        }
    }

    func load(from rootURL: URL) throws -> SceneProject {
        let projectFileURL = rootURL.appendingPathComponent("project.json")
        guard FileManager.default.fileExists(atPath: projectFileURL.path) else {
            throw LoadError.missingProjectFile(projectFileURL)
        }
        guard let data = try? Data(contentsOf: projectFileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError.invalidProjectJSON(projectFileURL)
        }

        let type = (root["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        guard type == "scene" else {
            throw LoadError.notSceneProject
        }

        let entryPath = (root["file"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let general = root["general"] as? [String: Any]
        let resolvedEntryPath = entryPath.flatMap { $0.isEmpty ? nil : $0 } ?? "scene.json"

        return SceneProject(
            rootURL: rootURL,
            projectFileURL: projectFileURL,
            entryPath: resolvedEntryPath,
            packageURL: SceneProjectLoader.scenePackageURL(
                in: rootURL,
                entryPath: resolvedEntryPath
            ),
            title: root["title"] as? String,
            supportsAudioProcessing: general?["supportsaudioprocessing"] as? Bool ?? false,
            userProperties: SceneUserPropertyDefinitionParser().parse(projectRoot: root)
        )
    }

    static func scenePackageURL(in rootURL: URL, entryPath: String) -> URL? {
        let entryFileName = (entryPath as NSString).lastPathComponent
        let entryBaseName = (entryFileName as NSString).deletingPathExtension
        let derivedPackageName = entryBaseName.isEmpty ? "scene.pkg" : "\(entryBaseName).pkg"
        let packageNames = derivedPackageName == "scene.pkg"
            ? [derivedPackageName]
            : [derivedPackageName, "scene.pkg"]
        return packageNames
            .map(rootURL.appendingPathComponent)
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
