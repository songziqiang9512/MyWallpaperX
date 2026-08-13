import Foundation

nonisolated struct SceneAuthoredEffectRenderPlan: Codable {
    struct EffectKey: Codable, Hashable {
        let layerID: Int
        let effectIndex: Int
        let descriptorID: String
    }

    enum TextureKind: String, Codable {
        case layerSource
        case effectOutput
        case framebuffer
        case unresolved
    }

    struct TextureIdentity: Codable, Hashable {
        let kind: TextureKind
        let layerID: Int
        let effect: EffectKey?
        let name: String?
    }

    enum TargetExtentKind: String, Codable {
        case input
        case scale
        case fit
        case absolute
        case composed
        case unsupported
    }

    struct TargetExtent: Codable, Equatable {
        private enum CodingKeys: String, CodingKey {
            case kind
            case first
            case second
            case width
            case height
            case fit
            case scale
        }

        let kind: TargetExtentKind
        let first: Double?
        let second: Double?
        let width: Double?
        let height: Double?
        let fit: Double?
        let scale: Double?

        init(kind: TargetExtentKind, first: Double?, second: Double?) {
            self.kind = kind
            self.first = first
            self.second = second
            switch kind {
            case .input, .composed, .unsupported:
                width = nil
                height = nil
                fit = nil
                scale = nil
            case .scale:
                width = nil
                height = nil
                fit = nil
                scale = first
            case .fit:
                width = nil
                height = nil
                fit = first
                scale = nil
            case .absolute:
                width = first
                height = second
                fit = nil
                scale = nil
            }
        }

        init(width: Double?, height: Double?, fit: Double?, scale: Double?) {
            self.width = width
            self.height = height
            self.fit = fit
            self.scale = scale

            let values = [width, height, fit, scale].compactMap { $0 }
            guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else {
                kind = .unsupported
                first = nil
                second = nil
                return
            }

            switch (width, height, fit, scale) {
            case (nil, nil, nil, nil):
                kind = .input
                first = nil
                second = nil
            case (nil, nil, nil, let scale?):
                kind = .scale
                first = scale
                second = nil
            case (nil, nil, let fit?, nil):
                kind = .fit
                first = fit
                second = nil
            case (let width?, let height?, nil, nil):
                kind = .absolute
                first = width
                second = height
            default:
                kind = .composed
                first = nil
                second = nil
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedKind = try container.decode(TargetExtentKind.self, forKey: .kind)
            let decodedFirst = try container.decodeIfPresent(Double.self, forKey: .first)
            let decodedSecond = try container.decodeIfPresent(Double.self, forKey: .second)
            let hasExpandedFields = [
                CodingKeys.width,
                .height,
                .fit,
                .scale,
            ].contains(where: container.contains)

            guard hasExpandedFields else {
                self.init(
                    kind: decodedKind,
                    first: decodedFirst,
                    second: decodedSecond
                )
                return
            }

            let decoded = Self(
                width: try container.decodeIfPresent(Double.self, forKey: .width),
                height: try container.decodeIfPresent(Double.self, forKey: .height),
                fit: try container.decodeIfPresent(Double.self, forKey: .fit),
                scale: try container.decodeIfPresent(Double.self, forKey: .scale)
            )
            guard decoded.kind == decodedKind,
                  decoded.first == decodedFirst,
                  decoded.second == decodedSecond else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Target extent fields do not describe one normalized value."
                )
            }
            self = decoded
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(first, forKey: .first)
            try container.encodeIfPresent(second, forKey: .second)
            guard kind == .composed else { return }
            try container.encodeIfPresent(width, forKey: .width)
            try container.encodeIfPresent(height, forKey: .height)
            try container.encodeIfPresent(fit, forKey: .fit)
            try container.encodeIfPresent(scale, forKey: .scale)
        }
    }

    struct RenderTarget: Codable {
        let texture: TextureIdentity
        let extent: TargetExtent
        let format: String?
        let declaredUnique: Bool
        let clear: SceneJSONValue?
        let uvs: SceneJSONValue?
        let conditions: SceneJSONValue?
    }

    struct Binding: Codable {
        let slot: Int?
        let authoredName: String?
        let texture: TextureIdentity
        let conditions: SceneJSONValue?
    }

    enum NodeKind: String, Codable {
        case material
        case copy
        case swap
        case unknownCommand
    }

    struct Node: Codable {
        let nodeIndex: Int
        let effect: EffectKey
        let definitionPassIndex: Int
        let materialOrdinal: Int?
        let instancePassIndex: Int?
        let kind: NodeKind
        let materialPath: String?
        let materialPassID: String?
        let target: TextureIdentity?
        let bindings: [Binding]
        let commandSource: TextureIdentity?
        let commandTarget: TextureIdentity?
        let compose: SceneJSONValue?
        let conditions: SceneJSONValue?
    }

    struct Effect: Codable {
        let key: EffectKey
        let definitionPath: String
        let input: TextureIdentity
        let output: TextureIdentity
        let nodeIndices: [Int]
    }

    enum BlockerReason: String, Codable {
        case missingDefinition
        case ambiguousDefinition
        case instancePassCountMismatch
        case invalidPassShape
        case missingMaterial
        case ambiguousMaterial
        case duplicateFramebuffer
        case unsupportedFramebufferExtent
        case unsupportedFramebufferFormat
        case unsupportedFramebufferUVs
        case invalidFramebufferClear
        case invalidFramebufferUnique
        case unsupportedCondition
        case unsupportedFunctions
        case unsupportedCompose
        case invalidBinding
        case unknownTexture
        case unknownCommand
        case incompatibleCommand
        case missingEffectOutput
        case multipleEffectOutputs
        case unknownDefinitionFields
    }

    struct Blocker: Codable {
        let effect: EffectKey
        let definitionPassIndex: Int?
        let reason: BlockerReason
        let detail: String
    }

    let layerID: Int
    let effects: [Effect]
    let renderTargets: [RenderTarget]
    let nodes: [Node]
    let finalOutput: TextureIdentity
    let blockers: [Blocker]

    nonisolated var isStructurallyResolved: Bool {
        blockers.isEmpty
    }
}

nonisolated enum SceneAuthoredEffectInputRole: Equatable {
    case layerSource
    case priorEffectOutput
}

enum SceneAuthoredEffectInputValidator {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func role(
        for input: Graph.TextureIdentity,
        layerID: Int
    ) -> SceneAuthoredEffectInputRole? {
        if input == layerSource(layerID: layerID) {
            return .layerSource
        }
        guard input.kind == .effectOutput,
              input.layerID == layerID,
              input.effect?.layerID == layerID,
              (input.effect?.effectIndex ?? -1) >= 0,
              input.effect?.descriptorID.isEmpty == false,
              input.name == nil else {
            return nil
        }
        return .priorEffectOutput
    }

    nonisolated static func accepts(
        _ input: Graph.TextureIdentity,
        layerID: Int,
        role: SceneAuthoredEffectInputRole
    ) -> Bool {
        self.role(for: input, layerID: layerID) == role
    }

    nonisolated static func layerSource(layerID: Int) -> Graph.TextureIdentity {
        .init(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
    }
}
