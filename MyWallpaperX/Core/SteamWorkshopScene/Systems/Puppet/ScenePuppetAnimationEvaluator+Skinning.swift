import simd

extension ScenePuppetAnimationEvaluator {
    enum DirectSkinningFailure: Error, Equatable {
        case vertexCountMismatch
        case nonAffineBindTransform
        case nonAffinePoseTransform(Int)
        case nonFiniteSkinMatrix(Int)
        case singularSkinFrame(Int)
        case invalidVertex(Int)
    }

    /// Writes a transform-only direct-model candidate. The caller admits its
    /// animation channels and publishes this scratch buffer only on success;
    /// any failure requires one complete bind fallback, never partial vertices.
    /// Bind vertices are the immutable model already validated by its reader.
    func writeDeformedVertices(
        bindVertices: [SceneMdlStaticModel.Vertex],
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?],
        into output: UnsafeMutableBufferPointer<SceneMdlStaticModel.Vertex>,
        localMatricesScratch: inout [simd_float4x4],
        skinMatricesScratch: inout [simd_float4x4],
        worldMatricesScratch: inout [simd_float4x4],
        boneOverrides: [Int: simd_float4x4] = [:],
        blends: [Double]? = nil
    ) throws {
        guard bindVertices.count == vertexCount, output.count >= vertexCount else {
            throw DirectSkinningFailure.vertexCountMismatch
        }
        guard hasAffineBindTransforms else {
            throw DirectSkinningFailure.nonAffineBindTransform
        }
        try writeSkinMatrices(selection: selection, frameSamples: frameSamples,
            localMatricesScratch: &localMatricesScratch,
            skinMatricesScratch: &skinMatricesScratch,
            worldMatricesScratch: &worldMatricesScratch,
            boneOverrides: boneOverrides, blends: blends)
        for index in 0..<boneCount {
            let world = worldMatricesScratch[index]
            guard world.columns.0.w == 0, world.columns.1.w == 0,
                  world.columns.2.w == 0, world.columns.3.w == 1 else {
                throw DirectSkinningFailure.nonAffinePoseTransform(index)
            }
            let skin = skinMatricesScratch[index]
            guard [skin.columns.0, skin.columns.1, skin.columns.2, skin.columns.3]
                .allSatisfy(Self.isFinite) else {
                throw DirectSkinningFailure.nonFiniteSkinMatrix(index)
            }
        }
        // Affine bind sources and current worlds prove the composed skin is
        // affine; do not infer a projective profile or clamp its numeric row.
        for index in bindVertices.indices {
            let bind = bindVertices[index]
            let skinned = try skinnedVertex(at: index,
                skinMatrices: skinMatricesScratch, includesLinear: true)
            let linear = Self.doubleMatrix(skinned.linear)
            let determinant = simd_determinant(linear)
            guard determinant.isFinite, determinant != 0 else {
                throw DirectSkinningFailure.singularSkinFrame(index)
            }
            let normalMatrix = simd_transpose(simd_inverse(linear))
            // Preserve raw magnitudes. Double inversion avoids rejecting a
            // small, nonsingular Float matrix due to determinant underflow.
            let normal = normalMatrix * SIMD3<Double>(
                Double(bind.normal.x), Double(bind.normal.y), Double(bind.normal.z))
            let tangent = linear * SIMD3<Double>(
                Double(bind.tangent.x), Double(bind.tangent.y), Double(bind.tangent.z))
            let normalFloat = SIMD3<Float>(Float(normal.x), Float(normal.y), Float(normal.z))
            let tangentFloat = SIMD4<Float>(Float(tangent.x), Float(tangent.y),
                Float(tangent.z), bind.tangent.w * (determinant < 0 ? -1 : 1))
            guard Self.isFinite(skinned.position), Self.isFinite(normalFloat),
                  Self.isFinite(tangentFloat) else {
                throw DirectSkinningFailure.invalidVertex(index)
            }
            output[index] = .init(position: skinned.position,
                normal: normalFloat, tangent: tangentFloat, uv: bind.uv)
        }
    }

    private static func doubleMatrix(_ value: simd_float3x3) -> simd_double3x3 {
        simd_double3x3(columns: (
            SIMD3(Double(value.columns.0.x), Double(value.columns.0.y), Double(value.columns.0.z)),
            SIMD3(Double(value.columns.1.x), Double(value.columns.1.y), Double(value.columns.1.z)),
            SIMD3(Double(value.columns.2.x), Double(value.columns.2.y), Double(value.columns.2.z))
        ))
    }
}
