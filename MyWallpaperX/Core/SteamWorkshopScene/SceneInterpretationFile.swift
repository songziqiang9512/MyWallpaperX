import Foundation

struct SceneInterpretationFile: Codable {
    // Cache-owned renderer input. Workshop samples remain read-only; deleting the
    // package cache causes SceneDiagnosticsBuilder to regenerate this file.
    static let fileName = ".mywallpaperx-scene-interpretation.json"

    let formatVersion: Int
    let generatedAt: Date
    let sourceEntryPath: String
    let renderDescriptor: SceneRenderDescriptor
    let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
}

struct SceneInterpretationFileWriter {
    // Format 17 preserves material user-texture providers and typed runtime references.
    static let currentFormatVersion = 17

    func write(
        renderDescriptor: SceneRenderDescriptor,
        outputDirectory: URL
    ) throws -> URL {
        let file = SceneInterpretationFile(
            formatVersion: Self.currentFormatVersion,
            generatedAt: Date(),
            sourceEntryPath: renderDescriptor.entryPath,
            renderDescriptor: renderDescriptor,
            authoredEffectRenderPlans: SceneAuthoredEffectRenderPlanner.plans(
                for: renderDescriptor
            )
        )
        let outputURL = outputDirectory.appendingPathComponent(SceneInterpretationFile.fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: [.atomic])
        return outputURL
    }
}

struct SceneInterpretationFileReader {
    func read(from url: URL) throws -> SceneInterpretationFile {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(SceneInterpretationFile.self, from: data)

        guard file.formatVersion == SceneInterpretationFileWriter.currentFormatVersion else {
            throw SceneInterpretationFileError.unsupportedFormatVersion(file.formatVersion)
        }

        return file
    }
}

enum SceneInterpretationFileError: LocalizedError {
    case unsupportedFormatVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            "不支持的 Scene 派生解释文件版本：\(version)"
        }
    }
}
