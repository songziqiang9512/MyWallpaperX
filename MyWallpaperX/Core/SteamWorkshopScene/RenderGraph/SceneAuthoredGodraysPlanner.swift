import CryptoKit
import Foundation
import simd

/// 官方 `effects/godrays` exact stock 5-pass / 2-half-RT profile 的执行计划。
///
/// pass 语义（stock 2.8.42，`CASTER=0` Radial / `COPYBG=0`）：
/// 1. downsample2 -> `_rt_HalfCompoBuffer1`：premultiply + luma 阈值提取，
///    可选实例遮罩（slot 1）与 `util/clouds_256` 双采样噪声调制 alpha；
/// 2. cast -> Buffer2：沿 `center - uv` 方向 30/50 采样加权积分；
/// 3/4. gaussian x/y（Buffer2 -> Buffer1 -> Buffer2）：`blur13a`/`blur7a`；
/// 5. combine：`ApplyBlending(BLENDMODE, albedo, rays.rgb, rays.a)`，
///    `alpha = saturate(albedo.a + rays.a)`（`BLENDMODE=0` 直接取 rays）。
nonisolated struct SceneGodraysPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let firstHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    /// pass 0：阈值与噪声调制（噪声 UV 在 vert 侧按 time 滚动）。
    let threshold: Float
    let noiseAmount: Float
    let noiseScale: Float
    let noiseSpeed: Float
    let noiseSmoothness: Float
    /// pass 1：Radial 光线积分。
    let center: SIMD2<Float>
    let colorRays: SIMD3<Float>
    let rayLength: Float
    let rayIntensity: Float
    /// `SAMPLES` combo：false=30 采样、true=50（强度补偿 30/50）。
    let samples50: Bool
    /// `KERNEL` combo：官方 gaussian.vert 注解默认 1（blur7a）；显式 0 用 blur13a。
    let kernel13: Bool
    /// pass 2/3 的 `blurscale`（gaussian_x 消费 `.x`、_y 消费 `.y`）。
    let blurScaleX: SIMD2<Float>
    let blurScaleY: SIMD2<Float>
    /// combine 的 `BLENDMODE`（`[COMBO]` 默认 9）。
    let blendMode: Int
    /// pass 0 槽位 1 遮罩；nil 表示实例未绑图。
    let maskTexturePath: String?
}

enum SceneAuthoredGodraysPlanner {
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
    ) -> SceneGodraysPlan? {
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
        guard normalized(effect.definitionPath) == "effects/godrays/effect.json",
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
            "materials/effects/godrays_downsample2.json",
            "materials/effects/godrays_cast.json",
            "materials/effects/godrays_gaussian_x.json",
            "materials/effects/godrays_gaussian_y.json",
            "materials/effects/godrays_combine.json",
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
                  validMaterial(
                      material,
                      ordinal: ordinal,
                      bindings: expectedBindings[ordinal]
                  )
            else {
                return nil
            }
            resolved.append(material)
        }

        guard let maskPath = maskTexturePath(
            effect: effect,
            layer: layer,
            resolvedDownsample: resolved[0]
        ),
            let downsample = downsampleConstants(resolved[0].constants),
            let cast = castConstants(resolved[1].constants),
            let blurX = blurScale(resolved[2].constants),
            let blurY = blurScale(resolved[3].constants),
            resolved[4].constants.isEmpty,
            let blendMode = combineBlendMode(resolved[4].combos),
            let samples50 = castSamples(resolved[1].combos),
            let kernel13 = gaussianKernel(
                resolved[2].combos,
                vertical: resolved[3].combos
            )
        else {
            return nil
        }

        return SceneGodraysPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            firstHalfTarget: firstTarget.texture,
            secondHalfTarget: secondTarget.texture,
            threshold: downsample.threshold,
            noiseAmount: downsample.noiseAmount,
            noiseScale: downsample.noiseScale,
            noiseSpeed: downsample.noiseSpeed,
            noiseSmoothness: downsample.noiseSmoothness,
            center: cast.center,
            colorRays: cast.color,
            rayLength: cast.length,
            rayIntensity: cast.intensity,
            samples50: samples50,
            kernel13: kernel13,
            blurScaleX: blurX,
            blurScaleY: blurY,
            blendMode: blendMode,
            maskTexturePath: maskPath.path
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains {
            normalized($0.definitionPath) == "effects/godrays/effect.json"
        }
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
            identity: "effects/godrays_downsample2",
            canonicalSHA256: "02ccdadd4e8a13ff7c96827de4a0a16b0aeed2a2557f9059555a4210b56cefd0",
            stages: [
                .init(kind: .vertex, path: "shaders/effects/godrays_downsample2.vert", rawSHA256: "da20834a9c4985ffb9035b6373d2d77279831d8340a125b6d1a50dffb735601b"),
                .init(kind: .fragment, path: "shaders/effects/godrays_downsample2.frag", rawSHA256: "f4cf3742456be482a345e17a1a9bd514d9df5d07e46b2be7d93e30f1e5dd3ab6"),
            ]
        ),
        .init(
            identity: "effects/godrays_cast",
            canonicalSHA256: "82acb5faa8bdb62a64a6482032ce1ef39f36841711d3bedfc0d075f0aae57f7f",
            stages: [
                .init(kind: .vertex, path: "shaders/effects/godrays_cast.vert", rawSHA256: "47a9753f646d150399faf48b3334d9a2b52c0da3ed38634a2a57914ccd83dd0f"),
                .init(kind: .fragment, path: "shaders/effects/godrays_cast.frag", rawSHA256: "ca22b4a78b2536a77007fd6e4e27ee40b091b1be94e0fbaa367a1098d064d915"),
            ]
        ),
        .init(
            identity: "effects/godrays_gaussian",
            canonicalSHA256: "7d6537722cb496626b1e834c2e2f3b77e3baf30054eb30b63d959cfe22ec18d9",
            stages: [
                .init(kind: .vertex, path: "shaders/effects/godrays_gaussian.vert", rawSHA256: "f584b60cf58ff02e768c543bc93743280c4d169802ce798b00e5acb99f3a24be"),
                .init(kind: .fragment, path: "shaders/effects/godrays_gaussian.frag", rawSHA256: "be030fe8a6375b4d8856028d070ab692f6efb18cb4184cbd01a059d4de18a644"),
            ]
        ),
        .init(
            identity: "effects/godrays_combine",
            canonicalSHA256: "c4d40bf0fba608b75737ee929db07645be86535cfc4e7e3f3145498f7e8c821d",
            stages: [
                .init(kind: .vertex, path: "shaders/effects/godrays_combine.vert", rawSHA256: "cd0636f15ff19225b5cbf10af006f9fe43d99c9b782baeb1dbfe62c507816fad"),
                .init(kind: .fragment, path: "shaders/effects/godrays_combine.frag", rawSHA256: "c4bf993a2176152b0482b04818b2f6d02f2f52018e1c160463b540ede9c0cd1b"),
            ]
        ),
    ]

    private nonisolated static func target(
        named name: String,
        graph: Graph
    ) -> Graph.RenderTarget? {
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
}
