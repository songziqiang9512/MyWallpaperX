import Foundation

nonisolated extension SceneScriptScalarProgram {
    static func projection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor,
        timelineTargets: Set<SceneDynamicTarget>
    ) -> SceneDynamicTarget? {
        guard binding.valueType == .number,
              let authored = binding.authoredValue?.numberValue,
              authored.isFinite,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              descriptor.layers.indices.contains(objectIndex),
              descriptor.layers[objectIndex].id == layerID,
              descriptor.layers[objectIndex].layerIndex == objectIndex else {
            return nil
        }
        if binding.owner.kind == .object {
            let layer = descriptor.layers[objectIndex]
            if binding.targetPath == [
                .key("objects"), .index(objectIndex), .key("pointsize"),
            ] {
                let target = SceneDynamicTarget.text(
                    layerID: layerID,
                    field: .pointSize
                )
                guard binding.targetKey == "pointsize",
                      binding.properties.isEmpty,
                      binding.wrapperKeys == ["script", "value"],
                      layer.contentKind == "text",
                      layer.text != nil,
                      let descriptorPointSize = layer.textStyle?.pointSize,
                      descriptorPointSize.isFinite,
                      SceneScriptScalarOwner.accepts(authored),
                      Float(authored).bitPattern == descriptorPointSize.bitPattern else {
                    return nil
                }
                return target
            }
            if binding.targetPath == [
                .key("objects"), .index(objectIndex),
                .key("instanceoverride"), .key("rate"),
            ] {
                guard binding.targetKey == "rate",
                      SceneScriptDynamicProviderHostContract.supports(
                          keys: binding.wrapperKeys ?? [],
                          host: .particleRate
                      ),
                      layer.contentKind == "particle",
                      let override = layer.particleInstanceOverride,
                      override.hasOnlyGenericRateScript,
                      let rate = override.rate,
                      rate.userPropertyKey == nil,
                      !rate.hasAnimation,
                      rate.value?.scalarValue?.bitPattern == authored.bitPattern else {
                    return nil
                }
                return .particle(layerID: layerID, field: .rate)
            }
            let target = SceneDynamicTarget.layer(layerID: layerID, field: .alpha)
            let isTimelineWrapper =
                binding.wrapperKeys == ["animation", "script", "value"]
                    && binding.properties.isEmpty
                    && timelineTargets.contains(target)
            let isPropertyWrapper =
                (binding.wrapperKeys == ["script", "value"]
                    && binding.properties.isEmpty)
                || SceneScriptDynamicProviderHostContract.supports(
                    keys: binding.wrapperKeys ?? [],
                    host: .objectScalar
                )
            guard binding.targetKey == "alpha",
                  isTimelineWrapper || isPropertyWrapper,
                  binding.targetPath == [
                      .key("objects"), .index(objectIndex), .key("alpha"),
                  ],
                  descriptor.layers[objectIndex].alpha?.bitPattern
                    == authored.bitPattern else { return nil }
            return target
        }
        guard binding.owner.kind == .pass,
              let effectIndex = binding.owner.effectIndex,
              let passIndex = binding.owner.passIndex,
              descriptor.layers[objectIndex].effects.indices.contains(effectIndex) else {
            return nil
        }
        let effect = descriptor.layers[objectIndex].effects[effectIndex]
        guard effect.effectID == binding.owner.effectID,
              effect.passes.indices.contains(passIndex) else { return nil }
        let pass = effect.passes[passIndex]
        let name = binding.targetKey
        guard pass.passIndex == passIndex,
              pass.id == binding.owner.passID,
              !name.isEmpty,
              binding.targetPath == expectedPath(
                  objectIndex: objectIndex,
                  effectIndex: effectIndex,
                  passIndex: passIndex,
                  name: name
              ),
              let value = pass.constantShaderValues[name],
              value.scriptSource == binding.source,
              value.components?.count == 1,
              value.components?.first?.bitPattern == authored.bitPattern else {
            return nil
        }
        let target = SceneDynamicTarget.effectConstant(
            layerID: layerID,
            effectIndex: effectIndex,
            passIndex: passIndex,
            name: name
        )
        let validWrapper =
            (binding.wrapperKeys == ["animation", "script", "value"]
                && binding.properties.isEmpty
                && value.userValueKind == nil
                && timelineTargets.contains(target))
            || (binding.wrapperKeys == ["script", "value"]
                && binding.properties.isEmpty
                && value.userValueKind == nil)
            || (SceneScriptDynamicProviderHostContract.supports(
                keys: binding.wrapperKeys ?? [],
                host: .passConstant
            ) && (value.userValueKind == nil || value.userValueKind == .null))
            || (binding.wrapperKeys == ["script", "user", "value"]
                && binding.properties.isEmpty
                && value.userValueKind == .null)
        guard validWrapper else { return nil }
        return target
    }

    private static func expectedPath(
        objectIndex: Int,
        effectIndex: Int,
        passIndex: Int,
        name: String
    ) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(objectIndex),
            .key("effects"), .index(effectIndex),
            .key("passes"), .index(passIndex),
            .key("constantshadervalues"), .key(name),
        ]
    }
}

private nonisolated extension SceneParticleInstanceOverride {
    var hasOnlyGenericRateScript: Bool {
        guard rate?.hasScript == true else { return false }
        let otherValues = [
            alpha, size, lifetime, speed, count, brightness,
            color, normalizedColor,
        ]
        return !otherValues.compactMap { $0 }.contains(where: \.hasScript)
            && !controlPoints.values.contains(where: \.hasScript)
            && !controlPointAngles.values.contains(where: \.hasScript)
    }
}
