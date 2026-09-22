import simd

enum SceneLayerCursorGeometry {
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
              rendererWorldPosition.z.isFinite,
              let sceneOrthoHeight,
              sceneOrthoHeight.isFinite,
              sceneOrthoHeight > 0 else {
            return rendererWorldPosition
        }
        return SIMD3(
            rendererWorldPosition.x,
            sceneOrthoHeight - rendererWorldPosition.y,
            rendererWorldPosition.z
        )
    }

    static func layerUV(
        mouseNormalized: SIMD2<Float>,
        modelViewProjection: simd_float4x4
    ) -> SIMD2<Float>? {
        guard let local = layerPoint(
            mouseNormalized: mouseNormalized,
            modelViewProjection: modelViewProjection
        ) else { return nil }
        let uv = SIMD2(local.x + 0.5, 0.5 - local.y)
        return uv.x.isFinite && uv.y.isFinite ? uv : nil
    }

    static func layerPoint(
        mouseNormalized: SIMD2<Float>,
        modelViewProjection: simd_float4x4
    ) -> SIMD3<Float>? {
        guard let inverse = inverseModelViewProjection(modelViewProjection) else {
            return nil
        }
        guard let near = localPoint(
            SIMD4(mouseNormalized.x, mouseNormalized.y, 0, 1),
            inverse: inverse
        ), let far = localPoint(
            SIMD4(mouseNormalized.x, mouseNormalized.y, 1, 1),
            inverse: inverse
        ) else {
            return nil
        }
        let direction = far - near
        guard direction.z.isFinite, abs(direction.z) > 1e-8 else { return nil }
        let distance = -near.z / direction.z
        guard distance.isFinite else { return nil }
        let local = near + direction * distance
        return local.x.isFinite && local.y.isFinite && local.z.isFinite ? local : nil
    }

    static func inverseModelViewProjection(
        _ modelViewProjection: simd_float4x4
    ) -> simd_float4x4? {
        let determinant = simd_determinant(modelViewProjection)
        // A fixed determinant epsilon rejects valid orthographic cameras whose
        // canvas and depth ranges are large. Exact singularity plus a finite
        // inverse/residual check is scale-aware and still rejects unsafe input.
        guard determinant.isFinite, determinant != 0 else { return nil }
        let inverse = simd_inverse(modelViewProjection)
        let columns = [
            inverse.columns.0, inverse.columns.1,
            inverse.columns.2, inverse.columns.3,
        ]
        guard columns.allSatisfy({ column in
            column.x.isFinite && column.y.isFinite
                && column.z.isFinite && column.w.isFinite
        }) else { return nil }
        let restored = modelViewProjection * inverse
        let identity = matrix_identity_float4x4
        for column in 0..<4 {
            for row in 0..<4 {
                if abs(restored[column][row] - identity[column][row]) > 1e-3 {
                    return nil
                }
            }
        }
        return inverse
    }

    /// Converts clip coordinates into the effect-texture coordinate convention
    /// consumed by authored projection uniforms. Authored shaders first map a
    /// screen pointer into clip space and then multiply the projected result by
    /// 0.5, so the inverse must produce `2 * layerLocal` rather than the
    /// `layerLocal` returned by a bare output-MVP inverse. The authored shader
    /// owns any later centered-local-to-UV conversion; adding a translation here
    /// would double that conversion for cursor ripple and move X-Ray to an edge.
    ///
    /// Identity is supplied only when the admitted execution graph has proven
    /// that no effect projection uniform is read.
    static func effectTextureProjectionInverse(
        _ modelViewProjection: simd_float4x4,
        required: Bool
    ) -> simd_float4x4? {
        guard required else { return matrix_identity_float4x4 }
        guard let inverse = inverseModelViewProjection(modelViewProjection) else {
            return nil
        }
        let centeredLocalToEffectTexture = simd_float4x4(
            SIMD4(2, 0, 0, 0),
            SIMD4(0, 2, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        )
        return centeredLocalToEffectTexture * inverse
    }

    private static func localPoint(
        _ point: SIMD4<Float>,
        inverse: simd_float4x4
    ) -> SIMD3<Float>? {
        let projected = inverse * point
        guard projected.w.isFinite, abs(projected.w) > 1e-8 else { return nil }
        let local = SIMD3(projected.x, projected.y, projected.z) / projected.w
        return local.x.isFinite && local.y.isFinite && local.z.isFinite ? local : nil
    }
}
