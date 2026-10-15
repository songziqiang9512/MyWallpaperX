import Foundation

nonisolated extension SceneScriptScalarProgram {
    static func projectedTargets(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        Set(projectedDefinitions(
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            timelineTargets: timelineTargets
        ).map(\.target))
    }

    static func projectedDefinitions(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> [SceneDynamicTargetDefinition] {
        let candidates = scriptBindings.compactMap { binding ->
            (target: SceneDynamicTarget, authored: Double)? in
            guard SceneScriptPropertyInputCodec.inputs(binding.properties) != nil,
                  let authored = binding.authoredValue?.numberValue,
                  authored.isFinite,
                  let target = projection(
                      binding,
                      descriptor: descriptor,
                      timelineTargets: timelineTargets
                  ), !excludedTargets.contains(target) else { return nil }
            return (target, authored)
        }
        let counts = Dictionary(grouping: candidates, by: \.target)
            .mapValues(\.count)
        return candidates.compactMap { candidate in
            guard counts[candidate.target] == 1 else { return nil }
            return .init(
                target: candidate.target,
                valueType: .scalar,
                authoredValue: .scalar(candidate.authored)
            )
        }
    }

    static func projectedOwnerSources(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> [String] {
        let candidates = scriptBindings.compactMap { binding ->
            (source: String, target: SceneDynamicTarget)? in
            guard SceneScriptPropertyInputCodec.inputs(binding.properties) != nil,
                  let target = projection(
                      binding,
                      descriptor: descriptor,
                      timelineTargets: timelineTargets
                  ),
                  !excludedTargets.contains(target) else { return nil }
            return (binding.source, target)
        }
        let counts = Dictionary(grouping: candidates, by: \.target)
            .mapValues(\.count)
        return candidates.compactMap { candidate in
            counts[candidate.target] == 1 ? candidate.source : nil
        }
    }

    /// Only uniquely projected volume owners may claim a named input. Resource
    /// admission and resolved seed identity remain in the Sound Program.
    static func projectedVolumePropertyKeys(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = []
    ) -> [SceneDynamicTarget: String] {
        let candidates = scriptBindings.compactMap { binding ->
            (target: SceneDynamicTarget, key: String?)? in
            guard SceneScriptPropertyInputCodec.inputs(binding.properties) != nil,
                  let target = projection(
                      binding, descriptor: descriptor, timelineTargets: timelineTargets
                  ), case .layer(_, .volume) = target else { return nil }
            return (target, binding.userPropertyKey)
        }
        let counts = Dictionary(grouping: candidates, by: \.target).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in
            guard counts[candidate.target] == 1, let key = candidate.key else { return nil }
            return (candidate.target, key)
        })
    }

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
                .key("objects"), .index(objectIndex), .key("volume"),
            ] {
                let target = SceneDynamicTarget.layer(
                    layerID: layerID, field: .volume
                )
                let validWrapper =
                    (binding.wrapperKeys == ["script", "value"]
                        && binding.properties.isEmpty)
                    || SceneScriptDynamicProviderHostContract.supports(
                        keys: binding.wrapperKeys ?? [], host: .objectScalar
                    )
                if binding.userPropertyKey != nil {
                    guard let input = SceneScriptDynamicProviderHostContract
                            .namedSoundVolumeInput(
                                source: binding.source,
                                wrapperKeys: binding.wrapperKeys ?? [],
                                userPropertyKey: binding.userPropertyKey,
                                value: binding.authoredValue
                            ),
                          case let .object(configuration)? = layer.initialConfiguration,
                          configuration["sound"] != nil,
                          case let .object(wrapper)? = configuration["volume"],
                          wrapper.keys.sorted() == binding.wrapperKeys,
                          wrapper["script"] == .string(input.source),
                          wrapper["user"] == .string(input.userPropertyKey),
                          wrapper["value"]?.numberValue?.isFinite == true,
                          wrapper["scriptproperties"] == (binding.wrapperKeys?.contains("scriptproperties") == true
                            ? .object(binding.properties) : nil) else { return nil }
                } else if !validWrapper {
                    return nil
                }
                // Named current values may differ from the IR's raw fallback.
                // The Sound Program validates their resource/key/resolved seed
                // identity before any owner module is evaluated.
                guard binding.targetKey == "volume",
                      layer.contentKind == "sound",
                      !timelineTargets.contains(target),
                      SceneScriptValueOwner.acceptsScalar(authored, for: target)
                else { return nil }
                return target
            }
            if binding.targetPath == [
                .key("objects"), .index(objectIndex), .key("brightness"),
            ] {
                let target = SceneDynamicTarget.layer(
                    layerID: layerID, field: .brightness
                )
                let validWrapper =
                    (binding.wrapperKeys == ["script", "value"]
                        && binding.properties.isEmpty)
                    || SceneScriptDynamicProviderHostContract.supports(
                        keys: binding.wrapperKeys ?? [], host: .objectScalar
                    )
                // Preparation separately excludes targets without an ordinary
                // source multiplier, before any owner module is evaluated.
                guard binding.targetKey == "brightness", validWrapper,
                      !timelineTargets.contains(target),
                      layer.supportsUserPropertyImageSourceModulationConsumer,
                      layer.brightness?.bitPattern == authored.bitPattern,
                      SceneScriptValueOwner.acceptsScalar(authored, for: target)
                else { return nil }
                return target
            }
            if binding.targetPath == [
                .key("objects"), .index(objectIndex), .key("fov"),
            ] {
                let target = SceneDynamicTarget.layer(layerID: layerID, field: .fov)
                let validWrapper = (binding.wrapperKeys == ["script", "value"] && binding.properties.isEmpty)
                    || SceneScriptDynamicProviderHostContract.supports(
                        keys: binding.wrapperKeys ?? [], host: .objectScalar)
                guard binding.targetKey == "fov", validWrapper,
                      !timelineTargets.contains(target),
                      SceneParticleCameraFrame.acceptsNativePerspectiveProjection(camera: descriptor.camera),
                      let cameraPath = layer.cameraPath,
                      cameraPath.camera.lowercased() == "default",
                      cameraPath.fov?.bitPattern == authored.bitPattern,
                      SceneScriptValueOwner.acceptsScalar(authored, for: target) else { return nil }
                return target
            }
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
                      SceneScriptValueOwner.acceptsScalar(authored, for: target),
                      Float(authored).bitPattern == descriptorPointSize.bitPattern else {
                    return nil
                }
                return target
            }
            if binding.targetPath == [
                .key("objects"), .index(objectIndex),
                .key("instanceoverride"), .key(binding.targetKey),
            ] {
                guard SceneScriptDynamicProviderHostContract.supports(
                          keys: binding.wrapperKeys ?? [], host: .particleValue
                      ),
                      layer.contentKind == "particle",
                      let override = layer.particleInstanceOverride,
                      let (field, value) = particleScalarBinding(
                          named: binding.targetKey, override: override
                      ),
                      value.hasScript,
                      value.userPropertyKey == nil,
                      !value.hasAnimation,
                      value.value?.scalarValue?.bitPattern == authored.bitPattern else {
                    return nil
                }
                return .particle(layerID: layerID, field: field)
            }
            if binding.targetPath == [
                .key("objects"), .index(objectIndex), .key("intensity"),
            ] {
                let target = SceneDynamicTarget.layer(
                    layerID: layerID, field: .intensity
                )
                let validWrapper =
                    (binding.wrapperKeys == ["script", "value"]
                        && binding.properties.isEmpty)
                    || SceneScriptDynamicProviderHostContract.supports(
                        keys: binding.wrapperKeys ?? [], host: .objectScalar
                    )
                guard binding.targetKey == "intensity", validWrapper,
                      let intensity = layer.authoredLightIntensity,
                      intensity.isFinite, intensity >= 0,
                      Float(authored).bitPattern == intensity.bitPattern else {
                    return nil
                }
                return target
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
              value.components?.first?.isFinite == true else {
            return nil
        }
        // A named input may already hold a saved slider value. Its source and
        // user identity must match the raw binding; the resolved current value
        // need not equal the authored fallback retained by the Scalar owner.
        let namedPropertyInput = binding.userPropertyKey.map {
            !$0.isEmpty && $0 == value.userBinding
                && value.userValueKind == .string
                && binding.wrapperKeys == ["script", "user", "value"]
                && value.bindingKeys == binding.wrapperKeys
                && value.timeline == nil
        } == true
        guard namedPropertyInput
                || value.components?.first?.bitPattern == authored.bitPattern else {
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
            || (namedPropertyInput && binding.properties.isEmpty)
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
    private static func particleScalarBinding(
        named name: String, override value: SceneParticleInstanceOverride
    ) -> (SceneDynamicParticleField, SceneParticleBoundValue)? {
        let field: SceneDynamicParticleField
        let bound: SceneParticleBoundValue?
        switch name {
        case "alpha": (field, bound) = (.alpha, value.alpha)
        case "size": (field, bound) = (.size, value.size)
        case "lifetime": (field, bound) = (.lifetime, value.lifetime)
        case "rate": (field, bound) = (.rate, value.rate)
        case "speed": (field, bound) = (.speed, value.speed)
        case "count": (field, bound) = (.count, value.count)
        case "brightness": (field, bound) = (.brightness, value.brightness)
        default: return nil
        }
        return bound.map { (field, $0) }
    }


}
