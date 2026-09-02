import CryptoKit
import Foundation

/// Output ABI requested from the generic compiler. It is source-independent
/// and participates in the request key so color-lowered and raw-data Metal can
/// never share an artifact.
nonisolated enum SceneGenericShaderOutputSemantics:
    String, Codable, Hashable, Sendable
{
    case color
    case redGreenUnorm = "red-green-unorm"
    case preservedRGBAUnorm = "preserved-rgba-unorm"
}

/// Immutable route authority captured during preparation and carried through
/// Program/execution telemetry. It contains no sample or layer identity and
/// is available to every standalone material source set.
nonisolated struct SceneGenericShaderRouteDecision: Hashable, Sendable {
    let profile: String
    let state: String
    let fallbackOwner: String
}

/// Source-keyed compiler output shared by the product preparation worker and
/// the independent cache reader. Decoding this value never grants execution;
/// `makeProgram` revalidates every ABI and color contract before publication.
nonisolated struct SceneGenericShaderProgramArtifact: Codable {
    struct Program: Codable {
        struct UniformLayout: Codable, Equatable {
            struct Field: Codable, Equatable {
                let name: String
                let authoredName: String
                let stage: String?
                let type: String
                let offset: Int
                let arrayCount: Int?

                init(
                    name: String,
                    authoredName: String,
                    stage: String? = nil,
                    type: String,
                    offset: Int,
                    arrayCount: Int? = nil
                ) {
                    self.name = name
                    self.authoredName = authoredName
                    self.stage = stage
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
        let premultipliedColorInputSlots: [Int]
        let colorTransfer: ColorTransfer
        let fragmentOutputChannelUse: String
    }

    let schemaVersion: Int
    let kind: String
    let backendID: String
    let requestKey: String
    let outputSemantics: SceneGenericShaderOutputSemantics
    let program: Program

    init(
        backendID: String,
        requestKey: String,
        outputSemantics: SceneGenericShaderOutputSemantics = .color,
        program: Program
    ) {
        schemaVersion = 7
        kind = "scene-generic-shader-program-artifact"
        self.backendID = backendID
        self.requestKey = requestKey
        self.outputSemantics = outputSemantics
        self.program = program
    }

    func makeProgram(
        expectedKey: String,
        expectedOutputSemantics: SceneGenericShaderOutputSemantics = .color,
        expectedPremultipliedColorInputSlots: Set<Int> = [],
        expectedColorTransfer: SceneShaderColorTransfer,
        expectedFragmentOutputChannelUse:
            SceneAuthoredShaderProgram.FragmentOutputChannelUse
    ) -> SceneAuthoredShaderProgram? {
        guard schemaVersion == 7,
              kind == "scene-generic-shader-program-artifact",
              backendID == "glslang-spirv-cross-msl-v2",
              requestKey == expectedKey,
              outputSemantics == expectedOutputSemantics else { return nil }
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
            guard let type = SceneAuthoredShaderValueType(rawValue: field.type),
                  field.stage == nil
                    || SceneShaderContract.StageKind(rawValue: field.stage!) != nil else {
                return nil
            }
            return .init(
                name: field.name,
                authoredName: field.authoredName,
                stage: field.stage.flatMap(SceneShaderContract.StageKind.init(rawValue:)),
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
              Set(bindings.map(\.slot)).count == bindings.count,
              SceneMaterialTextureTransformABI.validates(
                  layout: layout,
                  activeSlots: Set(bindings.map(\.slot))
              ), raw.premultipliedColorInputSlots
                == expectedPremultipliedColorInputSlots.sorted(),
              Set(raw.premultipliedColorInputSlots).count
                == raw.premultipliedColorInputSlots.count,
              raw.premultipliedColorInputSlots.allSatisfy({ slot in
                  bindings.contains(where: { $0.slot == slot })
              }) else { return nil }
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
        case ("generated-straight-alpha", nil, nil):
            colorTransfer = .generatedStraightAlpha
        case let ("straight-alpha", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .straightAlpha(textureSlot: slot)
        case let ("straight-alpha-unorm", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .straightAlphaUNorm(textureSlot: slot)
        case let ("straight-alpha-preserving", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .straightAlphaPreserving(textureSlot: slot)
        case let ("opaque-from-straight-color", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .opaqueFromStraightColor(textureSlot: slot)
        case let ("independent-alpha-signal", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .independentAlphaSignal(textureSlot: slot)
        case let ("independent-alpha-signal-preserving", slot?, nil):
            guard bindings.contains(where: { $0.slot == slot }) else { return nil }
            colorTransfer = .independentAlphaSignalPreserving(textureSlot: slot)
        case let ("independent-alpha-signal-compositing", nil, slots?):
            guard slots.count == 2,
                  slots[0] != slots[1],
                  slots.allSatisfy({ slot in
                      bindings.contains(where: { $0.slot == slot })
                  }) else { return nil }
            colorTransfer = .independentAlphaSignalCompositing(
                signalSlot: slots[0],
                colorSlot: slots[1]
            )
        case let (
            "independent-alpha-signal-underlay-compositing", nil, slots?
        ):
            guard slots.count == 3,
                  Set(slots).count == 3,
                  slots.allSatisfy({ slot in
                      bindings.contains(where: { $0.slot == slot })
                  }) else { return nil }
            colorTransfer = .independentAlphaSignalUnderlayCompositing(
                signalSlot: slots[0],
                colorSlot: slots[1],
                underlaySlot: slots[2]
            )
        case ("red-green-unorm-data", nil, nil):
            guard outputSemantics == .redGreenUnorm else { return nil }
            colorTransfer = .unresolved
        case ("preserved-rgba-data", nil, nil):
            guard outputSemantics == .preservedRGBAUnorm else { return nil }
            colorTransfer = .unresolved
        default:
            return nil
        }
        let requiresExactExpectedTransfer: Bool = switch colorTransfer {
        case .independentAlphaSignal,
             .independentAlphaSignalPreserving,
             .independentAlphaSignalCompositing,
             .independentAlphaSignalUnderlayCompositing:
            true
        default: false
        }
        guard outputSemantics != .color
                ? colorTransfer == .unresolved
                : requiresExactExpectedTransfer
                    ? colorTransfer == expectedColorTransfer
                    : expectedColorTransfer == .unresolved
                        || colorTransfer == expectedColorTransfer else {
            return nil
        }
        guard let fragmentOutputChannelUse =
                SceneAuthoredShaderProgram.FragmentOutputChannelUse(
                    rawValue: raw.fragmentOutputChannelUse
                ) else {
            return nil
        }
        // Color artifacts may decline this fact and let the Swift analyzer
        // promote it. Typed data artifacts must publish the fact themselves.
        let outputChannelContractSatisfied: Bool = switch expectedOutputSemantics {
        case .color:
            fragmentOutputChannelUse == .unproven
                || expectedFragmentOutputChannelUse == .redDefined
        case .redGreenUnorm:
            fragmentOutputChannelUse == .redDefined
        case .preservedRGBAUnorm:
            fragmentOutputChannelUse == .redDefined
                && expectedFragmentOutputChannelUse == .redDefined
        }
        guard outputChannelContractSatisfied else {
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
