import Foundation

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Codable, Hashable, Sendable {
        case material
        case instance
        case userTexture
        case explicitBinding
    }

    enum TextureSource {
        case asset(String)
        case userTexture(SceneEffectTextureInput)
        case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    }

    struct TextureCandidate {
        let source: TextureSource
        let provenance: TextureProvenance
    }

    struct TextureSlot {
        let index: Int
        let candidates: [TextureCandidate]

        var source: TextureSource { candidates[candidates.count - 1].source }
        var provenance: TextureProvenance { candidates[candidates.count - 1].provenance }
    }

    struct RenderState: Hashable, Sendable {
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let nodeIndex: Int
    let shaderPath: String
    let textureSlots: [TextureSlot?]
    let combos: [String: Int]
    let constants: [String: SceneDocument.ShaderValue]
    let userShaderValues: [String: String]
    let renderState: RenderState
}

nonisolated struct SceneAuthoredMaterialResolution {
    let node: SceneResolvedMaterialNode?
    let issues: [String]

    var isResolved: Bool { node != nil && issues.isEmpty }
}

enum SceneAuthoredMaterialResolver {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct InstanceOverlay {
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]

        static let empty = Self(
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:]
        )
    }

    nonisolated static func resolve(
        node: Graph.Node,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> SceneAuthoredMaterialResolution {
        var issues: [String] = []
        guard node.kind == .material else {
            return .init(node: nil, issues: ["Node is not a material pass."])
        }
        guard let materialID = node.materialPassID else {
            return .init(node: nil, issues: ["Material pass identity is missing."])
        }
        let materialMatches = descriptor.materialPasses.filter { $0.id == materialID }
        guard materialMatches.count == 1, let material = materialMatches.first else {
            return .init(
                node: nil,
                issues: ["Expected one material pass for \(materialID), found \(materialMatches.count)."]
            )
        }
        guard normalized(material.materialPath) == normalized(node.materialPath ?? "") else {
            return .init(node: nil, issues: ["Material path does not match the graph node."])
        }
        guard let shaderPath = material.shaderPath, !shaderPath.isEmpty else {
            return .init(node: nil, issues: ["Material shader path is missing."])
        }
        guard let instance = instanceOverlay(
            for: node,
            graph: graph,
            descriptor: descriptor
        ) else {
            return .init(node: nil, issues: ["Effect instance pass does not match the graph ordinal."])
        }

        var slots = Array<SceneResolvedMaterialNode.TextureSlot?>(repeating: nil, count: 8)
        mergeAssets(
            material.textureSlots,
            provenance: .material,
            into: &slots,
            issues: &issues
        )
        mergeUserTextures(material.userTextureInputs, into: &slots, issues: &issues)
        mergeAssets(
            instance.textureSlots,
            provenance: .instance,
            into: &slots,
            issues: &issues
        )
        mergeUserTextures(instance.userTextureInputs, into: &slots, issues: &issues)
        mergeBindings(node.bindings, into: &slots, issues: &issues)

        var combos = material.combos
        instance.combos.forEach { combos[$0.key] = $0.value }
        var constants = material.constantShaderValues
        instance.constantShaderValues.forEach { constants[$0.key] = $0.value }
        let resolved = SceneResolvedMaterialNode(
            nodeIndex: node.nodeIndex,
            shaderPath: shaderPath,
            textureSlots: slots,
            combos: combos,
            constants: constants,
            userShaderValues: material.userShaderValues,
            renderState: .init(
                blending: material.blending,
                depthTest: material.depthTest,
                depthWrite: material.depthWrite,
                cullMode: material.cullMode,
                alphaWriting: material.alphaWriting
            )
        )
        return .init(node: issues.isEmpty ? resolved : nil, issues: issues)
    }

    private nonisolated static func instanceOverlay(
        for node: Graph.Node,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> InstanceOverlay? {
        guard graph.layerID == node.effect.layerID,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              layer.effects.indices.contains(node.effect.effectIndex),
              let ordinal = node.materialOrdinal else {
            return nil
        }
        let effect = layer.effects[node.effect.effectIndex]
        guard effect.id == node.effect.descriptorID else { return nil }
        if effect.passes.isEmpty {
            return node.instancePassIndex == nil ? .empty : nil
        }
        guard effect.passes.indices.contains(ordinal) else { return nil }
        let pass = effect.passes[ordinal]
        guard node.instancePassIndex == pass.passIndex else { return nil }
        return .init(
            textureSlots: pass.textureSlots,
            userTextureInputs: pass.userTextureInputs,
            combos: pass.combos,
            constantShaderValues: pass.constantShaderValues
        )
    }

    private nonisolated static func mergeAssets(
        _ authored: [String?],
        provenance: SceneResolvedMaterialNode.TextureProvenance,
        into slots: inout [SceneResolvedMaterialNode.TextureSlot?],
        issues: inout [String]
    ) {
        for (index, value) in authored.enumerated() where value != nil {
            guard slots.indices.contains(index), let value else {
                issues.append("Texture slot \(index) is outside g_Texture0...7.")
                continue
            }
            append(
                source: .asset(value),
                provenance: provenance,
                at: index,
                into: &slots
            )
        }
    }

    private nonisolated static func mergeUserTextures(
        _ authored: [SceneEffectTextureInput?],
        into slots: inout [SceneResolvedMaterialNode.TextureSlot?],
        issues: inout [String]
    ) {
        for (index, value) in authored.enumerated() where value != nil {
            guard slots.indices.contains(index), let value else {
                issues.append("User texture slot \(index) is outside g_Texture0...7.")
                continue
            }
            append(
                source: .userTexture(value),
                provenance: .userTexture,
                at: index,
                into: &slots
            )
        }
    }

    private nonisolated static func mergeBindings(
        _ authored: [Graph.Binding],
        into slots: inout [SceneResolvedMaterialNode.TextureSlot?],
        issues: inout [String]
    ) {
        var used = Set<Int>()
        for binding in authored {
            guard let index = binding.slot, slots.indices.contains(index) else {
                issues.append("Explicit binding has an invalid texture slot.")
                continue
            }
            guard used.insert(index).inserted else {
                issues.append("Explicit binding repeats texture slot \(index).")
                continue
            }
            guard binding.texture.kind != .unresolved else {
                issues.append("Explicit binding at texture slot \(index) is unresolved.")
                continue
            }
            append(
                source: .graph(binding.texture),
                provenance: .explicitBinding,
                at: index,
                into: &slots
            )
        }
    }

    private nonisolated static func append(
        source: SceneResolvedMaterialNode.TextureSource,
        provenance: SceneResolvedMaterialNode.TextureProvenance,
        at index: Int,
        into slots: inout [SceneResolvedMaterialNode.TextureSlot?]
    ) {
        let candidate = SceneResolvedMaterialNode.TextureCandidate(
            source: source,
            provenance: provenance
        )
        let candidates = (slots[index]?.candidates ?? []) + [candidate]
        slots[index] = .init(index: index, candidates: candidates)
    }

    private nonisolated static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
