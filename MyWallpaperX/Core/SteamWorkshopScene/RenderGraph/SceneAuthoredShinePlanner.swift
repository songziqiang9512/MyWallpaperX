import CryptoKit
import Foundation

/// Stock `effects/shine` 5-pass / 2-half-RT graph admission.
///
/// Shader sources are used only as an exact profile boundary. Rendering is a
/// project-owned implementation of the documented threshold, multi-ray, blur,
/// and blend semantics.
enum SceneAuthoredShinePlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct StageFingerprint {
        let kind: SceneShaderContract.StageKind
        let path: String
        let rawSHA256: String
    }

    private struct ShaderFingerprint {
        let identity: String
        let canonicalSHA256: String
        let stages: [StageFingerprint]
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneShineExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 5,
              graph.renderTargets.count == 2,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text"].contains(layer.contentKind),
              shaderContractsMatch(shaderContracts)
        else {
            return nil
        }

        let effect = graph.effects[0]
        guard normalized(effect.definitionPath) == definitionPath,
              validDefinition(in: descriptor, path: effect.definitionPath),
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              let firstTarget = target(named: "_rt_halfcompobuffer1", graph: graph),
              let secondTarget = target(named: "_rt_halfcompobuffer2", graph: graph),
              validTarget(firstTarget, effect: effect.key),
              validTarget(secondTarget, effect: effect.key)
        else {
            return nil
        }

        let expectedTargets = [
            firstTarget.texture,
            secondTarget.texture,
            firstTarget.texture,
            secondTarget.texture,
            effect.output,
        ]
        let expectedBindings = [
            [(0, "previous", effect.input)],
            [(0, "_rt_halfcompobuffer1", firstTarget.texture)],
            [(0, "_rt_halfcompobuffer2", secondTarget.texture)],
            [(0, "_rt_halfcompobuffer1", firstTarget.texture)],
            [
                (0, "_rt_halfcompobuffer2", secondTarget.texture),
                (1, "previous", effect.input),
            ],
        ]
        let expectedMaterials = [
            "materials/effects/shine_downsample2.json",
            "materials/effects/shine_cast.json",
            "materials/effects/shine_gaussian_x.json",
            "materials/effects/shine_gaussian_y.json",
            "materials/effects/shine_combine.json",
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
            ) else {
                return nil
            }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: node,
                graph: graph,
                descriptor: descriptor
            )
            guard resolution.isResolved, let material = resolution.node,
                  validMaterial(material, ordinal: ordinal, bindings: expectedBindings[ordinal])
            else {
                return nil
            }
            resolved.append(material)
        }

        guard let resources = effectResources(effect: effect, layer: layer),
              let downsample = downsampleConstants(resolved[0].constants),
              let cast = castConstants(resolved[1].constants),
              let blurX = blurScale(resolved[2].constants),
              let blurY = blurScale(resolved[3].constants),
              resolved[4].constants.isEmpty,
              let edgeCount = castEdgeCount(resolved[1].combos),
              let sampleCount = castSampleCount(resolved[1].combos),
              let kernelRadius = gaussianKernelRadius(
                  resolved[2].combos,
                  vertical: resolved[3].combos
              ),
              let blendMode = combineBlendMode(resolved[4].combos)
        else {
            return nil
        }

        return SceneShineExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            firstHalfTarget: firstTarget.texture,
            secondHalfTarget: secondTarget.texture,
            threshold: downsample.threshold,
            noiseAmount: downsample.noiseAmount,
            noiseScale: downsample.noiseScale,
            noiseSpeed: downsample.noiseSpeed,
            maskTexturePath: resources.maskPath,
            noiseTexturePath: resources.noisePath,
            edgeCount: edgeCount,
            sampleCount: sampleCount,
            direction: cast.direction,
            rotationSpeed: cast.speed,
            rayLength: cast.length,
            rayIntensity: cast.intensity,
            rayColor: cast.color,
            kernelRadius: kernelRadius,
            blurScaleX: blurX,
            blurScaleY: blurY,
            blendMode: blendMode
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains { normalized($0.definitionPath) == definitionPath }
    }

    private nonisolated static func validTarget(
        _ target: Graph.RenderTarget,
        effect: Graph.EffectKey
    ) -> Bool {
        target.texture.kind == .framebuffer
            && target.texture.effect == effect
            && target.extent.kind == .scale
            && target.extent.first == 2
            && target.extent.second == nil
            && target.format?.lowercased() == "rgba_backbuffer"
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
              node.bindings.count == bindings.count
        else {
            return false
        }
        return zip(node.bindings, bindings).allSatisfy { authored, expected in
            authored.slot == expected.0
                && normalized(authored.authoredName ?? "") == expected.1
                && authored.texture == expected.2
                && authored.conditions == nil
        }
    }

    private nonisolated static func shaderContractsMatch(
        _ contracts: [SceneShaderContract]
    ) -> Bool {
        expectedShaderFingerprints.allSatisfy { expected in
            let matches = contracts.filter { normalized($0.identity) == expected.identity }
            guard matches.count == 1, let contract = matches.first,
                  contract.sourceKind == .authoredSource,
                  contract.diagnostics.isEmpty,
                  contract.canonicalSHA256 == expected.canonicalSHA256,
                  contract.stages.count == expected.stages.count
            else {
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

    private nonisolated static let expectedShaderFingerprints: [ShaderFingerprint] = [
        .init(
            identity: "effects/shine_downsample2",
            canonicalSHA256: "87b3ed5d2123da5e9226ab32d67545fce464ea2ed937bdd31e95712089b033a4",
            stages: [
                .init(kind: .vertex, path: "shaders/effects/shine_downsample2.vert", rawSHA256: "4b2a12f89ffbddad5f6bd6e3d3d805194f353005b0d45a6fe6f65eb9666e0e76"),
                .init(kind: .fragment, path: "shaders/effects/shine_downsample2.frag", rawSHA256: "c3e97ff70b0691eec217dc9b5c98f5121fe1f1268fbe8f9c5e396ac6ae423cea"),
            ]
        ),
        .init(
            identity: "effects/shine_cast",
            canonicalSHA256: "8efb55748554e057b1cc5a9d116998ce6960efeb0a5eb48c8622329988f2f6c4",
            stages: [
                .init(kind: .vertex, path: "shaders/effects/shine_cast.vert", rawSHA256: "22138f12ebbc365847b31e92ac9c0b8a2b86997792139a0e0d3a30f6930ab910"),
                .init(kind: .fragment, path: "shaders/effects/shine_cast.frag", rawSHA256: "65b2c756f936ca17d085433cdb463fb557f94cfcf26baa1bcaa3a00db3ee6e1b"),
            ]
        ),
        .init(
            identity: "effects/shine_gaussian",
            canonicalSHA256: "768cfdcfca170c6364b2786dcba0f30e802923d5ab28aacef7ea716dea8ec910",
            stages: [
                .init(kind: .vertex, path: "shaders/effects/shine_gaussian.vert", rawSHA256: "eb4429d6729cac9ecaca72bcf29b83241ce99e9863331aac2723c3042508b044"),
                .init(kind: .fragment, path: "shaders/effects/shine_gaussian.frag", rawSHA256: "04cada859c40c84f2952d1deb6ac5535ac8dde6ec56861dd8af33b02a145f116"),
            ]
        ),
        .init(
            identity: "effects/shine_combine",
            canonicalSHA256: "73d8580d38803b4cf82f12a69b13fe79663dc817d18b5b3f644ef8fb1dac4542",
            stages: [
                .init(kind: .vertex, path: "shaders/effects/shine_combine.vert", rawSHA256: "cd0636f15ff19225b5cbf10af006f9fe43d99c9b782baeb1dbfe62c507816fad"),
                .init(kind: .fragment, path: "shaders/effects/shine_combine.frag", rawSHA256: "c4bf993a2176152b0482b04818b2f6d02f2f52018e1c160463b540ede9c0cd1b"),
            ]
        ),
    ]

    private nonisolated static func target(named name: String, graph: Graph) -> Graph.RenderTarget? {
        let matches = graph.renderTargets.filter { normalized($0.texture.name ?? "") == name }
        return matches.count == 1 ? matches[0] : nil
    }

    private nonisolated static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static let definitionPath = "effects/shine/effect.json"
}
