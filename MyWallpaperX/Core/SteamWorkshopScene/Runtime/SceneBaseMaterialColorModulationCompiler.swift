import Foundation

/// Admits a package-local base material only when its prepared shader proves
/// equivalence to the existing single-texture image compositor plus typed RGB
/// tint. This is a lowering into the one compositor, not a parallel material
/// renderer.
nonisolated enum SceneBaseMaterialColorModulationCompiler {
    struct Binding: Sendable {
        let modelPath: String
        let sourceLayerID: Int
        let scriptSource: String
        let scriptProperties: [String: SceneJSONValue]
        let authoredColor: SIMD3<Double>
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        dynamicImageModelPaths: Set<String>,
        admittedLayerColorConsumerIDs: Set<Int>
    ) -> [Binding] {
        guard !shaderContracts.isEmpty,
              !admittedLayerColorConsumerIDs.isEmpty else { return [] }
        return dynamicImageModelPaths.sorted().compactMap { modelPath in
            binding(
                modelPath: modelPath,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                admittedLayerColorConsumerIDs:
                    admittedLayerColorConsumerIDs
            )
        }
    }

    private static func binding(
        modelPath: String,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        admittedLayerColorConsumerIDs: Set<Int>
    ) -> Binding? {
        let links = descriptor.modelMaterialLinks.filter {
            normalized($0.modelPath) == normalized(modelPath)
        }
        guard links.count == 1,
              let materialPath = links[0].materialPath else {
            return reject(modelPath, "model-material-link")
        }
        let passes = descriptor.materialPasses.filter {
            normalized($0.materialPath) == normalized(materialPath)
        }
        guard passes.count == 1, let pass = passes.first else {
            return reject(modelPath, "material-pass-count")
        }
        guard
              pass.passIndex == 0,
              pass.textureSlots.count == 1,
              pass.textureSlots[0] != nil,
              pass.userTextureInputs.count <= 1,
              pass.userTextureInputs.allSatisfy({ $0 == nil }),
              normalizedState(pass.blending) == "translucent",
              normalizedState(pass.depthTest) == "disabled",
              normalizedState(pass.depthWrite) == "disabled",
              normalizedState(pass.cullMode) == "nocull",
              ["", "default"].contains(normalizedState(pass.alphaWriting)),
              let shaderPath = pass.shaderPath else {
            return reject(modelPath, "material-pass-shape")
        }

        let sourceLayers = descriptor.layers.filter { layer in
            if case .some = layer.utilityLayer { return false }
            return layer.contentKind == "image"
                && layer.visible != false
                && layer.effects.isEmpty
                && layer.dependencyLayerIDs.isEmpty
                && layer.authoredDependencies.isEmpty
                && layer.parentID == nil
                && layer.childLayerIDs.isEmpty
                && admittedLayerColorConsumerIDs.contains(layer.id)
                && layer.imagePath.map(normalized) == normalized(modelPath)
        }
        guard sourceLayers.count == 1, let sourceLayer = sourceLayers.first else {
            return reject(modelPath, "source-layer-consumer")
        }

        let contracts = shaderContracts.filter {
            normalizedShader($0.identity) == normalizedShader(shaderPath)
        }
        guard contracts.count == 1, let contract = contracts.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty else {
            return reject(modelPath, "shader-contract")
        }
        let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, $0 == 0)
        })
        let prepared: SceneShaderPreparedProgram
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: contract,
            compatibilityTarget: .windowsDX11ShaderModel4,
            combos: pass.combos,
            textureReadiness: readiness
        ) {
        case let .accepted(value): prepared = value
        case .notApplicable:
            return reject(modelPath, "shader-preparation-not-applicable")
        case let .rejected(failure):
            return reject(
                modelPath,
                "shader-preparation-\(failure.code.rawValue)"
                    + (failure.details.isEmpty
                        ? "" : "-\(failure.details.joined(separator: ","))")
            )
        }
        let sources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: prepared.vertex.source,
            fragment: prepared.fragment.source
        )
        guard let fact = SceneAuthoredShaderNeutralTextureTintAnalyzer.analyze(
            vertexSource: sources.vertex,
            fragmentSource: sources.fragment
        ), fact.textureSlot == 0 else {
            return reject(modelPath, "neutral-texture-tint-proof")
        }
        guard neutralScalar(
                uniformName: fact.brightnessUniformName,
                stage: .fragment,
                expected: 1,
                pass: pass,
                prepared: prepared
              ),
              neutralScalar(
                uniformName: fact.alphaUniformName,
                stage: .fragment,
                expected: 1,
                pass: pass,
                prepared: prepared
              ),
              neutralScalar(
                uniformName: fact.powerUniformName,
                stage: .fragment,
                expected: 1,
                pass: pass,
                prepared: prepared
              ),
              fact.scrollUniformNames.count == 2,
              fact.scrollUniformNames.allSatisfy({
                neutralScalar(
                    uniformName: $0,
                    stage: .vertex,
                    expected: 0,
                    pass: pass,
                    prepared: prepared
                )
              }) else {
            return reject(modelPath, "neutral-scalar-values")
        }
        guard let colorUniform = SceneResolvedMaterialShaderSchema
                .uniqueActiveUniform(
                    named: fact.tintUniformName,
                    type: .float3,
                    stage: .fragment,
                    prepared: prepared
                ) else {
            return reject(modelPath, "color-uniform-schema")
        }
        let colorValues = pass.constantShaderValues.filter {
            colorUniform.materialKeys.contains($0.key)
        }
        guard colorValues.count == 1, let colorValue = colorValues.first?.value,
              colorValue.bindingKeys == ["script", "scriptproperties", "value"],
              colorValue.userValueKind == nil,
              colorValue.timeline == nil,
              colorValue.timelineDiagnostics.isEmpty,
              let source = colorValue.scriptSource,
              let properties = colorValue.scriptProperties,
              let components = colorValue.components,
              components.count == 3,
              components.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) })
        else { return reject(modelPath, "color-script-wrapper") }
        return .init(
            modelPath: modelPath,
            sourceLayerID: sourceLayer.id,
            scriptSource: source,
            scriptProperties: properties,
            authoredColor: .init(components[0], components[1], components[2])
        )
    }

    private static func reject(
        _ modelPath: String,
        _ reason: String
    ) -> Binding? {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-evidence-dir"
        ) {
            NSLog(
                "MWX Scene base material color: model=%@ state=rejected reason=%@ fallback=authored-layer-color",
                modelPath,
                reason
            )
        }
#endif
        return nil
    }

    private static func neutralScalar(
        uniformName: String,
        stage: SceneShaderContract.StageKind,
        expected: Double,
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        prepared: SceneShaderPreparedProgram
    ) -> Bool {
        guard let schema = SceneResolvedMaterialShaderSchema
                .uniqueActiveUniform(
                    named: uniformName,
                    type: .float,
                    stage: stage,
                    prepared: prepared
                ) else { return false }
        let authored = pass.constantShaderValues.filter {
            schema.materialKeys.contains($0.key)
        }
        if !authored.isEmpty {
            guard authored.count == 1, let value = authored.first?.value,
                  value.bindingKeys.isEmpty,
                  value.scriptSource == nil,
                  value.timeline == nil,
                  value.timelineDiagnostics.isEmpty,
                  value.components?.count == 1,
                  let scalar = value.components?.first else { return false }
            return scalar.isFinite && scalar.bitPattern == expected.bitPattern
        }
        guard let fallback = schema.defaultValue,
              fallback.componentBitPatterns.count == 1,
              fallback.authoredBindingKeys.isEmpty else { return false }
        return fallback.componentBitPatterns[0] == expected.bitPattern
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
    }

    private static func normalizedShader(_ path: String) -> String {
        var value = normalized(path)
        for suffix in [".vert", ".frag", ".json"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            break
        }
        if value.hasPrefix("shaders/") {
            value.removeFirst("shaders/".count)
        }
        return value
    }

    private static func normalizedState(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase ?? ""
    }
}
