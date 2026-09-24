import simd

nonisolated struct SceneParticleWorldSpaceFrame: Equatable, Sendable {
    let worldToLocalDirection: simd_double3x3

    nonisolated init?(worldFrame: simd_float4x4) {
        let localToWorld = simd_double3x3(columns: (
            SIMD3(
                Double(worldFrame.columns.0.x),
                Double(worldFrame.columns.0.y),
                Double(worldFrame.columns.0.z)
            ),
            SIMD3(
                Double(worldFrame.columns.1.x),
                Double(worldFrame.columns.1.y),
                Double(worldFrame.columns.1.z)
            ),
            SIMD3(
                Double(worldFrame.columns.2.x),
                Double(worldFrame.columns.2.y),
                Double(worldFrame.columns.2.z)
            )
        ))
        let determinant = simd_determinant(localToWorld)
        guard determinant.isFinite, abs(determinant) > 1e-12 else { return nil }
        let inverse = localToWorld.inverse
        guard inverse.columns.0.allFinite,
              inverse.columns.1.allFinite,
              inverse.columns.2.allFinite else { return nil }
        worldToLocalDirection = inverse
    }

    /// Author particle coordinates are Y-up while the layer world frame uses
    /// the scene's Y-down convention. Change basis on both sides of its inverse
    /// so world forces keep their direction under rotated/mirrored layers.
    nonisolated func localParticleDirection(_ direction: SIMD3<Double>) -> SIMD3<Double> {
        let sceneDirection = SIMD3(direction.x, -direction.y, direction.z)
        let local = worldToLocalDirection * sceneDirection
        return SIMD3(local.x, -local.y, local.z)
    }

    nonisolated func localDirection(_ worldDirection: SIMD3<Double>) -> SIMD3<Double> {
        worldToLocalDirection * worldDirection
    }
}

nonisolated enum SceneParticleStaticWorldSpacePlan {
    nonisolated struct Node: Equatable, Sendable {
        let id: Int
        let parentID: Int?
        let hasAuthoredTransformMotion: Bool
        let hasEffectiveParallaxMotion: Bool
    }

    nonisolated static func eligibleLayerIDs(nodes: [Node]) -> Set<Int> {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return Set(nodes.compactMap { node in
            var current: Node? = node
            var visited: Set<Int> = []
            while let value = current, visited.insert(value.id).inserted {
                if value.hasAuthoredTransformMotion || value.hasEffectiveParallaxMotion {
                    return nil
                }
                current = value.parentID.flatMap { byID[$0] }
            }
            return current == nil ? node.id : nil
        })
    }
}

private extension SIMD3 where Scalar == Double {
    nonisolated var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
