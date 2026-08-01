import Foundation

/// Compiles the official-shaped previous-cover event into a bounded host plan.
/// Admission is content-based: relocated assets are accepted, while sample,
/// layer, Workshop and resource identifiers never participate in selection.
enum SceneMediaThumbnailTransitionCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        currentProgram: SceneMediaThumbnailBindingProgram
    ) -> SceneMediaThumbnailBindingProgram {
        var transitions: [Int: SceneMediaThumbnailTransitionPlan] = [:]
        for layer in descriptor.layers
        where currentProgram.currentLayerIDs.contains(layer.id) {
            let candidates = layer.effects.compactMap { effect in
                plan(
                    layerID: layer.id,
                    effect: effect,
                    descriptor: descriptor,
                    shaderContracts: shaderContracts
                )
            }
            guard candidates.count == 1, let candidate = candidates.first else {
                continue
            }
            transitions[layer.id] = candidate
        }
        guard transitions.count <= maximumTransitionLayerCount else {
            return currentProgram
        }
        return SceneMediaThumbnailBindingProgram(
            currentLayerIDs: currentProgram.currentLayerIDs,
            previousTransitionsByLayerID: transitions
        )
    }

    private nonisolated static func plan(
        layerID: Int,
        effect: SceneRenderDescriptor.EffectDescriptor,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneMediaThumbnailTransitionPlan? {
        let path = normalized(effect.file)
        guard path.hasSuffix("/blendgradient/effect.json"),
              validAssetProfile(
                  effectPath: path,
                  descriptor: descriptor,
                  shaderContracts: shaderContracts
              ),
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.textureSlots.count == 3,
              pass.textureSlots[0] == nil,
              let fallback = nonEmpty(pass.textureSlots[1]),
              let gradient = nonEmpty(pass.textureSlots[2]),
              pass.texturePaths == [fallback, gradient],
              pass.userTextureInputs == [
                  nil,
                  SceneEffectTextureInput(
                      kind: .system,
                      value: SceneMediaThumbnailBindingProgram.previousIdentity
                  ),
              ],
              normalizedCombos(pass.combos) == ["EDGEGLOW": 1],
              let constants = normalizedConstants(pass.constantShaderValues),
              Set(constants.keys) == Set([
                  "alpha", "edgebrightness", "edgecolor", "gradientscale", "multiply",
              ]),
              scalar(constants["alpha"], equals: 1),
              scalar(constants["edgebrightness"], equals: 1),
              vector(constants["edgecolor"], equals: [0, 0, 0]),
              let gradientScale = scalar(constants["gradientscale"], range: 0.01...0.25),
              let duration = transitionDuration(constants["multiply"]) else {
            return nil
        }
        return SceneMediaThumbnailTransitionPlan(
            layerID: layerID,
            effectDescriptorID: effect.id,
            gradientTexturePath: gradient,
            gradientScale: gradientScale,
            durationSeconds: duration
        )
    }

    private nonisolated static func validAssetProfile(
        effectPath: String,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> Bool {
        let definitions = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == effectPath
        }
        guard definitions.count == 1, let definition = definitions.first,
              definition.rawSHA256 == effectDefinitionSHA256,
              definition.version == 1,
              definition.replacementKey?.lowercased() == "blendgradient",
              definition.group?.lowercased() == "colorize",
              definition.framebuffers.isEmpty,
              definition.passes.count == 1,
              let definitionPass = definition.passes.first,
              definitionPass.passIndex == 0,
              let materialPath = definitionPass.materialPath.map(normalized),
              definitionPass.bindings.isEmpty,
              definitionPass.target == nil,
              definitionPass.compose == nil,
              definitionPass.command == nil,
              definitionPass.source == nil,
              definitionPass.conditions == nil,
              definitionPass.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.extraFields.isEmpty else {
            return false
        }
        let materials = descriptor.materialPasses.filter {
            normalized($0.materialPath) == materialPath && $0.passIndex == 0
        }
        guard materials.count == 1, let material = materials.first,
              material.materialRawSHA256 == materialSHA256,
              let shaderIdentity = material.shaderPath.map(normalized),
              material.textureSlots.isEmpty,
              material.texturePaths.isEmpty,
              material.userTextureInputs.isEmpty,
              material.combos.isEmpty,
              material.constantShaderValues.isEmpty,
              material.userShaderValues.isEmpty,
              material.blending?.lowercased() == "normal",
              material.depthTest?.lowercased() == "disabled",
              material.depthWrite?.lowercased() == "disabled",
              material.cullMode?.lowercased() == "nocull" else {
            return false
        }
        let contracts = shaderContracts.filter { normalized($0.identity) == shaderIdentity }
        guard contracts.count == 1, let contract = contracts.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == canonicalShaderSHA256,
              contract.stages.count == 2 else {
            return false
        }
        let vertices = contract.stages.filter { $0.kind == .vertex }
        let fragments = contract.stages.filter { $0.kind == .fragment }
        return vertices.count == 1
            && fragments.count == 1
            && vertices[0].rawSHA256 == vertexShaderSHA256
            && fragments[0].rawSHA256 == fragmentShaderSHA256
            && Set(definition.dependencies.map(normalized)).isSuperset(of: [
                materialPath,
                "shaders/\(shaderIdentity).vert",
                "shaders/\(shaderIdentity).frag",
            ])
    }

    private nonisolated static func transitionDuration(
        _ value: SceneDocument.ShaderValue?
    ) -> Double? {
        guard let value,
              value.userBinding == nil,
              value.valueKind.lowercased() == "binding",
              Set(value.bindingKeys) == Set(["animation", "script", "value"]),
              value.timelineDiagnostics.isEmpty,
              validMediaEventScript(value.scriptSource),
              let animation = value.timeline,
              !animation.isRelative,
              animation.previewValue == nil,
              animation.lanes.count == 1,
              let lane = animation.lanes.first,
              lane.count == 2 else {
            return nil
        }
        let options = animation.options
        let duration = options.durationSeconds
        guard options.mode == .single,
              options.startsPaused,
              !options.wrapsLoop,
              options.smoothing == nil,
              options.stiffness == nil,
              options.parent == nil,
              options.children.isEmpty,
              options.fps.isFinite,
              (1...240).contains(options.fps),
              options.length.isFinite,
              options.length > 0,
              duration.isFinite,
              (0.05...10).contains(duration),
              keyframe(lane[0], frame: 0, value: 1),
              keyframe(lane[1], frame: options.length, value: 0) else {
            return nil
        }
        return duration
    }

    private nonisolated static func keyframe(
        _ keyframe: SceneTimelineKeyframe,
        frame: Double,
        value: Double
    ) -> Bool {
        keyframe.frame == frame
            && keyframe.value == value
            && keyframe.locksAngle == true
            && keyframe.locksLength == true
            && tangent(keyframe.back, x: -1)
            && tangent(keyframe.front, x: 1)
    }

    private nonisolated static func tangent(
        _ tangent: SceneTimelineTangent?,
        x: Double
    ) -> Bool {
        tangent?.isEnabled == true && tangent?.x == x && tangent?.y == 0
    }

    private nonisolated static func validMediaEventScript(_ source: String?) -> Bool {
        guard let source else { return false }
        let compact = source
            .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"//[^\n\r]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let pattern = #"exportfunctionmediaThumbnailChanged\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{if\(\1\.hasThumbnail\)\{(?:var|let|const)([A-Za-z_$][A-Za-z0-9_$]*)=thisObject\.getAnimation\(\);\2\.stop\(\);\2\.play\(\);?\}\}"#
        return compact.range(of: pattern, options: .regularExpression) != nil
    }

    private nonisolated static func normalizedConstants(
        _ values: [String: SceneDocument.ShaderValue]
    ) -> [String: SceneDocument.ShaderValue]? {
        var result: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in values {
            guard result.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        return result
    }

    private nonisolated static func normalizedCombos(
        _ values: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in values {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        return result
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Float>
    ) -> Float? {
        guard let value,
              value.userBinding == nil,
              value.timeline == nil,
              value.scriptSource == nil,
              value.bindingKeys.isEmpty,
              let components = value.components,
              components.count == 1,
              let raw = components.first,
              raw.isFinite else {
            return nil
        }
        let result = Float(raw)
        return range.contains(result) ? result : nil
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        equals expected: Float
    ) -> Bool {
        scalar(value, range: expected...expected) != nil
    }

    private nonisolated static func vector(
        _ value: SceneDocument.ShaderValue?,
        equals expected: [Double]
    ) -> Bool {
        value?.userBinding == nil
            && value?.timeline == nil
            && value?.scriptSource == nil
            && value?.bindingKeys.isEmpty == true
            && value?.components == expected
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let effectDefinitionSHA256 =
        "07c4d0fc7479c7c98a8290fa1c070be37e42b25a402fd0960b0d5dc79fa7ce79"
    private nonisolated static let materialSHA256 =
        "33af55c228574c4800b2f8f72327810dfd9779bdb3e77d2c2e7888a199e09ea9"
    private nonisolated static let canonicalShaderSHA256 =
        "76c476291a68d7caf0f3f38afe83aafa87d56110a5659e738f50dcc6c3aa575a"
    private nonisolated static let vertexShaderSHA256 =
        "9ac7bb9de5e8cc62f506ee0bfa895afc77bbe1c48fdc176c51efc4fe959382a1"
    private nonisolated static let fragmentShaderSHA256 =
        "12c73646d1a98dedba873bab5a067fc261256526a1d7a8e867f68f9e10fe572f"
    private nonisolated static let maximumTransitionLayerCount = 64
}
