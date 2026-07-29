import simd

/// One native instance produced by a verified SceneScript audio-bars plan.
///
/// The values are script-owned overrides. In particular, `scale` and
/// `angleRadians` must not be composed with the authored owner scale or angles.
nonisolated struct SceneScriptAudioBarInstance: Equatable, Sendable {
    let index: Int
    let originOffset: SIMD3<Float>
    let scale: SIMD3<Float>
    let angleRadians: Float
    let alignment: SceneScriptAudioBarsPlan.Alignment
    let pivot: SIMD2<Float>
}

/// Pure geometry evaluation for bounded 64-band SceneScript audio-bar profiles.
nonisolated enum SceneScriptAudioBarsGeometry {
    static let instanceBudget = SceneAudioSpectrumSnapshot.extendedBandCount

    static func instances(
        plan: SceneScriptAudioBarsPlan,
        spectrum: SceneAudioSpectrumSnapshot
    ) -> [SceneScriptAudioBarInstance]? {
        instances(
            plan: plan,
            left64: spectrum.left64,
            right64: spectrum.right64
        )
    }

    /// Array-based entry point keeps malformed buffer lengths fail-closed and
    /// makes that contract independently testable from snapshot sanitization.
    static func instances(
        plan: SceneScriptAudioBarsPlan,
        left64: [Float],
        right64: [Float]
    ) -> [SceneScriptAudioBarInstance]? {
        guard plan.barCount == instanceBudget,
              plan.audioResolution == instanceBudget,
              plan.channel == .average,
              left64.count == instanceBudget,
              right64.count == instanceBudget,
              finitePlanValues(plan) else {
            return nil
        }

        let angleRadians = plan.angleDegrees * (.pi / 180)
        guard angleRadians.isFinite else { return nil }
        let pivot = pivot(for: plan.alignment)
        var result: [SceneScriptAudioBarInstance] = []
        result.reserveCapacity(instanceBudget)

        for index in 0..<instanceBudget {
            let left = left64[index]
            let right = right64[index]
            guard left.isFinite, right.isFinite else { return nil }

            // Halving before addition preserves the mathematical channel mean
            // without overflowing when both inputs are large finite Floats.
            let average = left * 0.5 + right * 0.5
            let stepIndex = Float(plan.stepIndex(forBarIndex: index))
            let originOffset = SIMD3<Float>(
                plan.xStep * stepIndex,
                plan.yStep * stepIndex,
                0
            )
            let scale = SIMD3<Float>(
                plan.widthMultiplier,
                plan.height(forSpectrumValue: average),
                plan.depthMultiplier
            )
            guard average.isFinite,
                  stepIndex.isFinite,
                  allFinite(originOffset),
                  allFinite(scale) else {
                return nil
            }
            result.append(
                SceneScriptAudioBarInstance(
                    index: index,
                    originOffset: originOffset,
                    scale: scale,
                    angleRadians: angleRadians,
                    alignment: plan.alignment,
                    pivot: pivot
                )
            )
        }
        return result.count == instanceBudget ? result : nil
    }

    /// Builds a standalone root-layer model matrix from the owner's authored
    /// origin and model size. Scene coordinates use authored Y-up values while
    /// the render world is Y-down, so both the scripted Y offset and Z angle
    /// follow the same conversion as `SceneLayerWorldFrameResolver`.
    ///
    /// Authored owner scale/angles are deliberately absent from this API
    /// because the verified scripts replace both values for every bar.
    static func modelMatrix(
        authoredBaseOrigin: SIMD3<Float>,
        sceneOrthoHeight: Float,
        baseSize: SIMD2<Float>,
        instance: SceneScriptAudioBarInstance
    ) -> simd_float4x4? {
        guard allFinite(authoredBaseOrigin),
              sceneOrthoHeight.isFinite,
              sceneOrthoHeight > 0,
              allFinite(baseSize),
              baseSize.x > 0,
              baseSize.y > 0,
              allFinite(instance.originOffset),
              allFinite(instance.scale),
              instance.angleRadians.isFinite,
              allFinite(instance.pivot) else {
            return nil
        }

        let authoredOrigin = authoredBaseOrigin + instance.originOffset
        let worldOrigin = SIMD3<Float>(
            authoredOrigin.x,
            sceneOrthoHeight - authoredOrigin.y,
            authoredOrigin.z
        )
        let scaledSize = SIMD3<Float>(
            baseSize.x * instance.scale.x,
            -baseSize.y * instance.scale.y,
            instance.scale.z
        )
        guard allFinite(worldOrigin), allFinite(scaledSize) else { return nil }

        let matrix = SceneMatrix.translation(worldOrigin)
            * SceneMatrix.rotationZ(-instance.angleRadians)
            * SceneMatrix.scale(scaledSize)
            * SceneMatrix.translation(
                SIMD3(instance.pivot.x, instance.pivot.y, 0)
            )
        return allFinite(matrix) ? matrix : nil
    }

    private static func finitePlanValues(
        _ plan: SceneScriptAudioBarsPlan
    ) -> Bool {
        plan.widthMultiplier.isFinite
            && plan.heightMultiplier.isFinite
            && plan.depthMultiplier.isFinite
            && plan.xStep.isFinite
            && plan.yStep.isFinite
            && plan.angleDegrees.isFinite
    }

    private static func pivot(
        for alignment: SceneScriptAudioBarsPlan.Alignment
    ) -> SIMD2<Float> {
        switch alignment {
        case .centre:
            .zero
        case .bottom:
            SIMD2(0, 0.5)
        case .top:
            SIMD2(0, -0.5)
        }
    }

    private static func allFinite(_ value: SIMD2<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite
    }

    private static func allFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private static func allFinite(_ value: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { column in
            let value = value[column]
            return value.x.isFinite
                && value.y.isFinite
                && value.z.isFinite
                && value.w.isFinite
        }
    }
}
