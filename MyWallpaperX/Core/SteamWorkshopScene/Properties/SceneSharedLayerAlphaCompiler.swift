import Foundation

/// Compiles exact object-alpha consumers against exact scene-lifetime shared
/// boolean initializers. Unsupported sources retain display-script ownership.
nonisolated enum SceneSharedLayerAlphaProgramCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        scriptSourceEvidence: [SceneScriptSourceEvidenceIR]
    ) -> SceneSharedLayerAlphaProgram? {
        let initialFlags = sharedInitialFlags(
            descriptor: descriptor,
            sourceEvidence: scriptSourceEvidence
        )
        var bindings: [SceneSharedLayerAlphaBinding] = []
        for source in scriptBindings where source.owner.kind == .object
            && source.targetKey == "alpha"
        {
            guard let syntax = SceneSharedLayerAlphaSyntax.parse(source.source),
                  initialFlags[syntax.sharedFlag] != nil else { continue }
            guard let binding = project(
                source, syntax: syntax, descriptor: descriptor
            ) else {
                // Preserve this layer's display ownership. One malformed
                // consumer cannot suppress otherwise independent layers.
                continue
            }
            bindings.append(binding)
        }
        return SceneSharedLayerAlphaProgram.validated(
            initialFlags: initialFlags,
            bindings: bindings
        )
    }

    private static func sharedInitialFlags(
        descriptor: SceneRenderDescriptor,
        sourceEvidence: [SceneScriptSourceEvidenceIR]
    ) -> [String: Bool] {
        var values: [String: [Bool]] = [:]
        var invalid: Set<String> = []
        for evidence in sourceEvidence {
            guard let parsed = SceneLaunchOriginTransitionSyntax
                .parseSharedInitializer(evidence.source) else { continue }
            guard isExactInitializer(evidence, descriptor: descriptor) else {
                invalid.formUnion(parsed.keys)
                continue
            }
            for (flag, value) in parsed {
                values[flag, default: []].append(value)
            }
        }
        return values.reduce(into: [:]) { result, item in
            guard !invalid.contains(item.key), item.value.count == 1,
                  let value = item.value.first else { return }
            result[item.key] = value
        }
    }

    private static func isExactInitializer(
        _ evidence: SceneScriptSourceEvidenceIR,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        guard evidence.owner.kind == .object,
              evidence.wrapperKeys == ["script", "value"],
              let index = evidence.owner.objectIndex,
              let layerID = evidence.owner.objectID,
              descriptor.layers.indices.contains(index),
              descriptor.layers[index].id == layerID,
              descriptor.layers[index].layerIndex == index,
              descriptor.layers[index].visible == true,
              evidence.targetPath == objectPath(index: index, key: "visible") else {
            return false
        }
        return true
    }

    private static func project(
        _ source: SceneScriptBindingIR,
        syntax: SceneSharedLayerAlphaSyntax.Profile,
        descriptor: SceneRenderDescriptor
    ) -> SceneSharedLayerAlphaBinding? {
        guard source.wrapperKeys == ["script", "value"]
                || source.wrapperKeys == ["script", "scriptproperties", "value"],
              source.valueType == .number,
              case let .number(authored)? = source.authoredValue,
              authored.isFinite, (0...1).contains(authored),
              let index = source.owner.objectIndex,
              let layerID = source.owner.objectID,
              descriptor.layers.indices.contains(index),
              descriptor.layers[index].id == layerID,
              descriptor.layers[index].layerIndex == index,
              let descriptorAlpha = descriptor.layers[index].alpha,
              descriptorAlpha.bitPattern == authored.bitPattern,
              descriptor.layers[index].displayScriptOwnership?.alpha == true,
              source.targetPath == objectPath(index: index, key: "alpha"),
              source.properties.keys.sorted() == syntax.propertyNames,
              let resolvedBinding = resolvedLayerBinding(
                  descriptor.layers[index], source: source
              ),
              resolvedBinding.properties.keys.sorted() == syntax.propertyNames,
              let upper = scalarInput(
                  syntax.upperBound, properties: resolvedBinding.properties
              ), upper.fallback.isFinite,
              upper.fallback > syntax.lowerBound else { return nil }
        return SceneSharedLayerAlphaBinding(
            definition: SceneDynamicTargetDefinition(
                target: .layer(layerID: layerID, field: .alpha),
                valueType: .scalar,
                authoredValue: .scalar(authored)
            ),
            plan: SceneSharedLayerAlphaPlan(
                sharedFlag: syntax.sharedFlag,
                activeFlagValue: syntax.activeFlagValue,
                upperBound: upper,
                lowerBound: syntax.lowerBound,
                riseRate: syntax.riseRate,
                fallRate: syntax.fallRate
            )
        )
    }

    private static func resolvedLayerBinding(
        _ layer: SceneRenderDescriptor.Layer,
        source: SceneScriptBindingIR
    ) -> SceneScriptBindingDefinition? {
        let matches = (layer.scriptBindings ?? []).filter {
            $0.host == "alpha"
                && $0.source == source.source
                && $0.authoredValue == source.authoredValue
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func scalarInput(
        _ bound: SceneSharedLayerAlphaSyntax.Bound,
        properties: [String: SceneJSONValue]
    ) -> SceneSharedLayerAlphaScalarInput? {
        switch bound {
        case let .number(number):
            return .init(fallback: number, userPropertyKey: nil)
        case let .property(name):
            switch properties[name] {
            case let .number(number) where number.isFinite:
                return .init(fallback: number, userPropertyKey: nil)
            case let .object(wrapper):
                guard wrapper.keys.sorted() == ["user", "value"],
                      case let .string(key)? = wrapper["user"],
                      !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      case let .number(number)? = wrapper["value"],
                      number.isFinite else { return nil }
                return .init(fallback: number, userPropertyKey: key)
            default:
                return nil
            }
        }
    }

    private static func objectPath(
        index: Int, key: String
    ) -> [SceneScriptBindingPathComponent] {
        [.key("objects"), .index(index), .key(key)]
    }
}

nonisolated enum SceneSharedLayerAlphaProjection {
    nonisolated static func apply(
        program: SceneSharedLayerAlphaProgram,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        let layerIDs = Set(program.layerIDs)
        guard !layerIDs.isEmpty else { return descriptor }
        var projected = descriptor
        for index in projected.layers.indices
            where layerIDs.contains(projected.layers[index].id)
        {
            guard let ownership = projected.layers[index].displayScriptOwnership,
                  ownership.alpha else { continue }
            projected.layers[index].displayScriptOwnership =
                SceneLayerDisplayScriptOwnership(
                    visible: ownership.visible,
                    alpha: false
                )
        }
        return projected
    }
}
