import simd

nonisolated enum SceneLayerCursorGeometry {
    /// Converts the renderer's internal world frame to the absolute author
    /// world frame exposed by SceneScript. Orthographic Scene authors use a
    /// Y-up world coordinate, while the editor canvas/screen is top-left/Y-down
    /// and the renderer keeps that canvas in a Y-down world by reflecting root
    /// transforms around `orthoHeight`. CursorEvent.worldPosition is an author-space absolute
    /// coordinate; publishing the internal value directly makes a drag script
    /// such as `thisLayer.origin = event.worldPosition + offset` move in the
    /// opposite vertical direction. Native-perspective scenes already use the
    /// authored Y-up world and must remain unchanged.
    static func authoredWorldPosition(
        _ rendererWorldPosition: SIMD3<Float>,
        sceneOrthoHeight: Float?
    ) -> SIMD3<Float> {
        guard rendererWorldPosition.x.isFinite,
              rendererWorldPosition.y.isFinite,
              rendererWorldPosition.z.isFinite else {
            return rendererWorldPosition
        }
        let position = authoredWorldTransform(
            matrix_identity_float4x4, sceneOrthoHeight: sceneOrthoHeight
        ) * SIMD4(rendererWorldPosition, 1)
        return SIMD3(position.x, position.y, position.z)
    }

    /// Bone matrices and cursor points must expose the same author world.
    /// Reflect the complete basis as well as its translation so inverse bone
    /// writes recover the original model space.
    static func authoredWorldTransform(
        _ rendererWorldTransform: simd_float4x4,
        sceneOrthoHeight: Float?
    ) -> simd_float4x4 {
        guard let sceneOrthoHeight, sceneOrthoHeight.isFinite,
              sceneOrthoHeight > 0 else { return rendererWorldTransform }
        var result = rendererWorldTransform
        for column in 0..<4 {
            result[column].y = sceneOrthoHeight * rendererWorldTransform[column].w
                - rendererWorldTransform[column].y
        }
        return result
    }

    /// CursorEvent uses unscaled object pixels, with the image's lower-left
    /// corner at zero. The inverse model already removes size, pivot, parent
    /// and live transforms. Keep out-of-bounds points for captured drags.
    static func authoredLocalPosition(
        _ centeredLocal: SIMD3<Float>, size: SIMD2<Float>
    ) -> SIMD3<Double>? {
        guard centeredLocal.x.isFinite, centeredLocal.y.isFinite,
              centeredLocal.z.isFinite,
              size.x.isFinite, size.y.isFinite,
              size.x > 0, size.y > 0 else { return nil }
        return SIMD3(
            (Double(centeredLocal.x) + 0.5) * Double(size.x),
            (Double(centeredLocal.y) + 0.5) * Double(size.y),
            0
        )
    }

    static func layerUV(
        mouseNormalized: SIMD2<Float>,
        modelViewProjection: simd_float4x4
    ) -> SIMD2<Float>? {
        layerUV(
            mouseNormalized: mouseNormalized,
            inverseModelViewProjection: preciseInverseModelViewProjection(modelViewProjection)
        )
    }

    /// Current and previous pointers share this inverse only within their
    /// caller's current MVP. Each point keeps its own projection failure.
    static func layerUV(
        mouseNormalized: SIMD2<Float>,
        inverseModelViewProjection: simd_double4x4?
    ) -> SIMD2<Float>? {
        guard let inverseModelViewProjection else { return nil }
        guard let local = layerPoint(
            mouseNormalized: mouseNormalized,
            inverse: inverseModelViewProjection
        ) else { return nil }
        let uv = SIMD2(local.x + 0.5, 0.5 - local.y)
        return uv.x.isFinite && uv.y.isFinite ? uv : nil
    }

    static func layerPoint(
        mouseNormalized: SIMD2<Float>,
        modelViewProjection: simd_float4x4
    ) -> SIMD3<Float>? {
        guard let inverse = preciseInverseModelViewProjection(modelViewProjection) else {
            return nil
        }
        return layerPoint(mouseNormalized: mouseNormalized, inverse: inverse)
    }

    private static func layerPoint(
        mouseNormalized: SIMD2<Float>,
        inverse: simd_double4x4
    ) -> SIMD3<Float>? {
        guard let near = localPoint(
            SIMD4(Double(mouseNormalized.x), Double(mouseNormalized.y), 0, 1),
            inverse: inverse
        ), let far = localPoint(
            SIMD4(Double(mouseNormalized.x), Double(mouseNormalized.y), 1, 1),
            inverse: inverse
        ) else {
            return nil
        }
        let direction = far - near
        guard direction.z.isFinite, abs(direction.z) > 1e-8 else { return nil }
        let distance = -near.z / direction.z
        guard distance.isFinite else { return nil }
        let local = SIMD3<Float>(near + direction * distance)
        return local.x.isFinite && local.y.isFinite && local.z.isFinite ? local : nil
    }

    static func inverseModelViewProjection(
        _ modelViewProjection: simd_float4x4
    ) -> simd_float4x4? {
        guard let precise = preciseInverseModelViewProjection(modelViewProjection) else {
            return nil
        }
        return floatInverseModelViewProjection(precise)
    }

    private static func floatInverseModelViewProjection(
        _ precise: simd_double4x4
    ) -> simd_float4x4? {
        let inverse = simd_float4x4(columns: (
            SIMD4<Float>(precise.columns.0), SIMD4<Float>(precise.columns.1),
            SIMD4<Float>(precise.columns.2), SIMD4<Float>(precise.columns.3)
        ))
        for column in 0..<4 {
            for row in 0..<4 where !inverse[column][row].isFinite { return nil }
        }
        return inverse
    }

    /// A large far/near ratio makes Float inversion lose the distinction
    /// between depth rows. Keep both admission and CPU ray intersection in
    /// Double; the shader ABI still receives the same finite Float matrix.
    static func preciseInverseModelViewProjection(
        _ modelViewProjection: simd_float4x4
    ) -> simd_double4x4? {
        let precise = simd_double4x4(columns: (
            SIMD4<Double>(modelViewProjection.columns.0), SIMD4<Double>(modelViewProjection.columns.1),
            SIMD4<Double>(modelViewProjection.columns.2), SIMD4<Double>(modelViewProjection.columns.3)
        ))
        let determinant = simd_determinant(precise)
        // A fixed determinant epsilon rejects valid orthographic cameras whose
        // canvas and depth ranges are large. Exact singularity plus a finite
        // inverse/residual check is scale-aware and still rejects unsafe input.
        guard determinant.isFinite, determinant != 0 else { return nil }
        let inverse = simd_inverse(precise)
        let columns = [
            inverse.columns.0, inverse.columns.1,
            inverse.columns.2, inverse.columns.3,
        ]
        guard columns.allSatisfy({ column in
            column.x.isFinite && column.y.isFinite
                && column.z.isFinite && column.w.isFinite
        }) else { return nil }
        let restored = precise * inverse
        let identity = matrix_identity_double4x4
        for column in 0..<4 {
            for row in 0..<4 {
                if abs(restored[column][row] - identity[column][row]) > 1e-3 {
                    return nil
                }
            }
        }
        return inverse
    }

    /// In effect coordinates, clip Z=0 is at the output geometry's origin
    /// depth. DepthParallax and similar effects also read the direction basis.
    static func effectTextureProjectionInverse(
        inverseModelViewProjection: simd_double4x4?,
        projectedOrigin: SIMD4<Float>,
        required: Bool
    ) -> simd_float4x4? {
        guard required else { return matrix_identity_float4x4 }
        guard let inverseModelViewProjection else { return nil }
        let (x, y, depth, translation) = inverseModelViewProjection.columns
        let origin = SIMD4<Double>(projectedOrigin)
        // Inverse times projected origin is (0,0,0,1). Use that identity
        // to shift clip depth without subtracting nearly equal depth terms.
        let relativeTranslation = origin.w == 0 ? translation
            : (SIMD4(0, 0, 0, 1) - x * origin.x - y * origin.y) / origin.w
        let scale = SIMD4<Double>(2, 2, 1, 1)
        return floatInverseModelViewProjection(simd_double4x4(columns: (
            x * scale,
            y * scale,
            depth * scale,
            relativeTranslation * scale
        )))
    }

    private static func localPoint(
        _ point: SIMD4<Double>,
        inverse: simd_double4x4
    ) -> SIMD3<Double>? {
        let projected = inverse * point
        guard projected.w.isFinite, abs(projected.w) > 1e-8 else { return nil }
        let local = SIMD3(projected.x, projected.y, projected.z) / projected.w
        return local.x.isFinite && local.y.isFinite && local.z.isFinite ? local : nil
    }
}
