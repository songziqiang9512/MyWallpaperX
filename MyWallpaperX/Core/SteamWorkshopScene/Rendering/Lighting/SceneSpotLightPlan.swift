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
    let angleAnimation: SceneTimelineAnimation

    nonisolated init?(layer: SceneRenderDescriptor.Layer) {
        guard layer.contentKind == "spotLight",
              let light = layer.spotLight,
              light.kind == "lspot",
              light.castsVolumetrics == true,
              light.isSolid == true,
              layer.visible != false,
              layer.parentID == nil,
              layer.childLayerIDs.isEmpty,
              layer.dependencyLayerIDs.isEmpty,
              layer.effects.isEmpty,
              !layer.hasInlineScript,
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
        angleAnimation = timeline.animation
    }

    nonisolated func authoredAngle(at sceneTime: Double) -> Float? {
        let values = SceneTimelineEvaluator.values(
            of: angleAnimation,
            sceneTime: sceneTime
        )
        guard values.count == 3,
              values.allSatisfy(\.isFinite) else {
            return nil
        }
        let result = Double(baseAngles.z) + values[2]
        return result.isFinite ? Float(result) : nil
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
