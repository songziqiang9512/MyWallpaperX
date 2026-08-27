import Foundation

/// Stable identity and optional launch-time export for generic shader compiler
/// requests. The cache and compiler share this exact source-keyed contract.
nonisolated enum SceneResolvedMaterialGenericShaderRequest {
    private struct Envelope: Encodable {
        struct Stage: Encodable {
            let stage: String
            let entryPoint: String
            let source: String
        }

        let schemaVersion = 5
        let requestID: String
        let sourceDialect = "wallpaper-engine-glsl-like-v0"
        let outputSemantics: SceneGenericShaderOutputSemantics
        let expectedColorTransfer: SceneGenericShaderExpectedColorTransfer?
        let premultipliedColorInputSlots: [Int]
        let defines: [String: Int] = [:]
        let stages: [Stage]
    }

    private static let exportEnvironment =
        "MWX_SCENE_GENERIC_SHADER_REQUESTS"

    static func key(
        vertexSource: String,
        fragmentSource: String,
        outputSemantics: SceneGenericShaderOutputSemantics,
        expectedColorTransfer: SceneGenericShaderExpectedColorTransfer?,
        premultipliedColorInputSlots: Set<Int>
    ) -> String {
        var data = Data()
        for value in [
            "mwx-generic-shader-request-v10",
            "wallpaper-engine-glsl-like-v0",
            outputSemantics.rawValue,
            vertexSource,
            fragmentSource,
            expectedColorTransfer?.cacheKey ?? "-",
            premultipliedColorInputSlots.sorted().map(String.init)
                .joined(separator: ","),
            "{}",
        ] {
            let encoded = Data(value.utf8)
            var length = UInt64(encoded.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(encoded)
        }
        return SceneGenericShaderProgramArtifact.sha256(data)
    }

    static func export(
        key: String,
        vertexSource: String,
        fragmentSource: String,
        outputSemantics: SceneGenericShaderOutputSemantics,
        expectedColorTransfer: SceneGenericShaderExpectedColorTransfer?,
        premultipliedColorInputSlots: Set<Int>
    ) {
        let environment = ProcessInfo.processInfo.environment
        guard let rawRoot = environment[exportEnvironment],
              let root = validatedDirectory(rawRoot) else { return }
        let request = Envelope(
            requestID: key,
            outputSemantics: outputSemantics,
            expectedColorTransfer: expectedColorTransfer,
            premultipliedColorInputSlots: premultipliedColorInputSlots.sorted(),
            stages: [
                .init(stage: "vertex", entryPoint: "main", source: vertexSource),
                .init(stage: "fragment", entryPoint: "main", source: fragmentSource),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(request) else { return }
        let url = root.appendingPathComponent("\(key).json", isDirectory: false)
        if let existing = try? Data(contentsOf: url) {
            if existing != data {
                NSLog("MWX generic shader request collision request=%@", key)
            }
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            NSLog("MWX generic shader request exported request=%@", key)
        } catch {
            NSLog("MWX generic shader request export failed request=%@", key)
        }
    }

    private static func validatedDirectory(_ rawPath: String) -> URL? {
        guard !rawPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            return nil
        }
        return url
    }
}
