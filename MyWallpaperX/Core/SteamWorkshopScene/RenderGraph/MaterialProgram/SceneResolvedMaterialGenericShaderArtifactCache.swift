import CryptoKit
import Foundation

/// Development-gated preparation cache for Program artifacts produced by the
/// separately killable shader compiler harness. No compiler runs in the App.
nonisolated enum SceneResolvedMaterialGenericShaderArtifactCache {
    enum Resolution {
        case accepted(program: SceneAuthoredShaderProgram, requestKey: String)
        case unavailable(code: String, requestKey: String)
    }

    private struct Request: Encodable {
        struct Stage: Encodable {
            let stage: String
            let entryPoint: String
            let source: String
        }

        let schemaVersion = 1
        let requestID: String
        let sourceDialect = "wallpaper-engine-glsl-like-v0"
        let defines: [String: Int] = [:]
        let stages: [Stage]
    }

    private struct Artifact: Decodable {
        struct Program: Decodable {
            struct UniformLayout: Decodable {
                struct Field: Decodable {
                    let name: String
                    let authoredName: String
                    let type: String
                    let offset: Int
                    let arrayCount: Int?
                }

                let fields: [Field]
                let byteSize: Int
            }

            struct TextureBinding: Decodable {
                let name: String
                let slot: Int
                let channelUse: String
            }

            struct ColorTransfer: Decodable {
                let kind: String
                let slot: Int?
            }

            let metalSource: String
            let metalSourceSHA256: String
            let vertexFunctionName: String
            let fragmentFunctionName: String
            let uniformBufferIndex: Int
            let uniformLayout: UniformLayout
            let textureBindings: [TextureBinding]
            let staticLoopWork: Int
            let colorTransfer: ColorTransfer
        }

        let schemaVersion: Int
        let kind: String
        let backendID: String
        let requestKey: String
        let routeState: String
        let program: Program
    }

    private static let routeEnvironment = "MWX_SCENE_GENERIC_SHADER_ROUTE"
    private static let cacheEnvironment = "MWX_SCENE_GENERIC_SHADER_CACHE"
    private static let requestEnvironment = "MWX_SCENE_GENERIC_SHADER_REQUESTS"
    private static let maximumArtifactBytes = 2 * 1_024 * 1_024
    private static let routeTelemetry = RouteTelemetry()

    private final class RouteTelemetry: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var executedIdentities = Set<String>()

        func record(outcome: String, reason: String, requestKey: String) {
            let count = lock.withLock {
                let identity = "\(outcome):\(reason)"
                let updated = counts[identity, default: 0] + 1
                counts[identity] = updated
                return updated
            }
            NSLog(
                "MWX generic shader route state=prefer-generic outcome=%@ reason=%@ request=%@ count=%d",
                outcome,
                reason,
                requestKey,
                count
            )
        }

        func recordExecution(
            backend: SceneAuthoredShaderProgram.Backend,
            layerID: Int,
            effectIndex: Int,
            descriptorID: String,
            nodeIndex: Int,
            preparedKey: String
        ) {
            let identity = [
                String(layerID), String(effectIndex), descriptorID,
                String(nodeIndex), backend.rawValue, preparedKey,
            ].joined(separator: "|")
            guard lock.withLock({ executedIdentities.insert(identity).inserted }) else {
                return
            }
            NSLog(
                "MWX generic shader execution state=prefer-generic layer=%d effect=%d descriptor=%@ node=%d backend=%@ prepared=%@",
                layerID,
                effectIndex,
                descriptorID,
                nodeIndex,
                backend.rawValue,
                preparedKey
            )
        }
    }

    static func resolve(
        vertexSource: String,
        fragmentSource: String
    ) -> Resolution {
        let key = requestKey(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource
        )
        exportRequest(
            key: key,
            vertexSource: vertexSource,
            fragmentSource: fragmentSource
        )
        let environment = ProcessInfo.processInfo.environment
        guard environment[routeEnvironment] == "prefer-generic" else {
            return .unavailable(code: "route-observe-only", requestKey: key)
        }
        guard let rawRoot = environment[cacheEnvironment],
              let root = validatedDirectory(rawRoot) else {
            return fallback(code: "cache-unavailable", requestKey: key)
        }
        let artifactURL = root.appendingPathComponent("\(key).json", isDirectory: false)
        guard let data = regularFileData(artifactURL) else {
            return fallback(code: "artifact-missing", requestKey: key)
        }
        let artifact: Artifact
        do {
            artifact = try JSONDecoder().decode(Artifact.self, from: data)
        } catch {
            return fallback(code: "artifact-invalid-json", requestKey: key)
        }
        guard let program = program(artifact, expectedKey: key) else {
            return fallback(code: "artifact-contract-rejected", requestKey: key)
        }
        routeTelemetry.record(outcome: "accepted", reason: "-", requestKey: key)
        return .accepted(program: program, requestKey: key)
    }

    private static func fallback(code: String, requestKey: String) -> Resolution {
        routeTelemetry.record(outcome: "fallback", reason: code, requestKey: requestKey)
        return .unavailable(code: code, requestKey: requestKey)
    }

    static func recordExecution(
        backend: SceneAuthoredShaderProgram.Backend,
        layerID: Int,
        effectIndex: Int,
        descriptorID: String,
        nodeIndex: Int,
        preparedKey: String
    ) {
        guard ProcessInfo.processInfo.environment[routeEnvironment] == "prefer-generic"
        else { return }
        routeTelemetry.recordExecution(
            backend: backend,
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: descriptorID,
            nodeIndex: nodeIndex,
            preparedKey: preparedKey
        )
    }

    private static func program(
        _ artifact: Artifact,
        expectedKey: String
    ) -> SceneAuthoredShaderProgram? {
        guard artifact.schemaVersion == 1,
              artifact.kind == "scene-generic-shader-program-artifact",
              artifact.backendID == "glslang-spirv-cross-msl-v1",
              artifact.requestKey == expectedKey,
              artifact.routeState == "prefer-generic" else { return nil }
        let raw = artifact.program
        guard raw.vertexFunctionName == "mwxGenericVertex",
              raw.fragmentFunctionName == "mwxGenericFragment",
              raw.uniformBufferIndex == 8,
              (0 ... 256).contains(raw.staticLoopWork),
              !raw.metalSource.isEmpty,
              raw.metalSource.utf8.count <= 1_024 * 1_024,
              sha256(Data(raw.metalSource.utf8)) == raw.metalSourceSHA256 else {
            return nil
        }
        let fields = raw.uniformLayout.fields.compactMap { field ->
            SceneAuthoredShaderUniformLayout.Field? in
            guard let type = SceneAuthoredShaderValueType(rawValue: field.type) else {
                return nil
            }
            return .init(
                name: field.name,
                authoredName: field.authoredName,
                stage: nil,
                type: type,
                arrayCount: field.arrayCount,
                offset: field.offset
            )
        }
        let layout = SceneAuthoredShaderUniformLayout(
            fields: fields,
            byteSize: raw.uniformLayout.byteSize
        )
        guard fields.count == raw.uniformLayout.fields.count,
              valid(layout),
              fields.contains(where: {
                  $0.name == "mwxRenderSize" && $0.type == .float2
              }) else { return nil }
        let bindings = raw.textureBindings.compactMap { binding ->
            SceneAuthoredShaderProgram.TextureBinding? in
            guard binding.name == "g_Texture\(binding.slot)",
                  (0 ..< 8).contains(binding.slot),
                  let channelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse(
                      rawValue: binding.channelUse
                  ) else { return nil }
            return .init(name: binding.name, slot: binding.slot, channelUse: channelUse)
        }
        guard bindings.count == raw.textureBindings.count,
              bindings.map(\.slot) == bindings.map(\.slot).sorted(),
              Set(bindings.map(\.slot)).count == bindings.count else {
            return nil
        }
        let colorTransfer: SceneShaderColorTransfer
        switch (raw.colorTransfer.kind, raw.colorTransfer.slot) {
        case let ("passthrough", slot?):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .passthrough(textureSlot: slot)
        case ("opaque", nil):
            colorTransfer = .opaque
        case ("premultiplied", nil):
            colorTransfer = .premultipliedAlpha
        case let ("straight-alpha", slot?):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .straightAlpha(textureSlot: slot)
        default:
            return nil
        }
        return .init(
            metalSource: raw.metalSource,
            vertexFunctionName: raw.vertexFunctionName,
            fragmentFunctionName: raw.fragmentFunctionName,
            uniformBufferIndex: raw.uniformBufferIndex,
            uniformLayout: layout,
            textureBindings: bindings,
            staticLoopWork: raw.staticLoopWork,
            colorTransfer: colorTransfer,
            backend: .genericCompilerArtifact
        )
    }

    private static func valid(_ layout: SceneAuthoredShaderUniformLayout) -> Bool {
        guard (0 ... 4_096).contains(layout.byteSize),
              layout.byteSize.isMultiple(of: 16),
              Set(layout.fields.map(\.name)).count == layout.fields.count else {
            return false
        }
        var occupied = Set<Int>()
        for field in layout.fields {
            let end = field.offset + field.storageByteSize
            guard field.offset >= 0,
                  field.offset.isMultiple(of: field.type.alignment),
                  end <= layout.byteSize,
                  (field.offset ..< end).allSatisfy({ !occupied.contains($0) }) else {
                return false
            }
            occupied.formUnion(field.offset ..< end)
        }
        return true
    }

    private static func requestKey(
        vertexSource: String,
        fragmentSource: String
    ) -> String {
        var data = Data()
        for value in [
            "mwx-generic-shader-request-v1",
            "wallpaper-engine-glsl-like-v0",
            vertexSource,
            fragmentSource,
            "{}",
        ] {
            let encoded = Data(value.utf8)
            var length = UInt64(encoded.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(encoded)
        }
        return sha256(data)
    }

    private static func exportRequest(
        key: String,
        vertexSource: String,
        fragmentSource: String
    ) {
        let environment = ProcessInfo.processInfo.environment
        guard let rawRoot = environment[requestEnvironment],
              let root = validatedDirectory(rawRoot) else { return }
        let request = Request(
            requestID: key,
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

    private static func regularFileData(_ url: URL) -> Data? {
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let size = values?.fileSize,
              (1 ... maximumArtifactBytes).contains(size) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
