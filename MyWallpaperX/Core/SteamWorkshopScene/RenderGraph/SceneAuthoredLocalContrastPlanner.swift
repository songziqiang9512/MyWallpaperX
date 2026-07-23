import CryptoKit
import Foundation

nonisolated struct SceneLocalContrastPlan {
    nonisolated struct DirectStrengthBinding: Equatable, Sendable {
        let propertyKey: String
        let layerID: Int
        let effectIndex: Int
        let passIndex: Int
        let constantName: String

        nonisolated var dynamicTarget: SceneDynamicTarget {
            .effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: constantName
            )
        }
    }

    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let firstQuarterTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondQuarterTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let renderGraph: SceneAuthoredEffectRenderPlan
    let staticOrFallbackStrength: Float
    let directStrengthBinding: DirectStrengthBinding?

    nonisolated var liveStrengthTarget: SceneDynamicTarget? {
        directStrengthBinding?.dynamicTarget
    }

    nonisolated func resolvedStrength(in snapshot: SceneDynamicSnapshot) -> Float {
        guard let target = liveStrengthTarget,
              case .scalar(let rawValue) = snapshot[target]?.value else {
            return staticOrFallbackStrength
        }
        let value = Float(rawValue)
        return value.isFinite && (0...5).contains(value) ? value : staticOrFallbackStrength
    }
}

enum SceneAuthoredLocalContrastPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct StageFingerprint: Sendable {
        let kind: SceneShaderContract.StageKind
        let path: String
        let rawSHA256: String
    }

    private struct ShaderFingerprint: Sendable {
        let identity: String
        let canonicalSHA256: String
        let stages: [StageFingerprint]
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneLocalContrastPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 4,
              graph.renderTargets.count == 2,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text"].contains(layer.contentKind),
              shaderContractsMatch(shaderContracts) else {
            return nil
        }

        let effect = graph.effects[0]
        guard normalized(effect.definitionPath) == "effects/localcontrast/effect.json",
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              SceneAuthoredEffectInputValidator.accepts(
                effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              let firstTarget = target(named: "_rt_quartercompobuffer1", graph: graph),
              let secondTarget = target(named: "_rt_quartercompobuffer2", graph: graph),
              validTarget(firstTarget, effect: effect.key),
              validTarget(secondTarget, effect: effect.key) else {
            return nil
        }

        let expectedTargets = [
            firstTarget.texture,
            secondTarget.texture,
            firstTarget.texture,
            effect.output,
        ]
        let expectedBindings = [
            [(0, "previous", effect.input)],
            [(0, "_rt_quartercompobuffer1", firstTarget.texture)],
            [(0, "_rt_quartercompobuffer2", secondTarget.texture)],
            [
                (0, "_rt_quartercompobuffer1", firstTarget.texture),
                (2, "previous", effect.input),
            ],
        ]
        let expectedMaterials = [
            "materials/effects/localcontrast_downsample4.json",
            "materials/effects/localcontrast_gaussian_x.json",
            "materials/effects/localcontrast_gaussian_y.json",
            "materials/effects/localcontrast_combine.json",
        ]

        var resolved: [SceneResolvedMaterialNode] = []
        for ordinal in graph.nodes.indices {
            let node = graph.nodes[ordinal]
            guard validNode(
                node,
                ordinal: ordinal,
                nodeIndex: effect.nodeIndices[ordinal],
                effect: effect.key,
                target: expectedTargets[ordinal],
                bindings: expectedBindings[ordinal],
                materialPath: expectedMaterials[ordinal]
            ) else { return nil }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: node,
                graph: graph,
                descriptor: descriptor
            )
            guard resolution.isResolved, let material = resolution.node,
                  validMaterial(material, ordinal: ordinal, bindings: expectedBindings[ordinal]) else {
                return nil
            }
            resolved.append(material)
        }

        guard resolved[0].constants.isEmpty,
              validScale(resolved[1].constants),
              validScale(resolved[2].constants),
              let strength = strength(from: resolved[3].constants, effect: effect.key) else {
            return nil
        }
        return SceneLocalContrastPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            firstQuarterTarget: firstTarget.texture,
            secondQuarterTarget: secondTarget.texture,
            renderGraph: graph,
            staticOrFallbackStrength: strength.value,
            directStrengthBinding: strength.binding
        )
    }

    private nonisolated static func validTarget(
        _ target: Graph.RenderTarget,
        effect: Graph.EffectKey
    ) -> Bool {
        target.texture.kind == .framebuffer
            && target.texture.effect == effect
            && target.extent.kind == .scale
            && target.extent.first == 4
            && target.extent.second == nil
            && target.format?.lowercased() == "rgba8888"
            && !target.declaredUnique
            && target.clear == nil
            && target.uvs == nil
            && target.conditions == nil
    }

    private nonisolated static func validNode(
        _ node: Graph.Node,
        ordinal: Int,
        nodeIndex: Int,
        effect: Graph.EffectKey,
        target: Graph.TextureIdentity,
        bindings: [(Int, String, Graph.TextureIdentity)],
        materialPath: String
    ) -> Bool {
        guard node.nodeIndex == nodeIndex,
              node.effect == effect,
              node.definitionPassIndex == ordinal,
              node.materialOrdinal == ordinal,
              node.instancePassIndex == ordinal,
              node.kind == .material,
              normalized(node.materialPath ?? "") == materialPath,
              normalized(node.materialPassID ?? "") == "\(materialPath)#0",
              node.target == target,
              node.commandSource == nil,
              node.commandTarget == nil,
              node.compose == nil,
              node.conditions == nil,
              node.bindings.count == bindings.count else {
            return false
        }
        return zip(node.bindings, bindings).allSatisfy { authored, expected in
            authored.slot == expected.0
                && normalized(authored.authoredName ?? "") == expected.1
                && authored.texture == expected.2
                && authored.conditions == nil
        }
    }

    private nonisolated static func validMaterial(
        _ material: SceneResolvedMaterialNode,
        ordinal: Int,
        bindings: [(Int, String, Graph.TextureIdentity)]
    ) -> Bool {
        let shaders = [
            "effects/localcontrast_downsample4",
            "effects/localcontrast_gaussian",
            "effects/localcontrast_gaussian",
            "effects/localcontrast_combine",
        ]
        guard normalized(material.shaderPath) == shaders[ordinal],
              material.renderState.blending?.lowercased() == "normal",
              material.renderState.depthTest?.lowercased() == "disabled",
              material.renderState.depthWrite?.lowercased() == "disabled",
              material.renderState.cullMode?.lowercased() == "nocull",
              validCombos(material.combos, ordinal: ordinal) else {
            return false
        }
        let expectedBySlot = Dictionary(uniqueKeysWithValues: bindings.map { ($0.0, $0.2) })
        guard expectedBySlot.keys.allSatisfy(material.textureSlots.indices.contains) else {
            return false
        }
        for index in material.textureSlots.indices {
            guard let expected = expectedBySlot[index] else {
                if material.textureSlots[index] != nil { return false }
                continue
            }
            guard let slot = material.textureSlots[index],
                  slot.candidates.count == 1,
                  slot.provenance == .explicitBinding,
                  case .graph(let actual) = slot.source,
                  actual == expected else {
                return false
            }
        }
        return true
    }

    private nonisolated static func validCombos(
        _ authored: [String: Int],
        ordinal: Int
    ) -> Bool {
        var combos: [String: Int] = [:]
        for (key, value) in authored {
            guard combos.updateValue(value, forKey: key.uppercased()) == nil else { return false }
        }
        switch ordinal {
        case 0:
            return combos.isEmpty
        case 1:
            return combos.keys.allSatisfy { ["KERNEL", "VERTICAL"].contains($0) }
                && combos["KERNEL", default: 0] == 0
                && combos["VERTICAL", default: 0] == 0
        case 2:
            return combos.keys.allSatisfy { ["KERNEL", "VERTICAL"].contains($0) }
                && combos["KERNEL", default: 0] == 0
                && combos["VERTICAL"] == 1
        case 3:
            return combos.keys.allSatisfy { ["GREYSCALE", "MASK"].contains($0) }
                && combos["GREYSCALE", default: 0] == 0
                && combos["MASK", default: 0] == 0
        default:
            return false
        }
    }

    private nonisolated static func validScale(
        _ constants: [String: SceneDocument.ShaderValue]
    ) -> Bool {
        if constants.isEmpty { return true }
        guard constants.count == 1,
              let value = constants.first(where: { $0.key.lowercased() == "scale" })?.value,
              value.valueKind.lowercased() == "vector",
              value.userBinding == nil,
              value.components == [1, 1] else {
            return false
        }
        return true
    }

    private nonisolated static func strength(
        from constants: [String: SceneDocument.ShaderValue],
        effect: Graph.EffectKey
    ) -> (value: Float, binding: SceneLocalContrastPlan.DirectStrengthBinding?)? {
        if constants.isEmpty { return (1, nil) }
        guard constants.count == 1,
              let value = constants.first(where: { $0.key.lowercased() == "strength" })?.value,
              let component = value.components?.only,
              component.isFinite,
              component >= 0,
              component <= 5 else {
            return nil
        }
        let binding: SceneLocalContrastPlan.DirectStrengthBinding?
        if let property = value.userBinding?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !property.isEmpty, value.valueKind.lowercased() == "binding" else { return nil }
            binding = .init(
                propertyKey: property,
                layerID: effect.layerID,
                effectIndex: effect.effectIndex,
                passIndex: 3,
                constantName: "strength"
            )
        } else {
            guard value.valueKind.lowercased() == "number" else { return nil }
            binding = nil
        }
        return (Float(component), binding)
    }

    private nonisolated static func shaderContractsMatch(
        _ contracts: [SceneShaderContract]
    ) -> Bool {
        expectedShaderFingerprints().allSatisfy { expected in
            let matches = contracts.filter { normalized($0.identity) == expected.identity }
            guard matches.count == 1, let contract = matches.first,
                  contract.sourceKind == .authoredSource,
                  contract.diagnostics.isEmpty,
                  contract.canonicalSHA256 == expected.canonicalSHA256,
                  contract.stages.count == expected.stages.count else {
                return false
            }
            return zip(contract.stages, expected.stages).allSatisfy { stage, fingerprint in
                stage.kind == fingerprint.kind
                    && normalized(stage.relativePath) == fingerprint.path
                    && stage.rawSHA256 == fingerprint.rawSHA256
                    && sha256(Data(stage.source.utf8)) == fingerprint.rawSHA256
            }
        }
    }

    private nonisolated static func expectedShaderFingerprints() -> [ShaderFingerprint] {
        [
            .init(
                identity: "effects/localcontrast_downsample4",
                canonicalSHA256: "4b2678fda69092ea473a8c30e6c14b27a42056a2d9d38bde8ac8ccad1aa54a1b",
                stages: [
                    .init(kind: .vertex, path: "shaders/effects/localcontrast_downsample4.vert", rawSHA256: "522620fd19ca833762e965696c0c55e3136bae5442cec70227d5b32b32955747"),
                    .init(kind: .fragment, path: "shaders/effects/localcontrast_downsample4.frag", rawSHA256: "247c303a1925db1babae53f721710537338fe53810e94c38d1457444878f54f9"),
                ]
            ),
            .init(
                identity: "effects/localcontrast_gaussian",
                canonicalSHA256: "df9debe2c7f0bea3ead87458b37bcc387d04454a342e379f2f61d21dc56fa997",
                stages: [
                    .init(kind: .vertex, path: "shaders/effects/localcontrast_gaussian.vert", rawSHA256: "514f192a941cfb2aa0fa1e2e7f8b7a04405f5169e557d10293ed4e3d4f326144"),
                    .init(kind: .fragment, path: "shaders/effects/localcontrast_gaussian.frag", rawSHA256: "bb847f608de8c34b6c400c8e54da9db33e5438a47ad837ba762390e9eae9f9b6"),
                ]
            ),
            .init(
                identity: "effects/localcontrast_combine",
                canonicalSHA256: "e107f1264f4170b52c6aeb9925302d22f5b89347304c67be1ce0efc93814ddda",
                stages: [
                    .init(kind: .vertex, path: "shaders/effects/localcontrast_combine.vert", rawSHA256: "208d5f52d8ad1d5bac439ad1c653e75fc9dc062ac6bb7f8ff87c1d18827c5dad"),
                    .init(kind: .fragment, path: "shaders/effects/localcontrast_combine.frag", rawSHA256: "57a442cc99d46c0a102890e58671acf05dca6c1510a405f5d627d8b67100d151"),
                ]
            ),
        ]
    }

    private nonisolated static func target(
        named name: String,
        graph: Graph
    ) -> Graph.RenderTarget? {
        let matches = graph.renderTargets.filter { normalized($0.texture.name ?? "") == name }
        return matches.count == 1 ? matches[0] : nil
    }

    private nonisolated static func layerSource(layerID: Int) -> Graph.TextureIdentity {
        .init(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
    }

    private nonisolated static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Array {
    nonisolated var only: Element? { count == 1 ? self[0] : nil }
}
