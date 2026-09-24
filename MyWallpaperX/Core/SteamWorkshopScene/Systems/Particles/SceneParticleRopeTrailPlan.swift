import Foundation
import simd

/// Bounded Rope Trail support for the shape shared by current stock and
/// Workshop samples. Public renderer semantics define a per-particle path;
/// UV animation, size fading, and non-screen orientation remain
/// closed until their geometry and sampling contracts are implemented.
nonisolated struct SceneParticleRopeTrailPlan: Equatable, Sendable {
    static let defaultSegmentCount = 4
    static let maximumHistorySampleCount = 262_144
    static let maximumSegmentInstanceCount = 65_536

    let length: TimeInterval
    let segmentCount: Int
    let subdivision: Int
    var renderSegmentCount: Int { segmentCount * (subdivision + 1) }
    /// Upper bound for the drawable segments of one particle. The authored
    /// segment/subdivision pair decides how densely the prepared history is
    /// sampled; a curved path still needs enough drawable nodes so that the
    /// polyline does not show its corners.
    let maximumSegmentsPerParticle: Int
    let fadesAlpha: Bool
    var stepSnapshotPolicy: SceneParticleStepSnapshotPolicy? {
        SceneParticleStepSnapshotPolicy(
            interval: length / TimeInterval(renderSegmentCount * 4),
            maximumSnapshots: renderSegmentCount * 4 + 4
        )
    }

    nonisolated init?(
        renderer: SceneParticleRenderer,
        rendererCount: Int,
        maximumParticleCount: Int
    ) {
        guard rendererCount == 1,
              renderer.kind == .ropeTrail,
              renderer.orientation == nil || renderer.orientation == "screen",
              renderer.axis == nil,
              renderer.rawFlags == 0,
              renderer.minimumLength == nil,
              renderer.maximumLength == nil,
              renderer.uvScale == nil,
              renderer.smoothsUV == nil,
              renderer.scrollsUV == nil,
              renderer.fadesSize != true,
              !renderer.hasMalformedFields,
              renderer.unsupportedFieldNames.isEmpty else {
            return nil
        }
        guard let length = renderer.length else { return nil }
        let segmentCount = renderer.segments ?? Self.defaultSegmentCount
        guard let subdivision = Int(exactly: renderer.subdivision ?? 1),
              subdivision >= 0,
              subdivision < Self.maximumSegmentInstanceCount,
              segmentCount > 0,
              segmentCount <= Self.maximumSegmentInstanceCount / (subdivision + 1) else {
            return nil
        }
        let renderSegmentCount = segmentCount * (subdivision + 1)
        guard length.isFinite,
              length > 0,
              segmentCount > 0,
              renderSegmentCount <= (Self.maximumHistorySampleCount - 4) / 4,
              length / TimeInterval(renderSegmentCount * 4) > 0,
              maximumParticleCount > 0,
              maximumParticleCount
                <= Self.maximumHistorySampleCount / (renderSegmentCount * 4 + 4),
              maximumParticleCount
                <= Self.maximumSegmentInstanceCount / renderSegmentCount else {
            return nil
        }
        self.length = length
        self.segmentCount = segmentCount
        self.subdivision = subdivision
        maximumSegmentsPerParticle = min(
            renderSegmentCount * 4 + 4,
            max(renderSegmentCount, Self.maximumSegmentInstanceCount / maximumParticleCount)
        )
        fadesAlpha = renderer.fadesAlpha == true
    }
}

nonisolated struct SceneParticleRopeTrailParticle: Equatable, Sendable {
    let id: UInt64
    let position: SIMD3<Float>
    let size: Float
    let color: SIMD3<Float>
    let alpha: Float

    nonisolated init(
        id: UInt64,
        position: SIMD3<Float>,
        size: Float,
        color: SIMD3<Float>,
        alpha: Float
    ) {
        self.id = id
        self.position = position
        self.size = size
        self.color = color
        self.alpha = alpha
    }
}

/// Keeps a bounded, oversampled history per live particle and converts each
/// path segment into an existing particle quad instance. Reusing that pipeline
/// preserves TEX sampling, mip selection, blend, and refraction behavior.
nonisolated struct SceneParticleRopeTrailHistory {
    private struct TimedSample {
        var time: TimeInterval
        var position: SIMD3<Float>
    }

    private struct Track {
        var committed: [TimedSample]
        var current: TimedSample
        var appearance: SceneParticleRopeTrailParticle
    }

    private let plan: SceneParticleRopeTrailPlan
    private var elapsed: TimeInterval = 0
    private var tracks: [UInt64: Track] = [:]

    init(plan: SceneParticleRopeTrailPlan) {
        self.plan = plan
    }

    mutating func advance(
        by frameDelta: TimeInterval,
        particles: [SceneParticleRopeTrailParticle],
        layerAlpha: Float
    ) -> [SceneParticleGPUInstance] {
        let validParticles = update(by: frameDelta, particles: particles)
        let safeLayerAlpha = layerAlpha.isFinite ? min(max(layerAlpha, 0), 1) : 0
        return validParticles.flatMap { particle -> [SceneParticleGPUInstance] in
            guard let track = tracks[particle.id] else { return [] }
            return instances(for: track, layerAlpha: safeLayerAlpha)
        }
    }

    mutating func ingest(
        by frameDelta: TimeInterval,
        particles: [SceneParticleRopeTrailParticle]
    ) {
        _ = update(by: frameDelta, particles: particles)
    }

    private mutating func update(
        by frameDelta: TimeInterval,
        particles: [SceneParticleRopeTrailParticle]
    ) -> [SceneParticleRopeTrailParticle] {
        let delta = frameDelta.isFinite ? max(frameDelta, 0) : 0
        elapsed += delta
        let validParticles = particles.filter(Self.valid)
        let liveIDs = Set(validParticles.map(\.id))
        for id in tracks.keys.filter({ !liveIDs.contains($0) }) {
            tracks.removeValue(forKey: id)
        }

        for particle in validParticles {
            let sample = TimedSample(time: elapsed, position: particle.position)
            if var track = tracks[particle.id] {
                commit(sample, to: &track)
                track.current = sample
                track.appearance = particle
                prune(&track)
                tracks[particle.id] = track
            } else {
                tracks[particle.id] = Track(committed: [sample], current: sample, appearance: particle)
            }
        }
        return validParticles
    }

    private func commit(_ sample: TimedSample, to track: inout Track) {
        guard let latest = track.committed.last else {
            track.committed = [sample]
            return
        }
        if sample.time - latest.time >= historySampleInterval {
            track.committed.append(sample)
        } else if sample.time == latest.time {
            track.committed[track.committed.count - 1] = sample
        }
    }

    private func prune(_ track: inout Track) {
        let cutoff = elapsed - plan.length
        while track.committed.count > 2,
              track.committed[1].time < cutoff {
            track.committed.removeFirst()
        }
        let maximumSamples = plan.renderSegmentCount * 4 + 4
        if track.committed.count > maximumSamples {
            track.committed.removeFirst(track.committed.count - maximumSamples)
        }
    }

    private var historySampleInterval: TimeInterval {
        plan.stepSnapshotPolicy?.interval ?? plan.length
    }

    private func instances(
        for track: Track,
        layerAlpha: Float
    ) -> [SceneParticleGPUInstance] {
        var samples = track.committed
        if let latest = samples.last, latest.time == track.current.time {
            samples[samples.count - 1] = track.current
        } else {
            samples.append(track.current)
        }
        guard let first = samples.first, samples.count >= 2 else { return [] }

        // Refine the actual simulated path instead of inventing a curve that
        // can overshoot it. Drawable nodes come from the prepared history
        // samples so a curved path keeps its curvature; the authored
        // segments/subdivision pair only decides how densely that history is
        // sampled. Shared endpoint joins below keep coverage continuous.
        var nodes: [TimedSample] = [track.current]
        let oldest = elapsed - plan.length
        for sample in samples.dropLast().reversed() {
            guard sample.time > oldest else { break }
            guard let previous = nodes.last, sample.time < previous.time else { continue }
            nodes.append(sample)
        }
        if let last = nodes.last, last.time > oldest {
            var upperSampleIndex = samples.count - 1
            if let value = Self.interpolate(samples, at: oldest, upperIndex: &upperSampleIndex) {
                nodes.append(value)
            } else if first.time < last.time {
                nodes.append(first)
            }
        }
        // Keep one drawable segment budget for the whole layer.
        let allowedNodes = plan.maximumSegmentsPerParticle + 1
        if nodes.count > allowedNodes {
            let stride = Int(
                (Double(nodes.count - 1) / Double(max(allowedNodes - 1, 1))).rounded(.up)
            )
            var thinned: [TimedSample] = []
            thinned.reserveCapacity(allowedNodes)
            var index = 0
            while index < nodes.count {
                thinned.append(nodes[index])
                index += max(stride, 1)
            }
            if let last = nodes.last, thinned.last?.time != last.time {
                thinned[thinned.count - 1] = last
            }
            nodes = thinned
        }
        // Stationary intervals have no drawable length. Merge their endpoint
        // before finding neighbours so resumed motion still has one join and
        // one width/UV value at the shared position. Keep the newest sample.
        var distinctNodes: [TimedSample] = []
        distinctNodes.reserveCapacity(nodes.count)
        for node in nodes {
            if let previous = distinctNodes.last,
               simd_distance(previous.position, node.position) <= 0.0001 {
                continue
            }
            distinctNodes.append(node)
        }
        nodes = distinctNodes
        guard nodes.count >= 2 else { return [] }

        var result: [SceneParticleGPUInstance] = []
        result.reserveCapacity(nodes.count - 1)
        for index in 0..<(nodes.count - 1) {
            let newer = nodes[index]
            let older = nodes[index + 1]
            let displacement = newer.position - older.position
            let segmentLength = simd_length(displacement)
            // Path history must not turn a lifetime opacity/size animation
            // into a second, unrequested fade along the ribbon. The current
            // particle owns appearance; renderer fade is applied separately.
            let size = track.appearance.size
            guard segmentLength.isFinite, segmentLength > 0.0001,
                  size.isFinite, size > 0.0001 else {
                continue
            }

            let newerU = Self.normalizedTrailPosition(
                sampleTime: newer.time,
                elapsed: elapsed,
                length: plan.length
            )
            let olderU = Self.normalizedTrailPosition(
                sampleTime: older.time,
                elapsed: elapsed,
                length: plan.length
            )
            let alphaFade = plan.fadesAlpha ? (newerU + olderU) * 0.5 : 1
            let alpha = min(max(
                track.appearance.alpha * layerAlpha * alphaFade,
                0
            ), 1)
            let frame = SceneParticleFrameTransform.identity.verticalTrailSlice(
                tailPosition: olderU,
                headPosition: newerU
            )
            result.append(SceneParticleGPUInstance(
                position: (newer.position + older.position) * 0.5,
                size: size,
                rotation: .zero,
                color: simd_max(
                    track.appearance.color,
                    SIMD3(repeating: 0)
                ),
                alpha: alpha,
                velocity: displacement,
                trailStretch: segmentLength / size,
                trailUVRange: SIMD2(olderU, newerU),
                usesTrailDisplacement: true,
                trailHeadDirection: index > 0
                    ? nodes[index - 1].position - newer.position
                    : displacement,
                trailTailDirection: index + 2 < nodes.count
                    ? older.position - nodes[index + 2].position
                    : displacement,
                trailEndpointSizes: SIMD2(repeating: size),
                currentFrame: frame
            ))
        }
        return result
    }

    private static func interpolate(
        _ samples: [TimedSample],
        at target: TimeInterval,
        upperIndex: inout Int
    ) -> TimedSample? {
        guard let first = samples.first, let last = samples.last,
              target >= first.time else {
            return nil
        }
        if target >= last.time {
            return last
        }
        // Targets move backward along the trail, so each history sample is
        // visited at most once across all segments of this particle.
        while upperIndex > 1, samples[upperIndex - 1].time >= target {
            upperIndex -= 1
        }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        let duration = upper.time - lower.time
        let mix = duration > 0 ? Float((target - lower.time) / duration) : 0
        return TimedSample(
            time: target,
            position: lower.position + (upper.position - lower.position) * mix
        )
    }

    private static func normalizedTrailPosition(
        sampleTime: TimeInterval,
        elapsed: TimeInterval,
        length: TimeInterval
    ) -> Float {
        Float(min(max(1 - (elapsed - sampleTime) / length, 0), 1))
    }

    private static func valid(_ particle: SceneParticleRopeTrailParticle) -> Bool {
        particle.position.x.isFinite
            && particle.position.y.isFinite
            && particle.position.z.isFinite
            && particle.size.isFinite && particle.size >= 0
            && particle.color.x.isFinite
            && particle.color.y.isFinite
            && particle.color.z.isFinite
            && particle.alpha.isFinite
    }
}
