import Foundation
import simd

/// Bounded support for the basic Rope renderer shape. The public contract says
/// Rope connects spawned particles; unsupported curve and UV options remain
/// closed until their authored math can be verified independently.
nonisolated struct SceneParticleRopePlan: Equatable, Sendable {
    static let maximumParticleCount = 512
    static let maximumSegmentCount = maximumParticleCount - 1

    let particleLimit: Int

    nonisolated init?(
        renderer: SceneParticleRenderer,
        rendererCount: Int,
        maximumParticleCount: Int
    ) {
        guard rendererCount == 1,
              renderer.kind == .rope,
              renderer.orientation == nil || renderer.orientation == "screen",
              renderer.axis == nil,
              renderer.rawFlags == 0,
              renderer.length == nil,
              renderer.minimumLength == nil,
              renderer.maximumLength == nil,
              renderer.segments == nil,
              renderer.subdivision == nil || renderer.subdivision == 0,
              renderer.fadesAlpha == nil,
              renderer.fadesSize == nil,
              renderer.uvScale == nil,
              renderer.smoothsUV != true,
              renderer.scrollsUV != true,
              !renderer.hasMalformedFields,
              renderer.unsupportedFieldNames.isEmpty,
              (2...Self.maximumParticleCount).contains(maximumParticleCount) else {
            return nil
        }
        particleLimit = maximumParticleCount
    }

    nonisolated func instances(
        particles: [SceneParticleState],
        layerAlpha: Float
    ) -> [SceneParticleGPUInstance] {
        guard layerAlpha.isFinite,
              particles.count >= 2,
              particles.count <= particleLimit,
              particles.count - 1 <= Self.maximumSegmentCount else {
            return []
        }
        let nodes = particles.sorted { $0.id < $1.id }
        guard nodes.allSatisfy(Self.valid),
              zip(nodes, nodes.dropFirst()).allSatisfy({ $0.id < $1.id }) else {
            return []
        }

        let safeLayerAlpha = min(max(layerAlpha, 0), 1)
        let denominator = Float(nodes.count - 1)
        var result: [SceneParticleGPUInstance] = []
        result.reserveCapacity(nodes.count - 1)
        for index in 0..<(nodes.count - 1) {
            let tail = nodes[index]
            let head = nodes[index + 1]
            let displacement = Self.floatValue(head.position - tail.position)
            let segmentLength = simd_length(displacement)
            let size = Float((tail.size + head.size) * 0.5)
            guard segmentLength.isFinite, segmentLength > 0.0001,
                  size.isFinite, size > 0.0001 else {
                continue
            }
            let tailPosition = Float(index) / denominator
            let headPosition = Float(index + 1) / denominator
            let frame = SceneParticleFrameTransform.identity.verticalTrailSlice(
                tailPosition: tailPosition,
                headPosition: headPosition
            )
            result.append(SceneParticleGPUInstance(
                position: Self.floatValue((tail.position + head.position) * 0.5),
                size: size,
                rotation: .zero,
                color: simd_max(
                    Self.floatValue((tail.color + head.color) * 0.5),
                    SIMD3(repeating: 0)
                ),
                alpha: min(max(
                    Float((tail.alpha + head.alpha) * 0.5) * safeLayerAlpha,
                    0
                ), 1),
                velocity: displacement,
                trailStretch: segmentLength / size,
                trailUVRange: SIMD2(tailPosition, headPosition),
                usesTrailDisplacement: true,
                currentFrame: frame
            ))
        }
        return result
    }

    private nonisolated static func valid(_ particle: SceneParticleState) -> Bool {
        particle.position.x.isFinite
            && particle.position.y.isFinite
            && particle.position.z.isFinite
            && particle.size.isFinite && particle.size >= 0
            && particle.color.x.isFinite
            && particle.color.y.isFinite
            && particle.color.z.isFinite
            && particle.alpha.isFinite
    }

    private nonisolated static func floatValue(
        _ value: SIMD3<Double>
    ) -> SIMD3<Float> {
        SIMD3(Float(value.x), Float(value.y), Float(value.z))
    }
}
