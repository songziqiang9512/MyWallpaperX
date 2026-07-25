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
    let propertyBindingProgram: ScenePropertyBindingProgram
    let effectivePropertyValues: [String: SceneUserPropertyValue]
    let shaderContracts: [SceneShaderContract]
}

struct SceneInterpretationFileWriter {
    // Format 28 adds the authored text layer `anchor` (screen anchor).
    static let currentFormatVersion = 28

    func make(
        renderDescriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        effectivePropertyValues: [String: SceneUserPropertyValue],
        shaderContracts: [SceneShaderContract],
        generatedAt: Date = Date()
    ) -> SceneInterpretationFile {
        SceneInterpretationFile(
            formatVersion: Self.currentFormatVersion,
            generatedAt: generatedAt,
            sourceEntryPath: renderDescriptor.entryPath,
            renderDescriptor: renderDescriptor,
            authoredEffectRenderPlans: SceneAuthoredEffectRenderPlanner.plans(
                for: renderDescriptor
            ),
            propertyBindingProgram: propertyBindingProgram,
            effectivePropertyValues: effectivePropertyValues,
            shaderContracts: shaderContracts
        )
    }

    func write(
        renderDescriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        effectivePropertyValues: [String: SceneUserPropertyValue],
        shaderContracts: [SceneShaderContract],
        outputDirectory: URL
    ) throws -> URL {
        let file = make(
            renderDescriptor: renderDescriptor,
            propertyBindingProgram: propertyBindingProgram,
            effectivePropertyValues: effectivePropertyValues,
            shaderContracts: shaderContracts
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
        let header = try decoder.decode(FormatHeader.self, from: data)
        guard header.formatVersion == SceneInterpretationFileWriter.currentFormatVersion else {
            throw SceneInterpretationFileError.unsupportedFormatVersion(header.formatVersion)
        }
        return try decoder.decode(SceneInterpretationFile.self, from: data)
    }

    private struct FormatHeader: Decodable {
        let formatVersion: Int
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
