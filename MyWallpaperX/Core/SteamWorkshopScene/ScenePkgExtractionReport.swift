import Foundation

struct ScenePkgExtractionReport {
    enum Status: Equatable {
        case notNeeded
        case indexed
        case extracted
        case missingPackage
        case toolUnavailable
        case failed(String)
    }

    let packageURL: URL?
    let outputURL: URL?
    let status: Status
    let discoveredPaths: [String]
    let packageIndex: ScenePkgIndex?

    var blockingMessage: String? {
        switch status {
        case .notNeeded, .indexed, .extracted:
            return nil
        case .missingPackage:
            return "未找到 Scene 资源包。"
        case .toolUnavailable:
            return "未找到可用的 Scene 资源包解包工具。"
        case let .failed(message):
            return message
        }
    }
}

protocol ScenePkgExtracting {
    func extract(packageURL: URL, outputURL: URL) throws -> ScenePkgExtractionReport
}

struct ScenePkgExtractor: ScenePkgExtracting {
    enum ExtractError: LocalizedError {
        case missingTool

        var errorDescription: String? {
            switch self {
            case .missingTool:
                return "未配置 repkg 或兼容的 Scene 资源包解包工具。"
            }
        }
    }

    let toolURL: URL?

    init(toolURL: URL? = nil) {
        self.toolURL = toolURL
    }

    func extract(packageURL: URL, outputURL: URL) throws -> ScenePkgExtractionReport {
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            return ScenePkgExtractionReport(
                packageURL: packageURL,
                outputURL: outputURL,
                status: .missingPackage,
                discoveredPaths: [],
                packageIndex: nil
            )
        }

        guard let toolURL,
              FileManager.default.isExecutableFile(atPath: toolURL.path) else {
            do {
                let result = try ScenePkgCacheExtractor().extract(
                    packageURL: packageURL,
                    projectRootURL: packageURL.deletingLastPathComponent()
                )
                return ScenePkgExtractionReport(
                    packageURL: packageURL,
                    outputURL: result.outputURL,
                    status: .extracted,
                    discoveredPaths: result.extractedPaths,
                    packageIndex: result.index
                )
            } catch {
                return ScenePkgExtractionReport(
                    packageURL: packageURL,
                    outputURL: outputURL,
                    status: .failed(error.localizedDescription),
                    discoveredPaths: [],
                    packageIndex: nil
                )
            }
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) == false else {
            try? FileManager.default.removeItem(at: outputURL)
            return try extract(packageURL: packageURL, outputURL: outputURL)
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return ScenePkgExtractionReport(
                packageURL: packageURL,
                outputURL: outputURL,
                status: .failed(error.localizedDescription),
                discoveredPaths: [],
                packageIndex: nil
            )
        }

        let process = Process()
        process.executableURL = toolURL
        process.arguments = ["extract", packageURL.path, outputURL.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ScenePkgExtractionReport(
                packageURL: packageURL,
                outputURL: outputURL,
                status: .failed(error.localizedDescription),
                discoveredPaths: [],
                packageIndex: nil
            )
        }

        guard process.terminationStatus == 0 else {
            return ScenePkgExtractionReport(
                packageURL: packageURL,
                outputURL: outputURL,
                status: .failed("Scene 资源包解包工具退出码：\(process.terminationStatus)"),
                discoveredPaths: [],
                packageIndex: nil
            )
        }

        let index = SceneResourceIndexBuilder().build(rootURL: outputURL)
        let packageIndex = try? ScenePkgReader().readIndex(packageURL: packageURL)
        return ScenePkgExtractionReport(
            packageURL: packageURL,
            outputURL: outputURL,
            status: .extracted,
            discoveredPaths: index.resources.map(\.relativePath),
            packageIndex: packageIndex
        )
    }
}
