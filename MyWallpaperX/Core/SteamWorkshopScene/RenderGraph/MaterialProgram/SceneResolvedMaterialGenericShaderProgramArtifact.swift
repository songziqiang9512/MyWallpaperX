import CryptoKit
import Foundation

/// Source-keyed compiler output shared by the product preparation worker and
/// the independent cache reader. Decoding this value never grants execution;
/// `makeProgram` revalidates every ABI and color contract before publication.
nonisolated struct SceneGenericShaderProgramArtifact: Codable {
    struct Program: Codable {
        struct UniformLayout: Codable, Equatable {
            struct Field: Codable, Equatable {
                let name: String
                let authoredName: String
                let type: String
                let offset: Int
                let arrayCount: Int?

                init(
                    name: String,
                    authoredName: String,
                    type: String,
                    offset: Int,
                    arrayCount: Int? = nil
                ) {
                    self.name = name
                    self.authoredName = authoredName
                    self.type = type
                    self.offset = offset
                    self.arrayCount = arrayCount
                }
            }

            let fields: [Field]
            let byteSize: Int
        }

        struct TextureBinding: Codable {
            let name: String
            let slot: Int
            let channelUse: String
        }

        struct ColorTransfer: Codable {
            let kind: String
            let slot: Int?
            let slots: [Int]?
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
        let fragmentOutputChannelUse: String
    }

    let schemaVersion: Int
    let kind: String
    let backendID: String
    let requestKey: String
    let program: Program

    init(backendID: String, requestKey: String, program: Program) {
        schemaVersion = 3
        kind = "scene-generic-shader-program-artifact"
        self.backendID = backendID
        self.requestKey = requestKey
        self.program = program
    }

    func makeProgram(
        expectedKey: String,
        expectedColorTransfer: SceneShaderColorTransfer,
        expectedFragmentOutputChannelUse:
            SceneAuthoredShaderProgram.FragmentOutputChannelUse
    ) -> SceneAuthoredShaderProgram? {
        guard schemaVersion == 3,
              kind == "scene-generic-shader-program-artifact",
              backendID == "glslang-spirv-cross-msl-v1",
              requestKey == expectedKey else { return nil }
        let raw = program
        guard raw.vertexFunctionName == "mwxGenericVertex",
              raw.fragmentFunctionName == "mwxGenericFragment",
              raw.uniformBufferIndex == 8,
              (0 ... 256).contains(raw.staticLoopWork),
              !raw.metalSource.isEmpty,
              raw.metalSource.utf8.count <= 1_024 * 1_024,
              Self.sha256(Data(raw.metalSource.utf8)) == raw.metalSourceSHA256 else {
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
              Self.valid(layout),
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
              Set(bindings.map(\.slot)).count == bindings.count else { return nil }
        let colorTransfer: SceneShaderColorTransfer
        switch (raw.colorTransfer.kind, raw.colorTransfer.slot, raw.colorTransfer.slots) {
        case let ("passthrough", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .passthrough(textureSlot: slot)
        case let ("interpolated-color", nil, slots?):
            guard slots.count >= 2,
                  slots.count <= 8,
                  slots == slots.sorted(),
                  Set(slots).count == slots.count,
                  slots.allSatisfy({ slot in
                      bindings.contains(where: { $0.slot == slot })
                  }) else { return nil }
            colorTransfer = .interpolatedColor(textureSlots: slots)
        case ("opaque", nil, nil):
            colorTransfer = .opaque
        case ("premultiplied", nil, nil):
            colorTransfer = .premultipliedAlpha
        case let ("straight-alpha", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .straightAlpha(textureSlot: slot)
        case let ("straight-alpha-preserving", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .straightAlphaPreserving(textureSlot: slot)
        default:
            return nil
        }
        guard expectedColorTransfer == .unresolved
                || colorTransfer == expectedColorTransfer else {
            return nil
        }
        guard let fragmentOutputChannelUse =
                SceneAuthoredShaderProgram.FragmentOutputChannelUse(
                    rawValue: raw.fragmentOutputChannelUse
                ) else {
            return nil
        }
        // The producer may conservatively decline to prove this fact. The
        // current Swift source analyzer owns any promotion used by Program.
        guard fragmentOutputChannelUse == .unproven
                || expectedFragmentOutputChannelUse == .redDefined else {
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
            fragmentOutputChannelUse: expectedFragmentOutputChannelUse,
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

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
