import simd

/// Prepared geometry and material inputs for the existing volumetric cone.
nonisolated struct SceneSpotLightPlan {
    let layerID: Int
    let color: SIMD3<Float>
    let intensity: Float
    let alpha: Double?
    let radius: Float
    let supportHalfWidth: Float
    let innerRatio: Float
    let density: Float
    let exponent: Float
    let volumetricsExponent: Float

    nonisolated init?(
        layer: SceneRenderDescriptor.Layer,
        instantiatedSceneScriptTargets: Set<SceneDynamicTarget> = [],
        scriptSourceEvidence: [SceneScriptSourceEvidenceIR] = []
    ) {
        guard layer.contentKind == "spotLight",
              let light = layer.spotLight,
              light.kind == "lspot",
              light.castsVolumetrics == true,
              light.isSolid == true,
              layer.effects.isEmpty,
              Self.supportsInlineScripts(
                  layer,
                  instantiatedTargets: instantiatedSceneScriptTargets,
                  sourceEvidence: scriptSourceEvidence
              ),
              let colorValues = light.colorRGB,
              colorValues.count == 3,
              colorValues.allSatisfy({ (0...1).contains($0) }),
              let intensity = light.intensity,
              let radius = light.radius,
              let innerDegrees = light.innerConeDegrees,
              let outerDegrees = light.outerConeDegrees,
              innerDegrees >= 0, innerDegrees <= outerDegrees,
              outerDegrees > 0, outerDegrees < 180,
              let density = light.density,
              let exponent = light.exponent,
              let volumetricsExponent = light.volumetricsExponent,
              [intensity, radius, density, exponent, volumetricsExponent]
                .allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return nil
        }
        let outerTangent = tan(Double(outerDegrees) * .pi / 360)
        let supportHalfWidth = Float(Double(radius) * outerTangent * 1.6)
        guard supportHalfWidth.isFinite,
              radius == 0 || supportHalfWidth > 0 else {
            return nil
        }
        layerID = layer.id
        color = SIMD3(colorValues[0], colorValues[1], colorValues[2])
        self.intensity = intensity
        alpha = layer.alpha
        self.radius = radius
        self.supportHalfWidth = supportHalfWidth
        innerRatio = Float(tan(Double(innerDegrees) * .pi / 360) / (outerTangent * 1.6))
        self.density = density
        self.exponent = exponent
        self.volumetricsExponent = volumetricsExponent
    }

    /// Exhaustive source evidence keeps nested or unconsumed writers from
    /// silently becoming static fallbacks. Constructed targets own VM admission.
    private nonisolated static func supportsInlineScripts(
        _ layer: SceneRenderDescriptor.Layer,
        instantiatedTargets: Set<SceneDynamicTarget>,
        sourceEvidence: [SceneScriptSourceEvidenceIR]
    ) -> Bool {
        let layerEvidence = sourceEvidence.filter {
            $0.owner.objectID == layer.id
        }
        guard layer.hasInlineScript else { return layerEvidence.isEmpty }
        guard !layerEvidence.isEmpty else { return false }
        return layerEvidence.allSatisfy { evidence in
            guard evidence.owner.kind == .object,
                  evidence.owner.objectIndex == layer.layerIndex,
                  evidence.targetPath == [
                      .key("objects"), .index(layer.layerIndex),
                      .key(evidence.targetKey),
                  ],
                  let field = evidence.targetKey == "visible"
                    ? SceneDynamicLayerField.visibility
                    : SceneDynamicLayerField(rawValue: evidence.targetKey),
                  field != .visibility || evidence.targetKey == "visible" else {
                return false
            }
            switch field {
            case .origin, .angles, .scale, .color, .intensity, .alpha, .visibility:
                return instantiatedTargets.contains(.layer(layerID: layer.id, field: field))
            default:
                return false
            }
        }
    }
}
