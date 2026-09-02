import Foundation

nonisolated struct SceneScriptVectorCandidate: Sendable {
    let authoredOrdinal: Int
    let source: String
    let definition: SceneDynamicTargetDefinition
    let properties: [String: SceneScriptPropertyInput]
    let livePropertyInputTargets: Set<SceneDynamicTarget>
    let hasCurrentAnimation: Bool
    let dynamicImageReferences: [SceneScriptDynamicImageReference]
    /// Package-local image model whose proven neutral base-material tint is
    /// driven by this typed owner. Dynamic instances reuse the target value;
    /// the model path never selects an algorithm.
    let dynamicMaterialModelPath: String?

    var allowsDynamicLayerSideEffects: Bool {
        !dynamicImageReferences.isEmpty
    }
}

/// Side-effect-free projection of authored non-scalar typed bindings. Pass-owned
/// candidates are only metadata until resolved-material admission identifies
/// an actual consumer; projecting this catalog never evaluates JavaScript.
nonisolated struct SceneScriptVectorCandidateCatalog: Sendable {
    let candidates: [SceneScriptVectorCandidate]
    let duplicateTargets: Set<SceneDynamicTarget>

    static let empty = Self(candidates: [])

    init(candidates: [SceneScriptVectorCandidate]) {
        self.candidates = candidates
        let counts = Dictionary(grouping: candidates, by: { $0.definition.target })
            .mapValues(\.count)
        duplicateTargets = Set(counts.compactMap { target, count in
            count > 1 ? target : nil
        })
    }

    var uniqueCandidates: [SceneScriptVectorCandidate] {
        candidates.filter { !duplicateTargets.contains($0.definition.target) }
    }

    var definitions: [SceneDynamicTargetDefinition] {
        candidates.map(\.definition)
    }

    var targets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.map { $0.definition.target })
    }

    var passTargets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.compactMap { candidate in
            guard case .effectConstant = candidate.definition.target else {
                return nil
            }
            return candidate.definition.target
        })
    }

    var nonPassTargets: Set<SceneDynamicTarget> {
        targets.subtracting(passTargets)
    }

    var animationTargets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.compactMap { candidate in
            candidate.hasCurrentAnimation ? candidate.definition.target : nil
        })
    }

    func excludingTargets(
        _ targets: Set<SceneDynamicTarget>
    ) -> SceneScriptVectorCandidateCatalog {
        guard !targets.isEmpty else { return self }
        return .init(candidates: candidates.filter {
            !targets.contains($0.definition.target)
        })
    }

    var admittedScaleLayerIDs: Set<Int> {
        Set(uniqueCandidates.compactMap { candidate in
            guard case let .layer(layerID, .scale) = candidate.definition.target else {
                return nil
            }
            return layerID
        })
    }

    var dynamicImageModelPaths: Set<String> {
        Set(uniqueCandidates.flatMap(\.dynamicImageReferences).map(\.modelPath))
    }

    var dynamicImageMaterialColorTargets: [String: SceneDynamicTarget] {
        let entries = uniqueCandidates.compactMap { candidate -> (
            String, SceneDynamicTarget
        )? in
            guard let path = candidate.dynamicMaterialModelPath else {
                return nil
            }
            return (path.lowercased(), candidate.definition.target)
        }
        let grouped = Dictionary(grouping: entries, by: \.0)
        return Dictionary(uniqueKeysWithValues: grouped.compactMap { path, values in
            guard values.count == 1, let target = values.first?.1 else {
                return nil
            }
            return (path, target)
        })
    }
}

nonisolated struct SceneScriptVectorPassCompilation: Sendable {
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]

    var failedTargets: Set<SceneDynamicTarget> { Set(failures.keys) }
    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failedTargets)
    }
}

nonisolated struct SceneScriptVectorProgramConstruction: @unchecked Sendable {
    let program: SceneScriptVectorProgram
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]

    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failures.keys)
    }
}

nonisolated extension SceneScriptVectorProgram {
    static func project(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        admittedLayerColorConsumerIDs: Set<Int> = [],
        shaderContracts: [SceneShaderContract] = [],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> SceneScriptVectorCandidateCatalog {
        let namedTextureDependencyLayerIDs =
            SceneNamedTextureDependencyReferenceAnalysis.participatingLayerIDs(
                in: descriptor.layers
            )
        let authoredCandidates = scriptBindings.enumerated().compactMap {
            authoredOrdinal, binding in
            projection(
                binding,
                authoredOrdinal: authoredOrdinal,
                descriptor: descriptor,
                timelineTargets: timelineTargets,
                admittedLayerColorConsumerIDs: admittedLayerColorConsumerIDs,
                namedTextureDependencyLayerIDs: namedTextureDependencyLayerIDs
            )
        }
        let dynamicModelPaths = Set(
            authoredCandidates.flatMap(\.dynamicImageReferences).map(\.modelPath)
        )
        let materialBindings = SceneBaseMaterialColorModulationCompiler.compile(
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            dynamicImageModelPaths: dynamicModelPaths,
            admittedLayerColorConsumerIDs: admittedLayerColorConsumerIDs
        )
        let materialCandidates = materialBindings.enumerated().compactMap {
            offset, binding in
            dynamicMaterialColorProjection(
                binding,
                authoredOrdinal: scriptBindings.count + offset
            )
        }
        let occupiedTargets = Set(
            (authoredCandidates + materialCandidates).map {
                $0.definition.target
            }
        )
        let staticModelMaterialCandidates = staticModelViewTintProjections(
            descriptor: descriptor,
            admittedLayerColorConsumerIDs: admittedLayerColorConsumerIDs,
            excluding: occupiedTargets,
            authoredOrdinalOffset:
                scriptBindings.count + materialCandidates.count
        )
        return .init(candidates: (
            authoredCandidates + materialCandidates
                + staticModelMaterialCandidates
        ).filter {
            !excludedTargets.contains($0.definition.target)
        })
    }

    /// A direct model's scripted back-facing tint is lowered into the existing
    /// layer-color dynamic slot only when that slot has no authored owner.
    /// The material field name selects the shared view-tint primitive; model,
    /// sample, path, and shader identity never select a visual algorithm.
    private static func staticModelViewTintProjections(
        descriptor: SceneRenderDescriptor,
        admittedLayerColorConsumerIDs: Set<Int>,
        excluding occupiedTargets: Set<SceneDynamicTarget>,
        authoredOrdinalOffset: Int
    ) -> [SceneScriptVectorCandidate] {
        let linksByModel = Dictionary(grouping: descriptor.modelMaterialLinks) {
            normalizedMaterialPath($0.modelPath)
        }
        let passesByMaterial = Dictionary(grouping: descriptor.materialPasses) {
            normalizedMaterialPath($0.materialPath)
        }
        var candidates: [SceneScriptVectorCandidate] = []
        for layer in descriptor.layers where layer.staticModelPath != nil {
            let target = SceneDynamicTarget.layer(
                layerID: layer.id,
                field: .color
            )
            guard admittedLayerColorConsumerIDs.contains(layer.id),
                  !occupiedTargets.contains(target),
                  layer.visible != false,
                  let modelPath = layer.staticModelPath,
                  let links = linksByModel[normalizedMaterialPath(modelPath)],
                  links.count == 1,
                  let materialPath = links[0].materialPath,
                  let materialPasses = passesByMaterial[
                    normalizedMaterialPath(materialPath)
                  ],
                  case let firstPasses = materialPasses.filter({
                    $0.passIndex == 0
                  }),
                  firstPasses.count == 1,
                  let pass = firstPasses.first,
                  let entry = pass.constantShaderValues.first(where: {
                    $0.key.localizedCaseInsensitiveCompare("tintback")
                        == .orderedSame
                  }),
                  entry.value.bindingKeys
                    == ["script", "scriptproperties", "value"],
                  entry.value.userValueKind == nil,
                  entry.value.timeline == nil,
                  entry.value.timelineDiagnostics.isEmpty,
                  let source = entry.value.scriptSource,
                  materialValueSource(source),
                  let properties = entry.value.scriptProperties,
                  let inputs = SceneScriptPropertyInputCodec.inputs(properties),
                  let components = entry.value.components,
                  components.count == 3,
                  components.allSatisfy({
                    $0.isFinite && (0 ... 1).contains($0)
                  }) else { continue }
            candidates.append(.init(
                authoredOrdinal: authoredOrdinalOffset + candidates.count,
                source: source,
                definition: .init(
                    target: target,
                    valueType: .vector3,
                    authoredValue: .vector3(
                        components[0], components[1], components[2]
                    )
                ),
                properties: inputs,
                livePropertyInputTargets: [],
                hasCurrentAnimation: false,
                dynamicImageReferences: [],
                dynamicMaterialModelPath: nil
            ))
        }
        return candidates
    }

    private static func normalizedMaterialPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
    }

    private static func dynamicMaterialColorProjection(
        _ binding: SceneBaseMaterialColorModulationCompiler.Binding,
        authoredOrdinal: Int
    ) -> SceneScriptVectorCandidate? {
        guard materialValueSource(binding.scriptSource) else { return nil }
        var properties: [String: SceneScriptPropertyInput] = [:]
        for entry in binding.scriptProperties {
            guard validName(entry.key),
                  let input = propertyInput(entry.value) else { return nil }
            properties[entry.key] = input
        }
        return .init(
            authoredOrdinal: authoredOrdinal,
            source: binding.scriptSource,
            definition: .init(
                target: .layer(
                    layerID: binding.sourceLayerID,
                    field: .color
                ),
                valueType: .vector3,
                authoredValue: .vector3(
                    binding.authoredColor.x,
                    binding.authoredColor.y,
                    binding.authoredColor.z
                )
            ),
            properties: properties,
            livePropertyInputTargets: [],
            hasCurrentAnimation: false,
            dynamicImageReferences: [],
            dynamicMaterialModelPath: binding.modelPath
        )
    }

    private static func materialValueSource(_ source: String) -> Bool {
        guard source.utf8.count <= 65_536,
              source.range(
                of: #"(?m)(?<![A-Za-z0-9_$])export\s+function\s+(?:init|update)\s*\("#,
                options: .regularExpression
              ) != nil,
              !source.contains("\\u"), !source.contains("\\x") else {
            return false
        }
        let mutableDependencies = [
            "shared", "globalThis", "eval", "Function", "constructor",
            "thisLayer", "thisScene", "thisObject", "setTimeout",
            "setInterval", "requestAnimationFrame",
        ]
        return mutableDependencies.allSatisfy {
            !containsIdentifier($0, in: source)
        }
    }

    private static func projection(
        _ binding: SceneScriptBindingIR,
        authoredOrdinal: Int,
        descriptor: SceneRenderDescriptor,
        timelineTargets: Set<SceneDynamicTarget>,
        admittedLayerColorConsumerIDs: Set<Int>,
        namedTextureDependencyLayerIDs: Set<Int>
    ) -> SceneScriptVectorCandidate? {
        if let candidate = visibilityProjection(
            binding,
            authoredOrdinal: authoredOrdinal,
            descriptor: descriptor
        ) {
            return candidate
        }
        if let candidate = layerColorProjection(
            binding,
            authoredOrdinal: authoredOrdinal,
            descriptor: descriptor,
            admittedLayerColorConsumerIDs: admittedLayerColorConsumerIDs,
            namedTextureDependencyLayerIDs: namedTextureDependencyLayerIDs
        ) {
            return candidate
        }
        if let candidate = passVectorProjection(
            binding,
            authoredOrdinal: authoredOrdinal,
            descriptor: descriptor
        ) {
            return candidate
        }
        guard binding.owner.kind == .object,
              ["origin", "scale", "angles"].contains(binding.targetKey),
              binding.valueType == .string,
              let sourceValue = binding.authoredValue?.stringValue,
              let authored = vector3(sourceValue),
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              descriptor.layers.indices.contains(objectIndex) else { return nil }
        let layer = descriptor.layers[objectIndex]
        guard layer.id == layerID, layer.layerIndex == objectIndex,
              binding.targetPath == [
                  .key("objects"), .index(objectIndex), .key(binding.targetKey),
              ] else { return nil }
        let descriptorValue: [Float]?
        let target: SceneDynamicTarget
        switch binding.targetKey {
        case "origin":
            descriptorValue = layer.originXYZ
            target = .layer(layerID: layerID, field: .origin)
        case "scale":
            descriptorValue = layer.scaleXYZ
            target = .layer(layerID: layerID, field: .scale)
        case "angles":
            descriptorValue = layer.anglesXYZ
            target = .layer(layerID: layerID, field: .angles)
        default:
            return nil
        }
        let hasCurrentAnimation = timelineTargets.contains(target)
        let validWrapper =
            (binding.wrapperKeys == ["script", "value"] && binding.properties.isEmpty)
            || SceneScriptDynamicProviderHostContract.supports(
                keys: binding.wrapperKeys ?? [],
                host: .objectVector
            )
            || (binding.wrapperKeys == ["animation", "script", "value"]
                && binding.properties.isEmpty && hasCurrentAnimation)
        guard validWrapper else { return nil }
        guard let descriptorValue, descriptorValue.count == 3,
              Float(authored.x).bitPattern == descriptorValue[0].bitPattern,
              Float(authored.y).bitPattern == descriptorValue[1].bitPattern,
              Float(authored.z).bitPattern == descriptorValue[2].bitPattern else {
            return nil
        }
        var properties: [String: SceneScriptPropertyInput] = [:]
        for entry in binding.properties {
            guard validName(entry.key),
                  let input = propertyInput(entry.value) else { return nil }
            properties[entry.key] = input
        }
        return .init(
            authoredOrdinal: authoredOrdinal,
            source: binding.source,
            definition: .init(
                target: target,
                valueType: .vector3,
                authoredValue: .vector3(authored.x, authored.y, authored.z)
            ),
            properties: properties,
            livePropertyInputTargets:
                SceneScriptPropertyInputCodec.liveConsumerTargets(
                    binding: binding,
                    inputs: properties
                ),
            hasCurrentAnimation: hasCurrentAnimation,
            dynamicImageReferences: [],
            dynamicMaterialModelPath: nil
        )
    }

    /// Object color scripts only become VM owners after launch planning has
    /// identified an existing typed consumer. Images consume the value in the
    /// one compositor; text consumes it while rerasterizing its canonical
    /// provider publication before any authored effect suffix executes.
    private static func layerColorProjection(
        _ binding: SceneScriptBindingIR,
        authoredOrdinal: Int,
        descriptor: SceneRenderDescriptor,
        admittedLayerColorConsumerIDs: Set<Int>,
        namedTextureDependencyLayerIDs: Set<Int>
    ) -> SceneScriptVectorCandidate? {
        guard binding.owner.kind == .object,
              binding.targetKey == "color",
              binding.valueType == .string,
              let sourceValue = binding.authoredValue?.stringValue,
              let authored = vector3(sourceValue),
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              admittedLayerColorConsumerIDs.contains(layerID),
              descriptor.layers.indices.contains(objectIndex) else { return nil }
        let layer = descriptor.layers[objectIndex]
        let validWrapper =
            (binding.wrapperKeys == ["script", "value"]
                && binding.properties.isEmpty)
            || SceneScriptDynamicProviderHostContract.supports(
                keys: binding.wrapperKeys ?? [],
                host: .objectVector
            )
        guard validWrapper else { return nil }
        let target: SceneDynamicTarget
        switch layer.contentKind {
        case "image":
            guard layer.effects.isEmpty else { return nil }
            target = .layer(layerID: layerID, field: .color)
        case "text":
            guard layer.text != nil, layer.textStyle != nil else { return nil }
            target = .text(layerID: layerID, field: .color)
        case "spotLight":
            guard layer.spotLight != nil else { return nil }
            target = .layer(layerID: layerID, field: .color)
        case "directionalLight":
            guard layer.directionalLight != nil else { return nil }
            target = .layer(layerID: layerID, field: .color)
        default:
            return nil
        }
        guard layer.id == layerID,
              layer.layerIndex == objectIndex,
              layer.visible != false,
              layer.dependencyLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty,
              !namedTextureDependencyLayerIDs.contains(layerID),
              case nil = layer.utilityLayer,
              binding.targetPath == [
                  .key("objects"), .index(objectIndex), .key("color"),
              ],
              let descriptorValue = layer.colorRGB,
              descriptorValue.count == 3,
              Float(authored.x).bitPattern == descriptorValue[0].bitPattern,
              Float(authored.y).bitPattern == descriptorValue[1].bitPattern,
              Float(authored.z).bitPattern == descriptorValue[2].bitPattern else {
            return nil
        }
        var properties: [String: SceneScriptPropertyInput] = [:]
        for entry in binding.properties {
            guard validName(entry.key),
                  let input = propertyInput(entry.value) else { return nil }
            properties[entry.key] = input
        }
        return .init(
            authoredOrdinal: authoredOrdinal,
            source: binding.source,
            definition: .init(
                target: target,
                valueType: .vector3,
                authoredValue: .vector3(authored.x, authored.y, authored.z)
            ),
            properties: properties,
            livePropertyInputTargets:
                SceneScriptPropertyInputCodec.liveConsumerTargets(
                    binding: binding,
                    inputs: properties
                ),
            hasCurrentAnimation: false,
            dynamicImageReferences: [],
            dynamicMaterialModelPath: nil
        )
    }

    private static func visibilityProjection(
        _ binding: SceneScriptBindingIR,
        authoredOrdinal: Int,
        descriptor: SceneRenderDescriptor
    ) -> SceneScriptVectorCandidate? {
        guard binding.owner.kind == .object,
              binding.targetKey == "visible",
              binding.valueType == .boolean,
              let authored = binding.authoredValue?.boolValue,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              descriptor.layers.indices.contains(objectIndex) else { return nil }
        let layer = descriptor.layers[objectIndex]
        let dynamicImageReferences =
            SceneScriptDynamicImageReferenceAnalysis.references(
                in: binding.source,
                descriptor: descriptor
            ) ?? []
        let isIndependent = independentBooleanValueSource(binding.source)
        guard isIndependent || !dynamicImageReferences.isEmpty,
              layer.id == layerID,
              layer.layerIndex == objectIndex,
              layer.visible == authored,
              binding.targetPath == [
                  .key("objects"), .index(objectIndex), .key("visible"),
              ],
              (isIndependent
                ? ["image", "solid", "text"].contains(layer.contentKind)
                : layer.contentKind == "image"),
              layer.parentID == nil,
              layer.childLayerIDs.isEmpty,
              case nil = layer.utilityLayer else { return nil }
        let validWrapper =
            (binding.wrapperKeys == ["script", "value"]
                && binding.properties.isEmpty)
            || SceneScriptDynamicProviderHostContract.supports(
                keys: binding.wrapperKeys ?? [],
                host: .objectVisibility
            )
        guard validWrapper else { return nil }
        var properties: [String: SceneScriptPropertyInput] = [:]
        for entry in binding.properties {
            guard validName(entry.key),
                  let input = propertyInput(entry.value) else { return nil }
            properties[entry.key] = input
        }
        return .init(
            authoredOrdinal: authoredOrdinal,
            source: binding.source,
            definition: .init(
                target: .layer(layerID: layerID, field: .visibility),
                valueType: .bool,
                authoredValue: .bool(authored)
            ),
            properties: properties,
            livePropertyInputTargets:
                SceneScriptPropertyInputCodec.liveConsumerTargets(
                    binding: binding,
                    inputs: properties
                ),
            hasCurrentAnimation: false,
            dynamicImageReferences: dynamicImageReferences,
            dynamicMaterialModelPath: nil
        )
    }

    /// Boolean value-return owners remain isolated from shared/global state
    /// until authored cross-owner rollback is transactional. Read-only scene
    /// lookup is allowed because layer/effect/animation writes are collected by
    /// the host and rejected before a Boolean value is published. Graph and
    /// named-texture dependencies remain independently admitted by the graph;
    /// they do not change ownership of the visibility value itself.
    private static func independentBooleanValueSource(_ source: String) -> Bool {
        guard source.utf8.count <= 65_536,
              source.range(
                  of: #"(?m)(?<![A-Za-z0-9_$])export\s+function\s+(?:init|update)\s*\("#,
                  options: .regularExpression
              ) != nil,
              !source.contains("\\u"), !source.contains("\\x") else {
            return false
        }
        let mutableDependencies = [
            "shared", "globalThis", "eval", "Function", "constructor",
            "thisLayer", "thisObject",
        ]
        return mutableDependencies.allSatisfy {
            !containsIdentifier($0, in: source)
        }
    }

    private static func containsIdentifier(
        _ identifier: String,
        in source: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: identifier)
        return source.range(
            of: "(?<![A-Za-z0-9_$])\(escaped)(?![A-Za-z0-9_$])",
            options: .regularExpression
        ) != nil
    }

    private static func passVectorProjection(
        _ binding: SceneScriptBindingIR,
        authoredOrdinal: Int,
        descriptor: SceneRenderDescriptor
    ) -> SceneScriptVectorCandidate? {
        guard binding.owner.kind == .pass,
              binding.valueType == .string,
              let sourceValue = binding.authoredValue?.stringValue,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              let effectIndex = binding.owner.effectIndex,
              let passIndex = binding.owner.passIndex,
              descriptor.layers.indices.contains(objectIndex) else { return nil }
        let layer = descriptor.layers[objectIndex]
        guard layer.id == layerID, layer.layerIndex == objectIndex,
              layer.effects.indices.contains(effectIndex) else { return nil }
        let effect = layer.effects[effectIndex]
        guard effect.effectID == binding.owner.effectID,
              effect.passes.indices.contains(passIndex) else { return nil }
        let pass = effect.passes[passIndex]
        let name = binding.targetKey
        guard pass.passIndex == passIndex, pass.id == binding.owner.passID,
              !name.isEmpty,
              binding.targetPath == passConstantPath(
                  objectIndex: objectIndex, effectIndex: effectIndex,
                  passIndex: passIndex, name: name
              ),
              let descriptorValue = pass.constantShaderValues[name],
              descriptorValue.scriptSource == binding.source else {
            return nil
        }
        let definition: SceneDynamicTargetDefinition
        if let authored = vector2(sourceValue),
           descriptorValue.components?.count == 2,
           descriptorValue.components?[0].bitPattern == authored.x.bitPattern,
           descriptorValue.components?[1].bitPattern == authored.y.bitPattern {
            definition = .init(
                target: .effectConstant(
                    layerID: layerID, effectIndex: effectIndex,
                    passIndex: passIndex, name: name
                ),
                valueType: .vector2,
                authoredValue: .vector2(authored.x, authored.y)
            )
        } else if let authored = vector3(sourceValue),
                  descriptorValue.components?.count == 3,
                  descriptorValue.components?[0].bitPattern == authored.x.bitPattern,
                  descriptorValue.components?[1].bitPattern == authored.y.bitPattern,
                  descriptorValue.components?[2].bitPattern == authored.z.bitPattern {
            definition = .init(
                target: .effectConstant(
                    layerID: layerID, effectIndex: effectIndex,
                    passIndex: passIndex, name: name
                ),
                valueType: .vector3,
                authoredValue: .vector3(authored.x, authored.y, authored.z)
            )
        } else {
            return nil
        }
        let validWrapper =
            (binding.wrapperKeys == ["script", "value"]
                && binding.properties.isEmpty
                && descriptorValue.userValueKind == nil)
            || (SceneScriptDynamicProviderHostContract
                .supports(
                    keys: binding.wrapperKeys ?? [],
                    host: .passConstant
                )
                && (descriptorValue.userValueKind == nil
                    || descriptorValue.userValueKind == .null))
            || (binding.wrapperKeys == ["script", "user", "value"]
                && binding.properties.isEmpty
                && descriptorValue.userValueKind == .null)
        guard validWrapper else { return nil }
        var properties: [String: SceneScriptPropertyInput] = [:]
        for entry in binding.properties {
            guard validName(entry.key),
                  let input = propertyInput(entry.value) else { return nil }
            properties[entry.key] = input
        }
        return .init(
            authoredOrdinal: authoredOrdinal,
            source: binding.source,
            definition: definition,
            properties: properties,
            livePropertyInputTargets:
                SceneScriptPropertyInputCodec.liveConsumerTargets(
                    binding: binding,
                    inputs: properties
                ),
            hasCurrentAnimation: false,
            dynamicImageReferences: [],
            dynamicMaterialModelPath: nil
        )
    }

    static func passConstantPath(
        objectIndex: Int, effectIndex: Int, passIndex: Int, name: String
    ) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(objectIndex),
            .key("effects"), .index(effectIndex),
            .key("passes"), .index(passIndex),
            .key("constantshadervalues"), .key(name),
        ]
    }

    static func propertyInput(
        _ value: SceneJSONValue
    ) -> SceneScriptPropertyInput? {
        SceneScriptPropertyInputCodec.propertyInput(value)
    }

    static func vector3(_ value: String) -> SIMD3<Double>? {
        SceneScriptPropertyInputCodec.vector3(value)
    }

    static func vector2(_ value: String) -> SIMD2<Double>? {
        SceneScriptPropertyInputCodec.vector2(value)
    }

    static func validName(_ value: String) -> Bool {
        SceneScriptPropertyInputCodec.validName(value)
    }
}
