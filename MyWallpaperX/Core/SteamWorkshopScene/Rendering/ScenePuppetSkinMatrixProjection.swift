import simd

/// Converts a validated Puppet pose into skin matrices. Keeping hierarchy
/// resolution separate lets playback retain the exact current bone worlds for
/// dynamic attachments without rebuilding them in scratch storage.
nonisolated enum ScenePuppetSkinMatrixProjection {
    nonisolated static func write(
        localMatrices: [simd_float4x4],
        bones: [SceneMdlPuppetRig.Bone],
        inverseBindWorldMatrices: [simd_float4x4],
        into output: inout [simd_float4x4]
    ) throws {
        guard localMatrices.count >= bones.count,
              inverseBindWorldMatrices.count >= bones.count,
              output.count >= bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        for (boneIndex, bone) in bones.enumerated() {
            let local = localMatrices[boneIndex]
            output[boneIndex] = bone.parentIndex >= 0
                ? output[bone.parentIndex] * local
                : local
        }
        for boneIndex in bones.indices {
            output[boneIndex] *= inverseBindWorldMatrices[boneIndex]
        }
    }

    nonisolated static func write(
        worldMatrices: [simd_float4x4],
        bones: [SceneMdlPuppetRig.Bone],
        inverseBindWorldMatrices: [simd_float4x4],
        into output: inout [simd_float4x4]
    ) throws {
        guard worldMatrices.count >= bones.count,
              inverseBindWorldMatrices.count >= bones.count,
              output.count >= bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        for boneIndex in bones.indices {
            output[boneIndex] = worldMatrices[boneIndex]
                * inverseBindWorldMatrices[boneIndex]
        }
    }
}
