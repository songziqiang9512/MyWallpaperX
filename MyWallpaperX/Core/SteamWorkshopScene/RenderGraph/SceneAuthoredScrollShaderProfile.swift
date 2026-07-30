import Foundation

/// Exact source-only Scroll profiles whose hidden `g_Texture0` is the current
/// effect input. The stock and one relocated Workshop revision predate the
/// explicit `material: "framebuffer"` annotation, so the generic authored
/// shader planner may infer slot 0 only after this complete profile matches.
nonisolated enum SceneAuthoredScrollShaderProfile {
    case stock2842
    case workshop3302578859
    case workshop3387825383

    static func resolve(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        contract: SceneShaderContract,
        program: SceneAuthoredShaderProgram
    ) -> Self? {
        guard graph.effects.count == 1,
              graph.nodes.count == 1,
              let effect = graph.effects.first,
              let node = graph.nodes.first,
              let specification = specifications.first(where: {
                  normalized(effect.definitionPath) == $0.definitionPath
                      && normalized(node.materialPath) == $0.materialPath
                      && normalized(node.materialPassID) == "\($0.materialPath)#0"
                      && normalized(contract.identity) == $0.shaderIdentity
              }),
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == specification.canonicalSHA256,
              contract.stages.count == specification.stages.count,
              zip(contract.stages, specification.stages).allSatisfy({
                  stage, expected in
                  stage.kind == expected.kind
                      && normalized(stage.relativePath) == expected.path
                      && stage.rawSHA256 == expected.rawSHA256
              }),
              program.textureBindings.count == 1,
              program.textureBindings[0].name == "g_Texture0",
              program.textureBindings[0].slot == 0,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              layer.effects.indices.contains(effect.key.effectIndex),
              let pass = matchingPass(
                  effect: effect,
                  layer: layer,
                  specification: specification
              ),
              valid(values: pass.constantShaderValues) else {
            return nil
        }
        return specification.profile
    }

    var inferredFramebufferSlots: Set<Int> { [0] }

    private static func matchingPass(
        effect: SceneAuthoredEffectRenderPlan.Effect,
        layer: SceneRenderDescriptor.Layer,
        specification: Specification
    ) -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor? {
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0,
              pass.textureSlots.isEmpty,
              pass.userTextureInputs.isEmpty,
              pass.combos.isEmpty,
              normalized(effect.definitionPath) == specification.definitionPath else {
            return nil
        }
        return pass
    }

    private static func valid(
        values: [String: SceneDocument.ShaderValue]
    ) -> Bool {
        guard Set(values.keys.map { $0.lowercased() }) == constantKeys,
              let repeatValue = components(values["repeat"], count: 2),
              repeatValue.allSatisfy({ (0.01...10).contains($0) }),
              let speedX = components(values["speedx"], count: 1)?.first,
              let speedY = components(values["speedy"], count: 1)?.first,
              (-2...2).contains(speedX),
              (-2...2).contains(speedY) else {
            return false
        }
        return true
    }

    private static func components(
        _ value: SceneDocument.ShaderValue?,
        count: Int
    ) -> [Float]? {
        guard let value,
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              let components = value.components,
              components.count == count,
              components.allSatisfy(\.isFinite) else {
            return nil
        }
        return components.map(Float.init)
    }

    private struct Specification {
        let profile: SceneAuthoredScrollShaderProfile
        let definitionPath: String
        let materialPath: String
        let shaderIdentity: String
        let canonicalSHA256: String
        let stages: [StageFingerprint]
    }

    private struct StageFingerprint {
        let kind: SceneShaderContract.StageKind
        let path: String
        let rawSHA256: String
    }

    private static func normalized(_ value: String?) -> String {
        value?
            .replacingOccurrences(of: "\\", with: "/")
            .localizedLowercase ?? ""
    }

    private static let constantKeys = Set(["repeat", "speedx", "speedy"])
    private static let vertexSHA256 =
        "c7b1ec124d749cb78f5da6e643e790322422defb2d770f7e72cf45035f46d4f2"
    private static let specifications = [
        Specification(
            profile: .stock2842,
            definitionPath: "effects/scroll/effect.json",
            materialPath: "materials/effects/scroll.json",
            shaderIdentity: "effects/scroll",
            canonicalSHA256:
                "f094c0a44eca83dd0e13cfe3b061df5d9b4b13638f9997ccfc6165913d306a65",
            stages: [
                .init(
                    kind: .vertex,
                    path: "shaders/effects/scroll.vert",
                    rawSHA256: vertexSHA256
                ),
                .init(
                    kind: .fragment,
                    path: "shaders/effects/scroll.frag",
                    rawSHA256:
                        "0fea7e82941aff6302e0560b37f072be61448e9fbe3cd846b603857d80b91d84"
                ),
            ]
        ),
        Specification(
            profile: .workshop3302578859,
            definitionPath: "effects/workshop/3302578859/scroll/effect.json",
            materialPath: "materials/workshop/3302578859/effects/scroll.json",
            shaderIdentity: "workshop/3302578859/effects/scroll",
            canonicalSHA256:
                "dd44532865ec83022adfb7eae33a3b20dc8a4584f551b8e2b9fc4d36bfa00c5a",
            stages: [
                .init(
                    kind: .vertex,
                    path: "shaders/workshop/3302578859/effects/scroll.vert",
                    rawSHA256: vertexSHA256
                ),
                .init(
                    kind: .fragment,
                    path: "shaders/workshop/3302578859/effects/scroll.frag",
                    rawSHA256:
                        "caf5d4f91ed6b174afb68740348a6ef99a15667324294ec3f0636799c856688d"
                ),
            ]
        ),
        Specification(
            profile: .workshop3387825383,
            definitionPath: "effects/workshop/3387825383/scroll/effect.json",
            materialPath: "materials/workshop/3387825383/effects/scroll.json",
            shaderIdentity: "workshop/3387825383/effects/scroll",
            canonicalSHA256:
                "b402fb6f312703bec796ec986c23ce6524826840df68b61eeb86a682062d6202",
            stages: [
                .init(
                    kind: .vertex,
                    path: "shaders/workshop/3387825383/effects/scroll.vert",
                    rawSHA256: vertexSHA256
                ),
                .init(
                    kind: .fragment,
                    path: "shaders/workshop/3387825383/effects/scroll.frag",
                    rawSHA256:
                        "91ef4b402d0c904772b8f26db9d0c1d2abc0f1647da76382d9924e404b310eb8"
                ),
            ]
        ),
    ]
}
