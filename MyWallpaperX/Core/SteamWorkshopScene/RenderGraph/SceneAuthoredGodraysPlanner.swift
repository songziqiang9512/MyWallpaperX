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
    /// nil 为 radial；非 nil 为 legacy Directional 的弧度。
    let direction: Float?
    let colorRays: SIMD3<Float>
    let rayLength: Float
    let rayIntensity: Float
    /// `SAMPLES` combo：false=30 采样、true=50（强度补偿 30/50）。
    let samples50: Bool
    /// `KERNEL` combo：官方 gaussian.vert 注解默认 1（blur7a）；显式 0 用 blur13a。
    let kernel13: Bool
    /// 老编辑器 KERNEL=0 使用原始 13-tap 权重，而不是新版 blur13a 优化核。
    let legacyGaussianWeights: Bool
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
              let profile = SceneGodraysShaderProfile.resolve(shaderContracts)
        else {
#if DEBUG
            print("MWX godrays planner rejected layer=\(graph.layerID) reason=profile-topology")
#endif
            return nil
        }

        let effect = graph.effects[0]
        guard normalized(effect.definitionPath) == "effects/godrays/effect.json",
              validDefinition(in: descriptor, path: effect.definitionPath, profile: profile),
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              let firstTarget = target(named: "_rt_halfcompobuffer1", graph: graph),
              let secondTarget = target(named: "_rt_halfcompobuffer2", graph: graph),
              validTarget(firstTarget, effect: effect.key, profile: profile),
              validTarget(secondTarget, effect: effect.key, profile: profile)
        else {
#if DEBUG
            print("MWX godrays planner rejected layer=\(graph.layerID) reason=definition-target")
#endif
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
            ) else {
#if DEBUG
                print(
                    "MWX godrays planner rejected layer=\(graph.layerID) "
                        + "reason=node-\(ordinal)"
                )
#endif
                return nil
            }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: node,
                graph: graph,
                descriptor: descriptor
            )
            guard resolution.isResolved, let material = resolution.node,
                  validMaterial(
                      material,
                      ordinal: ordinal,
                      bindings: expectedBindings[ordinal],
                      profile: profile
                  )
            else {
#if DEBUG
                print(
                    "MWX godrays planner rejected layer=\(graph.layerID) "
                        + "reason=material-\(ordinal)"
                )
#endif
                return nil
            }
            resolved.append(material)
        }

        guard let maskPath = maskTexturePath(
            effect: effect,
            layer: layer,
            resolvedDownsample: resolved[0],
            profile: profile
        ),
            let downsample = downsampleConstants(resolved[0].constants),
            let cast = castConstants(resolved[1].constants, profile: profile),
            let blurX = blurScale(resolved[2].constants),
            let blurY = blurScale(resolved[3].constants),
            resolved[4].constants.isEmpty,
            let blendMode = combineBlendMode(resolved[4].combos),
            let samples50 = castSamples(resolved[1].combos),
            let kernel13 = gaussianKernel(
                resolved[2].combos,
                vertical: resolved[3].combos,
                profile: profile
            )
        else {
#if DEBUG
            print("MWX godrays planner rejected layer=\(graph.layerID) reason=parameters")
#endif
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
            direction: cast.direction,
            colorRays: cast.color,
            rayLength: cast.length,
            rayIntensity: cast.intensity,
            samples50: samples50,
            kernel13: kernel13,
            legacyGaussianWeights: profile == .legacyDirectional,
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
        effect: Graph.EffectKey,
        profile: SceneGodraysShaderProfile
    ) -> Bool {
        target.texture.kind == .framebuffer
            && target.texture.effect == effect
            && target.extent.kind == .scale
            && target.extent.first == 2
            && target.extent.second == nil
            && target.format?.lowercased()
                == (profile == .legacyDirectional ? "rgba8888" : "rgba_backbuffer")
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
}
