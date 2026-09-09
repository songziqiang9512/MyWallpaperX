import simd

/// One last-write-wins script override per dense bone. Keeping the space in
/// the value (rather than parallel dictionaries) prevents a stale world
/// write from surviving a later local write for the same bone.
enum ScenePuppetBoneOverride {
    case local(simd_float4x4)
    case world(simd_float4x4)
}

extension ScenePuppetAnimationEvaluator {
    var boneNames: [String] { rig.bones.map(\.name) }
    var boneParentIndices: [Int] { rig.bones.map(\.parentIndex) }

    func boneTransforms(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?],
        boneOverrides: [Int: ScenePuppetBoneOverride] = [:]
    ) throws -> (local: [simd_float4x4], world: [simd_float4x4]) {
        var local = Array(repeating: matrix_identity_float4x4, count: rig.bones.count)
        var world = local
        try writeLocalMatrices(
            selection: selection, frameSamples: frameSamples, into: &local
        )
        try applyOverrides(boneOverrides, to: &local, worlds: &world)
        return (local, world)
    }

    static func matrix(fromColumnMajor values: [Float]) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        ))
    }

    static func matrix(
        from transform: SceneMdlPuppetAnimation.Transform
    ) -> simd_float4x4 {
        SceneMatrix.translation(transform.translation)
            * SceneMatrix.eulerXYZ(transform.rotation)
            * SceneMatrix.scale(transform.scale)
    }

    static func matrix(from pose: Pose) -> simd_float4x4 {
        SceneMatrix.translation(pose.translation)
            * simd_float4x4(pose.rotation)
            * SceneMatrix.scale(pose.scale)
    }

    static func pose(
        from transform: SceneMdlPuppetAnimation.Transform
    ) -> Pose? {
        guard Self.isFinite(transform.translation),
              Self.isFinite(transform.rotation),
              Self.isFinite(transform.scale) else {
            return nil
        }
        let rotation4 = SceneMatrix.eulerXYZ(transform.rotation)
        let rotation3 = simd_float3x3(columns: (
            SIMD3(rotation4.columns.0.x, rotation4.columns.0.y, rotation4.columns.0.z),
            SIMD3(rotation4.columns.1.x, rotation4.columns.1.y, rotation4.columns.1.z),
            SIMD3(rotation4.columns.2.x, rotation4.columns.2.y, rotation4.columns.2.z)
        ))
        let rotation = simd_quatf(rotation3)
        guard Self.isFinite(rotation.vector) else { return nil }
        return Pose(
            translation: transform.translation,
            rotation: rotation,
            scale: transform.scale
        )
    }

    static func pose(from matrix: simd_float4x4) -> Pose? {
        let c0 = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let c1 = SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let c2 = SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        var scale = SIMD3(simd_length(c0), simd_length(c1), simd_length(c2))
        guard Self.isFinite(scale),
              scale.x > 0.000001, scale.y > 0.000001, scale.z > 0.000001 else { return nil }
        var r0 = c0 / scale.x
        let r1 = c1 / scale.y
        let r2 = c2 / scale.z
        let rotationMatrix = simd_float3x3(columns: (r0, r1, r2))
        let determinant = simd_determinant(rotationMatrix)
        guard determinant.isFinite, abs(determinant) > 0.000001 else { return nil }
        if determinant < 0 {
            scale.x = -scale.x
            r0 = -r0
        }
        let rotation = simd_quatf(simd_float3x3(columns: (r0, r1, r2)))
        guard Self.isFinite(rotation.vector) else { return nil }
        let translation = SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        guard Self.isFinite(translation) else { return nil }
        return Pose(translation: translation, rotation: rotation, scale: scale)
    }

    static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    static func isFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    static func maxDifference(_ lhs: Pose, _ rhs: Pose) -> Float {
        max(
            max(
                simd_length(lhs.translation - rhs.translation),
                simd_length(lhs.scale - rhs.scale)
            ),
            simd_length(lhs.rotation.vector - rhs.rotation.vector)
        )
    }

    static func maxDifference(
        _ lhs: simd_float4x4,
        _ rhs: simd_float4x4
    ) -> Float {
        var maximum: Float = 0
        for column in 0..<4 {
            for row in 0..<4 {
                maximum = max(maximum, abs(lhs[column][row] - rhs[column][row]))
            }
        }
        return maximum
    }
}
