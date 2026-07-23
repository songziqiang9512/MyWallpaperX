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
        case unsupported
    }

    struct TargetExtent: Codable, Equatable {
        let kind: TargetExtentKind
        let first: Double?
        let second: Double?
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
