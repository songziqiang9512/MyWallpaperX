import Foundation

/// Admits a package-local base material only when its prepared shader proves
/// equivalence to the existing single-texture image compositor plus typed RGB
/// tint. This is a lowering into the one compositor, not a parallel material
/// renderer.
nonisolated enum SceneBaseMaterialColorModulationCompiler {
    struct Binding: Sendable {
        let modelPath: String
        let sourceLayerID: Int
        let materialPath: String
        let colorKey: String
        let scriptSource: String?
        let scriptProperties: [String: SceneJSONValue]
        let authoredColor: SIMD3<Double>
        var alphaKey: String? = nil
        var authoredAlpha: Float = 1
        var alphaUserPropertyKey: String? = nil

        var alphaPropertyTarget: SceneDynamicTarget? {
            guard alphaUserPropertyKey != nil, let alphaKey else { return nil }
            return .materialConstant(layerID: sourceLayerID, passIndex: 0,
                name: alphaKey, materialPath: materialPath)
        }
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        dynamicImageModelPaths: Set<String>,
        admittedLayerColorConsumerIDs: Set<Int>
    ) -> [Binding] {
        guard !shaderContracts.isEmpty,
              !admittedLayerColorConsumerIDs.isEmpty else { return [] }
        let dynamicPaths = Set(dynamicImageModelPaths.map(normalized))
        let modelPaths = dynamicPaths.union(descriptor.layers.compactMap(\.imagePath).map(normalized))
        return modelPaths.sorted().compactMap { modelPath in
            guard let result = binding(
                modelPath: modelPath,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                admittedLayerColorConsumerIDs:
                    admittedLayerColorConsumerIDs
            ), result.scriptSource == nil || dynamicPaths.contains(modelPath) else { return nil }
            return result
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
              pass.userShaderValues.isEmpty,
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
                && layer.puppetMeshPath == nil
                && layer.staticModelPath == nil
                && layer.staticBaseTexturePath == nil
                && layer.usesPerspective != true
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
        guard let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(prepared),
              samplers.count == 1, let sampler = samplers[0], sampler.mode == .regular,
              !sampler.hasExplicitNonColorPurpose, !sampler.usesGraphInputMaterialAlias else {
            return reject(modelPath, "sampler-color-contract")
        }
        let colorSampler = sampler.permitsSourceStraightColorProjection
            ? sampler.withSourceProvenPurpose(.straightAlbedo) : sampler
        guard let asset = pass.textureSlots[0].flatMap(SceneVFSAssetPath.init),
              colorSampler.purpose(for: .asset(asset)) == .straightAlbedo else {
            return reject(modelPath, "sampler-asset-purpose")
        }
        // Shape alone cannot prove an arbitrary mat4 is the quad's host MVP.
        // Keep matrix binding semantics in the shared schema authority.
        guard SceneResolvedMaterialHostUniformSchema.resolve(
            .init(name: fact.positionMatrixUniformName, stage: .vertex, type: .float4x4, offset: 0),
            activeTextureSlots: [0]
        ) == .modelViewProjection,
        let matrixSchema = SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
            named: fact.positionMatrixUniformName, type: .float4x4, stage: .vertex, prepared: prepared
        ), matrixSchema.defaultValue == nil,
        matrixSchema.materialKeys.allSatisfy({ pass.constantShaderValues[$0] == nil }) else {
            return reject(modelPath, "position-matrix-binding")
        }
        guard neutralScalar(
                uniformName: fact.brightnessUniformName,
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
        guard let alpha = alphaBinding(
            uniformName: fact.alphaUniformName, pass: pass, prepared: prepared
        ) else { return reject(modelPath, "alpha-binding") }
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
        guard colorValues.count == 1, let colorEntry = colorValues.first else {
            return reject(modelPath, "color-binding-count")
        }
        let colorValue = colorEntry.value
        guard
              (colorValue.bindingKeys.isEmpty
                  || colorValue.bindingKeys == ["script", "scriptproperties", "value"]),
              colorValue.userValueKind == nil,
              colorValue.timeline == nil,
              colorValue.timelineDiagnostics.isEmpty,
              (colorValue.bindingKeys.isEmpty
                  ? colorValue.scriptSource == nil && colorValue.scriptProperties == nil
                  : colorValue.scriptSource != nil && colorValue.scriptProperties != nil),
              let components = colorValue.components,
              components.count == 3,
              components.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) })
        else { return reject(modelPath, "color-binding") }
        let tokens = colorValue.rawValue.split(whereSeparator: { $0.isWhitespace || $0 == "," })
        guard tokens.count == 3, zip(tokens, components).allSatisfy({ Double($0.0) == $0.1 })
        else { return reject(modelPath, "color-value") }
        return .init(
            modelPath: modelPath,
            sourceLayerID: sourceLayer.id,
            materialPath: normalized(pass.materialPath),
            colorKey: colorEntry.key,
            scriptSource: colorValue.scriptSource,
            scriptProperties: colorValue.scriptProperties ?? [:],
            authoredColor: .init(components[0], components[1], components[2]),
            alphaKey: alpha.key, authoredAlpha: alpha.value,
            alphaUserPropertyKey: alpha.userKey
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

    private static func alphaBinding(
        uniformName: String,
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        prepared: SceneShaderPreparedProgram
    ) -> (key: String?, value: Float, userKey: String?)? {
        guard SceneResolvedMaterialHostUniformSchema.resolve(
            .init(name: uniformName, stage: .fragment, type: .float, offset: 0),
            activeTextureSlots: [0]
        ) == nil,
        let schema = SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
            named: uniformName, type: .float, stage: .fragment, prepared: prepared
        ) else { return nil }
        let authored = pass.constantShaderValues.filter { schema.materialKeys.contains($0.key) }
        guard !authored.isEmpty else {
            guard let fallback = schema.defaultValue,
                  fallback.componentBitPatterns.count == 1,
                  fallback.authoredBindingKeys.isEmpty else { return nil }
            let value = Double(bitPattern: fallback.componentBitPatterns[0])
            guard value.isFinite, (0 ... 1).contains(value) else { return nil }
            return (nil, Float(value), nil)
        }
        guard authored.count == 1, let entry = authored.first else { return nil }
        let value = entry.value
        let tokens = value.rawValue.split(whereSeparator: { $0.isWhitespace || $0 == "," })
        guard tokens.count == 1, let scalar = Double(tokens[0]),
              scalar.isFinite, (0 ... 1).contains(scalar), value.components == [scalar],
              value.scriptSource == nil, value.scriptProperties == nil,
              value.timeline == nil, value.timelineDiagnostics.isEmpty else { return nil }
        if value.bindingKeys.isEmpty {
            guard value.userValueKind == nil, value.userBinding == nil else { return nil }
            return (entry.key, Float(scalar), nil)
        }
        guard value.bindingKeys.sorted() == ["user", "value"],
              value.userValueKind == .string, let key = value.userBinding, !key.isEmpty
        else { return nil }
        return (entry.key, Float(scalar), key)
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
            let tokens = value.rawValue.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            return tokens.count == 1 && Double(tokens[0]) == scalar
                && scalar.isFinite && scalar.bitPattern == expected.bitPattern
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
