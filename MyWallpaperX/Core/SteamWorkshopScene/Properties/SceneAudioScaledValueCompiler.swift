import Foundation

/// Compiles the stock audio-scaled value script by structural syntax and typed
/// binding identity. It is deliberately target-bounded: particle rate and
/// layer scale are admitted; every other scripted particle field is rejected
/// rather than rendered statically. Scripted layer-scale fail-closed ownership
/// is centralized in `SceneScriptedLayerTransformProjection` so independent
/// bounded scale producers cannot suppress one another.
nonisolated enum SceneAudioScaledValueProgramCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor
    ) -> SceneAudioScaledValueProgram {
        var bindings: [SceneAudioScaledValueBinding] = []
        var rejectedParticleLayerIDs: [Int] = []
        var rejectedScaleLayerIDs: [Int] = []

        for layer in descriptor.layers {
            if layer.contentKind == "particle",
               layer.particleInstanceOverride?.hasAnyScript == true {
                if let binding = compileParticleRate(layer) {
                    bindings.append(binding)
                } else {
                    rejectedParticleLayerIDs.append(layer.id)
                }
            }
            if layer.scaleHasScript == true {
                if let binding = compileLayerScale(layer) {
                    bindings.append(binding)
                } else {
                    rejectedScaleLayerIDs.append(layer.id)
                }
            }
        }
        return SceneAudioScaledValueProgram(
            bindings: bindings,
            rejectedParticleLayerIDs: rejectedParticleLayerIDs.sorted(),
            rejectedScaleLayerIDs: rejectedScaleLayerIDs.sorted()
        )
    }

    private nonisolated static func compileParticleRate(
        _ layer: SceneRenderDescriptor.Layer
    ) -> SceneAudioScaledValueBinding? {
        guard let override = layer.particleInstanceOverride,
              override.hasOnlyRateScript,
              let rate = override.rate,
              rate.userPropertyKey == nil,
              rate.hasScript,
              !rate.hasAnimation,
              case let .scalar(initialValue)? = rate.value,
              initialValue.isFinite,
              initialValue >= 0,
              let script = layer.particleRateAudioScript,
              script.authoredValue?.numberValue?.bitPattern
                == initialValue.bitPattern else { return nil }
        return compile(
            script: script,
            definition: SceneDynamicTargetDefinition(
                target: .particle(layerID: layer.id, field: .rate),
                valueType: .scalar,
                authoredValue: .scalar(initialValue)
            )
        )
    }

    private nonisolated static func compileLayerScale(
        _ layer: SceneRenderDescriptor.Layer
    ) -> SceneAudioScaledValueBinding? {
        guard let script = layer.scaleAudioScript,
              let components = authoredVector3(script.authoredValue),
              let descriptorComponents = layer.scaleXYZ,
              descriptorComponents.count == 3,
              zip(descriptorComponents, components).allSatisfy({
                  $0.0.bitPattern == Float($0.1).bitPattern
              }) else { return nil }
        return compile(
            script: script,
            definition: SceneDynamicTargetDefinition(
                target: .layer(layerID: layer.id, field: .scale),
                valueType: .vector3,
                authoredValue: .vector3(
                    components[0], components[1], components[2]
                )
            )
        )
    }

    private nonisolated static func compile(
        script: SceneAudioScaledValueScriptDefinition,
        definition: SceneDynamicTargetDefinition
    ) -> SceneAudioScaledValueBinding? {
        guard script.wrapperKeys == ["script", "scriptproperties", "value"],
              SceneAudioScaledValueSyntax.parse(script.source)?.resolution == 16,
              script.properties.keys.sorted()
                == ["frequency", "maxvalue", "minvalue", "smoothing"],
              let frequencyValue = script.properties["frequency"]?.numberValue,
              frequencyValue.isFinite,
              frequencyValue.rounded(.towardZero) == frequencyValue,
              (0..<SceneAudioSpectrumSnapshot.bandCount).contains(Int(frequencyValue)),
              let smoothing = script.properties["smoothing"]?.numberValue,
              smoothing.isFinite, (0...25).contains(smoothing),
              let minimum = script.properties["minvalue"]?.numberValue,
              minimum.isFinite, supportedScaleRange.contains(minimum),
              let maximum = script.properties["maxvalue"]?.numberValue,
              maximum.isFinite, supportedScaleRange.contains(maximum),
              minimum <= maximum else { return nil }
        return SceneAudioScaledValueBinding(
            definition: definition,
            frequency: Int(frequencyValue),
            smoothing: smoothing,
            minimumScale: minimum,
            maximumScale: maximum
        )
    }

    /// The builder's `min`/`max` fields are editor metadata, not a player-side
    /// clamp. Official host evidence shows script-property updates assign the
    /// persisted value directly. Keep execution bounded without rejecting this
    /// authored family whose exposed user controls reach 7 and whose particle
    /// multiplier reaches 5.
    private nonisolated static let supportedScaleRange = 0.0...8.0

    private nonisolated static func authoredVector3(
        _ value: SceneJSONValue?
    ) -> [Double]? {
        guard let source = value?.stringValue else { return nil }
        let components = source.split(whereSeparator: \.isWhitespace).compactMap {
            Double($0)
        }
        guard components.count == 3,
              components.allSatisfy(\.isFinite) else { return nil }
        return components
    }
}

nonisolated enum SceneAudioScaledValueProjection {
    nonisolated static func apply(
        program: SceneAudioScaledValueProgram,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        var result = descriptor
        let admittedParticle = program.admittedParticleLayerIDs
        result.layers = descriptor.layers.map { source in
            var layer = source
            if layer.contentKind == "particle",
               layer.particleInstanceOverride?.hasAnyScript == true {
                guard admittedParticle.contains(layer.id),
                      let override = layer.particleInstanceOverride else {
                    layer.visible = false
                    return layer
                }
                layer.particleInstanceOverride = override.admittingRateScript()
            }
            return layer
        }
        return result
    }
}

private nonisolated extension SceneParticleInstanceOverride {
    var hasAnyScript: Bool {
        let scalar = [alpha, size, lifetime, rate, speed, count, brightness]
        let colorValues = [color, normalizedColor]
        return scalar.compactMap { $0 }.contains(where: \.hasScript)
            || colorValues.compactMap { $0 }.contains(where: \.hasScript)
            || controlPoints.values.contains(where: \.hasScript)
            || controlPointAngles.values.contains(where: \.hasScript)
    }

    var hasOnlyRateScript: Bool {
        guard rate?.hasScript == true else { return false }
        let otherValues = [alpha, size, lifetime, speed, count, brightness,
                           color, normalizedColor]
        return !otherValues.compactMap { $0 }.contains(where: \.hasScript)
            && !controlPoints.values.contains(where: \.hasScript)
            && !controlPointAngles.values.contains(where: \.hasScript)
    }

    func admittingRateScript() -> Self {
        let admittedRate = rate.map {
            SceneParticleBoundValue(
                value: $0.value,
                userPropertyKey: $0.userPropertyKey,
                hasScript: false,
                hasAnimation: $0.hasAnimation
            )
        }
        return Self(
            id: id,
            alpha: alpha,
            size: size,
            lifetime: lifetime,
            rate: admittedRate,
            speed: speed,
            count: count,
            brightness: brightness,
            color: color,
            normalizedColor: normalizedColor,
            controlPoints: controlPoints,
            controlPointAngles: controlPointAngles
        )
    }
}
