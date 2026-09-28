import Foundation
import simd

/// Bounded Rope support. Curves and UV timing are clean-room interpretations of
/// the public renderer behavior; malformed or unbounded profiles remain closed.
nonisolated struct SceneParticleRopePlan: Equatable, Sendable {
    static let maximumParticleCount = 512
    /// Corpus author ceiling: the pointer-trail family declares 100.
    static let maximumSubdivisionCount = 100
    /// Covers the corpus worst case (maxcount 256, subdivision 100 ->
    /// 25,755 segments) and the subdivision-16/maxcount-500 shape (8,483).
    /// Child rope aggregation keeps its own smaller cross-system budget.
    static let maximumGeneratedSegmentCount = 32_768
    static let minimumUVScale = 1.0 / 1_024.0
    static let maximumUVScale = 1_024.0

    let particleLimit: Int
    let subdivisionCount: Int
    let uvScale: Float
    let smoothsUV: Bool
    let scrollsUV: Bool
    let maximumGeneratedSegments: Int

    nonisolated init?(
        renderer: SceneParticleRenderer,
        rendererCount: Int,
        maximumParticleCount: Int
    ) {
        // WE rope default: subdivision 3 when authored absent (MirageWallpaper
        // reference schema; `ropetrail` plans default to 1 and honor authored
        // overrides in their own path). A zero subdivision would collapse the
        // spline to straight segments.
        let rawSubdivision = renderer.subdivision ?? 3
        let rawUVScale = renderer.uvScale ?? 1
        // Renderer flag bit0 marks the pointer-trail rope family (all six
        // corpus shapes with this profile). The Catmull-Rom spline is
        // affine-invariant, so building it from layer-local positions and
        // rendering through the layer's affine model matrix is
        // image-identical to a world-space construction; no separate
        // world-space geometry path is needed.
        guard rendererCount == 1,
              renderer.kind == .rope,
              renderer.orientation == nil || renderer.orientation == "screen",
              renderer.axis == nil,
              renderer.rawFlags & ~1 == 0,
              renderer.length == nil,
              renderer.minimumLength == nil,
              renderer.maximumLength == nil,
              renderer.segments == nil,
              rawSubdivision.isFinite,
              rawSubdivision.rounded(.towardZero) == rawSubdivision,
              (0 ... Double(Self.maximumSubdivisionCount)).contains(rawSubdivision),
              rawUVScale.isFinite,
              (Self.minimumUVScale ... Self.maximumUVScale).contains(rawUVScale),
              renderer.fadesAlpha == nil,
              renderer.fadesSize == nil,
              !renderer.hasMalformedFields,
              renderer.unsupportedFieldNames.isEmpty,
              (2 ... Self.maximumParticleCount).contains(maximumParticleCount) else {
            return nil
        }
        let subdivision = Int(rawSubdivision)
        let generatedSegments = (maximumParticleCount - 1) * (subdivision + 1)
        guard generatedSegments <= Self.maximumGeneratedSegmentCount else { return nil }
        particleLimit = maximumParticleCount
        subdivisionCount = subdivision
        uvScale = Float(rawUVScale)
        smoothsUV = renderer.smoothsUV == true
        scrollsUV = renderer.scrollsUV == true
        maximumGeneratedSegments = generatedSegments
    }

    nonisolated func instances(
        particles: [SceneParticleState],
        origin: SIMD3<Double> = .zero,
        particleOrigins: [UInt64: SIMD3<Double>] = [:],
        layerAlpha: Float,
        simulationTime: TimeInterval = 0
    ) -> [SceneParticleGPUInstance] {
        guard layerAlpha.isFinite, simulationTime.isFinite,
              Self.valid(origin), particles.count >= 2,
              particles.count <= particleLimit else { return [] }
        let particles = particles.sorted { $0.id < $1.id }
        guard particles.allSatisfy(Self.valid),
              zip(particles, particles.dropFirst()).allSatisfy({ $0.id < $1.id }) else {
            return []
        }
        let nodes = particles.map { particle -> Node in
            let authoredOrigin = particleOrigins[particle.id] ?? origin
            return Node(particle: particle, position: authoredOrigin + particle.position)
        }
        guard nodes.allSatisfy({ Self.valid($0.position) }) else { return [] }
        let nodeUVs = uvPositions(for: particles, simulationTime: simulationTime)
        let generatedCount = (nodes.count - 1) * (subdivisionCount + 1)
        guard generatedCount <= maximumGeneratedSegments else { return [] }

        let safeLayerAlpha = min(max(layerAlpha, 0), 1)
        // Build one shared chain across particle boundaries. Independent quads
        // cannot agree on the width or bisector at a curved ribbon's joints.
        var samples: [(value: Sample, uv: Float)] = []
        samples.reserveCapacity(generatedCount + 1)
        for index in 0..<(nodes.count - 1) {
            let first = index == 0 ? 0 : 1
            for subdivision in first...(subdivisionCount + 1) {
                let t = Double(subdivision) / Double(subdivisionCount + 1)
                let value = sample(nodes: nodes, index: index, t: t)
                let uv = Self.mix(nodeUVs[index], nodeUVs[index + 1], Float(t))
                // A stationary span owns one vertex. Keep the first appearance
                // so both surviving neighbours use the same width and UV.
                if let previous = samples.last,
                   simd_distance(previous.value.position, value.position) <= 0.0001 {
                    continue
                }
                samples.append((value, uv))
            }
        }
        guard samples.count >= 2 else { return [] }
        var result: [SceneParticleGPUInstance] = []
        result.reserveCapacity(samples.count - 1)
        for index in 0..<(samples.count - 1) {
            let tail = samples[index]
            let head = samples[index + 1]
            let displacement = head.value.position - tail.value.position
            if let instance = Self.instance(
                tail: tail.value, head: head.value, tailUV: tail.uv, headUV: head.uv,
                headDirection: index + 2 < samples.count
                    ? samples[index + 2].value.position - head.value.position : displacement,
                tailDirection: index > 0
                    ? tail.value.position - samples[index - 1].value.position : displacement,
                layerAlpha: safeLayerAlpha
            ) {
                result.append(instance)
            }
        }
        return result
    }

    private nonisolated func uvPositions(
        for particles: [SceneParticleState],
        simulationTime: TimeInterval
    ) -> [Float] {
        var values: [Float]
        if smoothsUV, !scrollsUV, Self.hasUniformLifetimeProgress(particles) {
            values = particles.map { Float(1 - $0.age / $0.lifetime) }
        } else {
            let denominator = Float(particles.count - 1)
            values = particles.indices.map { Float($0) / denominator }
        }
        let phase: Float
        if scrollsUV {
            // Public docs do not expose a numeric rate; keep the project profile
            // deterministic at one texture repeat per simulation second.
            let remainder = simulationTime.truncatingRemainder(dividingBy: 1)
            phase = Float(remainder < 0 ? remainder + 1 : remainder)
        } else {
            phase = 0
        }
        return values.map { $0 * uvScale + phase }
    }

    private nonisolated func sample(nodes: [Node], index: Int, t: Double) -> Sample {
        let current = nodes[index]
        let next = nodes[index + 1]
        guard subdivisionCount > 0 else { return Sample.linear(current, next, t) }
        let previous = nodes[max(index - 1, 0)].position
        let after = nodes[min(index + 2, nodes.count - 1)].position
        let tangent0 = (next.position - previous) * 0.5
        let tangent1 = (after - current.position) * 0.5
        let t2 = t * t
        let t3 = t2 * t
        let position = current.position * (2 * t3 - 3 * t2 + 1)
            + tangent0 * (t3 - 2 * t2 + t)
            + next.position * (-2 * t3 + 3 * t2)
            + tangent1 * (t3 - t2)
        return Sample(
            position: position,
            size: Self.mix(current.particle.size, next.particle.size, t),
            color: Self.mix(current.particle.color, next.particle.color, t),
            alpha: Self.mix(current.particle.alpha, next.particle.alpha, t)
        )
    }

    private nonisolated static func instance(
        tail: Sample,
        head: Sample,
        tailUV: Float,
        headUV: Float,
        headDirection: SIMD3<Double>,
        tailDirection: SIMD3<Double>,
        layerAlpha: Float
    ) -> SceneParticleGPUInstance? {
        let displacement = floatValue(head.position - tail.position)
        let segmentLength = simd_length(displacement)
        let size = Float((tail.size + head.size) * 0.5)
        guard segmentLength.isFinite, segmentLength > 0.0001,
              size.isFinite, size > 0.0001,
              tailUV.isFinite, headUV.isFinite,
              Float(head.size).isFinite, Float(tail.size).isFinite else { return nil }
        // An adjacent span can exceed Float range and be discarded while this
        // span remains drawable. Treat that end as open, never publish infinity.
        let headVector = floatValue(headDirection)
        let tailVector = floatValue(tailDirection)
        let safeHead = headVector.x.isFinite && headVector.y.isFinite && headVector.z.isFinite
            ? headVector : displacement
        let safeTail = tailVector.x.isFinite && tailVector.y.isFinite && tailVector.z.isFinite
            ? tailVector : displacement
        let frame = SceneParticleFrameTransform.identity.verticalTrailSlice(
            tailPosition: tailUV, headPosition: headUV
        )
        return SceneParticleGPUInstance(
            position: floatValue((tail.position + head.position) * 0.5),
            size: size,
            rotation: .zero,
            color: simd_max(floatValue((tail.color + head.color) * 0.5), SIMD3(repeating: 0)),
            alpha: min(max(Float((tail.alpha + head.alpha) * 0.5) * layerAlpha, 0), 1),
            velocity: displacement,
            trailStretch: segmentLength / size,
            trailUVRange: SIMD2(tailUV, headUV),
            usesTrailDisplacement: true,
            trailHeadDirection: safeHead,
            trailTailDirection: safeTail,
            trailEndpointSizes: SIMD2(Float(head.size), Float(tail.size)),
            currentFrame: frame
        )
    }

    private nonisolated static func hasUniformLifetimeProgress(
        _ particles: [SceneParticleState]
    ) -> Bool {
        guard let lifetime = particles.first?.lifetime,
              lifetime.isFinite, lifetime > 0,
              particles.allSatisfy({
                  $0.lifetime.isFinite && abs($0.lifetime - lifetime) <= 1e-9
                      && $0.age.isFinite && (0 ... $0.lifetime).contains($0.age)
              }) else { return false }
        let progress = particles.map { 1 - $0.age / $0.lifetime }
        return zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 }
    }

    private nonisolated static func valid(_ particle: SceneParticleState) -> Bool {
        valid(particle.position)
            && particle.size.isFinite && particle.size >= 0
            && valid(particle.color)
            && particle.alpha.isFinite
    }

    private nonisolated static func valid(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private nonisolated static func mix(_ first: Double, _ second: Double, _ t: Double) -> Double {
        first + (second - first) * t
    }

    private nonisolated static func mix(
        _ first: SIMD3<Double>, _ second: SIMD3<Double>, _ t: Double
    ) -> SIMD3<Double> {
        first + (second - first) * t
    }

    private nonisolated static func mix(_ first: Float, _ second: Float, _ t: Float) -> Float {
        first + (second - first) * t
    }

    private nonisolated static func floatValue(_ value: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3(Float(value.x), Float(value.y), Float(value.z))
    }

    private struct Node {
        let particle: SceneParticleState
        let position: SIMD3<Double>
    }

    private struct Sample {
        let position: SIMD3<Double>
        let size: Double
        let color: SIMD3<Double>
        let alpha: Double

        static func linear(_ first: Node, _ second: Node, _ t: Double) -> Sample {
            Sample(
                position: SceneParticleRopePlan.mix(first.position, second.position, t),
                size: SceneParticleRopePlan.mix(first.particle.size, second.particle.size, t),
                color: SceneParticleRopePlan.mix(first.particle.color, second.particle.color, t),
                alpha: SceneParticleRopePlan.mix(first.particle.alpha, second.particle.alpha, t)
            )
        }
    }
}
