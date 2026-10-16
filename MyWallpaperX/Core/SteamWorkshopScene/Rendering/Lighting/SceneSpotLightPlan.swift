import simd

/// Strict bounded projection of authored volumetric `lspot` objects.
/// This is not the general Scene lighting, shadow, or PBR pipeline.
nonisolated struct SceneSpotLightPlan {
    let layerID: Int
    let color: SIMD3<Float>
    let intensity: Float
    let radius: Float
    let innerConeRadians: Float
    let outerConeRadians: Float
    let density: Float
    let exponent: Float
    let volumetricsExponent: Float
    let baseAngles: SIMD3<Float>

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
              layer.parentID == nil,
              layer.childLayerIDs.isEmpty,
              layer.dependencyLayerIDs.isEmpty,
              layer.effects.isEmpty,
              Self.supportsInlineScripts(
                  layer,
                  instantiatedTargets: instantiatedSceneScriptTargets,
                  sourceEvidence: scriptSourceEvidence
              ),
              let colorValues = light.colorRGB,
              colorValues.count == 3,
              colorValues.allSatisfy({ (0...1).contains($0) }),
              let intensity = light.intensity, (0...100).contains(intensity),
              let radius = light.radius, (100...5_000).contains(radius),
              let innerDegrees = light.innerConeDegrees,
              let outerDegrees = light.outerConeDegrees,
              innerDegrees > 0, innerDegrees <= outerDegrees, outerDegrees <= 15,
              let density = light.density, (0...10).contains(density),
              let exponent = light.exponent, (0.1...10).contains(exponent),
              let volumetricsExponent = light.volumetricsExponent,
              (0.1...10).contains(volumetricsExponent),
              let angleValues = layer.anglesXYZ, angleValues.count == 3,
              angleValues.allSatisfy(\.isFinite),
              layer.timelines.count == 1,
              let timeline = layer.timelines.first,
              timeline.host == .angles,
              Self.validAngleAnimation(timeline.animation) else {
            return nil
        }
        layerID = layer.id
        color = SIMD3(colorValues[0], colorValues[1], colorValues[2])
        self.intensity = intensity
        self.radius = radius
        innerConeRadians = innerDegrees * .pi / 180
        outerConeRadians = outerDegrees * .pi / 180
        self.density = density
        self.exponent = exponent
        self.volumetricsExponent = volumetricsExponent
        baseAngles = SIMD3(angleValues[0], angleValues[1], angleValues[2])
    }

    /// The standalone cone consumes these live fields from the same typed
    /// frame snapshot as model lighting. Other inline hosts still reject the
    /// bounded plan instead of silently freezing an authored fallback.
    private nonisolated static func supportsInlineScripts(
        _ layer: SceneRenderDescriptor.Layer,
        instantiatedTargets: Set<SceneDynamicTarget>,
        sourceEvidence: [SceneScriptSourceEvidenceIR]
    ) -> Bool {
        let layerEvidence = sourceEvidence.filter {
            $0.owner.objectID == layer.id
        }
        guard layer.hasInlineScript else { return layerEvidence.isEmpty }

        // The instantiated scalar program is the producer authority. Source
        // evidence is independently exhaustive, so a bounded cone is admitted
        // only when that authority covers the layer's sole authored script and
        // the script is the exact top-level lowercase intensity wrapper.
        let intensityTarget = SceneDynamicTarget.layer(
            layerID: layer.id, field: .intensity
        )
        guard instantiatedTargets.contains(intensityTarget),
              layerEvidence.count == 1,
              let evidence = layerEvidence.first,
              evidence.owner.kind == .object,
              evidence.owner.objectIndex == layer.layerIndex,
              evidence.targetPath == [
                  .key("objects"), .index(layer.layerIndex),
                  .key("intensity"),
              ] else {
            return false
        }
        return true
    }

    /// Timeline playback and relative composition have already been resolved by
    /// the shared frame snapshot. Keep the bounded cone's authored XY geometry,
    /// while consuming the same angle as the other light consumers.
    nonisolated func currentAngle(in snapshot: SceneDynamicSnapshot) -> Float {
        guard let resolved = snapshot[.layer(layerID: layerID, field: .angles)],
              resolved.source != .authored,
              case let .vector3(x, y, z) = resolved.value,
              x.isFinite, y.isFinite, z.isFinite,
              Float(x).isFinite, Float(y).isFinite, Float(z).isFinite else {
            return baseAngles.z
        }
        return Float(z)
    }

    private nonisolated static func validAngleAnimation(
        _ animation: SceneTimelineAnimation
    ) -> Bool {
        guard animation.isRelative,
              animation.options.mode == .mirror,
              !animation.options.startsPaused,
              !animation.options.wrapsLoop,
              animation.options.parent == nil,
              animation.options.children.isEmpty,
              animation.options.fps > 0,
              animation.options.length > 0,
              animation.componentCount == 3,
              animation.lanes.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        return animation.lanes[0].allSatisfy { abs($0.value) <= 0.000_001 }
            && animation.lanes[1].allSatisfy { abs($0.value) <= 0.000_001 }
            && animation.lanes[2].allSatisfy {
                $0.value.isFinite && abs($0.value) <= Double.pi
            }
    }
}
